import Foundation
import simd

/// One object found on the floor: an oriented footprint plus a height. Metres.
struct BoxFit: Sendable, Equatable {
    var rect: OrientedRect
    var height: Float
    var cellCount: Int
    /// Seen cells over the rectangle's area. Low values mean merged clutter.
    var fillRatio: Float

    var dimsCm: (w: Double, h: Double, d: Double) {
        MeasurementMath.dimsCm(widthM: Double(rect.long), heightM: Double(height), depthM: Double(rect.short))
    }
}

/// Splits a height grid into separate objects and boxes each one.
enum BoxFitter {
    struct Options: Sendable {
        var minHeight: Float = 0.012
        var minHits: UInt16 = 3
        var minSide: Float = 0.02
        var minFill: Float = 0.4
        var maxLong: Float = 1.2
        var dilation = 1
    }

    static func fit(_ grid: HeightGrid, excluding: [OrientedRect] = [], options: Options = Options()) -> [BoxFit] {
        var mask = [Bool](repeating: false, count: grid.cols * grid.rows)
        for i in mask.indices {
            let h = grid.heights[i]
            guard !h.isNaN, h > options.minHeight, grid.hits[i] >= options.minHits else { continue }
            if !excluding.isEmpty {
                let p = grid.center(of: i)
                if excluding.contains(where: { $0.contains(p) }) { continue }
            }
            mask[i] = true
        }

        var fits: [BoxFit] = []
        for cells in components(mask: mask, cols: grid.cols, rows: grid.rows, dilation: options.dilation) {
            let points = cells.map(grid.center(of:))
            guard let rect = RectFit.minAreaRect(points, cell: grid.cell) else { continue }
            let heights = cells.map { grid.heights[$0] }.sorted()
            let height = RectFit.percentile(heights, 0.98)
            let fill = Float(cells.count) * grid.cell * grid.cell / (rect.long * rect.short)
            guard rect.short >= options.minSide, rect.long <= options.maxLong, fill >= options.minFill else { continue }
            fits.append(BoxFit(rect: rect, height: height, cellCount: cells.count, fillRatio: min(fill, 1)))
        }
        return fits.sorted { $0.rect.center.x != $1.rect.center.x ? $0.rect.center.x < $1.rect.center.x : $0.rect.center.y < $1.rect.center.y }
    }

    /// 8-connected components of `mask` after dilating by `dilation` cells, so items with a
    /// one-cell gap of missing depth stay whole. Each component lists only original cells,
    /// in ascending index order.
    static func components(mask: [Bool], cols: Int, rows: Int, dilation: Int) -> [[Int]] {
        var grown = mask
        if dilation > 0 {
            for i in mask.indices where mask[i] {
                let c = i % cols, r = i / cols
                for dr in -dilation...dilation {
                    for dc in -dilation...dilation {
                        let cc = c + dc, rr = r + dr
                        if cc >= 0, cc < cols, rr >= 0, rr < rows { grown[rr * cols + cc] = true }
                    }
                }
            }
        }
        var label = [Int32](repeating: -1, count: mask.count)
        var result: [[Int]] = []
        var stack: [Int] = []
        for start in grown.indices where grown[start] && label[start] < 0 {
            let id = Int32(result.count)
            var cells: [Int] = []
            label[start] = id
            stack.append(start)
            while let i = stack.popLast() {
                if mask[i] { cells.append(i) }
                let c = i % cols, r = i / cols
                for dr in -1...1 {
                    for dc in -1...1 where dr != 0 || dc != 0 {
                        let cc = c + dc, rr = r + dr
                        guard cc >= 0, cc < cols, rr >= 0, rr < rows else { continue }
                        let j = rr * cols + cc
                        if grown[j] && label[j] < 0 {
                            label[j] = id
                            stack.append(j)
                        }
                    }
                }
            }
            result.append(cells.sorted())
        }
        return result.filter { !$0.isEmpty }
    }
}
