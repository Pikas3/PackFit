import Foundation
import Testing
import simd
@testable import PackFit

// MARK: - Synthetic scenes

/// Deterministic noise so the tests never flake.
private struct LCG {
    var state: UInt64
    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(state >> 40) / Float(1 << 24)
    }
}

private func floorGrid(size: Float = 2, noise: Float = 0.002, seed: UInt64 = 7) -> HeightGrid {
    let n = Int(size / 0.01)
    var g = HeightGrid(cols: n, rows: n, cell: 0.01, origin: [-size / 2, -size / 2])
    var rng = LCG(state: seed)
    for i in g.heights.indices {
        g.heights[i] = (rng.next() - 0.5) * 2 * noise
        g.hits[i] = 5
    }
    return g
}

private extension HeightGrid {
    mutating func paint(_ rect: OrientedRect, height: Float) {
        for i in heights.indices where rect.contains(center(of: i)) { heights[i] = height }
    }
}

private func rect(_ x: Float, _ z: Float, yawDeg: Float = 0, long: Float, short: Float) -> OrientedRect {
    OrientedRect(center: [x, z], yaw: yawDeg * .pi / 180, long: long, short: short)
}

private func yawError(_ a: Float, _ b: Float) -> Float {
    var d = abs(a - b).truncatingRemainder(dividingBy: .pi)
    if d > .pi / 2 { d = .pi - d }
    return d * 180 / .pi
}

// MARK: - HeightMap

struct HeightMapTests {
    @Test func mergeKeepsMedianTopHeightAndCounts() {
        var map = HeightMap(center: [0, 0], size: 1)
        map.merge([[0.005, 0.10, 0.005], [0.005, 0.12, 0.005], [0.205, 0.30, 0.205]])
        map.merge([[0.005, 0.10, 0.005]])
        map.merge([[0.005, 0.11, 0.005]])
        let grid = map.grid(floorY: 0.01)
        let a = grid.index(of: [0.005, 0.005])!
        let b = grid.index(of: [0.205, 0.205])!
        #expect(abs(grid.heights[a] - 0.10) < 1e-5)
        #expect(grid.hits[a] == 3)
        #expect(abs(grid.heights[b] - 0.29) < 1e-5)
        #expect(grid.hits[b] == 1)
        #expect(grid.heights[0].isNaN)
    }

    @Test func pointsOutsideTheMapAreIgnored() {
        var map = HeightMap(center: [0, 0], size: 1)
        map.merge([[5, 0, 5], [-0.6, 0, 0]])
        #expect(map.hits.allSatisfy { $0 == 0 })
    }
}

// MARK: - BoxFitter

struct BoxFitterTests {
    @Test func findsThreeSeparateBoxes() throws {
        var g = floorGrid()
        let truth = [
            (rect(-0.5, 0, long: 0.30, short: 0.20), Float(0.10)),
            (rect(0, 0, yawDeg: 30, long: 0.25, short: 0.15), Float(0.05)),
            (rect(0.5, 0.3, yawDeg: 0, long: 0.12, short: 0.10), Float(0.20)),
        ]
        for (r, h) in truth { g.paint(r, height: h) }

        let fits = BoxFitter.fit(g)
        try #require(fits.count == 3)
        for (fit, (r, h)) in zip(fits, truth) {
            #expect(abs(fit.rect.long - r.long) <= 0.01, "long \(fit.rect.long) vs \(r.long)")
            #expect(abs(fit.rect.short - r.short) <= 0.01, "short \(fit.rect.short) vs \(r.short)")
            #expect(abs(fit.height - h) <= 0.005)
            #expect(distance(fit.rect.center, r.center) <= 0.01)
            #expect(fit.fillRatio > 0.8)
        }
        #expect(yawError(fits[0].rect.yaw, 0) <= 2)
        #expect(yawError(fits[1].rect.yaw, 30 * .pi / 180) <= 3)
    }

    @Test func touchingBoxesMergeIntoOne() {
        var g = floorGrid()
        g.paint(rect(-0.1025, 0, long: 0.20, short: 0.20), height: 0.08)
        g.paint(rect(0.1025, 0, long: 0.20, short: 0.20), height: 0.08)
        #expect(BoxFitter.fit(g).count == 1)
    }

    @Test func sparseClutterIsDropped() {
        var g = floorGrid()
        var rng = LCG(state: 42)
        for i in g.heights.indices where rect(0, 0, long: 0.4, short: 0.4).contains(g.center(of: i)) {
            if rng.next() < 0.3 { g.heights[i] = 0.03 }
        }
        #expect(BoxFitter.fit(g).isEmpty)
    }

    @Test func excludedAreaIsIgnored() {
        var g = floorGrid()
        g.paint(rect(-0.4, 0, long: 0.3, short: 0.2), height: 0.1)
        g.paint(rect(0.4, 0, long: 0.2, short: 0.1), height: 0.1)
        let fits = BoxFitter.fit(g, excluding: [rect(-0.4, 0, long: 0.3, short: 0.2).expanded(by: 0.1)])
        #expect(fits.count == 1)
        #expect(abs(fits[0].rect.center.x - 0.4) < 0.01)
    }

    @Test func cellsSeenTooFewTimesDoNotCount() {
        var g = floorGrid()
        g.paint(rect(0, 0, long: 0.2, short: 0.2), height: 0.1)
        for i in g.hits.indices { g.hits[i] = 2 }
        #expect(BoxFitter.fit(g).isEmpty)
    }
}

// MARK: - CavityFitter

struct CavityFitterTests {
    /// Open shell, 78×53 outer and 72×47 inner, 13 cm walls, cavity floor at 2 cm, rotated
    /// 20°, with the opened lid lying beside it on the far side.
    private func shellScene() -> (HeightGrid, OrientedRect) {
        var g = floorGrid()
        let outer = rect(0, 0.1, yawDeg: 20, long: 0.78, short: 0.53)
        let lid = OrientedRect(center: outer.center - outer.axisShort * 0.55, yaw: outer.yaw, long: 0.78, short: 0.53)
        g.paint(lid, height: 0.04)
        g.paint(outer, height: 0.13)
        g.paint(OrientedRect(center: outer.center, yaw: outer.yaw, long: 0.72, short: 0.47), height: 0.02)
        return (g, outer)
    }

    @Test func measuresInnerCavity() throws {
        let (g, outer) = shellScene()
        let fit = try CavityFitter.fit(g, floorY: 0, seed: outer.center).get()
        #expect(abs(fit.box.rect.long - 0.72) <= 0.015)
        #expect(abs(fit.box.rect.short - 0.47) <= 0.015)
        #expect(abs(fit.shellDepth - 0.11) <= 0.01)
        #expect(abs(fit.floorY - 0.02) <= 0.005)
        #expect(yawError(fit.box.rect.yaw, outer.yaw) <= 2)
    }

    @Test func frameHasOriginAtFarLeftCorner() throws {
        let (g, outer) = shellScene()
        let fit = try CavityFitter.fit(g, floorY: 0, seed: outer.center).get()
        let camera = outer.center + outer.axisShort * 1.0
        let t = fit.transform(cameraXZ: camera)
        let x = SIMD3(t.columns.0.x, t.columns.0.y, t.columns.0.z)
        let y = SIMD3(t.columns.1.x, t.columns.1.y, t.columns.1.z)
        let z = SIMD3(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        let o = SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)

        #expect(abs(length(x) - 1) < 1e-4 && abs(length(y) - 1) < 1e-4 && abs(length(z) - 1) < 1e-4)
        #expect(abs(dot(x, y)) < 1e-4 && abs(dot(y, z)) < 1e-4 && abs(dot(x, z)) < 1e-4)
        #expect(simd_length(cross(x, y) - z) < 1e-4, "right-handed")
        // z points toward the camera.
        let toCamera = SIMD3(camera.x - outer.center.x, 0, camera.y - outer.center.y)
        #expect(dot(z, toCamera) > 0)
        // Origin is the inner corner on the far (back) side, at the cavity floor.
        let c = SIMD3(outer.center.x, Float(0.02), outer.center.y)
        let expected = c - x * 0.36 - z * 0.235
        #expect(simd_distance(o, expected) <= 0.015)
        #expect(dot(o - c, toCamera) < 0)
    }

    @Test func cameraOnTheOtherSideFlipsBackAndFront() throws {
        let (g, outer) = shellScene()
        let fit = try CavityFitter.fit(g, floorY: 0, seed: outer.center).get()
        let front = fit.transform(cameraXZ: outer.center + outer.axisShort)
        let back = fit.transform(cameraXZ: outer.center - outer.axisShort)
        #expect(simd_length(front.columns.2 + back.columns.2) < 1e-4)
        #expect(simd_length(front.columns.0 + back.columns.0) < 1e-4)
    }

    @Test func seedOnOpenFloorLeaks() {
        let (g, _) = shellScene()
        let result = CavityFitter.fit(g, floorY: 0, seed: [0.8, 0.8])
        #expect(result == .failure(.leaked))
    }
}

// MARK: - FitStabilizer

struct FitStabilizerTests {
    private func box(_ x: Float, long: Float = 0.2) -> BoxFit {
        BoxFit(rect: rect(x, 0, long: long, short: 0.1), height: 0.05, cellCount: 200, fillRatio: 0.95)
    }

    @Test func settlesAfterSixConsistentFits() {
        var s = FitStabilizer(tolerance: 0.01)
        for n in 1...6 {
            s.update([box(0, long: 0.2 + (n % 2 == 0 ? 0.003 : 0))])
            #expect(s.stableTracks.count == (n == 6 ? 1 : 0))
        }
        s.update([box(0, long: 0.25)])
        #expect(s.stableTracks.isEmpty)
    }

    @Test func keepsIdsAcrossUpdates() {
        var s = FitStabilizer(tolerance: 0.01)
        s.update([box(-0.3), box(0.3)])
        let ids = s.tracks.map(\.id)
        s.update([box(0.31), box(-0.29)])
        #expect(s.tracks.count == 2)
        #expect(s.tracks.map(\.id) == ids)
        #expect(abs(s.tracks[1].fit.rect.center.x - 0.304) < 1e-4)
    }

    @Test func suppressedFitsStayGone() {
        var s = FitStabilizer(tolerance: 0.01)
        s.update([box(0)])
        s.suppress(id: s.tracks[0].id)
        s.update([box(0.01)])
        #expect(s.tracks.isEmpty)
    }

    @Test func missingTracksExpire() {
        var s = FitStabilizer(tolerance: 0.01)
        s.update([box(0)])
        for _ in 0..<5 { s.update([]) }
        #expect(s.tracks.count == 1)
        s.update([])
        #expect(s.tracks.isEmpty)
    }
}

// MARK: - Depth snapshot, confidence, container mapping

struct DepthSnapshotTests {
    @Test func unprojectsCentrePixelStraightAhead() {
        var conf = [UInt8](repeating: 2, count: 9)
        conf[0] = 1
        let snap = DepthSnapshot(
            width: 3, height: 3, depth: Array(repeating: 1, count: 9), confidence: conf,
            fx: 1, fy: 1, cx: 1.5, cy: 1.5, cameraToWorld: matrix_identity_float4x4, timestamp: 0,
            videoWidth: 3, videoHeight: 3
        )
        let points = snap.worldPoints()
        #expect(points.count == 8)
        #expect(points.contains { simd_distance($0, [0, 0, -1]) < 1e-5 })
        // Pixel (2, 0) is right of and above centre.
        #expect(points.contains { simd_distance($0, [1, 1, -1]) < 1e-5 })
    }
}

struct FitConfidenceTests {
    @Test func cleanFitScoresHigh() {
        let c = MeasurementMath.fitConfidence(highConfidenceFraction: 0.9, minSideCm: 10, cellCount: 400, fillRatio: 0.9, longSideCm: 30)
        #expect(c == 0.95)
    }

    @Test func penaltiesFloorAtHalf() {
        let c = MeasurementMath.fitConfidence(highConfidenceFraction: 0.2, minSideCm: 2, cellCount: 5, fillRatio: 0.45, longSideCm: 150)
        #expect(c == 0.5)
    }
}

struct ContainerMappingTests {
    @Test func cavityBecomesTwoSidedClamshell() {
        let bag = ContainerFactory.fromCavity(innerLongCm: 72, innerShortCm: 47, shellDepthCm: 11, confidence: 0.9)
        #expect(bag.compartments.map(\.name) == ["base", "lid"])
        #expect(bag.compartments.map(\.dims) == [[72, 11, 47], [72, 11, 47]])
        #expect(bag.outer == [78, 28, 53])
        #expect(bag.wheelsSide == .back)
        #expect(bag.measurement?.method == .lidar)
        #expect(bag.type == .suitcase)
    }

    @Test func applyingTwoSidedSplitsPreset() {
        let single = ContainerFactory.custom(outer: [55, 23, 40], method: .manual, confidence: 1, shell: .single)
        let two = ContainerFactory.applying(.twoSided, to: single)
        #expect(two.compartments.map(\.name) == ["base", "lid"])
        #expect(two.compartments[0].dims[1] == two.compartments[1].dims[1])
        #expect(two.compartments[0].dims[1] * 2 == single.compartments[0].dims[1]
            || abs(two.compartments[0].dims[1] * 2 - single.compartments[0].dims[1]) < 0.2)
        let bounds = ContainerFactory.openBoundsCm(of: two)
        #expect(bounds[2] > two.compartments[0].dims[2])
    }
}
