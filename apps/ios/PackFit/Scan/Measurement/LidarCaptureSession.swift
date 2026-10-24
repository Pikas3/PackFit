@preconcurrency import AVFoundation
import CoreImage
import Foundation
import UIKit

/// Synchronized RGB + absolute LiDAR depth from `builtInLiDARDepthCamera` (AVFoundation).
@MainActor
final class LidarCaptureSession: NSObject {
    /// Handed from the capture queue to main once and never mutated, so sharing it is safe.
    struct Frame: @unchecked Sendable {
        let depthData: AVDepthData
        let videoBuffer: CVPixelBuffer
        let timestamp: TimeInterval
    }

    let session = AVCaptureSession()
    // Read by the synchronizer delegate on the capture queue; configured only before it runs.
    private nonisolated(unsafe) let videoOutput = AVCaptureVideoDataOutput()
    private nonisolated(unsafe) let depthOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private let queue = DispatchQueue(label: "packfit.lidar.capture", qos: .userInitiated)

    private(set) var isRunning = false
    private(set) var latest: Frame?
    /// Portrait-upright JPEG-ready still from the latest video buffer.
    private(set) var latestVideoBuffer: CVPixelBuffer?

    private let preferredWidth = 1920

    static var isLiDARAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil
        #endif
    }

    func start() async throws {
        guard !isRunning else { return }
        let granted = await Self.requestCameraAccess()
        guard granted else { throw CaptureError.cameraDenied }
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
            throw CaptureError.lidarUnavailable
        }

        session.beginConfiguration()
        session.sessionPreset = .inputPriority

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)

        try configureFormats(device: device)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ]
        guard session.canAddOutput(videoOutput) else { throw CaptureError.cannotAddOutput }
        session.addOutput(videoOutput)
        if let conn = videoOutput.connection(with: .video), conn.isVideoRotationAngleSupported(90) {
            conn.videoRotationAngle = 90 // portrait
        }

        depthOutput.isFilteringEnabled = false
        guard session.canAddOutput(depthOutput) else { throw CaptureError.cannotAddOutput }
        session.addOutput(depthOutput)
        if let conn = depthOutput.connection(with: .depthData) {
            conn.isEnabled = true
        }

        let sync = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
        sync.setDelegate(self, queue: queue)
        synchronizer = sync

        session.commitConfiguration()
        queue.async { [session] in session.startRunning() }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        session.stopRunning()
        isRunning = false
        latest = nil
        latestVideoBuffer = nil
    }

    private func configureFormats(device: AVCaptureDevice) throws {
        let match = device.formats.last { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width >= preferredWidth,
                  format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                  !format.isVideoBinned,
                  !format.supportedDepthDataFormats.isEmpty
            else { return false }
            return format.supportedDepthDataFormats.contains {
                CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
            }
        } ?? device.formats.last { !$0.supportedDepthDataFormats.isEmpty }

        guard let format = match,
              let depthFormat = format.supportedDepthDataFormats.first(where: {
                  CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
              }) ?? format.supportedDepthDataFormats.first
        else { throw CaptureError.noDepthFormat }

        try device.lockForConfiguration()
        device.activeFormat = format
        device.activeDepthDataFormat = depthFormat
        device.unlockForConfiguration()
    }

    enum CaptureError: Error {
        case lidarUnavailable
        case cameraDenied
        case cannotAddInput
        case cannotAddOutput
        case noDepthFormat
    }

    private static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

extension LidarCaptureSession: AVCaptureDataOutputSynchronizerDelegate {
    nonisolated func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        guard let syncedDepth = synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData,
              !syncedDepth.depthDataWasDropped,
              let syncedVideo = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
              !syncedVideo.sampleBufferWasDropped,
              let pixelBuffer = CMSampleBufferGetImageBuffer(syncedVideo.sampleBuffer)
        else { return }

        var depth = syncedDepth.depthData
        if depth.depthDataType != kCVPixelFormatType_DepthFloat32 {
            depth = depth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        }
        let seconds = CMTimeGetSeconds(syncedVideo.timestamp)
        let frame = Frame(depthData: depth, videoBuffer: pixelBuffer, timestamp: seconds)
        Task { @MainActor in
            self.latest = frame
            self.latestVideoBuffer = frame.videoBuffer
        }
    }
}
