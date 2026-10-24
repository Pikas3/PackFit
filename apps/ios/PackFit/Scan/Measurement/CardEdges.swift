import CoreGraphics
import Foundation
import simd

/// 8-bit luminance copy of an image, origin top-left, for sampling edges.
struct GrayImage: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(_ image: CGImage) {
        let (w, h) = (image.width, image.height)
        guard w > 0, h > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: w * h)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        (width, height, pixels) = (w, h, buffer)
    }

    /// Bilinear sample at a pixel position (pixel centres at +0.5), clamped to the image.
    func sample(_ p: SIMD2<Double>) -> Double {
        let x = min(max(p.x - 0.5, 0), Double(width - 1)), y = min(max(p.y - 0.5, 0), Double(height - 1))
        let x0 = Int(x), y0 = Int(y), x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = x - Double(x0), fy = y - Double(y0)
        func at(_ x: Int, _ y: Int) -> Double { Double(pixels[y * width + x]) }
        let top = at(x0, y0) * (1 - fx) + at(x1, y0) * fx
        let bottom = at(x0, y1) * (1 - fx) + at(x1, y1) * fx
        return top * (1 - fy) + bottom * fy
    }
}

/// Sharpens a card's corners. Cards have rounded corners, so a rectangle detector's corners
/// are guesses; the four edges are straight. Each edge is found along its middle 60% as the
/// strongest brightness step across it, a line is fitted through those points, and the
/// corners are where neighbouring lines meet.
enum CardEdges {
    /// Nil when an edge cannot be found or a corner would move implausibly far. Two passes:
    /// a wide search (Vision's corners can be 15 px off on a card 100 px tall), then a tight
    /// one around the edges the first pass found.
    static func refine(_ quad: ImageQuad, in image: GrayImage) -> ImageQuad? {
        guard quad.corners.count == 4,
              let coarse = refine(quad, in: image, reach: { min(30, max(6, $0 * 0.2)) }),
              let fine = refine(coarse, in: image, reach: { _ in 3 }) else { return nil }
        for i in 0..<4 where simd_distance(fine.corners[i], quad.corners[i]) > max(4, quad.shortestSide * 0.3) {
            return nil
        }
        return fine
    }

    private static func refine(_ quad: ImageQuad, in image: GrayImage, reach reachFor: (Double) -> Double) -> ImageQuad? {
        var lines: [(point: SIMD2<Double>, direction: SIMD2<Double>)] = []
        for i in 0..<4 {
            let a = quad.corners[i], b = quad.corners[(i + 1) % 4]
            let length = simd_distance(a, b)
            guard length > 16 else { return nil }
            let along = (b - a) / length, across = SIMD2(-along.y, along.x)
            let reach = reachFor(length)
            // Average a short stretch along the edge so floor texture does not win.
            let spread = min(4, length * 0.03)
            func brightness(_ p: SIMD2<Double>) -> Double {
                [-1.0, -0.5, 0, 0.5, 1].reduce(0) { $0 + image.sample(p + along * ($1 * spread)) } / 5
            }
            var found: [(point: SIMD2<Double>, rising: Bool)] = []
            for k in 0..<24 {
                let base = a + (b - a) * (0.2 + 0.6 * Double(k) / 23)
                let offsets = stride(from: -reach, through: reach, by: 0.5).map { $0 }
                let signed = offsets.map { brightness(base + across * ($0 + 0.5)) - brightness(base + across * ($0 - 0.5)) }
                let steps = signed.map(abs)
                guard let m = steps.indices.max(by: { steps[$0] < steps[$1] }), steps[m] > 6 else { continue }
                var offset = offsets[m]
                if m > 0, m < steps.count - 1 {
                    let (l, c, r) = (steps[m - 1], steps[m], steps[m + 1])
                    let curve = l - 2 * c + r
                    if abs(curve) > 1e-9 { offset += 0.5 * 0.5 * (l - r) / curve }
                }
                found.append((base + across * offset, signed[m] > 0))
            }
            // The card is darker (or lighter) than the floor all along one edge: drop steps
            // that go the other way, which are texture.
            let rising = found.filter(\.rising).count * 2 >= found.count
            let points = found.filter { $0.rising == rising }.map(\.point)
            guard points.count >= 8, let line = fitLine(points) else { return nil }
            lines.append(line)
        }
        var corners: [SIMD2<Double>] = []
        for i in 0..<4 {
            // Corner i joins the edge ending there and the edge starting there.
            guard let p = intersect(lines[(i + 3) % 4], lines[i]) else { return nil }
            corners.append(p)
        }
        return ImageQuad(corners: corners)
    }

    /// Total least squares, refitted once without points far off the first line.
    static func fitLine(_ points: [SIMD2<Double>]) -> (point: SIMD2<Double>, direction: SIMD2<Double>)? {
        func fit(_ pts: [SIMD2<Double>]) -> (point: SIMD2<Double>, direction: SIMD2<Double>)? {
            guard pts.count >= 2 else { return nil }
            let mean = pts.reduce(.zero, +) / Double(pts.count)
            var sxx = 0.0, sxy = 0.0, syy = 0.0
            for p in pts {
                let d = p - mean
                sxx += d.x * d.x; sxy += d.x * d.y; syy += d.y * d.y
            }
            let angle = 0.5 * atan2(2 * sxy, sxx - syy)
            return (mean, SIMD2(cos(angle), sin(angle)))
        }
        guard let first = fit(points) else { return nil }
        func residual(_ p: SIMD2<Double>) -> Double {
            let d = p - first.point
            return abs(d.x * first.direction.y - d.y * first.direction.x)
        }
        let sorted = points.map(residual).sorted()
        let limit = max(0.75, 2.5 * sorted[sorted.count / 2])
        return fit(points.filter { residual($0) <= limit }) ?? first
    }

    static func intersect(_ l1: (point: SIMD2<Double>, direction: SIMD2<Double>), _ l2: (point: SIMD2<Double>, direction: SIMD2<Double>)) -> SIMD2<Double>? {
        let cross = l1.direction.x * l2.direction.y - l1.direction.y * l2.direction.x
        guard abs(cross) > 1e-6 else { return nil }
        let d = l2.point - l1.point
        let t = (d.x * l2.direction.y - d.y * l2.direction.x) / cross
        return l1.point + l1.direction * t
    }
}
