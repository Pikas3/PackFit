import Foundation
import simd

/// Geometry for measuring by tapping in AR, for phones without LiDAR. ARKit's world tracking
/// is metric on every supported iPhone, so taps on the floor plane give real distances.
enum TapMeasure {
    /// A rectangle from three corner taps: `a` and `b` along one side, `c` anywhere on the
    /// opposite side. World points; only x and z are used.
    static func footprint(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> OrientedRect? {
        let a2 = SIMD2(a.x, a.z), b2 = SIMD2(b.x, b.z), c2 = SIMD2(c.x, c.z)
        let side = b2 - a2
        let length = simd_length(side)
        guard length > 0.005 else { return nil }
        let u = side / length
        var n = SIMD2(-u.y, u.x)
        var width = dot(c2 - a2, n)
        if width < 0 {
            n = -n
            width = -width
        }
        guard width > 0.005 else { return nil }
        let center = (a2 + b2) / 2 + n * (width / 2)
        var yaw = atan2(u.y, u.x)
        var long = length, short = width
        if short > long {
            swap(&long, &short)
            yaw += .pi / 2
        }
        return OrientedRect(center: center, yaw: OrientedRect.normalizedYaw(yaw), long: long, short: short)
    }

    /// Height from a tap on the item's top front edge: where the tap ray meets the vertical
    /// plane through the footprint side nearest the camera. Nil if the ray misses or the
    /// result is implausible.
    static func heightFromEdgeRay(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        footprint rect: OrientedRect,
        floorY: Float
    ) -> Float? {
        let camera = SIMD2(origin.x, origin.z)
        let halfs: [(SIMD2<Float>, Float)] = [
            (rect.axisLong, rect.long / 2), (-rect.axisLong, rect.long / 2),
            (rect.axisShort, rect.short / 2), (-rect.axisShort, rect.short / 2),
        ]
        guard let (normal2, half) = halfs.min(by: {
            simd_distance(rect.center + $0.0 * $0.1, camera) < simd_distance(rect.center + $1.0 * $1.1, camera)
        }) else { return nil }
        let point2 = rect.center + normal2 * half
        let normal = SIMD3(normal2.x, 0, normal2.y)
        let planePoint = SIMD3(point2.x, floorY, point2.y)
        let denom = dot(direction, normal)
        guard abs(denom) > 1e-4 else { return nil }
        let t = dot(planePoint - origin, normal) / denom
        guard t > 0 else { return nil }
        let height = (origin + direction * t).y - floorY
        return plausibleHeight(height)
    }

    /// Height from a surface hit on top of the item, when it lands over the footprint.
    static func heightFromSurfaceHit(_ hit: SIMD3<Float>, footprint rect: OrientedRect, floorY: Float) -> Float? {
        guard rect.contains(SIMD2(hit.x, hit.z), margin: 0.03) else { return nil }
        return plausibleHeight(hit.y - floorY)
    }

    /// Lower than LiDAR so the badge asks the user to check the size.
    static func confidence(heightFromSurface: Bool) -> Double {
        heightFromSurface ? 0.75 : 0.65
    }

    private static func plausibleHeight(_ h: Float) -> Float? {
        h >= 0.005 && h <= 1.5 ? h : nil
    }
}
