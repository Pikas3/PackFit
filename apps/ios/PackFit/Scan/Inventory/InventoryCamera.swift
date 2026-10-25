@preconcurrency import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Vision

/// Back-camera stills for the photo inventory, plus a live check for the credit card.
/// Works on every iPhone; no depth needed.
@MainActor
@Observable
final class InventoryCamera: NSObject {
    enum CameraError: Error {
        case unavailable
        case notAuthorized
        case captureFailed
    }

    struct Shot {
        var image: CGImage
        /// From the lens field of view. Nil if the format did not report one.
        var intrinsics: CameraIntrinsics?
        /// The photo as the camera encoded it, EXIF included. Kept for replaying scans.
        var jpeg: Data?
        /// Horizontal field of view of the sensor's long side the intrinsics came from, degrees.
        var fieldOfView: Double
        /// EXIF 35 mm-equivalent focal length, a second opinion on the intrinsics.
        var focalLength35mm: Double?
    }

    /// What the photo delegate hands back.
    private struct Capture: @unchecked Sendable {
        var image: CGImage
        var jpeg: Data
        var focalLength35mm: Double?
    }

    /// The card in the live preview, corners normalized 0-1 to the upright frame. Nil when no
    /// rectangle in view fits a real card.
    private(set) var liveCard: ImageQuad?
    /// Normalized upright point the user last tapped to focus/find the card. Nil when idle.
    private(set) var focusPoint: CGPoint?
    /// Normalized upright box around the tap where live detection looks for the card.
    private(set) var focusRegion: CGRect?

    // startRunning blocks, so it is called on the capture queue; Apple documents the session as thread-safe.
    @ObservationIgnored nonisolated(unsafe) let session = AVCaptureSession()
    @ObservationIgnored nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "packfit.inventory.capture", qos: .userInitiated)
    @ObservationIgnored private var pending: [Int64: CheckedContinuation<Capture, Error>] = [:]
    @ObservationIgnored private var configured = false
    /// Horizontal field of view of the sensor's long side, degrees.
    @ObservationIgnored nonisolated(unsafe) private var fieldOfView: Double = 0
    /// Only touched on the capture queue.
    @ObservationIgnored nonisolated(unsafe) private var frameCount = 0
    @ObservationIgnored nonisolated(unsafe) private var device: AVCaptureDevice?
    /// Normalized upright search region; read on the capture queue, written on main after a tap.
    @ObservationIgnored nonisolated(unsafe) private var searchRegion: CGRect?
    /// Remaining video frames to search densely in `searchRegion` after a tap.
    @ObservationIgnored nonisolated(unsafe) private var searchBudget = 0

    /// Box for `CardMeasurer` when Claude did not mark the card: live lock, else the tap region.
    var cardHintBox: InventoryBox? {
        if let live = liveCard {
            let b = live.bounds
            return InventoryBox(x: b.minX, y: b.minY, w: b.width, h: b.height)
        }
        if let r = focusRegion, r.width > 0, r.height > 0 {
            return InventoryBox(x: r.minX, y: r.minY, w: r.width, h: r.height)
        }
        return nil
    }

    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
        #endif
    }

    func start() async throws {
        if !configured {
            guard await AVCaptureDevice.requestAccess(for: .video) else { throw CameraError.notAuthorized }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw CameraError.unavailable
            }
            self.device = device
            session.beginConfiguration()
            session.sessionPreset = .photo
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                throw CameraError.unavailable
            }
            session.addInput(input)
            session.addOutput(photoOutput)
            if session.canAddOutput(videoOutput) {
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.setSampleBufferDelegate(self, queue: queue)
                session.addOutput(videoOutput)
                if let conn = videoOutput.connection(with: .video), conn.isVideoRotationAngleSupported(90) {
                    conn.videoRotationAngle = 90
                }
            }
            session.commitConfiguration()
            fieldOfView = Double(device.activeFormat.videoFieldOfView)
            configured = true
        }
        let session = session
        queue.async { if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    /// Autofocus / expose on the tap, then hunt for an ID-1 card in that region of the frame.
    /// `normalized` is upright image space (origin top-left, 0…1).
    func focusOnCard(at normalized: CGPoint) {
        let x = min(1, max(0, normalized.x))
        let y = min(1, max(0, normalized.y))
        focusPoint = CGPoint(x: x, y: y)
        // Large enough to cover a credit card at typical packing distance, small enough to
        // ignore other rectangles across the room.
        let side: CGFloat = 0.42
        let region = CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        focusRegion = region
        searchRegion = region
        searchBudget = 90
        liveCard = nil
        applyLensFocus(at: CGPoint(x: x, y: y))
    }

    private func applyLensFocus(at upright: CGPoint) {
        guard let device else { return }
        // Preview / sample buffers are rotated 90° to portrait; device POI is sensor-native.
        let poi = CGPoint(x: upright.y, y: 1 - upright.x)
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = poi
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                } else if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = poi
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                } else if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }
            device.unlockForConfiguration()
        } catch {
            // Focus is best-effort; rectangle search still runs.
        }
    }

    /// One portrait-upright still, with the camera geometry needed to measure in it.
    func capture() async throws -> Shot {
        guard configured else { throw CameraError.unavailable }
        if let conn = photoOutput.connection(with: .video), conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
        }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        let capture: Capture = try await withCheckedThrowingContinuation { continuation in
            pending[settings.uniqueID] = continuation
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
        let image = capture.image
        let intrinsics = fieldOfView > 1
            ? CameraIntrinsics.fromFieldOfView(degrees: fieldOfView, width: image.width, height: image.height)
            : nil
        return Shot(image: image, intrinsics: intrinsics, jpeg: capture.jpeg, fieldOfView: fieldOfView,
                    focalLength35mm: capture.focalLength35mm)
    }

    private func finish(id: Int64, result: Result<Capture, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    /// Applies the EXIF orientation so box coordinates match what the user saw.
    nonisolated static func uprightImage(fromJPEG data: Data) -> CGImage? {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        return CIContext().createCGImage(image, from: image.extent)
    }
}

extension InventoryCamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        let result: Result<Capture, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(), let image = Self.uprightImage(fromJPEG: data) {
            let exif = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]
            let focal = (exif?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? NSNumber)?.doubleValue
            result = .success(Capture(image: image, jpeg: data, focalLength35mm: focal))
        } else {
            result = .failure(CameraError.captureFailed)
        }
        // Capture is Sendable (its CGImage is immutable), so the result goes straight to main.
        Task { @MainActor in self.finish(id: id, result: result) }
    }
}

extension InventoryCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Live card hunt. Idle: ~3 Hz full frame. After a tap: every frame, prefer / ROI the
    /// tapped region until a card locks or the budget runs out.
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        let searching = searchBudget > 0
        if searching {
            searchBudget -= 1
        } else if frameCount % 10 != 0 {
            return
        }
        guard fieldOfView > 1, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let size = SIMD2(Double(width), Double(height))
        let region = searchRegion
        let quads = Self.detectRectangles(in: buffer, region: searching ? region : nil, loose: searching)
        let intrinsics = CameraIntrinsics.fromFieldOfView(degrees: fieldOfView, width: width, height: height)
        let hintPixels: CGRect? = region.map {
            CGRect(x: $0.minX * size.x, y: $0.minY * size.y, width: $0.width * size.x, height: $0.height * size.y)
        }
        var card = PlanePose.bestCard(
            among: quads,
            intrinsics: intrinsics,
            hint: hintPixels,
            requireHint: searching && region != nil
        ).map { ImageQuad(corners: $0.card.corners.map { $0 / size }) }

        // ROI can miss a slightly off tap: one full-frame pass still biased to the region.
        if card == nil, searching, region != nil {
            let all = Self.detectRectangles(in: buffer, region: nil, loose: true)
            card = PlanePose.bestCard(
                among: all,
                intrinsics: intrinsics,
                hint: hintPixels,
                requireHint: true
            ).map { ImageQuad(corners: $0.card.corners.map { $0 / size }) }
        }

        let locked = card != nil
        let exhausted = !searching && region != nil
        if locked || exhausted {
            searchRegion = nil
            searchBudget = 0
        }

        Task { @MainActor in
            self.liveCard = card
            if locked || exhausted {
                self.focusRegion = nil
                self.focusPoint = nil
            }
        }
    }

    /// Rectangles in pixels, origin top-left. Optional Vision ROI (upright normalized → Vision
    /// bottom-left). Looser thresholds while the user is pointing at the card.
    nonisolated private static func detectRectangles(
        in buffer: CVPixelBuffer,
        region: CGRect?,
        loose: Bool
    ) -> [ImageQuad] {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = loose ? 16 : 8
        request.minimumAspectRatio = 0.25
        request.maximumAspectRatio = 1.0
        request.quadratureTolerance = loose ? 40 : 35
        request.minimumSize = loose ? 0.025 : 0.04
        request.minimumConfidence = loose ? 0.3 : 0.5
        if let region, region.width > 0.05, region.height > 0.05 {
            // Vision regionOfInterest: origin bottom-left, unit square.
            request.regionOfInterest = CGRect(
                x: region.minX,
                y: 1 - region.maxY,
                width: region.width,
                height: region.height
            )
        }
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
        let width = Double(CVPixelBufferGetWidth(buffer))
        let height = Double(CVPixelBufferGetHeight(buffer))
        return (request.results ?? []).map { r in
            ImageQuad(corners: [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft].map {
                SIMD2(Double($0.x) * width, (1 - Double($0.y)) * height)
            })
        }
    }
}
