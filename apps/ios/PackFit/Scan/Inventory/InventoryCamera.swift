@preconcurrency import AVFoundation
import CoreImage
import Foundation

/// Plain back-camera stills for the photo inventory. Works on every iPhone; no depth needed.
@MainActor
final class InventoryCamera: NSObject {
    enum CameraError: Error {
        case unavailable
        case notAuthorized
        case captureFailed
    }

    // startRunning blocks, so it is called on the capture queue; Apple documents the session as thread-safe.
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "packfit.inventory.capture", qos: .userInitiated)
    private var pending: [Int64: CheckedContinuation<CGImage, Error>] = [:]
    private var configured = false

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
            session.commitConfiguration()
            configured = true
        }
        let session = session
        queue.async { if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    /// One portrait-upright still.
    func capture() async throws -> CGImage {
        guard configured else { throw CameraError.unavailable }
        if let conn = photoOutput.connection(with: .video), conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90
        }
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        return try await withCheckedThrowingContinuation { continuation in
            pending[settings.uniqueID] = continuation
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func finish(id: Int64, result: Result<CGImage, Error>) {
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
        let result: Result<CGImage, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(), let image = Self.uprightImage(fromJPEG: data) {
            result = .success(image)
        } else {
            result = .failure(CameraError.captureFailed)
        }
        // CGImage is immutable; handing it to the main actor is safe.
        nonisolated(unsafe) let sendable = result
        Task { @MainActor in self.finish(id: id, result: sendable) }
    }
}
