import Foundation
import simd

/// Pure measurement helpers from raycast hits / depth samples → (w, h, d, confidence).
/// Units: metres in, centimetres out (for Item fields).
enum MeasurementMath {
    struct Footprint {
        var widthM: Double
        var depthM: Double
        var planeNormal: SIMD3<Float>
        var planeOrigin: SIMD3<Float>
        var localX: SIMD3<Float>
        var localZ: SIMD3<Float>
    }

    /// Project two opposite-corner hits onto the plane's local x/z axes.
    static func footprint(
        cornerA: SIMD3<Float>,
        cornerB: SIMD3<Float>,
        planeOrigin: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> Footprint {
        let n = normalize(planeNormal)
        var localX = cross(n, SIMD3<Float>(0, 1, 0))
        if length(localX) < 1e-4 {
            localX = cross(n, SIMD3<Float>(1, 0, 0))
        }
        localX = normalize(localX)
        let localZ = normalize(cross(localX, n))

        let a = cornerA - planeOrigin
        let b = cornerB - planeOrigin
        let ax = Double(dot(a, localX))
        let az = Double(dot(a, localZ))
        let bx = Double(dot(b, localX))
        let bz = Double(dot(b, localZ))
        let width = abs(bx - ax)
        let depth = abs(bz - az)
        return Footprint(
            widthM: max(width, 0.001),
            depthM: max(depth, 0.001),
            planeNormal: n,
            planeOrigin: planeOrigin,
            localX: localX,
            localZ: localZ
        )
    }

    /// Height above plane from samples (metres). Uses 98th percentile.
    static func heightMeters(samplesAbovePlane: [Double]) -> (heightM: Double, sampleCount: Int) {
        let positive = samplesAbovePlane.filter { $0 > 0.002 }.sorted()
        guard !positive.isEmpty else { return (0.01, 0) }
        let index = min(positive.count - 1, Int(Double(positive.count - 1) * 0.98))
        return (positive[index], positive.count)
    }

    static func heightFromTopTap(topY: Float, planeY: Float) -> Double {
        max(0.01, Double(topY - planeY))
    }

    /// Confidence model from CLAUDE.md WS3.
    static func confidence(
        meanDepthConfidenceBelowMedium: Bool,
        footprintMinSideCm: Double,
        heightSampleCount: Int
    ) -> Double {
        var c = 0.95
        if meanDepthConfidenceBelowMedium { c -= 0.1 }
        if footprintMinSideCm < 4 { c -= 0.1 }
        if heightSampleCount < 20 { c -= 0.15 }
        return max(0.5, c)
    }

    static func dimsCm(widthM: Double, heightM: Double, depthM: Double) -> (w: Double, h: Double, d: Double) {
        (round1(widthM * 100), round1(heightM * 100), round1(depthM * 100))
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
