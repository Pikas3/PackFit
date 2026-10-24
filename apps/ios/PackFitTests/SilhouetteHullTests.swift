import Foundation
import Testing
import simd
@testable import PackFit

/// A box on the floor at y = 0, turned by `yaw` about the vertical axis. Metres.
struct SyntheticBox {
    var center: SIMD2<Float>
    var yaw: Float = 0
    var size: SIMD3<Float>   // long (x), height (y), short (z) before turning

    /// Ray-box intersection in the box's own frame (slab method).
    func hit(origin: SIMD3<Float>, direction: SIMD3<Float>) -> Bool {
        let c = cos(-yaw), s = sin(-yaw)
        func local(_ v: SIMD3<Float>, point: Bool) -> SIMD3<Float> {
            let p = point ? v - SIMD3(center.x, size.y / 2, center.y) : v
            return [c * p.x - s * p.z, p.y, s * p.x + c * p.z]
        }
        let o = local(origin, point: true), d = local(direction, point: false)
        let half = size / 2
        var t0: Float = 0, t1: Float = .infinity
        for k in 0..<3 {
            if abs(d[k]) < 1e-9 {
                if abs(o[k]) > half[k] { return false }
                continue
            }
            var a = (-half[k] - o[k]) / d[k], b = (half[k] - o[k]) / d[k]
            if a > b { swap(&a, &b) }
            t0 = max(t0, a); t1 = min(t1, b)
            if t0 > t1 { return false }
        }
        return true
    }
}

/// A camera at `distance` from `target`, at the given azimuth and elevation (degrees),
/// looking at it. Returns camera-to-world with -z forward and y up.
func lookAt(target: SIMD3<Float>, azimuth: Float, elevation: Float, distance: Float) -> simd_float4x4 {
    let az = azimuth * .pi / 180, el = elevation * .pi / 180
    let eye = target + distance * SIMD3(cos(el) * cos(az), sin(el), cos(el) * sin(az))
    let back = normalize(eye - target)
    let right = normalize(cross([0, 1, 0], back))
    let up = cross(back, right)
    return simd_float4x4(columns: (SIMD4(right, 0), SIMD4(up, 0), SIMD4(back, 0), SIMD4(eye, 1)))
}

/// Renders the outline of `shapes` from a camera, as `HullView`.
func render(_ shapes: [SyntheticBox], cameraToWorld: simd_float4x4, width: Int = 240, height: Int = 180) -> HullView {
    let f: Float = 220, cx = Float(width) / 2, cy = Float(height) / 2
    let origin = SIMD3(cameraToWorld.columns.3.x, cameraToWorld.columns.3.y, cameraToWorld.columns.3.z)
    var mask = [Bool](repeating: false, count: width * height)
    for v in 0..<height {
        for u in 0..<width {
            let cam = SIMD4<Float>((Float(u) + 0.5 - cx) / f, -(Float(v) + 0.5 - cy) / f, -1, 0)
            let w = cameraToWorld * cam
            let dir = normalize(SIMD3(w.x, w.y, w.z))
            mask[v * width + u] = shapes.contains { $0.hit(origin: origin, direction: dir) }
        }
    }
    return HullView(width: width, height: height, mask: mask, fx: f, fy: f, cx: cx, cy: cy, cameraToWorld: cameraToWorld)
}

/// An orbit like a user's: half the views high, half low, across `span` degrees.
func orbit(
    _ shapes: [SyntheticBox], target: SIMD3<Float>, span: Float = 150, count: Int = 12,
    elevations: [Float] = [80, 50, 30], distance: Float = 0.8
) -> [HullView] {
    (0..<count).map { i in
        let az = -span / 2 + span * Float(i) / Float(max(count - 1, 1)) + 90
        let el = elevations[i % elevations.count]
        return render(shapes, cameraToWorld: lookAt(target: target, azimuth: az, elevation: el, distance: distance))
    }
}

private func fitted(_ views: [HullView], seed: SIMD3<Float>) throws -> HullFitter.Fit {
    try #require(HullFitter.fit(carved(views, seed: seed), views: views))
}

private func carved(_ views: [HullView], seed: SIMD3<Float>, options: VoxelHull.Options = .init(size: 0.6, maxHeight: 0.4)) -> VoxelHull {
    var hull = VoxelHull(seed: seed, floorY: 0, options: options)
    for v in views { hull.carve(v) }
    return hull
}

struct SilhouetteHullTests {
    @Test func boxMeasuresWithinTolerance() throws {
        let box = SyntheticBox(center: [0.02, -0.01], yaw: 0.4, size: [0.30, 0.10, 0.20])
        let fit = try fitted(orbit([box], target: [0, 0.05, 0]), seed: [0.03, 0.1, 0])
        let cm = fit.box.dimsCm
        #expect(abs(cm.w - 30) <= 1.5, "long \(cm.w)")
        #expect(abs(cm.d - 20) <= 1.5, "short \(cm.d)")
        #expect(abs(cm.h - 10) <= 2, "height \(cm.h)")
        #expect(fit.coverage.complete)
        #expect(fit.confidence >= 0.75)
    }

    @Test func tallBottleKeepsItsHeight() throws {
        let bottle = SyntheticBox(center: [0, 0], size: [0.07, 0.25, 0.07])
        let fit = try fitted(orbit([bottle], target: [0, 0.12, 0], distance: 0.9), seed: [0, 0.1, 0])
        let cm = fit.box.dimsCm
        #expect(abs(cm.h - 25) <= 2, "height \(cm.h)")
        #expect(abs(cm.w - 7) <= 1.5 && abs(cm.d - 7) <= 1.5, "footprint \(cm.w) × \(cm.d)")
    }

    @Test func thinPassportFootprint() throws {
        let passport = SyntheticBox(center: [0, 0], yaw: 1.0, size: [0.125, 0.006, 0.088])
        let fit = try fitted(orbit([passport], target: [0, 0, 0], distance: 0.6), seed: [0, 0, 0])
        let cm = fit.box.dimsCm
        #expect(abs(cm.w - 12.5) <= 1.5 && abs(cm.d - 8.8) <= 1.5, "footprint \(cm.w) × \(cm.d)")
        #expect(cm.h <= 2, "height \(cm.h)")
    }

    @Test func topDownOnlyIsNotConfident() throws {
        let box = SyntheticBox(center: [0, 0], size: [0.30, 0.10, 0.20])
        let views = orbit([box], target: [0, 0.05, 0], span: 40, count: 6, elevations: [80])
        let fit = try fitted(views, seed: [0, 0.1, 0])
        #expect(!fit.coverage.complete)
        #expect(fit.confidence <= 0.6)
    }

    @Test func survivesTwoBadMasks() throws {
        let box = SyntheticBox(center: [0, 0], size: [0.30, 0.10, 0.20])
        var views = orbit([box], target: [0, 0.05, 0])
        // Segmentation dropped the object completely in two frames.
        for i in [3, 8] {
            let v = views[i]
            views[i] = HullView(width: v.width, height: v.height, mask: [Bool](repeating: false, count: v.mask.count),
                                fx: v.fx, fy: v.fy, cx: v.cx, cy: v.cy, cameraToWorld: v.cameraToWorld)
        }
        let fit = try fitted(views, seed: [0, 0.1, 0])
        let cm = fit.box.dimsCm
        #expect(abs(cm.w - 30) <= 1.5 && abs(cm.d - 20) <= 1.5 && abs(cm.h - 10) <= 2, "\(cm)")
    }

    @Test func neighbourStaysOut() throws {
        let box = SyntheticBox(center: [0, 0], size: [0.20, 0.08, 0.12])
        let other = SyntheticBox(center: [0.22, 0], size: [0.10, 0.08, 0.10])
        // The neighbour's outline is in every mask (merged instance), but it is a separate
        // column group, so it stays out of the fit.
        // Masks of the target only; the neighbour shares no outline but sits inside the grid.
        let fit = try fitted(orbit([box], target: [0, 0.04, 0]), seed: [0, 0.1, 0])
        let merged = try #require(HullFitter.fit(carved(orbit([box, other], target: [0, 0.04, 0]), seed: [0, 0.1, 0])))
        #expect(abs(fit.box.dimsCm.w - 20) <= 1.5, "long \(fit.box.dimsCm.w)")
        #expect(merged.box.rect.long < 0.45, "merged long \(merged.box.rect.long)")
    }

    @Test func featurePointsOnTheTopAddConfidence() throws {
        let box = SyntheticBox(center: [0, 0], size: [0.30, 0.10, 0.20])
        let views = orbit([box], target: [0, 0.05, 0])
        // Feature points on the top agree with the outline, which lifts the confidence.
        var points: [SIMD3<Float>] = []
        for i in 0..<20 { points.append([Float(i % 5) * 0.02 - 0.04, 0.1, Float(i / 5) * 0.02 - 0.03]) }
        let with = try #require(HullFitter.fit(carved(views, seed: [0, 0.1, 0]), views: views, featurePoints: points))
        let without = try fitted(views, seed: [0, 0.1, 0])
        #expect(with.pointHeight != nil)
        #expect(with.confidence >= without.confidence)
    }

    @Test func openClamshellSplitsIntoTwoShells() throws {
        // Base 70 × 45 × 14 cm and lid 70 × 45 × 9 cm, side by side, hinge gap 2 cm.
        let base = SyntheticBox(center: [0, -0.235], size: [0.70, 0.14, 0.45])
        let lid = SyntheticBox(center: [0, 0.235], size: [0.70, 0.09, 0.45])
        let hinge = SyntheticBox(center: [0, 0], size: [0.70, 0.02, 0.03])
        let views = orbit([base, lid, hinge], target: [0, 0.06, 0], span: 160, count: 14, elevations: [80, 50, 30], distance: 1.6)
        let options = VoxelHull.Options(size: 1.3, maxHeight: 0.3, cell: 0.01, layer: 0.01)
        let hull = carved(views, seed: [0, 0.1, -0.2], options: options)
        let fit = try #require(HullFitter.fit(hull))
        let shells = ShellSplitter.split(hull, fit: fit.box, seed: [0, -0.2], expectTwo: true, views: views)
        let lidFit = try #require(shells.lid)
        #expect(abs(shells.base.rect.long - 0.70) <= 0.03, "base long \(shells.base.rect.long)")
        #expect(abs(shells.base.rect.short - 0.46) <= 0.04, "base short \(shells.base.rect.short)")
        #expect(abs(shells.base.height - 0.14) <= 0.025, "base h \(shells.base.height)")
        #expect(abs(lidFit.height - 0.09) <= 0.025, "lid h \(lidFit.height)")
    }

    /// As the worker runs it: views arrive one by one and each fit starts from the last.
    @Test func incrementalWarmStartConverges() throws {
        let box = SyntheticBox(center: [0.03, 0.02], yaw: 0.7, size: [0.26, 0.08, 0.18])
        let views = orbit([box], target: [0, 0.04, 0], count: 10)
        var hull = VoxelHull(seed: [0.03, 0.1, 0.02], floorY: 0, options: .init(size: 0.6, maxHeight: 0.4))
        var last: HullFitter.Fit?
        for (i, v) in views.enumerated() {
            hull.carve(v)
            guard i >= 3 else { continue }
            last = HullFitter.fit(hull, views: Array(views[...i]), start: last?.box) ?? last
        }
        let cm = try #require(last).box.dimsCm
        #expect(abs(cm.w - 26) <= 1.5 && abs(cm.d - 18) <= 1.5 && abs(cm.h - 8) <= 2, "\(cm)")
    }

    @Test func coverageCountsBins() {
        let center = SIMD3<Float>(0, 0, 0)
        let cams = (0..<7).map { i -> SIMD3<Float> in
            let a = Float(i) * 15 * .pi / 180
            return [cos(a), 0.5, sin(a)]
        }
        let c = HullCoverage(cameras: cams, center: center)
        #expect(c.azimuthDegrees == 105)
        #expect(c.hasLowView)
    }
}
