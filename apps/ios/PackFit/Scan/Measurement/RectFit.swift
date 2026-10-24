import Foundation
import simd

/// A rectangle on the floor plane. Coordinates are world (x, z) in metres.
struct OrientedRect: Sendable, Equatable {
    var center: SIMD2<Float>
    /// Angle of the long axis from world +x toward world +z, in [0, π).
    var yaw: Float
    var long: Float
    var short: Float

    var axisLong: SIMD2<Float> { [cos(yaw), sin(yaw)] }
    var axisShort: SIMD2<Float> { [-sin(yaw), cos(yaw)] }

    func contains(_ p: SIMD2<Float>, margin: Float = 0) -> Bool {
        let v = p - center
        return abs(dot(v, axisLong)) <= long / 2 + margin && abs(dot(v, axisShort)) <= short / 2 + margin
    }

    func expanded(by margin: Float) -> OrientedRect {
        OrientedRect(center: center, yaw: yaw, long: long + 2 * margin, short: short + 2 * margin)
    }

    /// Corners in order around the rectangle.
    var corners: [SIMD2<Float>] {
        let a = axisLong * (long / 2), b = axisShort * (short / 2)
        return [center - a - b, center + a - b, center + a + b, center - a + b]
    }

    static func normalizedYaw(_ yaw: Float) -> Float {
        var y = fmodf(yaw, .pi)
        if y < 0 { y += .pi }
        if y >= .pi { y -= .pi }
        return y
    }
}

/// Convex hull plus minimum-area rectangle over grid cell centres.
enum RectFit {
    /// Andrew's monotone chain. Counter-clockwise, no repeated first point.
    static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        let pts = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard pts.count > 2 else { return pts }
        func turn(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Float>] = []
        for p in pts {
            while lower.count >= 2 && turn(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [SIMD2<Float>] = []
        for p in pts.reversed() {
            while upper.count >= 2 && turn(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Minimum-area rectangle tested along each hull edge. Extents come from the `trim` and
    /// `1 - trim` percentiles of all points projected on the chosen axes, plus one cell so
    /// cell centres become cell edges.
    static func minAreaRect(_ points: [SIMD2<Float>], cell: Float, trim: Float = 0.01) -> OrientedRect? {
        guard !points.isEmpty else { return nil }
        let hull = convexHull(points)
        var bestYaw: Float = 0
        var bestArea = Float.infinity
        if hull.count >= 2 {
            for i in hull.indices {
                let e = hull[(i + 1) % hull.count] - hull[i]
                guard length(e) > 1e-6 else { continue }
                let u = normalize(e), v = SIMD2<Float>(-u.y, u.x)
                var lo = SIMD2<Float>(repeating: .infinity), hi = SIMD2<Float>(repeating: -.infinity)
                for p in hull {
                    let q = SIMD2<Float>(dot(p, u), dot(p, v))
                    lo = simd_min(lo, q); hi = simd_max(hi, q)
                }
                let area = (hi.x - lo.x + cell) * (hi.y - lo.y + cell)
                if area < bestArea - 1e-9 {
                    bestArea = area
                    bestYaw = atan2(u.y, u.x)
                }
            }
        }
        let u = SIMD2<Float>(cos(bestYaw), sin(bestYaw)), v = SIMD2<Float>(-u.y, u.x)
        let pu = points.map { dot($0, u) }.sorted()
        let pv = points.map { dot($0, v) }.sorted()
        let (u0, u1) = (percentile(pu, trim), percentile(pu, 1 - trim))
        let (v0, v1) = (percentile(pv, trim), percentile(pv, 1 - trim))
        var long = u1 - u0 + cell, short = v1 - v0 + cell
        let center = u * ((u0 + u1) / 2) + v * ((v0 + v1) / 2)
        var yaw = bestYaw
        if short > long {
            swap(&long, &short)
            yaw += .pi / 2
        }
        return OrientedRect(center: center, yaw: OrientedRect.normalizedYaw(yaw), long: long, short: short)
    }

    /// Nearest-rank percentile of an ascending array.
    static func percentile(_ sorted: [Float], _ q: Float) -> Float {
        guard !sorted.isEmpty else { return .nan }
        let i = Int((Float(sorted.count - 1) * q).rounded())
        return sorted[min(max(i, 0), sorted.count - 1)]
    }
}
