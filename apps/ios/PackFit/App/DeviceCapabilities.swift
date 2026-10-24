import Foundation
#if canImport(ARKit)
import ARKit
#endif

@Observable
@MainActor
final class DeviceCapabilities {
    let hasLidar: Bool
    let isSimulator: Bool

    init() {
        #if targetEnvironment(simulator)
        isSimulator = true
        hasLidar = false
        #else
        isSimulator = false
        #if canImport(ARKit)
        hasLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        #else
        hasLidar = false
        #endif
        #endif
    }

    var measurementModeLabel: String {
        if isSimulator { return Copy.Scan.simulatorMode }
        if hasLidar { return Copy.Scan.lidarMeasuring }
        return Copy.Scan.referenceCardHint
    }
}
