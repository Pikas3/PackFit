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
    /// About three times a second: is there a real card in view? Same test as the final photo.
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        guard frameCount % 10 == 0, fieldOfView > 1, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 8
        request.minimumAspectRatio = 0.25
        request.maximumAspectRatio = 1.0
        request.quadratureTolerance = 35
        request.minimumSize = 0.04
        request.minimumConfidence = 0.5
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
        let size = SIMD2(Double(width), Double(height))
        let quads = (request.results ?? []).map { r in
            ImageQuad(corners: [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft].map {
                SIMD2(Double($0.x) * size.x, (1 - Double($0.y)) * size.y)
            })
        }
        let intrinsics = CameraIntrinsics.fromFieldOfView(degrees: fieldOfView, width: width, height: height)
        let card = PlanePose.bestCard(among: quads, intrinsics: intrinsics)
            .map { ImageQuad(corners: $0.card.corners.map { $0 / size }) }
        Task { @MainActor in self.liveCard = card }
    }
}
