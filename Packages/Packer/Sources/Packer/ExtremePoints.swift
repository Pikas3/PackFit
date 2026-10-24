import PackFitSchemas

struct Size: Equatable {
    var w: Double, h: Double, d: Double
}

struct Point: Equatable {
    var x: Double, y: Double, z: Double
}

/// Candidate positions for a box of size (w, h, d), best first.
///
/// Extreme points in the floor plane: x from the left wall, the right wall, and both sides of
/// every placed item (snug against its right edge or its left edge); z likewise. Each (x, z) is dropped under gravity onto the highest
/// surface its footprint overlaps, so candidates never intersect anything below and are
/// never under anything. Sorted by (y, z, x): lowest, then back-most, then left-most; with
/// `frontFirst`, front-most instead of back-most (toward a clamshell's lid).
func candidatePoints(
    w: Double, h: Double, d: Double, placed: [Placement], size: Size, frontFirst: Bool = false
) -> [Point] {
    let xs = edges(placed.flatMap { [$0.x + $0.w, $0.x - w] } + [size.w - w], limit: size.w - w)
    let zs = edges(placed.flatMap { [$0.z + $0.d, $0.z - d] } + [size.d - d], limit: size.d - d)
    var points: [Point] = []
    points.reserveCapacity(xs.count * zs.count)
    var column: [(z0: Double, z1: Double, top: Double)] = []
    column.reserveCapacity(placed.count)
    for x in xs {
        // Items overlapping this x band; only they can be under the candidate.
        column.removeAll(keepingCapacity: true)
        for p in placed where overlap(x, x + w, p.x, p.x + p.w) > eps {
            column.append((p.z, p.z + p.d, p.y + p.h))
        }
        for z in zs {
            var y = 0.0
            for c in column where overlap(z, z + d, c.z0, c.z1) > eps {
                y = max(y, c.top)
            }
            if y + h <= size.h + eps {
                points.append(Point(x: x, y: y, z: z))
            }
        }
    }
    if frontFirst {
        points.sort { ($0.y, -$0.z, $0.x) < ($1.y, -$1.z, $1.x) }
    } else {
        points.sort { ($0.y, $0.z, $0.x) < ($1.y, $1.z, $1.x) }
    }
    return points
}

/// 0 plus the given edges inside [0, limit], sorted, near-duplicates merged.
private func edges(_ values: [Double], limit: Double) -> [Double] {
    var out: [Double] = []
    for v in ([0] + values).sorted() where v >= 0 && v <= limit + eps {
        if let last = out.last, v - last <= eps { continue }
        out.append(v)
    }
    return out
}

/// Length of the intersection of [a0, a1] and [b0, b1]; negative when they are apart.
func overlap(_ a0: Double, _ a1: Double, _ b0: Double, _ b1: Double) -> Double {
    min(a1, b1) - max(a0, b0)
}
