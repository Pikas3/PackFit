import AVFoundation
import SwiftUI
import UIKit

/// Live camera preview for single-item scan. Prefers LiDAR depth camera; falls back to wide angle.
@MainActor
final class ItemCameraController: NSObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "packfit.item.camera")
    private var continuation: CheckedContinuation<String?, Never>?
    private(set) var isRunning = false
    var statusMessage: String?

    static var canUseCamera: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            || LidarCaptureSession.isLiDARAvailable
        #endif
    }

    func start() async {
        let granted = await Self.requestAccess()
        guard granted else {
            statusMessage = Copy.Scan.cameraDenied
            return
        }
        do {
            try configure()
            queue.async { [session] in session.startRunning() }
            isRunning = true
            statusMessage = nil
        } catch {
            statusMessage = Copy.Scan.cameraStartFailed
        }
    }

    func stop() {
        guard isRunning else { return }
        session.stopRunning()
        isRunning = false
    }

    /// Captures a JPEG base64 still from the live session.
    func captureJPEGBase64() async -> String? {
        guard isRunning, session.isRunning else { return nil }
        return await withCheckedContinuation { cont in
            continuation = cont
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        let device =
            AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let device else { throw CameraError.unavailable }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.unavailable }
        session.addInput(input)
        guard session.canAddOutput(photoOutput) else { throw CameraError.unavailable }
        session.addOutput(photoOutput)
        if let conn = photoOutput.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }
        session.sessionPreset = .photo
        session.commitConfiguration()
    }

    enum CameraError: Error { case unavailable }
}

extension ItemCameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        let base64: String?
        if let data, let image = UIImage(data: data), let cg = image.cgImage {
            base64 = ImageCapture.jpegBase64(from: cg)
        } else {
            base64 = nil
        }
        Task { @MainActor in
            continuation?.resume(returning: base64)
            continuation = nil
        }
    }
}

struct ItemCameraPreview: UIViewRepresentable {
    let controller: ItemCameraController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = controller.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = controller.session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
