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
    /// Pixels on a depth discontinuity are dropped: they interpolate between an object's edge
    /// and whatever is behind it, and would smear the object away from the camera.
    func worldPoints(minConfidence: UInt8 = 2, near: Float = 0.1, far: Float = 3) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(width * height)
        for v in 0..<height {
            for u in 0..<width where usable(u, v, minConfidence: minConfidence, near: near, far: far) {
                out.append(worldPoint(u: u, v: v))
            }
        }
        return out
    }

    /// World points for the pixels set in `mask` (depth resolution, sensor orientation).
    func worldPoints(in mask: [Bool], minConfidence: UInt8 = 1, near: Float = 0.1, far: Float = 3) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        for v in 0..<height {
            for u in 0..<width where mask[v * width + u] && usable(u, v, minConfidence: minConfidence, near: near, far: far) {
                out.append(worldPoint(u: u, v: v))
            }
        }
        return out
    }

    /// Camera frame: x right, y up, z backward; image v runs down.
    func worldPoint(u: Int, v: Int) -> SIMD3<Float> {
        let d = depth[v * width + u]
        let p = SIMD4<Float>((Float(u) + 0.5 - cx) * d / fx, -(Float(v) + 0.5 - cy) * d / fy, -d, 1)
        let w = cameraToWorld * p
        return SIMD3(w.x, w.y, w.z)
    }

    /// Normalized sensor coordinates (0...1, origin at the top-left of the landscape image)
    /// of a world point. Nil when the point is behind the camera.
    func project(_ world: SIMD3<Float>) -> SIMD2<Float>? {
        let c = cameraToWorld.inverse * SIMD4(world, 1)
        let d = -c.z
        guard d > 0.05 else { return nil }
        let u = c.x * fx / d + cx
        let v = -c.y * fy / d + cy
        return [u / Float(width), v / Float(height)]
    }

    /// World point under normalized sensor coordinates: the median depth of a 5×5 patch.
    func worldPoint(atNormalized n: SIMD2<Float>) -> SIMD3<Float>? {
        let cu = Int(n.x * Float(width)), cv = Int(n.y * Float(height))
        guard cu >= 0, cu < width, cv >= 0, cv < height else { return nil }
        var ds: [Float] = []
        for v in max(cv - 2, 0)...min(cv + 2, height - 1) {
            for u in max(cu - 2, 0)...min(cu + 2, width - 1) {
                let i = v * width + u
                if confidence[i] >= 1, depth[i] > 0.1, depth[i] < 3 { ds.append(depth[i]) }
            }
        }
        guard ds.count >= 5 else { return nil }
        let d = ds.sorted()[ds.count / 2]
        let p = SIMD4<Float>((Float(cu) + 0.5 - cx) * d / fx, -(Float(cv) + 0.5 - cy) * d / fy, -d, 1)
        let w = cameraToWorld * p
        return SIMD3(w.x, w.y, w.z)
    }

    private func usable(_ u: Int, _ v: Int, minConfidence: UInt8, near: Float, far: Float) -> Bool {
        let i = v * width + u
        let d = depth[i]
        guard confidence[i] >= minConfidence, d >= near, d <= far else { return false }
        // A floor seen at a grazing angle steps about 1% of depth per pixel; edges step more.
        let limit = 0.005 + 0.03 * d
        if u > 0, abs(depth[i - 1] - d) > limit { return false }
        if u < width - 1, abs(depth[i + 1] - d) > limit { return false }
        if v > 0, abs(depth[i - width] - d) > limit { return false }
        if v < height - 1, abs(depth[i + width] - d) > limit { return false }
        return true
    }
}

#if canImport(ARKit)
extension DepthSnapshot {
    /// Copies the frame's raw depth (or smoothed depth). Raw depth keeps object edges sharp;
    /// the height map does its own smoothing across frames. Nil when the frame has no depth.
    init?(frame: ARFrame) {
        guard let data = frame.sceneDepth ?? frame.smoothedSceneDepth,
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
