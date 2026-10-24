import AVFoundation
import Foundation
import simd

/// A Sendable copy of one LiDAR depth frame so fitting can run off the main actor.
struct DepthSnapshot: Sendable {
    let width: Int
    let height: Int
    /// Metres, row-major in the sensor's landscape orientation.
    let depth: [Float]
    /// Confidence: 0 low, 1 medium, 2 high (ARKit-compatible scale).
    let confidence: [UInt8]
    /// Intrinsics scaled to the depth resolution.
    let fx: Float, fy: Float, cx: Float, cy: Float
    let cameraToWorld: simd_float4x4
    let timestamp: TimeInterval
    /// Video size used when mapping portrait view taps → sensor UV.
    let videoWidth: Int
    let videoHeight: Int

    var cameraPosition: SIMD3<Float> {
        SIMD3(cameraToWorld.columns.3.x, cameraToWorld.columns.3.y, cameraToWorld.columns.3.z)
    }

    var highConfidenceFraction: Double {
        guard !confidence.isEmpty else { return 0 }
        return Double(confidence.reduce(0) { $0 + ($1 >= 2 ? 1 : 0) }) / Double(confidence.count)
    }

    /// World points for pixels at or above `minConfidence` between `near` and `far` metres.
    /// Pixels on a depth discontinuity are dropped.
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

    /// Normalized sensor coordinates (0...1, origin at the top-left of the landscape image).
    func project(_ world: SIMD3<Float>) -> SIMD2<Float>? {
        let c = cameraToWorld.inverse * SIMD4(world, 1)
        let d = -c.z
        guard d > 0.05 else { return nil }
        let u = c.x * fx / d + cx
        let v = -c.y * fy / d + cy
        return [u / Float(width), v / Float(height)]
    }

    /// World point under normalized sensor coordinates: median depth of a 5×5 patch.
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

    /// Portrait view tap (0...1 in the preview) → landscape sensor UV for this depth map.
    func sensorUV(fromPortraitNormalized p: SIMD2<Float>) -> SIMD2<Float> {
        // Video connection is portrait; depth map is landscape (home-button right / sensor native).
        // Portrait (u,v) → landscape sensor: u_s = v, v_s = 1 - u
        return [p.y, 1 - p.x]
    }

    private func usable(_ u: Int, _ v: Int, minConfidence: UInt8, near: Float, far: Float) -> Bool {
        let i = v * width + u
        let d = depth[i]
        guard confidence[i] >= minConfidence, d >= near, d <= far, d.isFinite else { return false }
        let limit = 0.005 + 0.03 * d
        if u > 0, abs(depth[i - 1] - d) > limit { return false }
        if u < width - 1, abs(depth[i + 1] - d) > limit { return false }
        if v > 0, abs(depth[i - width] - d) > limit { return false }
        if v < height - 1, abs(depth[i + width] - d) > limit { return false }
        return true
    }
}

extension DepthSnapshot {
    /// Builds a snapshot from AVFoundation LiDAR depth + gravity pose.
    init?(depthData: AVDepthData, videoBuffer: CVPixelBuffer, cameraToWorld: simd_float4x4, timestamp: TimeInterval) {
        var depth = depthData
        if depth.depthDataType != kCVPixelFormatType_DepthFloat32 {
            depth = depth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        }
        let depthMap = depth.depthDataMap
        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let dBase = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let dRow = CVPixelBufferGetBytesPerRow(depthMap)

        var depthValues = [Float](repeating: 0, count: w * h)
        var conf = [UInt8](repeating: 0, count: w * h)
        // AVDepthData has no confidenceMap (that is ARKit-only). With filtering off,
        // low-confidence samples are holes / non-finite; treat valid depths as high.
        for v in 0..<h {
            let dp = dBase.advanced(by: v * dRow).assumingMemoryBound(to: Float32.self)
            for u in 0..<w {
                let d = dp[u]
                depthValues[v * w + u] = d
                conf[v * w + u] = (d.isFinite && d > 0.05 && d < 5) ? 2 : 0
            }
        }

        guard let calibration = depth.cameraCalibrationData else { return nil }
        let k = calibration.intrinsicMatrix
        let ref = calibration.intrinsicMatrixReferenceDimensions
        let scaleX = Float(w) / Float(ref.width)
        let scaleY = Float(h) / Float(ref.height)

        self.init(
            width: w,
            height: h,
            depth: depthValues,
            confidence: conf,
            fx: k[0][0] * scaleX,
            fy: k[1][1] * scaleY,
            cx: k[2][0] * scaleX,
            cy: k[2][1] * scaleY,
            cameraToWorld: cameraToWorld,
            timestamp: timestamp,
            videoWidth: CVPixelBufferGetWidth(videoBuffer),
            videoHeight: CVPixelBufferGetHeight(videoBuffer)
        )
    }
}
