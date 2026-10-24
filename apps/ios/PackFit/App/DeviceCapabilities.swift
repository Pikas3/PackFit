import Foundation

@Observable
@MainActor
final class DeviceCapabilities {
    /// Absolute depth from `builtInLiDARDepthCamera` (AVFoundation).
    let hasLidar: Bool
    let isSimulator: Bool
    /// Guided one-tap flow needs LiDAR depth (no ARKit on this branch).
    let supportsGuidedScan: Bool

    init() {
        #if targetEnvironment(simulator)
        isSimulator = true
        hasLidar = false
        supportsGuidedScan = false
        #else
        isSimulator = false
        hasLidar = LidarCaptureSession.isLiDARAvailable
        supportsGuidedScan = hasLidar
        #endif
    }

    var measurementModeLabel: String {
        if isSimulator { return Copy.Scan.simulatorMode }
        if hasLidar { return Copy.Scan.lidarMeasuring }
        return Copy.Scan.referenceCardHint
    }
}
