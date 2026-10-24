import CoreGraphics
import Foundation
import simd

/// Which image pixels belong to one object.
struct ObjectMask: Sendable {
    /// Where to look, in image pixels. Everything outside counts as background.
    var region: CGRect
    var contains: @Sendable (SIMD2<Double>) -> Bool
    /// False when the outline had to be cut by Claude's rough box (two touching objects
    /// segmented as one), so its edges there are guesses.
    var fromSegmentation: Bool
    /// True when the object runs off the edge of the photo, so part of it is not seen.
    var touchesImageEdge: Bool
}

/// The solid fitted to an object's outline. Cans and bottles are cylinders; a box fit to a
/// cylinder's outline comes out too deep.
enum ObjectShape: String, Sendable, CaseIterable {
    case box
    case uprightCylinder = "cylinder_upright"
    case lyingCylinder = "cylinder_lying"
}

/// A solid resting on the floor, in plane cm (see `PlanePose`). For a cylinder, `long` and
/// `short` are its footprint: diameter × diameter standing, length × diameter lying.
struct CardBoxFit: Sendable {
    var shape: ObjectShape = .box
    var center: SIMD2<Double>
    var yaw: Double
    var long: Double
    var short: Double
    var height: Double
    /// Overlap between the projected solid and the object's outline, 0-1.
    var iou: Double
    /// False when the photo looks almost straight down, so height barely changes the outline.
    var heightReliable: Bool
    /// False when the photo is nearly level with the floor, so depth is squashed.
    var footprintReliable: Bool
    /// The fitted solid's outline in image pixels, for drawing over the photo.
    var outline: [SIMD2<Double>] = []
}

/// Fits a floor-standing solid to an object's outline in one photo, given the floor pose from
/// the card. The solid is the one whose projection through the camera best overlaps the outline.
enum SilhouetteFit {
    /// The solid's size and place, decoded from the optimiser's parameters (sizes are logs so
    /// they stay positive):
    /// - box: cx, cy, yaw, ln w, ln d, ln h
    /// - upright cylinder: cx, cy, ln diameter, ln h
    /// - lying cylinder: cx, cy, yaw, ln length, ln diameter
    struct Body {
        var center: SIMD2<Double>
        var yaw: Double
        var w: Double
        var d: Double
        var h: Double

        /// `w` runs along `yaw`. For cylinders: upright w = d = diameter; lying w = length, d = h = diameter.
        init(center: SIMD2<Double>, yaw: Double, w: Double, d: Double, h: Double) {
            (self.center, self.yaw, self.w, self.d, self.h) = (center, yaw, w, d, h)
        }

        init(_ x: [Double], shape: ObjectShape) {
            center = SIMD2(x[0], x[1])
            switch shape {
            case .box:
                (yaw, w, d, h) = (x[2], exp(x[3]), exp(x[4]), exp(x[5]))
            case .uprightCylinder:
                (yaw, w, d, h) = (0, exp(x[2]), exp(x[2]), exp(x[3]))
            case .lyingCylinder:
                (yaw, w, d, h) = (x[2], exp(x[3]), exp(x[4]), exp(x[4]))
            }
        }
    }

    static func fit(_ mask: ObjectMask, pose: PlanePose, shape: ObjectShape = .box, gridCells: Int = 48) -> CardBoxFit? {
        guard let grid = Grid(mask: mask, cells: gridCells) else { return nil }
        let starts = initialGuesses(grid: grid, pose: pose).map { parameters(fromBox: $0, shape: shape) }
        guard !starts.isEmpty else { return nil }

        // One view cannot tell a tall thin bottle from one that runs far back behind its own
        // front face: both cast the same outline. Among solids that match the outline equally,
        // a tiny volume penalty picks the smallest, the tightest one the photo supports.
        let objective: ([Double]) -> Double = {
            let b = Body($0, shape: shape)
            return cost($0, shape: shape, grid: grid, pose: pose) + 0.005 * log(b.w * b.d * b.h)
        }
        let yawOffsets: [Double] = switch shape {
        case .box: [0, .pi / 4]
        case .uprightCylinder: [0]
        case .lyingCylinder: [0, .pi / 2]
        }
        var best: (x: [Double], cost: Double)?
        for start in starts {
            for yawOffset in yawOffsets {
                var x = start
                if shape != .uprightCylinder { x[2] += yawOffset }
                var result = nelderMead(x, steps: steps(for: x, shape: shape), iterations: 220, objective)
                result = nelderMead(result.x, steps: steps(for: result.x, shape: shape), iterations: 120, objective)
                if result.cost < (best?.cost ?? .infinity) { best = result }
            }
        }
        guard let best else { return nil }
        let mismatch = cost(best.x, shape: shape, grid: grid, pose: pose)
        guard mismatch < 0.85 else { return nil }

        let body = Body(best.x, shape: shape)
        let elevation = pose.viewElevation(at: body.center)
        var yaw = body.w >= body.d ? body.yaw : body.yaw + .pi / 2
        yaw = yaw.truncatingRemainder(dividingBy: .pi)
        if yaw < 0 { yaw += .pi }
        return CardBoxFit(
            shape: shape,
            center: body.center,
            yaw: yaw,
            long: max(body.w, body.d),
            short: min(body.w, body.d),
            height: body.h,
            iou: 1 - mismatch,
            heightReliable: elevation < 75,
            footprintReliable: elevation > 20,
            outline: silhouette(body, shape: shape, pose: pose) ?? []
        )
    }

    /// A box start (cx, cy, yaw, ln long, ln short, ln h) as parameters for `shape`.
    static func parameters(fromBox x: [Double], shape: ObjectShape) -> [Double] {
        switch shape {
        case .box: x
        // Standing: as wide as the base, as tall as the outline.
        case .uprightCylinder: [x[0], x[1], x[3], x[5]]
        // Lying: along the base's long side, as thick as the outline is tall.
        case .lyingCylinder: [x[0], x[1], x[2], x[3], min(x[3], x[5])]
        }
    }

    /// Confidence for packing, 0.35-0.85. A card photo never beats LiDAR.
    static func confidence(_ fit: CardBoxFit, mask: ObjectMask, pose: PlanePose) -> Double {
        var c = 0.85
        if fit.iou < 0.75 { c -= 0.1 }
        if fit.iou < 0.6 { c -= 0.15 }
        if pose.error > 0.1 { c -= 0.1 }
        if pose.card.shortestSide < 80 { c -= 0.1 }
        if !fit.heightReliable { c -= 0.15 }
        if !fit.footprintReliable { c -= 0.1 }
        if !mask.fromSegmentation { c -= 0.15 }
        if mask.touchesImageEdge { c -= 0.15 }
        return max(0.35, c)
    }

    // MARK: Grid of outline coverage

    struct Grid {
        let origin: SIMD2<Double>
        let cell: Double
        let cols: Int
        let rows: Int
        /// Fraction of each cell inside the outline (2 × 2 samples).
        let coverage: [Double]

        init?(mask: ObjectMask, cells: Int) {
            let r = mask.region
            guard r.width > 2, r.height > 2 else { return nil }
            cell = Double(max(r.width, r.height)) / Double(cells)
            cols = max(2, Int((Double(r.width) / cell).rounded(.up)))
            rows = max(2, Int((Double(r.height) / cell).rounded(.up)))
            origin = [Double(r.minX), Double(r.minY)]
            var cov = [Double](repeating: 0, count: cols * rows)
            let offsets: [SIMD2<Double>] = [[0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]]
            for row in 0..<rows {
                for col in 0..<cols {
                    var n = 0
                    for o in offsets where mask.contains(origin + (SIMD2(Double(col), Double(row)) + o) * cell) { n += 1 }
                    cov[row * cols + col] = Double(n) / 4
                }
            }
            guard cov.reduce(0, +) >= 4 else { return nil }
            coverage = cov
        }

        func center(col: Int, row: Int) -> SIMD2<Double> {
            origin + (SIMD2(Double(col), Double(row)) + 0.5) * cell
        }
    }

    // MARK: Start point

    /// Two starting boxes. Footprint: where the outline meets the floor, i.e. the lowest outline
    /// pixel in each column, keeping only columns that reach down near the object's base (with
    /// perspective, the top of a tall object overhangs its base, and those columns never touch
    /// the floor). Compact: a square as wide as the base. Height from the top of the outline.
    static func initialGuesses(grid: Grid, pose: PlanePose) -> [[Double]] {
        var lowestByCol: [(col: Int, row: Int)] = []
        var topRow = Int.max, topCol = 0
        for col in 0..<grid.cols {
            var lowest: Int?
            for row in 0..<grid.rows where grid.coverage[row * grid.cols + col] > 0.5 {
                lowest = row
                if row < topRow { (topRow, topCol) = (row, col) }
            }
            if let lowest { lowestByCol.append((col, lowest)) }
        }
        guard lowestByCol.count >= 2, topRow != .max else { return [] }
        let base = lowestByCol.map(\.row).max()!
        let reach = max(2, (base - topRow) / 2)
        let contacts: [SIMD2<Double>] = lowestByCol.filter { base - $0.row <= reach }.compactMap {
            pose.floorPoint(grid.origin + SIMD2(Double($0.col) + 0.5, Double($0.row) + 1) * grid.cell)
        }
        guard contacts.count >= 2 else { return [] }

        func height(above center: SIMD2<Double>, fallback: Double) -> Double {
            let (o, d) = pose.ray(grid.origin + SIMD2(Double(topCol) + 0.5, Double(topRow)) * grid.cell)
            let dxy = SIMD2(d.x, d.y)
            var h = fallback
            if length_squared(dxy) > 1e-6 {
                let s = dot(center - SIMD2(o.x, o.y), dxy) / length_squared(dxy)
                if s > 0 { h = o.z + s * d.z }
            }
            return min(max(h, 0.5), 200)
        }

        var starts: [[Double]] = []
        let floats = contacts.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
        if let rect = RectFit.minAreaRect(floats, cell: 0, trim: 0.02) {
            let long = max(Double(rect.long), 1)
            let short = max(Double(rect.short), long * 0.3) // one visible face: depth unknown
            let center = SIMD2(Double(rect.center.x), Double(rect.center.y))
            starts.append([center.x, center.y, Double(rect.yaw), log(long), log(short), log(height(above: center, fallback: long * 0.3))])
        }

        // Compact: square as wide as the base, its front at the base's middle.
        let xs = contacts.map(\.x), ys = contacts.map(\.y)
        let width = max(1, max(xs.max()! - xs.min()!, ys.max()! - ys.min()!))
        let front = contacts.reduce(.zero, +) / Double(contacts.count)
        let away = normalize(front - SIMD2(pose.cameraPosition.x, pose.cameraPosition.y))
        let center = front + away * (width / 2)
        let yaw = atan2(away.y, away.x)
        starts.append([center.x, center.y, yaw, log(width), log(width), log(height(above: center, fallback: width))])
        return starts
    }

    private static func steps(for x: [Double], shape: ObjectShape) -> [Double] {
        let body = Body(x, shape: shape)
        let size = max(body.w, body.d)
        return switch shape {
        case .box: [size * 0.1, size * 0.1, 0.2, 0.15, 0.15, 0.2]
        case .uprightCylinder: [size * 0.1, size * 0.1, 0.15, 0.2]
        case .lyingCylinder: [size * 0.1, size * 0.1, 0.2, 0.15, 0.15]
        }
    }

    // MARK: Cost: 1 - soft IoU of projected solid and outline

    static func cost(_ x: [Double], shape: ObjectShape = .box, grid: Grid, pose: PlanePose) -> Double {
        let body = Body(x, shape: shape)
        guard [body.w, body.d, body.h].allSatisfy({ $0 > 0.3 && $0 < 300 }) else { return 1 }
        guard let hull = silhouette(body, shape: shape, pose: pose) else { return 1 }
        var inter = 0.0, union = 0.0
        for row in 0..<grid.rows {
            for col in 0..<grid.cols {
                let m = grid.coverage[row * grid.cols + col]
                let s = coverage(of: grid.center(col: col, row: row), in: hull, softness: grid.cell)
                inter += min(m, s)
                union += max(m, s)
            }
        }
        return union > 0 ? 1 - inter / union : 1
    }

    /// Image outline of the solid: convex hull of its projected corners (box) or of its two end
    /// circles (cylinder), which for a convex solid is exactly its silhouette.
    static func silhouette(_ body: Body, shape: ObjectShape, pose: PlanePose) -> [SIMD2<Double>]? {
        let along = SIMD2(cos(body.yaw), sin(body.yaw)), across = SIMD2(-sin(body.yaw), cos(body.yaw))
        var points: [SIMD3<Double>] = []
        let ring = (0..<20).map { Double($0) * 2 * .pi / 20 }
        switch shape {
        case .box:
            let u = along * (body.w / 2), v = across * (body.d / 2)
            for foot in [body.center - u - v, body.center + u - v, body.center + u + v, body.center - u + v] {
                points += [SIMD3(foot.x, foot.y, 0), SIMD3(foot.x, foot.y, body.h)]
            }
        case .uprightCylinder:
            let r = body.w / 2
            for a in ring {
                let p = body.center + SIMD2(cos(a), sin(a)) * r
                points += [SIMD3(p.x, p.y, 0), SIMD3(p.x, p.y, body.h)]
            }
        case .lyingCylinder:
            let r = body.d / 2
            for end in [body.center - along * (body.w / 2), body.center + along * (body.w / 2)] {
                for a in ring {
                    let p = end + across * (r * cos(a))
                    points.append(SIMD3(p.x, p.y, r + r * sin(a)))
                }
            }
        }
        var projected: [SIMD2<Double>] = []
        for p in points {
            guard let q = pose.project(p) else { return nil }
            projected.append(q)
        }
        return convexHull(projected)
    }

    /// 1 well inside, 0 well outside, linear across one `softness` band at the edge.
    static func coverage(of p: SIMD2<Double>, in hull: [SIMD2<Double>], softness: Double) -> Double {
        guard hull.count >= 3 else { return 0 }
        var inside = Double.infinity
        for i in hull.indices {
            let a = hull[i], b = hull[(i + 1) % hull.count]
            let e = b - a
            let len = length(e)
            guard len > 1e-9 else { continue }
            inside = min(inside, (e.x * (p.y - a.y) - e.y * (p.x - a.x)) / len)
        }
        return min(1, max(0, 0.5 + inside / softness))
    }

    /// Monotone chain; counter-clockwise in a y-up sense, which is what `coverage` expects.
    static func convexHull(_ points: [SIMD2<Double>]) -> [SIMD2<Double>] {
        let pts = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard pts.count > 2 else { return pts }
        func turn(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Double>] = []
        for p in pts {
            while lower.count >= 2 && turn(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [SIMD2<Double>] = []
        for p in pts.reversed() {
            while upper.count >= 2 && turn(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    // MARK: Nelder-Mead

    static func nelderMead(
        _ start: [Double],
        steps: [Double],
        iterations: Int,
        _ f: ([Double]) -> Double
    ) -> (x: [Double], cost: Double) {
        let n = start.count
        var simplex = [start]
        for i in 0..<n {
            var p = start
            p[i] += steps[i]
            simplex.append(p)
        }
        var values = simplex.map(f)
        for _ in 0..<iterations {
            let order = values.indices.sorted { values[$0] < values[$1] }
            simplex = order.map { simplex[$0] }
            values = order.map { values[$0] }
            if values[n] - values[0] < 1e-6 { break }

            var centroid = [Double](repeating: 0, count: n)
            for p in simplex.dropLast() { for i in 0..<n { centroid[i] += p[i] / Double(n) } }
            func along(_ t: Double) -> [Double] { (0..<n).map { centroid[$0] + t * (simplex[n][$0] - centroid[$0]) } }

            let reflected = along(-1), fr = f(reflected)
            if fr < values[0] {
                let expanded = along(-2), fe = f(expanded)
                (simplex[n], values[n]) = fe < fr ? (expanded, fe) : (reflected, fr)
            } else if fr < values[n - 1] {
                (simplex[n], values[n]) = (reflected, fr)
            } else {
                let contracted = along(fr < values[n] ? -0.5 : 0.5), fc = f(contracted)
                if fc < min(fr, values[n]) {
                    (simplex[n], values[n]) = (contracted, fc)
                } else {
                    for k in 1...n {
                        simplex[k] = (0..<n).map { simplex[0][$0] + 0.5 * (simplex[k][$0] - simplex[0][$0]) }
                        values[k] = f(simplex[k])
                    }
                }
            }
        }
        let i = values.indices.min { values[$0] < values[$1] }!
        return (simplex[i], values[i])
    }
}
