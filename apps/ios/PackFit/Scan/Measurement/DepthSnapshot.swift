import Foundation
import simd
#if canImport(ARKit)
import ARKit
#endif

/// A Sendable copy of one ARFrame's LiDAR depth, so the frame can be released at once and
/// the fitting can run off the main actor.
struct DepthSnapshot: Sendable {
    let width: Int
    let height: Int
    /// Metres, row-major in the sensor's landscape orientation.
    let depth: [Float]
    /// ARConfidenceLevel raw values: 0 low, 1 medium, 2 high.
    let confidence: [UInt8]
    /// Intrinsics scaled to the depth resolution.
    let fx: Float, fy: Float, cx: Float, cy: Float
    let cameraToWorld: simd_float4x4
    let timestamp: TimeInterval

    var cameraPosition: SIMD3<Float> {
        SIMD3(cameraToWorld.columns.3.x, cameraToWorld.columns.3.y, cameraToWorld.columns.3.z)
    }

    var highConfidenceFraction: Double {
        guard !confidence.isEmpty else { return 0 }
        return Double(confidence.reduce(0) { $0 + ($1 >= 2 ? 1 : 0) }) / Double(confidence.count)
    }

    /// World points for pixels at or above `minConfidence` between `near` and `far` metres.
    func worldPoints(minConfidence: UInt8 = 2, near: Float = 0.1, far: Float = 3) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(width * height)
        for v in 0..<height {
            for u in 0..<width {
                let i = v * width + u
                let d = depth[i]
                guard confidence[i] >= minConfidence, d >= near, d <= far else { continue }
                // Camera frame: x right, y up, z backward; image v runs down.
                let p = SIMD4<Float>((Float(u) + 0.5 - cx) * d / fx, -(Float(v) + 0.5 - cy) * d / fy, -d, 1)
                let w = cameraToWorld * p
                out.append(SIMD3(w.x, w.y, w.z))
            }
        }
        return out
    }
}

#if canImport(ARKit)
extension DepthSnapshot {
    /// Copies the frame's smoothed depth (or raw depth). Nil when the frame has no depth.
    init?(frame: ARFrame) {
        guard let data = frame.smoothedSceneDepth ?? frame.sceneDepth,
              let confMap = data.confidenceMap else { return nil }
        let depthMap = data.depthMap
        let w = CVPixelBufferGetWidth(depthMap), h = CVPixelBufferGetHeight(depthMap)
        guard CVPixelBufferGetWidth(confMap) == w, CVPixelBufferGetHeight(confMap) == h else { return nil }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(confMap, .readOnly)
        }
        guard let dBase = CVPixelBufferGetBaseAddress(depthMap),
              let cBase = CVPixelBufferGetBaseAddress(confMap) else { return nil }
        let dRow = CVPixelBufferGetBytesPerRow(depthMap), cRow = CVPixelBufferGetBytesPerRow(confMap)

        var depth = [Float](repeating: 0, count: w * h)
        var conf = [UInt8](repeating: 0, count: w * h)
        for v in 0..<h {
            let dp = dBase.advanced(by: v * dRow).assumingMemoryBound(to: Float32.self)
            let cp = cBase.advanced(by: v * cRow).assumingMemoryBound(to: UInt8.self)
            for u in 0..<w {
                depth[v * w + u] = dp[u]
                conf[v * w + u] = cp[u]
            }
        }

        let k = frame.camera.intrinsics
        let scale = Float(w) / Float(frame.camera.imageResolution.width)
        self.init(
            width: w,
            height: h,
            depth: depth,
            confidence: conf,
            fx: k[0][0] * scale,
            fy: k[1][1] * scale,
            cx: k[2][0] * scale,
            cy: k[2][1] * scale,
            cameraToWorld: frame.camera.transform,
            timestamp: frame.timestamp
        )
    }
}
#endif
