import Foundation
import Testing
import simd
@testable import PackFit

struct TapMeasureTests {
    @Test func footprintFromThreeCorners() throws {
        // 30 × 20 cm box rotated 30°, corners tapped on a floor at y = 0.
        let yaw: Float = 30 * .pi / 180
        let u = SIMD3<Float>(cos(yaw), 0, sin(yaw)), v = SIMD3<Float>(-sin(yaw), 0, cos(yaw))
        let a = SIMD3<Float>(0.1, 0, 0.2)
        let rect = try #require(TapMeasure.footprint(a, a + u * 0.3, a + u * 0.12 + v * 0.2))
        #expect(abs(rect.long - 0.3) < 1e-4)
        #expect(abs(rect.short - 0.2) < 1e-4)
        #expect(abs(rect.yaw - yaw) < 1e-4)
        let center = a + u * 0.15 + v * 0.1
        #expect(simd_distance(rect.center, SIMD2(center.x, center.z)) < 1e-4)
    }

    @Test func shortFirstSideStillGivesLongAxis() throws {
        let rect = try #require(TapMeasure.footprint([0, 0, 0], [0, 0, 0.1], [-0.4, 0, 0.05]))
        #expect(abs(rect.long - 0.4) < 1e-4)
        #expect(abs(rect.short - 0.1) < 1e-4)
        #expect(abs(rect.center.x + 0.2) < 1e-4)
    }

    @Test func degenerateTapsAreRejected() {
        #expect(TapMeasure.footprint([0, 0, 0], [0.001, 0, 0], [0, 0, 0.2]) == nil)
        #expect(TapMeasure.footprint([0, 0, 0], [0.3, 0, 0], [0.1, 0, 0.001]) == nil)
    }

    @Test func edgeRayHitsFrontFaceAtTopEdge() throws {
        // Box 30 × 20, 12 cm tall, front face at z = 0.1; camera in front and above.
        let rect = OrientedRect(center: [0, 0], yaw: 0, long: 0.3, short: 0.2)
        let origin = SIMD3<Float>(0, 0.5, 0.6)
        let target = SIMD3<Float>(0.05, 0.12, 0.1)
        let h = try #require(TapMeasure.heightFromEdgeRay(origin: origin, direction: normalize(target - origin), footprint: rect, floorY: 0))
        #expect(abs(h - 0.12) < 1e-4)
    }

    @Test func edgeRayPicksTheSideFacingTheCamera() throws {
        let rect = OrientedRect(center: [0, 0], yaw: 0, long: 0.3, short: 0.2)
        let origin = SIMD3<Float>(0.8, 0.4, 0)
        let target = SIMD3<Float>(0.15, 0.08, 0.02)
        let h = try #require(TapMeasure.heightFromEdgeRay(origin: origin, direction: normalize(target - origin), footprint: rect, floorY: 0))
        #expect(abs(h - 0.08) < 1e-4)
    }

    @Test func surfaceHitMustLandOverTheItem() {
        let rect = OrientedRect(center: [0, 0], yaw: 0, long: 0.3, short: 0.2)
        #expect(TapMeasure.heightFromSurfaceHit([0.05, 0.1, 0], footprint: rect, floorY: 0) == 0.1)
        #expect(TapMeasure.heightFromSurfaceHit([0.5, 0.1, 0], footprint: rect, floorY: 0) == nil)
        #expect(TapMeasure.heightFromSurfaceHit([0, 0.001, 0], footprint: rect, floorY: 0) == nil)
    }

    @Test func tapMeasuredBagUsesManualMethod() {
        let bag = ContainerFactory.fromCavity(innerLongCm: 70, innerShortCm: 45, shellDepthCm: 12, confidence: 0.7, method: .manual)
        #expect(bag.measurement?.method == .manual)
        #expect(bag.measurement?.deviceHasLidar == false)
        #expect(bag.compartments.first?.dims == [70, 24, 45])
    }
}
