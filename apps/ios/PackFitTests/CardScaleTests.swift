import CoreGraphics
import Foundation
import Testing
import simd
@testable import PackFit

/// Synthetic camera above a floor: plane cm, z up. Projects known geometry so the tests can
/// check that the card pose and box fit recover it.
private struct SyntheticCamera {
    let intrinsics = CameraIntrinsics.fromFieldOfView(degrees: 70, width: 1200, height: 1600)
    let rotation: simd_double3x3
    let translation: SIMD3<Double>

    init(at position: SIMD3<Double>, lookingAt target: SIMD3<Double>) {
        let f = normalize(target - position)
        let x = normalize(cross(f, SIMD3(0, 0, 1)))
        let y = cross(f, x)
        rotation = simd_double3x3(rows: [x, y, f])
        translation = -(rotation * position)
    }

    func project(_ p: SIMD3<Double>) -> SIMD2<Double> {
        let c = rotation * p + translation
        return [intrinsics.fx * c.x / c.z + intrinsics.cx, intrinsics.fy * c.y / c.z + intrinsics.cy]
    }

    /// Card on the floor with one corner at `at`, long side turned by `yaw`.
    func cardQuad(at: SIMD2<Double>, yaw: Double) -> ImageQuad {
        let u = SIMD2(cos(yaw), sin(yaw)), v = SIMD2(-sin(yaw), cos(yaw))
        let L = PlanePose.cardLongCm, S = PlanePose.cardShortCm
        let corners = [at, at + u * L, at + u * L + v * S, at + v * S]
        return ImageQuad(corners: corners.map { project(SIMD3($0.x, $0.y, 0)) })
    }
}

struct CardScaleTests {
    private let camera = SyntheticCamera(at: [10, -45, 45], lookingAt: [12, 8, 0])

    @Test func cardPoseRecoversFloorPoints() throws {
        let quad = camera.cardQuad(at: [0, 0], yaw: 0.35)
        let pose = try #require(PlanePose.fromCard(quad, intrinsics: camera.intrinsics))
        #expect(pose.error < 1e-6)
        // Distances on the floor come back true, whatever frame the card picked.
        let a = SIMD3<Double>(20, 15, 0), b = SIMD3<Double>(-5, 30, 0)
        let pa = try #require(pose.floorPoint(camera.project(a)))
        let pb = try #require(pose.floorPoint(camera.project(b)))
        #expect(abs(simd_distance(pa, pb) - simd_distance(a, b)) < 0.01)
        #expect(abs(pose.cameraPosition.z - 45) < 0.01)
    }

    @Test func cornerOrderDoesNotMatter() throws {
        var quad = camera.cardQuad(at: [3, 2], yaw: 1.2)
        quad.corners = [quad.corners[2], quad.corners[1], quad.corners[0], quad.corners[3]]
        let pose = try #require(PlanePose.fromCard(quad, intrinsics: camera.intrinsics))
        #expect(pose.error < 1e-6)
    }

    @Test func nonCardRectangleIsRejected() {
        // A 20 × 20 cm square tile is not an ID-1 card.
        let corners: [SIMD2<Double>] = [[0, 0], [20, 0], [20, 20], [0, 20]]
        let quad = ImageQuad(corners: corners.map { camera.project(SIMD3($0.x, $0.y, 0)) })
        #expect(PlanePose.bestCard(among: [quad], intrinsics: camera.intrinsics) == nil)
    }

    @Test func bestCardPrefersTheHintedQuad() throws {
        let left = camera.cardQuad(at: [-20, 5], yaw: 0)
        let right = camera.cardQuad(at: [30, 5], yaw: 0.2)
        let hint = right.bounds
        let pose = try #require(PlanePose.bestCard(among: [left, right], intrinsics: camera.intrinsics, hint: hint))
        #expect(pose.card == right)
    }

    @Test func bestCardRequireHintIgnoresCardsOutsideRegion() {
        let left = camera.cardQuad(at: [-20, 5], yaw: 0)
        let right = camera.cardQuad(at: [30, 5], yaw: 0.2)
        let hint = right.bounds
        #expect(PlanePose.bestCard(among: [left], intrinsics: camera.intrinsics, hint: hint, requireHint: true) == nil)
        let pose = PlanePose.bestCard(among: [left, right], intrinsics: camera.intrinsics, hint: hint, requireHint: true)
        #expect(pose?.card == right)
    }

    @Test func boxFitRecoversDimensions() throws {
        let card = camera.cardQuad(at: [0, 0], yaw: 0)
        let pose = try #require(PlanePose.fromCard(card, intrinsics: camera.intrinsics))
        // Ground truth in the card's frame, which the pose uses.
        let truth = (center: SIMD2<Double>(22, 14), yaw: 0.5, w: 30.0, d: 20.0, h: 12.0)
        let hull = try #require(SilhouetteFit.silhouette(.init(center: truth.center, yaw: truth.yaw, w: truth.w, d: truth.d, h: truth.h), shape: .box, pose: pose))
        let mask = Self.mask(hull)
        let fit = try #require(SilhouetteFit.fit(mask, pose: pose))
        #expect(abs(fit.long - 30) / 30 < 0.1)
        #expect(abs(fit.short - 20) / 20 < 0.1)
        #expect(abs(fit.height - 12) / 12 < 0.1)
        #expect(fit.iou > 0.85)
        #expect(fit.heightReliable && fit.footprintReliable)
    }

    @Test func tallThinBottleAsBox() throws {
        let card = camera.cardQuad(at: [0, 0], yaw: 0)
        let pose = try #require(PlanePose.fromCard(card, intrinsics: camera.intrinsics))
        let hull = try #require(SilhouetteFit.silhouette(.init(center: [-12, 10], yaw: 0, w: 7, d: 7, h: 24), shape: .box, pose: pose))
        let fit = try #require(SilhouetteFit.fit(Self.mask(hull), pose: pose))
        #expect(abs(fit.height - 24) / 24 < 0.12)
        #expect(fit.long < 10)
    }

    /// Soda can 6.6 × 12.2, bottle 7 × 24 standing, bottle 24 × 7 lying at an angle: each
    /// within 5% when fitted as the cylinder it is.
    @Test(arguments: [
        (ObjectShape.uprightCylinder, SIMD2<Double>(-10, 12), 0.0, 6.6, 6.6, 12.2),
        (.uprightCylinder, SIMD2<Double>(25, 14), 0.0, 7.0, 7.0, 24.0),
        (.lyingCylinder, SIMD2<Double>(8, 25), 0.5, 24.0, 7.0, 7.0),
    ])
    func cylinderFitRecoversDimensions(shape: ObjectShape, center: SIMD2<Double>, yaw: Double, w: Double, d: Double, h: Double) throws {
        let pose = try #require(PlanePose.fromCard(camera.cardQuad(at: [0, 0], yaw: 0), intrinsics: camera.intrinsics))
        let hull = try #require(SilhouetteFit.silhouette(.init(center: center, yaw: yaw, w: w, d: d, h: h), shape: shape, pose: pose))
        let fit = try #require(SilhouetteFit.fit(Self.mask(hull), pose: pose, shape: shape))
        #expect(fit.shape == shape)
        #expect(abs(fit.long - max(w, d)) / max(w, d) < 0.05)
        #expect(abs(fit.short - min(w, d)) / min(w, d) < 0.05)
        #expect(abs(fit.height - h) / h < 0.05)
        #expect(fit.outline.count >= 3)
    }

    /// A dark card with rounded corners on noisy carpet. Corners 12 px off (as Vision's can be)
    /// come back within a pixel, and the floor tilt within 2 degrees.
    @Test func cardEdgesSharpenRoughCorners() throws {
        let (w, h) = (1200, 1600)
        // Card about 120 px across, as in a phone photo from half a metre.
        let camera = SyntheticCamera(at: [4, -22, 28], lookingAt: [5, 4, 0])
        let truth = camera.cardQuad(at: [0, 0], yaw: 0.3)
        let r = 0.318, L = PlanePose.cardLongCm, S = PlanePose.cardShortCm
        let (u, v) = (SIMD2(cos(0.3), sin(0.3)), SIMD2(-sin(0.3), cos(0.3)))
        var outline: [CGPoint] = []
        for (c, a0) in [(SIMD2(L - r, r), -Double.pi / 2), (SIMD2(L - r, S - r), 0), (SIMD2(r, S - r), .pi / 2), (SIMD2(r, r), .pi)] {
            for k in 0...8 {
                let a = a0 + Double(k) / 8 * .pi / 2
                let p = u * (c.x + r * cos(a)) + v * (c.y + r * sin(a))
                let q = camera.project(SIMD3(p.x, p.y, 0))
                outline.append(CGPoint(x: q.x, y: q.y))
            }
        }
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        let pixels = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        var seed: UInt64 = 7
        for i in 0..<(w * h) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            pixels[i] = UInt8(80 + Int((seed >> 33) % 91)) // 80-170
        }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(gray: 0.12, alpha: 1)
        ctx.addLines(between: outline)
        ctx.closePath()
        ctx.fillPath()
        let rendered = try #require(ctx.makeImage())
        let gray = try #require(GrayImage(rendered))

        let offsets: [SIMD2<Double>] = [[-12, 5], [9, -10], [11, 8], [-7, 12]]
        let rough = ImageQuad(corners: zip(truth.corners, offsets).map { $0 + $1 })
        let sharp = try #require(CardEdges.refine(rough, in: gray))
        for (a, b) in zip(sharp.corners, truth.corners) { #expect(simd_distance(a, b) < 1) }
        let truePose = try #require(PlanePose.fromCard(truth, intrinsics: camera.intrinsics))
        let pose = try #require(PlanePose.fromCard(sharp, intrinsics: camera.intrinsics))
        let tilt = acos(min(1, abs(dot(pose.rotation.columns.2, truePose.rotation.columns.2)))) * 180 / .pi
        #expect(tilt < 2)
    }

    // MARK: Matching Claude's boxes to outlines

    private func instance(_ label: UInt8, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CardMeasurer.Instance {
        CardMeasurer.Instance(label: label, bounds: CGRect(x: x, y: y, width: w, height: h), pixels: 1000)
    }

    @Test func offsetAndClippedBoxesFindTheirOutlines() {
        let can = instance(1, 0.30, 0.40, 0.10, 0.15)
        let bottle = instance(2, 0.60, 0.20, 0.12, 0.40)
        // Can box shifted left so it barely touches the can; bottle box covers its left half.
        let boxes: [CGRect?] = [CGRect(x: 0.22, y: 0.40, width: 0.10, height: 0.15), CGRect(x: 0.58, y: 0.22, width: 0.07, height: 0.36)]
        #expect(CardMeasurer.match(boxes: boxes, instances: [can, bottle]) == [0, 1])
    }

    @Test func boxThatMissesTakesTheNearbyOutline() {
        let can = instance(1, 0.30, 0.40, 0.10, 0.15)
        let far = instance(2, 0.80, 0.80, 0.10, 0.10)
        let boxes: [CGRect?] = [CGRect(x: 0.18, y: 0.40, width: 0.10, height: 0.15), nil]
        #expect(CardMeasurer.match(boxes: boxes, instances: [can, far]) == [0, nil])
    }

    @Test func touchingObjectsShareOneOutline() {
        let pair = instance(1, 0.20, 0.30, 0.40, 0.20)
        let boxes: [CGRect?] = [CGRect(x: 0.20, y: 0.30, width: 0.20, height: 0.20), CGRect(x: 0.40, y: 0.30, width: 0.20, height: 0.20)]
        #expect(CardMeasurer.match(boxes: boxes, instances: [pair]) == [0, 0])
    }

    @Test func straightDownViewFlagsHeight() throws {
        let top = SyntheticCamera(at: [10, 8, 60], lookingAt: [10.01, 8.01, 0])
        let pose = try #require(PlanePose.fromCard(top.cardQuad(at: [0, 0], yaw: 0), intrinsics: top.intrinsics))
        let hull = try #require(SilhouetteFit.silhouette(.init(center: [15, 12], yaw: 0, w: 20, d: 15, h: 8), shape: .box, pose: pose))
        let fit = try #require(SilhouetteFit.fit(Self.mask(hull), pose: pose))
        #expect(!fit.heightReliable)
        #expect(SilhouetteFit.confidence(fit, mask: Self.mask(hull), pose: pose) < 0.75)
    }

    static func mask(_ hull: [SIMD2<Double>]) -> ObjectMask {
        let xs = hull.map(\.x), ys = hull.map(\.y)
        let bounds = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        return ObjectMask(
            region: bounds.insetBy(dx: -bounds.width * 0.2, dy: -bounds.height * 0.2),
            contains: { SilhouetteFit.coverage(of: $0, in: hull, softness: 1e-6) > 0.5 },
            fromSegmentation: true,
            touchesImageEdge: false
        )
    }
}
