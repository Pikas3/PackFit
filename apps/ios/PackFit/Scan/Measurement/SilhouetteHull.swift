import Foundation
import simd

/// One camera view of the target: a pinhole camera and the target's outline in that image.
/// Sensor (landscape) orientation, like `DepthSnapshot`.
struct HullView: Sendable {
    let width: Int
    let height: Int
    /// Row-major, true inside the target's outline.
    let mask: [Bool]
    /// Intrinsics scaled to the mask resolution.
    let fx: Float, fy: Float, cx: Float, cy: Float
    let cameraToWorld: simd_float4x4

    var cameraPosition: SIMD3<Float> {
        SIMD3(cameraToWorld.columns.3.x, cameraToWorld.columns.3.y, cameraToWorld.columns.3.z)
    }

    /// Pixel coordinates of a world point, or nil behind the camera. Camera frame: x right,
    /// y up, z backward; image v runs down.
    func project(_ world: SIMD3<Float>) -> SIMD2<Float>? {
        let c = cameraToWorld.inverse * SIMD4(world, 1)
        let d = -c.z
        guard d > 0.05 else { return nil }
        return [c.x * fx / d + cx, -c.y * fy / d + cy]
    }

    func inside(_ px: SIMD2<Float>) -> Bool? {
        let u = Int(px.x.rounded(.down)), v = Int(px.y.rounded(.down))
        guard u >= 0, u < width, v >= 0, v < height else { return nil }
        return mask[v * width + u]
    }
}

/// Measures an object without depth by carving a voxel grid with its outline from several
/// camera poses (a visual hull). The grid stands on the floor around the tapped point.
///
/// The hull is exact at the floor and on the side walls once the views cover about 90° of
/// azimuth. Above the object it bulges into a roof, because elevated views can't see where the
/// top ends; so height is read at the edge of the footprint, where the roof meets the walls,
/// and from ARKit feature points on the top when there are enough.
struct VoxelHull: Sendable {
    struct Options: Sendable {
        /// Horizontal extent of the grid, metres.
        var size: Float = 0.9
        var maxHeight: Float = 0.6
        var cell: Float = 0.01
        var layer: Float = 0.005
        /// A voxel dies after this many views saw it outside the outline...
        var killVotes: UInt8 = 2
        /// ...and when at least this fraction of the views that saw it did. Keeps a few bad
        /// masks (occlusion, a flicker in segmentation) from cutting into the object.
        var killFraction: Float = 0.25
        /// A column needs this many views before it counts.
        var minSeen: UInt8 = 3
    }

    let options: Options
    let origin: SIMD3<Float>
    let cols: Int, rows: Int, layers: Int
    private(set) var outside: [UInt8]
    private(set) var seen: [UInt8]
    private(set) var viewCount = 0
    /// A floor point known to be on the object's outline, when the grid isn't centred on it.
    var anchor: SIMD2<Float>?
    /// Camera positions of the views carved so far.
    private(set) var cameras: [SIMD3<Float>] = []

    init(seed: SIMD3<Float>, floorY: Float, anchor: SIMD2<Float>? = nil, options: Options = Options()) {
        self.options = options
        self.anchor = anchor
        cols = Int((options.size / options.cell).rounded())
        rows = cols
        layers = Int((options.maxHeight / options.layer).rounded())
        origin = [seed.x - options.size / 2, floorY, seed.z - options.size / 2]
        outside = [UInt8](repeating: 0, count: cols * rows * layers)
        seen = outside
    }

    var floorY: Float { origin.y }
    var seedXZ: SIMD2<Float> { [origin.x + options.size / 2, origin.z + options.size / 2] }

    func columnCenter(_ c: Int, _ r: Int) -> SIMD2<Float> {
        [origin.x + (Float(c) + 0.5) * options.cell, origin.z + (Float(r) + 0.5) * options.cell]
    }

    @inline(__always) private func index(_ c: Int, _ r: Int, _ l: Int) -> Int { (r * cols + c) * layers + l }

    @inline(__always) func alive(_ i: Int) -> Bool {
        let o = outside[i]
        return o < options.killVotes || Float(o) < options.killFraction * Float(seen[i])
    }

    /// Carves with one view. Each column is projected incrementally: along a column only y
    /// changes, so camera coordinates step by a constant.
    mutating func carve(_ view: HullView) {
        let toCamera = view.cameraToWorld.inverse
        let up = SIMD3(toCamera.columns.1.x, toCamera.columns.1.y, toCamera.columns.1.z) * options.layer
        for r in 0..<rows {
            for c in 0..<cols {
                let p = columnCenter(c, r)
                let base = toCamera * SIMD4(p.x, origin.y + options.layer / 2, p.y, 1)
                var cam = SIMD3(base.x, base.y, base.z)
                let start = index(c, r, 0)
                for l in 0..<layers {
                    defer { cam += up }
                    let d = -cam.z
                    guard d > 0.05 else { continue }
                    let u = Int((cam.x * view.fx / d + view.cx).rounded(.down))
                    let v = Int((-cam.y * view.fy / d + view.cy).rounded(.down))
                    guard u >= 0, u < view.width, v >= 0, v < view.height else { continue }
                    let i = start + l
                    if seen[i] < .max { seen[i] += 1 }
                    if !view.mask[v * view.width + u], outside[i] < .max { outside[i] += 1 }
                }
            }
        }
        viewCount += 1
        cameras.append(view.cameraPosition)
    }

    /// Top of each column (metres above the floor), nil where the column is empty or has
    /// not been seen often enough. Layers are counted from the floor while they stay alive,
    /// allowing one dead layer so a mask flicker doesn't cut the column short.
    func columnTops() -> [Float?] {
        var tops = [Float?](repeating: nil, count: cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let start = index(c, r, 0)
                guard seen[start] >= options.minSeen else { continue }
                var top = -1, gap = 0
                for l in 0..<layers {
                    if alive(start + l) {
                        top = l
                        gap = 0
                    } else {
                        gap += 1
                        if gap > 1 { break }
                    }
                }
                // The bottom layers must be solid: a column alive only above the floor is
                // the roof of something else, not an object resting here.
                if top >= 1, alive(start), alive(start + 1) {
                    tops[r * cols + c] = Float(top + 1) * options.layer
                }
            }
        }
        return tops
    }

    /// Columns connected to the one nearest `anchor` (default: the grid centre, where the
    /// tap was). Other objects that ended up inside the grid (outlines merged in a frame or
    /// two) stay out.
    func seedComponent(_ tops: [Float?], anchor: SIMD2<Float>? = nil, maxDistance: Float = 0.06) -> [Int] {
        let a = anchor ?? seedXZ
        let seedCell = SIMD2((a.x - origin.x) / options.cell, (a.y - origin.z) / options.cell)
        var start: Int?
        var bestD = Float.infinity
        for r in 0..<rows {
            for c in 0..<cols where tops[r * cols + c] != nil {
                let d = simd_distance(SIMD2(Float(c) + 0.5, Float(r) + 0.5), seedCell)
                if d < bestD { bestD = d; start = r * cols + c }
            }
        }
        // The tap lands on the object, so its outline must come close to the anchor.
        guard let start, bestD * options.cell <= maxDistance else { return [] }
        var visited = [Bool](repeating: false, count: cols * rows)
        var stack = [start], out: [Int] = []
        visited[start] = true
        while let i = stack.popLast() {
            out.append(i)
            let c = i % cols, r = i / cols
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nc = c + dc, nr = r + dr
                guard nc >= 0, nc < cols, nr >= 0, nr < rows else { continue }
                let j = nr * cols + nc
                if !visited[j], tops[j] != nil {
                    visited[j] = true
                    stack.append(j)
                }
            }
        }
        return out.sorted()
    }
}

/// What the views around the object cover.
struct HullCoverage: Sendable, Equatable {
    /// Degrees of azimuth around the object seen, from 15° bins.
    var azimuthDegrees: Float
    /// Lowest and highest camera elevation above the floor as seen from the object, degrees.
    var lowestElevation: Float
    var highestElevation: Float
    var views: Int

    static let binDegrees: Float = 15

    /// The bins between the first and last view, the longest way round without a gap.
    init(cameras: [SIMD3<Float>], center: SIMD3<Float>) {
        views = cameras.count
        var bins = Set<Int>()
        var lowest: Float = 90, highest: Float = -90
        for cam in cameras {
            let v = cam - center
            let horizontal = simd_length(SIMD2(v.x, v.z))
            let az = atan2(v.z, v.x) * 180 / .pi
            let elevation = atan2(v.y, horizontal) * 180 / .pi
            lowest = min(lowest, elevation)
            highest = max(highest, elevation)
            // Near-vertical views say little about azimuth.
            if elevation < 70 {
                bins.insert(Int(((az + 360).truncatingRemainder(dividingBy: 360)) / Self.binDegrees))
            }
        }
        azimuthDegrees = Float(bins.count) * Self.binDegrees
        lowestElevation = lowest
        highestElevation = highest
    }

    var wideEnough: Bool { azimuthDegrees >= 90 }
    /// A low view bounds the height: elevated views can't see where the top ends.
    var hasLowView: Bool { lowestElevation <= 40 }
    /// A view from above bounds the far side: side views can't see behind the object.
    var hasTopView: Bool { highestElevation >= 70 }
    var complete: Bool { wideEnough && hasLowView && hasTopView && views >= 6 }
}

/// Turns a carved hull into a box.
enum HullFitter {
    struct Fit: Sendable, Equatable {
        var box: BoxFit
        var coverage: HullCoverage
        /// IoU of the box's outline with the observed ones (trimmed mean), 0 without views.
        var silhouetteScore: Float
        /// Height from feature points on the top, when there were enough.
        var pointHeight: Float?
        var confidence: Double
    }

    /// The hull's box, refined against `views` when given. `featurePoints` are ARKit's sparse
    /// world points (any, they are filtered here).
    /// `start` warm-starts the refinement from the previous fit.
    static func fit(_ hull: VoxelHull, views: [HullView] = [], featurePoints: [SIMD3<Float>] = [], start: BoxFit? = nil, minHeight: Float = 0.004) -> Fit? {
        guard let hullBox = initialBox(hull) else { return nil }
        let initial = start ?? hullBox
        var box = initial
        var score: Float = 0
        if !views.isEmpty {
            let refined = BoxSilhouetteFit.refine([initial], floorY: hull.floorY, views: views, minHeight: minHeight)
            box = refined.boxes[0]
            score = refined.score
        }
        box.height = max(box.height, minHeight)
        let pointHeight = heightFromPoints(featurePoints, rect: box.rect, floorY: hull.floorY, ceiling: box.height + 0.05)
        let coverage = HullCoverage(cameras: hull.cameras, center: [box.rect.center.x, hull.floorY + box.height / 2, box.rect.center.y])
        return Fit(
            box: box,
            coverage: coverage,
            silhouetteScore: score,
            pointHeight: pointHeight,
            confidence: confidence(coverage: coverage, fill: box.fillRatio, score: views.isEmpty ? nil : score,
                                   height: box.height, pointHeight: pointHeight)
        )
    }

    /// A first box from the hull's columns. Columns under half the typical height are the
    /// wedge behind the object that no camera saw past, so they don't widen the footprint.
    static func initialBox(_ hull: VoxelHull) -> BoxFit? {
        let tops = hull.columnTops()
        let cells = hull.seedComponent(tops, anchor: hull.anchor)
        guard cells.count >= 4 else { return nil }
        let heights = cells.compactMap { tops[$0] }.sorted()
        let median = RectFit.percentile(heights, 0.5)
        let solid = cells.filter { (tops[$0] ?? 0) >= 0.5 * median }
        let use = solid.count >= 4 ? solid : cells
        let points = use.map { hull.columnCenter($0 % hull.cols, $0 / hull.cols) }
        guard let rect = RectFit.minAreaRect(points, cell: hull.options.cell, trim: 0.005) else { return nil }
        let fill = Float(use.count) * hull.options.cell * hull.options.cell / max(rect.long * rect.short, 1e-6)
        return BoxFit(rect: rect, height: median, cellCount: use.count, fillRatio: min(fill, 1))
    }

    /// The 90th percentile height of feature points over the footprint, if there are 8 or
    /// more. Points under 4 mm are the floor.
    static func heightFromPoints(_ points: [SIMD3<Float>], rect: OrientedRect, floorY: Float, ceiling: Float) -> Float? {
        let inner = rect.expanded(by: -min(0.01, rect.short / 4))
        let hs = points
            .filter { inner.contains(SIMD2($0.x, $0.z)) }
            .map { $0.y - floorY }
            .filter { $0 > 0.004 && $0 <= ceiling + 0.02 }
            .sorted()
        guard hs.count >= 8 else { return nil }
        return RectFit.percentile(hs, 0.9)
    }

    /// Without LiDAR the best case stays below LiDAR's, so the badge asks for a check until
    /// the views are complete and the outline agrees with the box.
    static func confidence(coverage: HullCoverage, fill: Float, score: Float?, height: Float, pointHeight: Float?) -> Double {
        var c = 0.5
        if coverage.wideEnough { c += 0.1 }
        if coverage.hasLowView { c += 0.05 }
        if coverage.hasTopView { c += 0.05 }
        if let score {
            if score >= 0.85 { c += 0.15 } else if score >= 0.75 { c += 0.05 } else { c -= 0.1 }
        }
        if let pointHeight, abs(pointHeight - height) <= 0.02 { c += 0.05 }
        if fill < 0.6 { c -= 0.1 }
        // Missing the low or the top view leaves height or the far side unbounded.
        let cap = coverage.hasLowView && coverage.hasTopView ? 0.85 : 0.6
        return min(max(c, 0.5), cap)
    }
}

/// An open bag lying flat: one shell, or a clamshell with both halves side by side.
enum ShellSplitter {
    struct Shells: Sendable, Equatable {
        /// The half the user tapped, outer size, metres.
        var base: BoxFit
        /// The other half of a clamshell, when there is one.
        var lid: BoxFit?
    }

    /// Splits at a valley in the column heights across the middle of either axis (the
    /// hinge), else at the middle of the long axis when `expectTwo`. Each half starts from
    /// its rim height, then both are refined together against `views`. The base is the half
    /// holding `seed`.
    static func split(_ hull: VoxelHull, fit: BoxFit, seed: SIMD2<Float>, expectTwo: Bool, views: [HullView] = []) -> Shells {
        let tops = hull.columnTops()
        let cells = hull.seedComponent(tops, anchor: hull.anchor)
        let rect = fit.rect
        let samples: [(a: Float, b: Float, h: Float)] = cells.compactMap { i in
            guard let h = tops[i] else { return nil }
            let v = hull.columnCenter(i % hull.cols, i / hull.cols) - rect.center
            return (dot(v, rect.axisLong), dot(v, rect.axisShort), h)
        }

        func valley(alongLong: Bool) -> Float? {
            let half = (alongLong ? rect.long : rect.short) / 2
            let bin: Float = 0.02
            let n = Int((2 * half / bin).rounded(.up))
            guard n >= 10 else { return nil }
            var sums = [Float](repeating: 0, count: n), counts = [Int](repeating: 0, count: n)
            for s in samples {
                let x = alongLong ? s.a : s.b
                let k = min(max(Int((x + half) / bin), 0), n - 1)
                sums[k] += s.h
                counts[k] += 1
            }
            let profile = (0..<n).map { counts[$0] > 0 ? sums[$0] / Float(counts[$0]) : 0 }
            let lo = n * 3 / 10, hi = n * 7 / 10
            guard let k = (lo...hi).min(by: { (profile[$0], $0) < (profile[$1], $1) }) else { return nil }
            let left = profile[..<k].max() ?? 0, right = profile[(k + 1)...].max() ?? 0
            // A hinge drops well below both rims.
            guard profile[k] < 0.6 * min(left, right) else { return nil }
            return (Float(k) + 0.5) * bin - half
        }

        var cut: (alongLong: Bool, at: Float)?
        if let v = valley(alongLong: true) {
            cut = (true, v)
        } else if let v = valley(alongLong: false) {
            cut = (false, v)
        } else if expectTwo {
            cut = (true, 0)
        }
        guard let cut else {
            let one = views.isEmpty ? fit : BoxSilhouetteFit.refine([fit], floorY: hull.floorY, views: views).boxes[0]
            return Shells(base: one, lid: nil)
        }

        func half(_ positive: Bool) -> BoxFit {
            let axis = cut.alongLong ? rect.axisLong : rect.axisShort
            let full = cut.alongLong ? rect.long : rect.short
            let lo = positive ? cut.at : -full / 2
            let hi = positive ? full / 2 : cut.at
            let mine = samples.filter { s in
                let x = cut.alongLong ? s.a : s.b
                return x >= lo && x < hi
            }
            // Rim height: the outer edges of this half, away from the hinge.
            let edgeBand: Float = 0.04
            let rim = mine.filter { s in
                let x = cut.alongLong ? s.a : s.b
                let y = cut.alongLong ? s.b : s.a
                let other = cut.alongLong ? rect.short / 2 : rect.long / 2
                let farFromHinge = positive ? x > hi - edgeBand : x < lo + edgeBand
                return farFromHinge || abs(y) > other - edgeBand
            }.map(\.h).sorted()
            let height = rim.isEmpty ? fit.height : RectFit.percentile(rim, 0.75)
            var r = rect
            r.center = rect.center + axis * ((lo + hi) / 2)
            if cut.alongLong { r.long = hi - lo } else { r.short = hi - lo }
            if r.short > r.long {
                swap(&r.long, &r.short)
                r.yaw = OrientedRect.normalizedYaw(r.yaw + .pi / 2)
            }
            return BoxFit(rect: r, height: height, cellCount: mine.count, fillRatio: fit.fillRatio)
        }

        var pos = half(true), neg = half(false)
        if !views.isEmpty {
            let refined = BoxSilhouetteFit.refine([pos, neg], floorY: hull.floorY, views: views).boxes
            pos = refined[0]
            neg = refined[1]
        }
        let seedSide = dot(seed - rect.center, cut.alongLong ? rect.axisLong : rect.axisShort) >= cut.at
        return seedSide ? Shells(base: pos, lid: neg) : Shells(base: neg, lid: pos)
    }
}
