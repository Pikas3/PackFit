import Foundation
import simd

/// The inner cavity of an open suitcase shell lying on the floor.
struct CavityFit: Sendable, Equatable {
    /// Inner footprint; `height` is the shell depth from the cavity floor to the rim.
    var box: BoxFit
    /// World y of the cavity floor.
    var floorY: Float

    var shellDepth: Float { box.height }

    /// Container frame for the plan: origin at the inner bottom-left-back corner, y up,
    /// z toward the camera along the short side, x = y × z along the long side.
    func transform(cameraXZ: SIMD2<Float>) -> simd_float4x4 {
        let rect = box.rect
        var s = rect.axisShort
        if dot(cameraXZ - rect.center, s) < 0 { s = -s }
        let z = SIMD3<Float>(s.x, 0, s.y)
        let y = SIMD3<Float>(0, 1, 0)
        let x = cross(y, z)
        let c = SIMD3<Float>(rect.center.x, floorY, rect.center.y)
        let origin = c - x * (rect.long / 2) - z * (rect.short / 2)
        return simd_float4x4(
            SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(origin, 1)
        )
    }
}

/// Finds the cavity as the basin around a tapped seed point, bounded by the shell walls.
/// The water level rises until it spills over the walls; the cavity is the basin at half
/// that level, which takes in bumps on the floor (handle channels, seams) but not the walls.
/// The opened lid lies outside the walls, so it never joins the basin.
enum CavityFitter {
    enum Failure: Error, Equatable {
        case seedUnseen
        case leaked
        case tooSmall
        case noWalls
    }

    struct Options: Sendable {
        var minRise: Float = 0.02
        var maxRise: Float = 0.35
        var riseStep: Float = 0.01
        var maxExtent: Float = 1.2
        var minSide: Float = 0.2
        var rimBand = 3
        var minShellDepth: Float = 0.04
        /// How far a side may move out to its wall across cells hidden behind the near rim.
        var maxWallGap: Float = 0.15
    }

    static func fit(_ grid: HeightGrid, floorY: Float, seed: SIMD2<Float>, options: Options = Options()) -> Result<CavityFit, Failure> {
        guard let start = nearestSeen(grid, to: seed, radius: 3) else { return .failure(.seedUnseen) }
        let base = localHeight(grid, around: start, radius: 3)
        let maxCells = Int(options.maxExtent / grid.cell)

        var spill: Float?
        var level = options.minRise
        while level <= options.maxRise + 1e-4 {
            if flood(grid, from: start, limit: base + level, maxCells: maxCells) == nil {
                spill = level
                break
            }
            level += options.riseStep
        }
        let spillRise = spill ?? options.maxRise + options.riseStep
        guard spillRise > options.minRise + 1e-4 else { return .failure(.leaked) }
        let rise = max(options.minRise, min(spillRise - options.riseStep, spillRise / 2))
        guard let inBasin = flood(grid, from: start, limit: base + rise, maxCells: maxCells) else { return .failure(.leaked) }
        let basin = inBasin.indices.filter { inBasin[$0] }

        guard let rawRect = RectFit.minAreaRect(basin.map(grid.center(of:)), cell: grid.cell) else { return .failure(.tooSmall) }

        let floorHeights = basin.map { grid.heights[$0] }.sorted()
        let cavityFloor = RectFit.percentile(floorHeights, 0.5)

        // Rim: the walls are the highest cells in a thin band just outside the basin.
        var band: [Float] = []
        var seen = Set<Int>()
        for i in basin {
            let c = i % grid.cols, r = i / grid.cols
            for dr in -options.rimBand...options.rimBand {
                for dc in -options.rimBand...options.rimBand {
                    let cc = c + dc, rr = r + dr
                    guard cc >= 0, cc < grid.cols, rr >= 0, rr < grid.rows else { continue }
                    let j = rr * grid.cols + cc
                    if !inBasin[j], !grid.heights[j].isNaN, seen.insert(j).inserted { band.append(grid.heights[j]) }
                }
            }
        }
        let rimCandidates = band.filter { $0 > base + rise }.sorted()
        guard !rimCandidates.isEmpty else { return .failure(.noWalls) }
        let rim = RectFit.percentile(rimCandidates, 0.5)
        let depth = rim - cavityFloor
        guard depth >= options.minShellDepth else { return .failure(.noWalls) }

        let rect = expandToWalls(grid, rawRect, wallHeight: cavityFloor + 0.6 * depth, maxGap: options.maxWallGap)
        guard rect.short >= options.minSide else { return .failure(.tooSmall) }

        let fill = Float(basin.count) * grid.cell * grid.cell / (rect.long * rect.short)
        let box = BoxFit(rect: rect, height: depth, cellCount: basin.count, fillRatio: min(fill, 1))
        return .success(CavityFit(box: box, floorY: floorY + cavityFloor))
    }

    /// 4-connected seen cells no higher than `limit`. Nil when the water runs past
    /// `maxCells` from the start or off the grid: it spilled out of the bag.
    private static func flood(_ grid: HeightGrid, from start: Int, limit: Float, maxCells: Int) -> [Bool]? {
        let (sc, sr) = (start % grid.cols, start / grid.cols)
        var inBasin = [Bool](repeating: false, count: grid.cols * grid.rows)
        var stack = [start]
        inBasin[start] = true
        while let i = stack.popLast() {
            let c = i % grid.cols, r = i / grid.cols
            if abs(c - sc) > maxCells || abs(r - sr) > maxCells { return nil }
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let cc = c + dc, rr = r + dr
                guard cc >= 0, cc < grid.cols, rr >= 0, rr < grid.rows else { return nil }
                let j = rr * grid.cols + cc
                let h = grid.heights[j]
                if !inBasin[j], !h.isNaN, h <= limit {
                    inBasin[j] = true
                    stack.append(j)
                }
            }
        }
        return inBasin
    }

    /// The near wall hides a strip of floor behind it, so the basin stops short there. Each
    /// side moves out to the first wall cell found across the gap, by the median over
    /// several lines.
    private static func expandToWalls(_ grid: HeightGrid, _ rect: OrientedRect, wallHeight: Float, maxGap: Float) -> OrientedRect {
        var lo = SIMD2(-rect.long / 2, -rect.short / 2)
        var hi = SIMD2(rect.long / 2, rect.short / 2)
        func world(_ local: SIMD2<Float>) -> SIMD2<Float> {
            rect.center + rect.axisLong * local.x + rect.axisShort * local.y
        }
        for axis in 0..<2 {
            for sign: Float in [-1, 1] {
                let other = 1 - axis
                var gaps: [Float] = []
                for k in 1...7 {
                    var p = SIMD2<Float>.zero
                    p[other] = lo[other] + (hi[other] - lo[other]) * Float(k) / 8
                    p[axis] = sign < 0 ? lo[axis] : hi[axis]
                    var s: Float = 0
                    while s <= maxGap {
                        var q = p
                        q[axis] += sign * (s + grid.cell / 2)
                        if let i = grid.index(of: world(q)), !grid.heights[i].isNaN, grid.heights[i] >= wallHeight {
                            gaps.append(s)
                            break
                        }
                        s += grid.cell
                    }
                }
                guard gaps.count >= 3 else { continue }
                let gap = RectFit.percentile(gaps.sorted(), 0.5)
                if sign < 0 { lo[axis] -= gap } else { hi[axis] += gap }
            }
        }
        let center = world((lo + hi) / 2)
        var long = hi.x - lo.x, short = hi.y - lo.y
        var yaw = rect.yaw
        if short > long {
            swap(&long, &short)
            yaw += .pi / 2
        }
        return OrientedRect(center: center, yaw: OrientedRect.normalizedYaw(yaw), long: long, short: short)
    }

    private static func localHeight(_ grid: HeightGrid, around i: Int, radius: Int) -> Float {
        let c = i % grid.cols, r = i / grid.cols
        var hs: [Float] = []
        for rr in max(r - radius, 0)...min(r + radius, grid.rows - 1) {
            for cc in max(c - radius, 0)...min(c + radius, grid.cols - 1) {
                let h = grid.heights[rr * grid.cols + cc]
                if !h.isNaN { hs.append(h) }
            }
        }
        return RectFit.percentile(hs.sorted(), 0.5)
    }

    private static func nearestSeen(_ grid: HeightGrid, to p: SIMD2<Float>, radius: Int) -> Int? {
        guard let i = grid.index(of: p) else { return nil }
        if !grid.heights[i].isNaN { return i }
        let c = i % grid.cols, r = i / grid.cols
        var best: (Int, Int)?
        for dr in -radius...radius {
            for dc in -radius...radius {
                let cc = c + dc, rr = r + dr
                guard cc >= 0, cc < grid.cols, rr >= 0, rr < grid.rows else { continue }
                let j = rr * grid.cols + cc
                let d = dc * dc + dr * dr
                if !grid.heights[j].isNaN, best == nil || d < best!.1 { best = (j, d) }
            }
        }
        return best?.0
    }
}
