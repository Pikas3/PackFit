import Foundation
#if canImport(ARKit)
import ARKit
#endif

@Observable
@MainActor
final class DeviceCapabilities {
    let hasLidar: Bool
    let isSimulator: Bool
    /// ARKit world tracking: metric tap-measuring works on every such iPhone, LiDAR or not.
    let supportsAR: Bool

    init() {
        #if targetEnvironment(simulator)
        isSimulator = true
        hasLidar = false
        supportsAR = false
        #else
        isSimulator = false
        #if canImport(ARKit)
        hasLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        supportsAR = ARWorldTrackingConfiguration.isSupported
        #else
        hasLidar = false
        supportsAR = false
        #endif
        #endif
    }

    var measurementModeLabel: String {
        if isSimulator { return Copy.Scan.simulatorMode }
        if hasLidar { return Copy.Scan.lidarMeasuring }
        return Copy.Scan.referenceCardHint
    }
}
