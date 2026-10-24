import Foundation
import simd

/// Owns the height map and the stabilizers. Runs off the main actor; the guided session
/// sends it one depth snapshot per tick.
actor ScanWorker {
    enum Mode: Sendable {
        /// Fit the open bag around the point the camera's centre ray hits.
        case bag
        /// Fit items on the floor, ignoring the bag and its lid.
        case items(bag: CavityFit?)
    }

    struct CavityState: Sendable {
        var fit: CavityFit
        var stable: Bool
        var confidence: Double
    }

    struct ItemState: Sendable, Identifiable {
        var id: Int
        var fit: BoxFit
        var floorY: Float
        var stable: Bool
        var confidence: Double
    }

    struct Result: Sendable {
        var floorY: Float?
        var cavity: CavityState?
        var cavityFailure: CavityFitter.Failure?
        var items: [ItemState] = []
    }

    private var map: HeightMap?
    private var items = FitStabilizer(tolerance: 0.01)
    private var cavity = FitStabilizer(tolerance: 0.015)
    private var lastCavity: CavityFit?
    private var confidenceEMA = 0.8

    func reset() {
        map = nil
        items.reset()
        cavity.reset()
        lastCavity = nil
    }

    func resetItems() {
        items.reset()
    }

    func suppressItem(id: Int) {
        items.suppress(id: id)
    }

    /// Merges the snapshot, then fits for `mode`. `planeFloorY` is ARKit's floor plane when
    /// it has one; otherwise the floor is estimated from the map.
    func process(_ snapshot: DepthSnapshot, mode: Mode, planeFloorY: Float?) -> Result {
        let points = snapshot.worldPoints()
        if map == nil {
            guard points.count > 500 else { return Result() }
            let xs = points.map(\.x).sorted(), zs = points.map(\.z).sorted()
            map = HeightMap(center: [xs[xs.count / 2], zs[zs.count / 2]])
        }
        map!.merge(points)
        confidenceEMA += 0.2 * (snapshot.highConfidenceFraction - confidenceEMA)

        guard let floorY = planeFloorY ?? map!.estimatedFloorY() else { return Result() }
        let grid = map!.grid(floorY: floorY)
        var result = Result(floorY: floorY)

        switch mode {
        case .bag:
            guard let seed = centreRayHit(snapshot) else { return result }
            switch CavityFitter.fit(grid, floorY: floorY, seed: SIMD2(seed.x, seed.z)) {
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

        case .items(let bag):
            var excluded: [OrientedRect] = []
            if let bag {
                // Shell walls plus a margin, and the opened lid on either side of the hinge.
                let shell = bag.box.rect.expanded(by: 0.13)
                excluded.append(shell)
                let offset = bag.box.rect.axisShort * (bag.box.rect.short + 0.1)
                for sign: Float in [-1, 1] {
                    excluded.append(OrientedRect(center: bag.box.rect.center + sign * offset, yaw: bag.box.rect.yaw, long: shell.long, short: shell.short))
                }
            }
            items.update(BoxFitter.fit(grid, excluding: excluded))
            result.items = items.tracks.map { track in
                ItemState(
                    id: track.id,
                    fit: track.fit,
                    floorY: floorY,
                    stable: items.isStable(track),
                    confidence: MeasurementMath.fitConfidence(
                        highConfidenceFraction: confidenceEMA,
                        minSideCm: Double(track.fit.rect.short * 100),
                        cellCount: track.fit.cellCount,
                        fillRatio: Double(track.fit.fillRatio),
                        longSideCm: Double(track.fit.rect.long * 100)
                    )
                )
            }
        }
        return result
    }

    /// World point under the middle of the depth image (the screen reticle): the median
    /// depth of a 5×5 patch, unprojected.
    private func centreRayHit(_ s: DepthSnapshot) -> SIMD3<Float>? {
        let cu = s.width / 2, cv = s.height / 2
        var ds: [Float] = []
        for v in (cv - 2)...(cv + 2) {
            for u in (cu - 2)...(cu + 2) where u >= 0 && v >= 0 && u < s.width && v < s.height {
                let i = v * s.width + u
                if s.confidence[i] >= 1, s.depth[i] > 0.1, s.depth[i] < 3 { ds.append(s.depth[i]) }
            }
        }
        guard ds.count >= 5 else { return nil }
        let d = ds.sorted()[ds.count / 2]
        let p = SIMD4<Float>((Float(cu) + 0.5 - s.cx) * d / s.fx, -(Float(cv) + 0.5 - s.cy) * d / s.fy, -d, 1)
        let w = s.cameraToWorld * p
        return SIMD3(w.x, w.y, w.z)
    }
}
