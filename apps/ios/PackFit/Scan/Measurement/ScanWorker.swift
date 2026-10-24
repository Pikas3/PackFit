import Foundation
import simd

/// Owns the height map, the bag stabilizer and the tapped item targets. Runs off the main
/// actor; the guided session sends it one depth snapshot per tick.
actor ScanWorker {
    enum Mode: Sendable {
        /// Fit the open bag around the point the user tapped.
        case bag(seed: SIMD2<Float>?)
        /// Measure each tapped item.
        case items
    }

    struct CavityState: Sendable {
        var fit: CavityFit
        var stable: Bool
        var confidence: Double
    }

    struct ItemState: Sendable, Identifiable {
        var id: Int
        var fit: BoxFit
        /// World y of the surface the item rests on.
        var floorY: Float
        var stable: Bool
        var confidence: Double
    }

    struct Result: Sendable {
        var floorY: Float?
        var cavity: CavityState?
        var cavityFailure: CavityFitter.Failure?
        var items: [ItemState] = []
        /// Targets that gave up without a fit.
        var failedItems: [Int] = []
    }

    /// One tapped item, refined over several frames.
    private struct Target {
        let id: Int
        let seed: SIMD3<Float>
        var cloud = ObjectCloud()
        var history: [BoxFit] = []
        var fit: BoxFit?
        var ground: Float?
        var ticks = 0
        var locked = false
        var fromMask = false
    }

    /// Ticks (5 Hz) before a target stops refining.
    private static let maxTicks = 20
    private static let settleTolerance: Float = 0.008

    private var map: HeightMap?
    private var cavity = FitStabilizer(tolerance: 0.015)
    private var lastCavity: CavityFit?
    private var confidenceEMA = 0.8
    private var targets: [Target] = []

    func reset() {
        map = nil
        cavity.reset()
        lastCavity = nil
        targets = []
    }

    func resetCavity() {
        cavity.reset()
        lastCavity = nil
    }

    func resetItems() {
        targets = []
    }

    func addTarget(id: Int, seed: SIMD3<Float>) {
        targets.append(Target(id: id, seed: seed))
    }

    func removeTarget(id: Int) {
        targets.removeAll { $0.id == id }
    }

    /// Merges the snapshot, then fits for `mode`. `planeFloorY` is ARKit's floor plane when
    /// it has one; otherwise the floor is estimated from the map. `image` is this frame's
    /// camera image while items are being measured.
    func process(_ snapshot: DepthSnapshot, image: UprightImage?, mode: Mode, planeFloorY: Float?) -> Result {
        let points = snapshot.worldPoints()
        if map == nil {
            guard points.count > 500 else { return Result() }
            let xs = points.map(\.x).sorted(), zs = points.map(\.z).sorted()
            map = HeightMap(center: [xs[xs.count / 2], zs[zs.count / 2]])
        }
        map!.merge(points)
        confidenceEMA += 0.2 * (snapshot.highConfidenceFraction - confidenceEMA)

        guard let floorY = planeFloorY ?? map!.estimatedFloorY() else { return Result() }
        var result = Result(floorY: floorY)

        switch mode {
        case .bag(let seed):
            guard let seed else { return result }
            let grid = map!.grid(floorY: floorY)
            switch CavityFitter.fit(grid, floorY: floorY, seed: seed) {
            case .success(let fit):
                cavity.update([fit.box])
                lastCavity = fit
            case .failure(let failure):
                cavity.update([])
                result.cavityFailure = failure
            }
            if let track = cavity.tracks.max(by: { $0.stableCount < $1.stableCount }), let last = lastCavity {
                let smoothed = CavityFit(box: track.fit, floorY: last.floorY)
                result.cavity = CavityState(
                    fit: smoothed,
                    stable: cavity.isStable(track),
                    confidence: MeasurementMath.fitConfidence(
                        highConfidenceFraction: confidenceEMA,
                        minSideCm: Double(track.fit.rect.short * 100),
                        cellCount: track.fit.cellCount,
                        fillRatio: Double(track.fit.fillRatio),
                        longSideCm: Double(track.fit.rect.long * 100),
                        maxLongSideCm: 110
                    )
                )
            }

        case .items:
            let labels = image.flatMap(Segmenter.labels(for:))
            var grid: HeightGrid?
            for i in targets.indices where !targets[i].locked {
                targets[i].ticks += 1
                if !refineFromMask(&targets[i], snapshot: snapshot, labels: labels, planeFloorY: floorY), !targets[i].fromMask {
                    if grid == nil { grid = map!.grid(floorY: floorY) }
                    refineFromDepth(&targets[i], grid: grid!, floorY: floorY)
                }
                settle(&targets[i])
            }
            for t in targets {
                guard let fit = t.fit, let ground = t.ground else {
                    if t.locked { result.failedItems.append(t.id) }
                    continue
                }
                result.items.append(ItemState(
                    id: t.id,
                    fit: fit,
                    floorY: ground,
                    stable: t.locked,
                    confidence: confidence(for: t, fit: fit)
                ))
            }
            targets.removeAll { $0.locked && $0.fit == nil }
        }
        return result
    }

    /// Adds this frame's masked points to the target. False when the image has no object
    /// under the seed or the mask is implausible (it swallowed the floor or a neighbour).
    private func refineFromMask(_ t: inout Target, snapshot: DepthSnapshot, labels: InstanceLabels?, planeFloorY: Float) -> Bool {
        guard let labels, let n = snapshot.project(t.seed),
              n.x > 0.02, n.x < 0.98, n.y > 0.02, n.y < 0.98,
              let instance = labels.instance(nearSensor: n) else { return false }
        let (w, h) = (snapshot.width, snapshot.height)
        let mask = labels.depthMask(instance, width: w, height: h)
        // Shrink away from the outline, where the mask and the depth disagree by a pixel or two.
        let core = PixelMask.erode(mask, width: w, height: h, by: 2)
        let near = PixelMask.dilate(mask, width: w, height: h, by: 2)
        let far = PixelMask.dilate(mask, width: w, height: h, by: 7)
        let ring = zip(far, near).map { $0 && !$1 }

        let points = snapshot.worldPoints(in: core)
        guard points.count >= 15 else { return false }
        let xs = points.map(\.x).sorted(), zs = points.map(\.z).sorted()
        let lo = SIMD2(RectFit.percentile(xs, 0.02), RectFit.percentile(zs, 0.02))
        let hi = SIMD2(RectFit.percentile(xs, 0.98), RectFit.percentile(zs, 0.98))
        guard simd_length(hi - lo) < 1.4 else { return false }
        let seed2 = SIMD2(t.seed.x, t.seed.z)
        guard seed2.x > lo.x - 0.05, seed2.x < hi.x + 0.05, seed2.y > lo.y - 0.05, seed2.y < hi.y + 0.05 else { return false }

        let ringYs = snapshot.worldPoints(in: ring).map(\.y).sorted()
        let ground = ringYs.count >= 20 ? RectFit.percentile(ringYs, 0.5) : planeFloorY
        // The ring can land on a neighbour; the ground is never above the tapped surface.
        t.cloud.merge(points, ground: min(ground, t.seed.y))
        guard let fit = t.cloud.fit() else { return false }
        t.fit = fit
        t.ground = t.cloud.ground
        t.fromMask = true
        t.history.append(fit)
        return true
    }

    private func refineFromDepth(_ t: inout Target, grid: HeightGrid, floorY: Float) {
        guard let (fit, ground) = SeedFitter.fit(grid, seed: [t.seed.x, t.seed.z]) else { return }
        t.fit = fit
        t.ground = floorY + ground
        t.history.append(fit)
    }

    /// Locks once three fits in a row agree, or when time runs out.
    private func settle(_ t: inout Target) {
        if t.history.count > 5 { t.history.removeFirst(t.history.count - 5) }
        let recent = t.history.suffix(3)
        if recent.count == 3, let first = recent.first {
            let agree = recent.allSatisfy { f in
                max(
                    distance(f.rect.center, first.rect.center),
                    abs(f.rect.long - first.rect.long),
                    abs(f.rect.short - first.rect.short),
                    abs(f.height - first.height)
                ) <= Self.settleTolerance
            }
            if agree { t.locked = true }
        }
        if t.ticks >= Self.maxTicks { t.locked = true }
    }

    private func confidence(for t: Target, fit: BoxFit) -> Double {
        let base = MeasurementMath.fitConfidence(
            highConfidenceFraction: confidenceEMA,
            minSideCm: Double(fit.rect.short * 100),
            cellCount: t.fromMask ? fit.cellCount / 4 : fit.cellCount,
            fillRatio: Double(fit.fillRatio),
            longSideCm: Double(fit.rect.long * 100)
        )
        // Without an image outline the footprint comes from 1 cm depth cells only.
        return t.fromMask ? base : max(0.5, base - 0.1)
    }
}
