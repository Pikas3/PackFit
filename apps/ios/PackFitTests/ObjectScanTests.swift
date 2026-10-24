import Foundation
import Testing
import simd
@testable import PackFit

/// Deterministic noise so the tests never flake.
private struct Noise {
    var state: UInt64
    /// Uniform in [-1, 1).
    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(state >> 40) / Float(1 << 23) - 1
    }
}

private func flatGrid(size: Float = 2, level: Float = 0, noise: Float = 0.002, seed: UInt64 = 3) -> HeightGrid {
    let n = Int(size / 0.01)
    var g = HeightGrid(cols: n, rows: n, cell: 0.01, origin: [-size / 2, -size / 2])
    var rng = Noise(state: seed)
    for i in g.heights.indices {
        g.heights[i] = level + rng.next() * noise
        g.hits[i] = 5
    }
    return g
}

private extension HeightGrid {
    mutating func paint(_ rect: OrientedRect, height: Float) {
        for i in heights.indices where rect.contains(center(of: i)) { heights[i] = height }
    }
}

/// Points a depth camera would return for a box: its top, the side facing the camera, and a
/// thin ring of floor where the image mask spills past the outline.
private func boxPoints(_ rect: OrientedRect, ground: Float, height: Float, spill: Float, rng: inout Noise) -> [SIMD3<Float>] {
    var out: [SIMD3<Float>] = []
    let step: Float = 0.002
    func world(_ a: Float, _ b: Float) -> SIMD2<Float> { rect.center + rect.axisLong * a + rect.axisShort * b }
    var a = -rect.long / 2 - spill
    while a <= rect.long / 2 + spill {
        var b = -rect.short / 2 - spill
        while b <= rect.short / 2 + spill {
            let p = world(a, b)
            let inside = abs(a) <= rect.long / 2 && abs(b) <= rect.short / 2
            let y = (inside ? ground + height : ground) + rng.next() * 0.0015
            out.append([p.x, y, p.y])
            b += step
        }
        a += step
    }
    var y: Float = 0
    while y < height {
        var a = -rect.long / 2
        while a <= rect.long / 2 {
            let p = world(a, rect.short / 2)
            out.append([p.x, ground + y, p.y])
            a += step
        }
        y += step
    }
    return out
}

struct InstanceLabelTests {
    /// 4 wide × 8 tall upright image whose right half is instance 1.
    private let labels = InstanceLabels(width: 4, height: 8, labels: (0..<32).map { $0 % 4 >= 2 ? 1 : 0 })

    @Test func sensorTopRowIsUprightRightColumn() {
        #expect(InstanceLabels.upright([0.1, 0.2]) == [0.8, 0.1])
        #expect(labels.label(atSensor: [0.5, 0.1]) == 1)
        #expect(labels.label(atSensor: [0.5, 0.9]) == 0)
    }

    @Test func depthMaskFollowsTheRotation() {
        let mask = labels.depthMask(1, width: 8, height: 4)
        for v in 0..<4 {
            for u in 0..<8 {
                #expect(mask[v * 8 + u] == (v < 2), "u \(u) v \(v)")
            }
        }
    }

    @Test func nearbyInstanceIsFoundWhenTheTapJustMisses() {
        #expect(labels.instance(nearSensor: [0.5, 0.51], radius: 0.05) == 1)
        #expect(labels.instance(nearSensor: [0.5, 0.9], radius: 0.05) == nil)
    }

    @Test func dilateAndErode() {
        var m = [Bool](repeating: false, count: 49)
        m[24] = true
        let d = PixelMask.dilate(m, width: 7, height: 7, by: 1)
        #expect(d.filter { $0 }.count == 9)
        #expect(PixelMask.erode(d, width: 7, height: 7, by: 1).filter { $0 }.count == 1)
    }
}

struct SnapshotGeometryTests {
    private func snapshot(depth: [Float], width: Int, height: Int) -> DepthSnapshot {
        var pose = simd_float4x4(simd_quatf(angle: 0.7, axis: normalize(SIMD3<Float>(1, 0.4, -0.2))))
        pose.columns.3 = [0.3, 1.2, -0.5, 1]
        return DepthSnapshot(
            width: width, height: height, depth: depth, confidence: Array(repeating: 2, count: width * height),
            fx: 200, fy: 200, cx: Float(width) / 2, cy: Float(height) / 2, cameraToWorld: pose, timestamp: 0,
            videoWidth: width, videoHeight: height
        )
    }

    @Test func projectInvertsUnproject() throws {
        let s = snapshot(depth: Array(repeating: 0.8, count: 256 * 192), width: 256, height: 192)
        let p = s.worldPoint(u: 40, v: 150)
        let n = try #require(s.project(p))
        #expect(abs(n.x - 40.5 / 256) < 1e-4)
        #expect(abs(n.y - 150.5 / 192) < 1e-4)
        let back = try #require(s.worldPoint(atNormalized: n))
        #expect(simd_distance(back, p) < 1e-4)
    }

    @Test func depthEdgesAreDropped() {
        var depth = [Float](repeating: 1, count: 100)
        for v in 3...5 { for u in 3...5 { depth[v * 10 + u] = 0.5 } }
        let s = snapshot(depth: depth, width: 10, height: 10)
        let points = s.worldPoints()
        #expect(points.contains { simd_distance($0, s.worldPoint(u: 4, v: 4)) < 1e-5 })
        #expect(!points.contains { simd_distance($0, s.worldPoint(u: 3, v: 4)) < 1e-5 })
        #expect(!points.contains { simd_distance($0, s.worldPoint(u: 2, v: 4)) < 1e-5 })
        #expect(points.contains { simd_distance($0, s.worldPoint(u: 0, v: 0)) < 1e-5 })
    }
}

struct ObjectCloudTests {
    @Test func boxOnATableFitsTightly() throws {
        let truth = OrientedRect(center: [0.1, -0.2], yaw: 25 * .pi / 180, long: 0.30, short: 0.20)
        var cloud = ObjectCloud()
        var rng = Noise(state: 11)
        for _ in 0..<4 {
            cloud.merge(boxPoints(truth, ground: 0.75, height: 0.10, spill: 0.008, rng: &rng), ground: 0.75 + rng.next() * 0.002)
        }
        let fit = try #require(cloud.fit())
        #expect(abs(fit.rect.long - 0.30) <= 0.01, "long \(fit.rect.long)")
        #expect(abs(fit.rect.short - 0.20) <= 0.01, "short \(fit.rect.short)")
        #expect(abs(fit.height - 0.10) <= 0.006, "height \(fit.height)")
        #expect(distance(fit.rect.center, truth.center) <= 0.01)
        #expect(abs(cloud.ground! - 0.75) <= 0.002)
    }

    @Test func thinItemKeepsItsFootprintAndHeight() throws {
        let truth = OrientedRect(center: [0, 0], yaw: 0.3, long: 0.125, short: 0.088)
        var cloud = ObjectCloud()
        var rng = Noise(state: 5)
        for _ in 0..<4 {
            cloud.merge(boxPoints(truth, ground: 0, height: 0.006, spill: 0.006, rng: &rng), ground: rng.next() * 0.001)
        }
        let fit = try #require(cloud.fit())
        #expect(abs(fit.rect.long - 0.125) <= 0.01, "long \(fit.rect.long)")
        #expect(abs(fit.rect.short - 0.088) <= 0.01, "short \(fit.rect.short)")
        #expect(abs(fit.height - 0.006) <= 0.004, "height \(fit.height)")
    }
}

struct SeedFitterTests {
    @Test func thinItemWithAWrongFloorPlane() throws {
        // ARKit's plane sits 8 mm below the real floor; the item is 1.2 cm tall.
        var g = flatGrid(level: 0.008)
        let truth = OrientedRect(center: [0.1, 0.05], yaw: 0.4, long: 0.20, short: 0.15)
        g.paint(truth, height: 0.020)
        let (fit, ground) = try #require(SeedFitter.fit(g, seed: truth.center))
        #expect(abs(ground - 0.008) <= 0.002, "ground \(ground)")
        #expect(abs(fit.height - 0.012) <= 0.004, "height \(fit.height)")
        #expect(abs(fit.rect.long - 0.20) <= 0.015)
        #expect(abs(fit.rect.short - 0.15) <= 0.015)
    }

    @Test func itemOnATableMeasuresFromTheTable() throws {
        var g = flatGrid()
        g.paint(OrientedRect(center: [0, 0], yaw: 0, long: 1.2, short: 0.7), height: 0.74)
        let truth = OrientedRect(center: [0.2, 0.1], yaw: 0, long: 0.24, short: 0.16)
        g.paint(truth, height: 0.82)
        let (fit, ground) = try #require(SeedFitter.fit(g, seed: truth.center))
        #expect(abs(ground - 0.74) <= 0.003)
        #expect(abs(fit.height - 0.08) <= 0.005)
        #expect(abs(fit.rect.long - 0.24) <= 0.015)
    }

    @Test func bareFloorIsNotAnItem() {
        #expect(SeedFitter.fit(flatGrid(), seed: [0.3, 0.3]) == nil)
    }
}

struct CavityRobustnessTests {
    /// Open shell, 78×53 outer and 72×47 inner, 13 cm walls, cavity floor at 2 cm.
    private func shell(_ g: inout HeightGrid) -> OrientedRect {
        let outer = OrientedRect(center: [0, 0.1], yaw: 20 * .pi / 180, long: 0.78, short: 0.53)
        g.paint(OrientedRect(center: outer.center - outer.axisShort * 0.55, yaw: outer.yaw, long: 0.78, short: 0.53), height: 0.04)
        g.paint(outer, height: 0.13)
        g.paint(OrientedRect(center: outer.center, yaw: outer.yaw, long: 0.72, short: 0.47), height: 0.02)
        return outer
    }

    @Test func handleChannelsOnTheFloorStayInside() throws {
        var g = flatGrid()
        let outer = shell(&g)
        // Two 4 cm ridges, 3 cm tall, along the back wall where the trolley handle runs.
        for offset: Float in [-0.15, 0.15] {
            let c = outer.center + outer.axisLong * offset - outer.axisShort * 0.21
            g.paint(OrientedRect(center: c, yaw: outer.yaw + .pi / 2, long: 0.05, short: 0.04), height: 0.05)
        }
        let fit = try CavityFitter.fit(g, floorY: 0, seed: outer.center).get()
        #expect(abs(fit.box.rect.long - 0.72) <= 0.015, "long \(fit.box.rect.long)")
        #expect(abs(fit.box.rect.short - 0.47) <= 0.015, "short \(fit.box.rect.short)")
    }

    @Test func floorHiddenBehindTheNearWallIsRecovered() throws {
        var g = flatGrid()
        let outer = shell(&g)
        // An 8 cm strip inside the near wall that the camera never saw.
        let strip = OrientedRect(center: outer.center + outer.axisShort * 0.195, yaw: outer.yaw, long: 0.72, short: 0.08)
        for i in g.heights.indices where strip.contains(g.center(of: i)) { g.heights[i] = .nan }
        let fit = try CavityFitter.fit(g, floorY: 0, seed: outer.center).get()
        #expect(abs(fit.box.rect.long - 0.72) <= 0.015, "long \(fit.box.rect.long)")
        #expect(abs(fit.box.rect.short - 0.47) <= 0.015, "short \(fit.box.rect.short)")
    }
}
