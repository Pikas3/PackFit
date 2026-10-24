import Foundation
import simd

/// A height field over the floor: one value per 1 cm cell, in metres above the floor.
/// `heights` is NaN where the cell has never been seen.
struct HeightGrid: Sendable {
    let cols: Int
    let rows: Int
    let cell: Float
    /// World (x, z) of the min corner of cell (0, 0). Columns run along +x, rows along +z.
    let origin: SIMD2<Float>
    var heights: [Float]
    var hits: [UInt16]

    init(cols: Int, rows: Int, cell: Float, origin: SIMD2<Float>) {
        self.cols = cols
        self.rows = rows
        self.cell = cell
        self.origin = origin
        heights = Array(repeating: .nan, count: cols * rows)
        hits = Array(repeating: 0, count: cols * rows)
    }

    func center(of index: Int) -> SIMD2<Float> {
        origin + SIMD2(Float(index % cols) + 0.5, Float(index / cols) + 0.5) * cell
    }

    func index(of p: SIMD2<Float>) -> Int? {
        let c = Int(floor((p.x - origin.x) / cell)), r = Int(floor((p.y - origin.y) / cell))
        guard c >= 0, c < cols, r >= 0, r < rows else { return nil }
        return r * cols + c
    }
}

/// Persistent world-space height map built from many depth snapshots. Each cell keeps the
/// per-snapshot top height of the last few snapshots that saw it; the grid reports their
/// median, which rejects flying pixels at object edges.
struct HeightMap: Sendable {
    static let samplesPerCell = 8

    let cols: Int
    let rows: Int
    let cell: Float
    let origin: SIMD2<Float>
    private var samples: [Float]
    private var sampleCount: [UInt8]
    private var nextSample: [UInt8]
    private(set) var hits: [UInt16]
    private var scratch: [Float]

    init(center: SIMD2<Float>, size: Float = 4, cell: Float = 0.01) {
        let n = Int((size / cell).rounded())
        cols = n
        rows = n
        self.cell = cell
        origin = center - SIMD2(repeating: size / 2)
        samples = Array(repeating: 0, count: n * n * Self.samplesPerCell)
        sampleCount = Array(repeating: 0, count: n * n)
        nextSample = Array(repeating: 0, count: n * n)
        hits = Array(repeating: 0, count: n * n)
        scratch = Array(repeating: -.infinity, count: n * n)
    }

    /// Merges one snapshot's world points (metres).
    mutating func merge(_ points: [SIMD3<Float>]) {
        var touched: [Int] = []
        touched.reserveCapacity(4096)
        for p in points {
            let c = Int(floor((p.x - origin.x) / cell)), r = Int(floor((p.z - origin.y) / cell))
            guard c >= 0, c < cols, r >= 0, r < rows else { continue }
            let i = r * cols + c
            if scratch[i] == -.infinity { touched.append(i) }
            scratch[i] = max(scratch[i], p.y)
        }
        let k = Self.samplesPerCell
        for i in touched {
            samples[i * k + Int(nextSample[i])] = scratch[i]
            nextSample[i] = UInt8((Int(nextSample[i]) + 1) % k)
            sampleCount[i] = UInt8(min(Int(sampleCount[i]) + 1, k))
            hits[i] = hits[i] &+ (hits[i] == .max ? 0 : 1)
            scratch[i] = -.infinity
        }
    }

    /// Median absolute height (world y) of each seen cell; NaN where unseen.
    func absoluteHeights() -> [Float] {
        let k = Self.samplesPerCell
        var out = Array(repeating: Float.nan, count: cols * rows)
        var buf = [Float](repeating: 0, count: k)
        for i in 0..<(cols * rows) {
            let n = Int(sampleCount[i])
            guard n > 0 else { continue }
            for j in 0..<n { buf[j] = samples[i * k + j] }
            // Insertion sort on at most 8 values.
            for a in 1..<max(n, 1) {
                let v = buf[a]
                var b = a - 1
                while b >= 0 && buf[b] > v { buf[b + 1] = buf[b]; b -= 1 }
                buf[b + 1] = v
            }
            out[i] = n % 2 == 1 ? buf[n / 2] : (buf[n / 2 - 1] + buf[n / 2]) / 2
        }
        return out
    }

    /// The grid relative to `floorY`.
    func grid(floorY: Float) -> HeightGrid {
        var g = HeightGrid(cols: cols, rows: rows, cell: cell, origin: origin)
        g.heights = absoluteHeights().map { $0 - floorY }
        g.hits = hits
        return g
    }

    /// Floor estimate when ARKit has no plane: the 10th percentile of seen cell heights.
    func estimatedFloorY() -> Float? {
        let seen = absoluteHeights().filter { !$0.isNaN }.sorted()
        guard seen.count >= 100 else { return nil }
        return RectFit.percentile(seen, 0.1)
    }
}
