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

/// Finds the cavity as the basin around a seed point: cells no higher than the seed plus
/// `basinRise`, bounded by the shell walls. The opened lid lies outside the walls, so it
/// never joins the basin.
enum CavityFitter {
    enum Failure: Error, Equatable {
        case seedUnseen
        case leaked
        case tooSmall
        case noWalls
    }

    struct Options: Sendable {
        var basinRise: Float = 0.025
        var maxExtent: Float = 1.2
        var minSide: Float = 0.2
        var rimBand = 3
        var minShellDepth: Float = 0.04
    }

    static func fit(_ grid: HeightGrid, floorY: Float, seed: SIMD2<Float>, options: Options = Options()) -> Result<CavityFit, Failure> {
        guard let start = nearestSeen(grid, to: seed, radius: 3) else { return .failure(.seedUnseen) }
        let limit = grid.heights[start] + options.basinRise
        let maxCells = Int(options.maxExtent / grid.cell)
        let (sc, sr) = (start % grid.cols, start / grid.cols)

        var inBasin = [Bool](repeating: false, count: grid.cols * grid.rows)
        var basin: [Int] = []
        var stack = [start]
        inBasin[start] = true
        while let i = stack.popLast() {
            basin.append(i)
            let c = i % grid.cols, r = i / grid.cols
            if abs(c - sc) > maxCells || abs(r - sr) > maxCells { return .failure(.leaked) }
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let cc = c + dc, rr = r + dr
                guard cc >= 0, cc < grid.cols, rr >= 0, rr < grid.rows else { return .failure(.leaked) }
                let j = rr * grid.cols + cc
                let h = grid.heights[j]
                if !inBasin[j], !h.isNaN, h <= limit {
                    inBasin[j] = true
                    stack.append(j)
                }
            }
        }
        basin.sort()

        guard let rect = RectFit.minAreaRect(basin.map(grid.center(of:)), cell: grid.cell),
              rect.short >= options.minSide else { return .failure(.tooSmall) }

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
        let rimCandidates = band.filter { $0 > cavityFloor + options.basinRise }.sorted()
        guard !rimCandidates.isEmpty else { return .failure(.noWalls) }
        let rim = RectFit.percentile(rimCandidates, 0.5)
        let depth = rim - cavityFloor
        guard depth >= options.minShellDepth else { return .failure(.noWalls) }

        let fill = Float(basin.count) * grid.cell * grid.cell / (rect.long * rect.short)
        let box = BoxFit(rect: rect, height: depth, cellCount: basin.count, fillRatio: min(fill, 1))
        return .success(CavityFit(box: box, floorY: floorY + cavityFloor))
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
