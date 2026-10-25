import CoreGraphics
import Foundation
import simd

/// Pinhole camera in pixels of one image. Principal point usually at the image centre.
struct CameraIntrinsics: Sendable, Equatable {
    var fx: Double
    var fy: Double
    var cx: Double
    var cy: Double

    /// From the horizontal field of view of the sensor's long side, for an image of `width` × `height` px.
    static func fromFieldOfView(degrees: Double, width: Int, height: Int) -> CameraIntrinsics {
        let longSide = Double(max(width, height))
        let f = (longSide / 2) / tan(degrees * .pi / 360)
        return CameraIntrinsics(fx: f, fy: f, cx: Double(width) / 2, cy: Double(height) / 2)
    }

    func scaled(by s: Double) -> CameraIntrinsics {
        CameraIntrinsics(fx: fx * s, fy: fy * s, cx: cx * s, cy: cy * s)
    }
}

/// Four image corners of a quadrilateral, in pixels with origin top-left, in order around it.
struct ImageQuad: Sendable, Equatable {
    var corners: [SIMD2<Double>]

    var center: SIMD2<Double> { corners.reduce(.zero, +) / Double(corners.count) }

    var bounds: CGRect {
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// Shortest side in pixels; small cards measure badly.
    var shortestSide: Double {
        (0..<4).map { simd_distance(corners[$0], corners[($0 + 1) % 4]) }.min() ?? 0
    }

    func contains(_ p: SIMD2<Double>) -> Bool {
        var sign = 0.0
        for i in 0..<4 {
            let a = corners[i], b = corners[(i + 1) % 4]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if cross != 0 {
                if sign == 0 { sign = cross } else if (cross > 0) != (sign > 0) { return false }
            }
        }
        return true
    }
}

/// The floor plane recovered from a credit card lying on it.
///
/// Plane frame, in cm: origin at one card corner, x along the card's long side, y along its
/// short side, z up out of the floor toward the camera. Camera frame is the usual pinhole frame
/// (x right, y down, z forward). `camera = rotation * plane + translation`.
struct PlanePose: Sendable {
    /// ISO/IEC 7810 ID-1 (bank cards, most ID cards).
    static let cardLongCm = 8.560
    static let cardShortCm = 5.398

    var intrinsics: CameraIntrinsics
    var rotation: simd_double3x3
    var translation: SIMD3<Double>
    /// How far the card's corners are from a true ID-1 card seen through this camera: 0 is a
    /// perfect fit; above ~0.2 it is not a card, or the focal length is wrong.
    var error: Double
    var card: ImageQuad

    var cameraPosition: SIMD3<Double> { -(rotation.transpose * translation) }

    func project(_ p: SIMD3<Double>) -> SIMD2<Double>? {
        let c = rotation * p + translation
        guard c.z > 1e-6 else { return nil }
        return [intrinsics.fx * c.x / c.z + intrinsics.cx, intrinsics.fy * c.y / c.z + intrinsics.cy]
    }

    /// Ray through a pixel, in plane coordinates.
    func ray(_ pixel: SIMD2<Double>) -> (origin: SIMD3<Double>, direction: SIMD3<Double>) {
        let d = SIMD3<Double>((pixel.x - intrinsics.cx) / intrinsics.fx, (pixel.y - intrinsics.cy) / intrinsics.fy, 1)
        return (cameraPosition, normalize(rotation.transpose * d))
    }

    /// Where a pixel's ray meets the floor, in plane cm. Nil above the horizon.
    func floorPoint(_ pixel: SIMD2<Double>) -> SIMD2<Double>? {
        let (o, d) = ray(pixel)
        guard d.z < -1e-9 else { return nil }
        let s = -o.z / d.z
        return [o.x + s * d.x, o.y + s * d.y]
    }

    /// Angle between the line of sight to a floor point and the floor, in degrees (90 = straight down).
    func viewElevation(at floor: SIMD2<Double>) -> Double {
        let d = normalize(SIMD3<Double>(floor.x, floor.y, 0) - cameraPosition)
        return asin(min(1, abs(d.z))) * 180 / .pi
    }

    /// Recover the floor from the card's four image corners. Tries every way the card's corners
    /// can match the quad and keeps the one that best fits a real card in front of the camera.
    static func fromCard(_ quad: ImageQuad, intrinsics: CameraIntrinsics) -> PlanePose? {
        guard quad.corners.count == 4 else { return nil }
        let L = cardLongCm, S = cardShortCm
        let card: [SIMD2<Double>] = [[0, 0], [L, 0], [L, S], [0, S]]
        var best: PlanePose?
        for start in 0..<4 {
            for reversed in [false, true] {
                let image = (0..<4).map { i -> SIMD2<Double> in
                    let k = reversed ? (start - i + 4) % 4 : (start + i) % 4
                    return quad.corners[k]
                }
                guard let h = homography(from: card, to: image),
                      var pose = decompose(h, intrinsics: intrinsics) else { continue }
                pose.card = quad
                if pose.error < (best?.error ?? .infinity) { best = pose }
            }
        }
        return best
    }

    /// Plane → image homography from four correspondences (h33 = 1).
    static func homography(from src: [SIMD2<Double>], to dst: [SIMD2<Double>]) -> simd_double3x3? {
        var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let (x, y) = (src[i].x, src[i].y), (u, v) = (dst[i].x, dst[i].y)
            a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        guard let h = solve(a) else { return nil }
        return simd_double3x3(rows: [[h[0], h[1], h[2]], [h[3], h[4], h[5]], [h[6], h[7], 1]])
    }

    private static func decompose(_ h: simd_double3x3, intrinsics k: CameraIntrinsics) -> PlanePose? {
        let kInv = simd_double3x3(rows: [[1 / k.fx, 0, -k.cx / k.fx], [0, 1 / k.fy, -k.cy / k.fy], [0, 0, 1]])
        let m = kInv * h
        let h1 = m.columns.0, h2 = m.columns.1, h3 = m.columns.2
        let n1 = length(h1), n2 = length(h2)
        guard n1 > 1e-12, n2 > 1e-12 else { return nil }
        var s = 2 / (n1 + n2)
        if h3.z * s < 0 { s = -s } // the card is in front of the camera
        let r1 = normalize(h1 * s)
        let r2 = normalize(h2 * s - dot(h2 * s, r1) * r1)
        let r3 = cross(r1, r2)
        let t = h3 * s
        let rotation = simd_double3x3(columns: (r1, r2, r3))
        let error = abs(n1 - n2) / ((n1 + n2) / 2) + abs(dot(h1, h2)) / (n1 * n2)
        let pose = PlanePose(intrinsics: k, rotation: rotation, translation: t, error: error, card: ImageQuad(corners: []))
        // The camera must be above the floor (+z side), or this corner order is mirrored.
        guard pose.cameraPosition.z > 0 else { return nil }
        return pose
    }

    /// Gaussian elimination with partial pivoting on an n × (n+1) augmented matrix.
    private static func solve(_ m: [[Double]]) -> [Double]? {
        var a = m
        let n = a.count
        for col in 0..<n {
            guard let pivot = (col..<n).max(by: { abs(a[$0][col]) < abs(a[$1][col]) }),
                  abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot)
            for row in 0..<n where row != col {
                let f = a[row][col] / a[col][col]
                if f != 0 { for c in col...n { a[row][c] -= f * a[col][c] } }
            }
        }
        return (0..<n).map { a[$0][n] / a[$0][$0] }
    }

    /// Picks the card among rectangle candidates. Prefers quads inside `hint` (where the user
    /// tapped, or where Claude saw a card), then the best ID-1 fit. When `requireHint` is set,
    /// only a card in that region counts — nothing elsewhere. Nil when nothing plausibly is a card.
    static func bestCard(
        among quads: [ImageQuad],
        intrinsics: CameraIntrinsics,
        hint: CGRect? = nil,
        maxError: Double = 0.2,
        requireHint: Bool = false
    ) -> PlanePose? {
        let poses = quads.compactMap { fromCard($0, intrinsics: intrinsics) }.filter { $0.error <= maxError }
        if let hint {
            let expanded = hint.insetBy(dx: -hint.width * 0.25, dy: -hint.height * 0.25)
            let inside = poses.filter {
                expanded.contains(CGPoint(x: $0.card.center.x, y: $0.card.center.y))
            }
            if let pick = inside.min(by: { $0.error < $1.error }) { return pick }
            if requireHint { return nil }
        }
        return poses.min(by: { $0.error < $1.error })
    }
}
