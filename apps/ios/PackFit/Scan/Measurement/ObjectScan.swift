import Foundation
import simd

/// Foreground instances found in the camera image, in the upright portrait orientation the
/// user sees. Label 0 is background.
struct InstanceLabels: Sendable {
    let width: Int
    let height: Int
    let labels: [UInt8]

    /// Sensor (landscape) normalized coordinates to upright portrait ones. The portrait image
    /// is the sensor image turned 90° clockwise (`CGImagePropertyOrientation.right`).
    static func upright(_ sensor: SIMD2<Float>) -> SIMD2<Float> { [1 - sensor.y, sensor.x] }

    func label(atSensor p: SIMD2<Float>) -> UInt8 {
        let q = Self.upright(p)
        let x = Int(q.x * Float(width)), y = Int(q.y * Float(height))
        guard x >= 0, x < width, y >= 0, y < height else { return 0 }
        return labels[y * width + x]
    }

    /// The instance under `p`, or the nearest one within `radius` (normalized), so a tap
    /// that lands just off a thin item still selects it.
    func instance(nearSensor p: SIMD2<Float>, radius: Float = 0.02) -> UInt8? {
        let direct = label(atSensor: p)
        if direct != 0 { return direct }
        let steps = 6
        var best: (label: UInt8, dist: Float)?
        for j in -steps...steps {
            for i in -steps...steps {
                let offset = SIMD2(Float(i), Float(j)) * (radius / Float(steps))
                let d = simd_length(offset)
                guard d <= radius else { continue }
                let l = label(atSensor: p + offset)
                if l != 0, best == nil || d < best!.dist { best = (l, d) }
            }
        }
        return best?.label
    }

    /// Mask of `target` at the depth map's resolution and sensor orientation.
    func depthMask(_ target: UInt8, width w: Int, height h: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: w * h)
        for v in 0..<h {
            for u in 0..<w {
                mask[v * w + u] = label(atSensor: [(Float(u) + 0.5) / Float(w), (Float(v) + 0.5) / Float(h)]) == target
            }
        }
        return mask
    }
}

/// Square-window binary morphology, separable so it stays cheap at 5 Hz.
enum PixelMask {
    static func dilate(_ mask: [Bool], width: Int, height: Int, by r: Int) -> [Bool] {
        guard r > 0 else { return mask }
        var rows = [Bool](repeating: false, count: mask.count)
        for y in 0..<height {
            // Two sweeps per row: distance to the nearest set pixel on each side.
            var last = Int.min / 2
            for x in 0..<width {
                if mask[y * width + x] { last = x }
                if x - last <= r { rows[y * width + x] = true }
            }
            last = Int.max / 2
            for x in stride(from: width - 1, through: 0, by: -1) {
                if mask[y * width + x] { last = x }
                if last - x <= r { rows[y * width + x] = true }
            }
        }
        var out = [Bool](repeating: false, count: mask.count)
        for x in 0..<width {
            var last = Int.min / 2
            for y in 0..<height {
                if rows[y * width + x] { last = y }
                if y - last <= r { out[y * width + x] = true }
            }
            last = Int.max / 2
            for y in stride(from: height - 1, through: 0, by: -1) {
                if rows[y * width + x] { last = y }
                if last - y <= r { out[y * width + x] = true }
            }
        }
        return out
    }

    static func erode(_ mask: [Bool], width: Int, height: Int, by r: Int) -> [Bool] {
        dilate(mask.map { !$0 }, width: width, height: height, by: r).map { !$0 }
    }
}

/// One tapped object's points gathered over several frames, binned into 5 mm floor cells.
/// Each cell keeps the top height of each frame that saw it, and the fit uses their median.
struct ObjectCloud: Sendable {
    static let cell: Float = 0.005
    static let samplesPerCell = 8

    private(set) var cells: [SIMD2<Int32>: [Float]] = [:]
    private(set) var frames = 0
    private var grounds: [Float] = []

    /// World y of the surface the object rests on: the median of each frame's estimate.
    var ground: Float? {
        guard !grounds.isEmpty else { return nil }
        return RectFit.percentile(grounds.sorted(), 0.5)
    }

    mutating func merge(_ points: [SIMD3<Float>], ground: Float) {
        var top: [SIMD2<Int32>: Float] = [:]
        for p in points {
            let k = Self.key(p)
            top[k] = max(top[k] ?? -.infinity, p.y)
        }
        for (k, y) in top {
            var s = cells[k] ?? []
            s.append(y)
            if s.count > Self.samplesPerCell { s.removeFirst() }
            cells[k] = s
        }
        frames += 1
        grounds.append(ground)
    }

    /// The object's box. Cells barely above the ground at the rim are mask spill onto the
    /// floor; they are dropped once the object's height is known.
    func fit(minHeight: Float = 0.004) -> BoxFit? {
        guard let ground else { return nil }
        let need = frames >= 3 ? 2 : 1
        let keys = cells.keys.filter { cells[$0]!.count >= need }.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard keys.count >= 8 else { return nil }
        let heights = keys.map { RectFit.percentile(cells[$0]!.sorted(), 0.5) - ground }
        let top = RectFit.percentile(heights.sorted(), 0.9)
        let height = max(top, minHeight)
        let floorCut = max(0.003, 0.25 * height)
        let kept = zip(keys, heights).filter { $0.1 >= floorCut }
        let centres = (kept.count >= 8 ? kept.map(\.0) : keys).map(Self.center)
        guard let rect = RectFit.minAreaRect(centres, cell: Self.cell, trim: 0.02) else { return nil }
        let fill = Float(centres.count) * Self.cell * Self.cell / (rect.long * rect.short)
        return BoxFit(rect: rect, height: height, cellCount: centres.count, fillRatio: min(fill, 1))
    }

    private static func key(_ p: SIMD3<Float>) -> SIMD2<Int32> {
        [Int32(floor(p.x / cell)), Int32(floor(p.z / cell))]
    }

    private static func center(_ k: SIMD2<Int32>) -> SIMD2<Float> {
        (SIMD2(Float(k.x), Float(k.y)) + 0.5) * cell
    }
}

/// Depth-only fallback when the camera image gives no mask under the tap: the cells joined
/// to the seed that stand clear of the ground right around them.
enum SeedFitter {
    struct Options: Sendable {
        var maxExtent: Float = 0.8
        var minRise: Float = 0.004
        var ringInner = 2
        var ringOuter = 5
    }

    /// `grid` heights are relative to some floor guess; the returned `ground` is in the same
    /// frame and comes from the cells around the object, so a wrong guess doesn't matter.
    static func fit(_ grid: HeightGrid, seed: SIMD2<Float>, options: Options = Options()) -> (fit: BoxFit, ground: Float)? {
        guard let start = nearestSeen(grid, to: seed, radius: 2) else { return nil }
        let (sc, sr) = (start % grid.cols, start / grid.cols)
        var near: [Float] = []
        for r in max(sr - 1, 0)...min(sr + 1, grid.rows - 1) {
            for c in max(sc - 1, 0)...min(sc + 1, grid.cols - 1) where !grid.heights[r * grid.cols + c].isNaN {
                near.append(grid.heights[r * grid.cols + c])
            }
        }
        let seedTop = RectFit.percentile(near.sorted(), 0.5)
        let reach = Int(options.maxExtent / grid.cell)

        guard var ground = surfaceHeight(grid, around: start, radius: reach / 2, below: seedTop - 0.003) else { return nil }
        var region: [Int] = []
        for _ in 0..<3 {
            let rise = seedTop - ground
            guard rise > options.minRise else { return nil }
            // Halfway up the object, but never more than 3 cm, so floor noise stays out and
            // a thin item still clears the cut.
            let cut = ground + min(max(0.4 * rise, 0.003), 0.03)
            guard let grown = grow(grid, from: start, above: cut, reach: reach) else { return nil }
            region = grown
            guard let ringGround = ringMedian(grid, region: region, inner: options.ringInner, outer: options.ringOuter) else { break }
            if abs(ringGround - ground) < 0.001 { break }
            ground = ringGround
        }
        guard region.count >= 4, let rect = RectFit.minAreaRect(region.map(grid.center(of:)), cell: grid.cell) else { return nil }
        let heights = region.map { grid.heights[$0] }.sorted()
        let height = RectFit.percentile(heights, 0.9) - ground
        guard height > options.minRise else { return nil }
        let fill = Float(region.count) * grid.cell * grid.cell / (rect.long * rect.short)
        return (BoxFit(rect: rect, height: height, cellCount: region.count, fillRatio: min(fill, 1)), ground)
    }

    /// 8-connected cells above `cut`. Nil when the region runs past `reach` cells from the
    /// seed: the seed is on a large surface, not an object.
    private static func grow(_ grid: HeightGrid, from start: Int, above cut: Float, reach: Int) -> [Int]? {
        guard grid.heights[start] >= cut else { return [start] }
        let (sc, sr) = (start % grid.cols, start / grid.cols)
        var seen = Set([start])
        var stack = [start]
        var out: [Int] = []
        while let i = stack.popLast() {
            out.append(i)
            let c = i % grid.cols, r = i / grid.cols
            if abs(c - sc) > reach || abs(r - sr) > reach { return nil }
            for dr in -1...1 {
                for dc in -1...1 where dr != 0 || dc != 0 {
                    let cc = c + dc, rr = r + dr
                    guard cc >= 0, cc < grid.cols, rr >= 0, rr < grid.rows else { return nil }
                    let j = rr * grid.cols + cc
                    let h = grid.heights[j]
                    if !h.isNaN, h >= cut, seen.insert(j).inserted { stack.append(j) }
                }
            }
        }
        return out.sorted()
    }

    /// The most common height (2 mm bins) below `limit` near the seed: the surface the item
    /// rests on, whether floor or table, and independent of ARKit's plane estimate.
    private static func surfaceHeight(_ grid: HeightGrid, around i: Int, radius: Int, below limit: Float) -> Float? {
        let c = i % grid.cols, r = i / grid.cols
        var bins: [Int: Int] = [:]
        for rr in max(r - radius, 0)...min(r + radius, grid.rows - 1) {
            for cc in max(c - radius, 0)...min(c + radius, grid.cols - 1) {
                let h = grid.heights[rr * grid.cols + cc]
                if !h.isNaN, h < limit { bins[Int(floor(h / 0.002)), default: 0] += 1 }
            }
        }
        guard let best = bins.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }), best.value >= 20 else { return nil }
        return (Float(best.key) + 0.5) * 0.002
    }

    /// Median height of seen cells between `inner` and `outer` cells outside the region.
    private static func ringMedian(_ grid: HeightGrid, region: [Int], inner: Int, outer: Int) -> Float? {
        let cs = region.map { $0 % grid.cols }, rs = region.map { $0 / grid.cols }
        let c0 = max(cs.min()! - outer, 0), c1 = min(cs.max()! + outer, grid.cols - 1)
        let r0 = max(rs.min()! - outer, 0), r1 = min(rs.max()! + outer, grid.rows - 1)
        let w = c1 - c0 + 1, h = r1 - r0 + 1
        var mask = [Bool](repeating: false, count: w * h)
        for i in region { mask[(i / grid.cols - r0) * w + (i % grid.cols - c0)] = true }
        let near = PixelMask.dilate(mask, width: w, height: h, by: inner)
        let far = PixelMask.dilate(mask, width: w, height: h, by: outer)
        var ring: [Float] = []
        for y in 0..<h {
            for x in 0..<w where far[y * w + x] && !near[y * w + x] {
                let v = grid.heights[(y + r0) * grid.cols + (x + c0)]
                if !v.isNaN { ring.append(v) }
            }
        }
        guard ring.count >= 10 else { return nil }
        return RectFit.percentile(ring.sorted(), 0.5)
    }

    private static func nearestSeen(_ grid: HeightGrid, to p: SIMD2<Float>, radius: Int) -> Int? {
        guard let i = grid.index(of: p) else { return nil }
        if !grid.heights[i].isNaN { return i }
        let c = i % grid.cols, r = i / grid.cols
        var best: (index: Int, dist: Int)?
        for dr in -radius...radius {
            for dc in -radius...radius {
                let cc = c + dc, rr = r + dr
                guard cc >= 0, cc < grid.cols, rr >= 0, rr < grid.rows else { continue }
                let j = rr * grid.cols + cc
                let d = dc * dc + dr * dr
                if !grid.heights[j].isNaN, best == nil || d < best!.dist { best = (j, d) }
            }
        }
        return best?.index
    }
}
