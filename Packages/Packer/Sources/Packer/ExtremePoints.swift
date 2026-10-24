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
/// never under anything. Sorted by (y, z, x): lowest, then back-most, then left-most.
func candidatePoints(
    w: Double, h: Double, d: Double, placed: [Placement], size: Size
) -> [Point] {
    let xs = edges(placed, alongX: true, size: w, limit: size.w - w)
    let zs = edges(placed, alongX: false, size: d, limit: size.d - d)
    var points: [Point] = []
    points.reserveCapacity(xs.count * zs.count)
    var column: [ColumnItem] = []
    column.reserveCapacity(placed.count)
    for x in xs {
        // Items overlapping this x band; only they can be under the candidate.
        column.removeAll(keepingCapacity: true)
        for p in placed where overlap(x, x + w, p.x, p.x + p.w) > eps {
            column.append(ColumnItem(z0: p.z, z1: p.z + p.d, top: p.y + p.h))
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
    // Plain comparisons rather than tuple keys: this sort runs for every item and
    // orientation, and tuple comparison is slow outside optimised builds.
    points.sort { a, b in
        if a.y != b.y { return a.y < b.y }
        if a.z != b.z { return a.z < b.z }
        return a.x < b.x
    }
    return points
}

/// A placed item under an x band: its z extent and top.
private struct ColumnItem {
    var z0: Double, z1: Double, top: Double
}

/// Positions along one axis for a box of `size`: 0, the far wall (`limit`), and snug
/// against either side of every placed item, kept inside [0, limit], sorted, with
/// near-duplicates merged. One buffer, no per-item arrays: this runs for every candidate set.
private func edges(_ placed: [Placement], alongX: Bool, size: Double, limit: Double) -> [Double] {
    var values: [Double] = []
    values.reserveCapacity(placed.count * 2 + 2)
    values.append(0)
    values.append(limit)
    for p in placed {
        let start = alongX ? p.x : p.z
        values.append(start + (alongX ? p.w : p.d))
        values.append(start - size)
    }
    values.sort()
    var out: [Double] = []
    out.reserveCapacity(values.count)
    for v in values where v >= 0 && v <= limit + eps {
        if let last = out.last, v - last <= eps { continue }
        out.append(v)
    }
    return out
}

/// Length of the intersection of [a0, a1] and [b0, b1]; negative when they are apart.
func overlap(_ a0: Double, _ a1: Double, _ b0: Double, _ b1: Double) -> Double {
    min(a1, b1) - max(a0, b0)
}
