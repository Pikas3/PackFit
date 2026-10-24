import Foundation
import simd
#if canImport(ARKit)
import ARKit
#endif

/// One camera frame for measuring without depth: the upright image to segment, plus the
/// pose, intrinsics and ARKit's sparse feature points.
struct HullFrame: Sendable {
    let image: UprightImage
    /// Sensor (landscape) image size and intrinsics at that size.
    let sensorWidth: Int, sensorHeight: Int
    let fx: Float, fy: Float, cx: Float, cy: Float
    let cameraToWorld: simd_float4x4
    let featurePoints: [SIMD3<Float>]

    var cameraPosition: SIMD3<Float> {
        SIMD3(cameraToWorld.columns.3.x, cameraToWorld.columns.3.y, cameraToWorld.columns.3.z)
    }

    /// Normalized sensor coordinates of a world point, nil behind the camera.
    func project(_ p: SIMD3<Float>) -> SIMD2<Float>? {
        let c = cameraToWorld.inverse * SIMD4(p, 1)
        let d = -c.z
        guard d > 0.05 else { return nil }
        return [(c.x * fx / d + cx) / Float(sensorWidth), (-c.y * fy / d + cy) / Float(sensorHeight)]
    }

    /// Where the ray through normalized sensor coordinates meets the floor.
    func floorPoint(atSensor n: SIMD2<Float>, floorY: Float) -> SIMD3<Float>? {
        let u = n.x * Float(sensorWidth), v = n.y * Float(sensorHeight)
        let dirCam = SIMD4<Float>((u - cx) / fx, -(v - cy) / fy, -1, 0)
        let w = cameraToWorld * dirCam
        let dir = SIMD3(w.x, w.y, w.z)
        guard dir.y < -1e-4 else { return nil }
        let t = (floorY - cameraPosition.y) / dir.y
        guard t > 0, t < 5 else { return nil }
        return cameraPosition + dir * t
    }

    /// A view of `mask` at mask resolution.
    func view(mask: [Bool], width: Int, height: Int) -> HullView {
        let s = Float(width) / Float(sensorWidth)
        return HullView(width: width, height: height, mask: mask, fx: fx * s, fy: fy * s, cx: cx * s, cy: cy * s, cameraToWorld: cameraToWorld)
    }
}

#if canImport(ARKit)
extension HullFrame {
    init(frame: ARFrame, image: UprightImage) {
        let k = frame.camera.intrinsics
        self.init(
            image: image,
            sensorWidth: Int(frame.camera.imageResolution.width),
            sensorHeight: Int(frame.camera.imageResolution.height),
            fx: k[0][0], fy: k[1][1], cx: k[2][0], cy: k[2][1],
            cameraToWorld: frame.camera.transform,
            featurePoints: frame.rawFeaturePoints?.points ?? []
        )
    }
}
#endif

/// Measures tapped items and bags on phones without LiDAR. Each target collects outlines
/// from a spread of poses, carves a voxel hull, and fits a box to the outlines. Runs off the
/// main actor; the guided session sends it one frame per tick while something is measuring.
actor HullWorker {
    enum Kind: Sendable, Equatable {
        case item
        /// An open bag. `expectTwo`: a clamshell with both halves lying open.
        case bag(expectTwo: Bool)
    }

    /// What the user should do next to complete the views.
    enum Hint: Sendable, Equatable {
        case keepInView
        case lookFromAbove
        case lookFromLow
        case moveAround
    }

    struct State: Sendable, Identifiable {
        var id: Int
        var kind: Kind
        var fit: BoxFit
        var floorY: Float
        var stable: Bool
        var confidence: Double
        var coverage: HullCoverage
        /// Bags only, once locked.
        var shells: ShellSplitter.Shells?
    }

    struct Result: Sendable {
        var states: [State] = []
        var failed: [Int] = []
        /// For the target still measuring, if any.
        var hint: Hint?
    }

    private struct Target {
        let id: Int
        let kind: Kind
        /// Normalized sensor point of the tap, used on the first frame only.
        let tapSensor: SIMD2<Float>
        /// Floor point under the tap.
        let tapFloor: SIMD3<Float>
        let floorY: Float
        var hull: VoxelHull?
        var views: [HullView] = []
        var points: [SIMD3<Float>] = []
        var fit: HullFitter.Fit?
        var shells: ShellSplitter.Shells?
        var history: [BoxFit] = []
        var ticks = 0
        var misses = 0
        var newViews = 0
        var locked = false
    }

    static let maskWidth = 320, maskHeight = 240
    /// 12 s at 5 Hz, then the best fit so far is kept.
    private static let maxTicks = 60
    private static let maxViews = 20
    /// Minimum angle between kept views as seen from the object, radians.
    private static let minViewAngle: Float = 6 * .pi / 180

    private var targets: [Target] = []

    func reset() { targets = [] }

    func add(id: Int, kind: Kind, tapSensor: SIMD2<Float>, tapFloor: SIMD3<Float>, floorY: Float) {
        targets.append(Target(id: id, kind: kind, tapSensor: tapSensor, tapFloor: tapFloor, floorY: floorY))
    }

    func remove(id: Int) { targets.removeAll { $0.id == id } }

    func remove(kind: Kind) { targets.removeAll { $0.kind == kind } }

    var isMeasuring: Bool { targets.contains { !$0.locked } }

    func process(_ frame: HullFrame) -> Result {
        var result = Result()
        let active = targets.indices.filter { !targets[$0].locked }
        let labels = active.isEmpty ? nil : Segmenter.labels(for: frame.image)
        for i in active {
            step(&targets[i], frame: frame, labels: labels)
            if !targets[i].locked, result.hint == nil { result.hint = hint(for: targets[i]) }
        }
        for t in targets {
            guard let fit = t.fit else {
                if t.locked { result.failed.append(t.id) }
                continue
            }
            let box = t.shells?.base ?? fit.box
            result.states.append(State(
                id: t.id, kind: t.kind, fit: box, floorY: t.floorY, stable: t.locked,
                confidence: t.locked && !fit.coverage.complete ? min(fit.confidence, 0.6) : fit.confidence,
                coverage: fit.coverage, shells: t.shells
            ))
        }
        targets.removeAll { $0.locked && $0.fit == nil }
        return result
    }

    private func step(_ t: inout Target, frame: HullFrame, labels: InstanceLabels?) {
        t.ticks += 1
        defer {
            if t.ticks >= Self.maxTicks, !t.locked { lock(&t) }
        }
        guard let labels, let instance = instance(for: t, frame: frame, labels: labels) else {
            t.misses += 1
            // Nothing under the tap at all: give up early so the user can tap again.
            if t.hull == nil, t.misses >= 5 { t.locked = true }
            return
        }
        let mask = labels.depthMask(instance, width: Self.maskWidth, height: Self.maskHeight)
        let view = frame.view(mask: mask, width: Self.maskWidth, height: Self.maskHeight)
        if t.hull == nil {
            guard let hull = makeHull(t, view: view, frame: frame) else {
                t.misses += 1
                if t.misses >= 5 { t.locked = true }
                return
            }
            t.hull = hull
        }
        t.misses = 0
        collectPoints(&t, frame.featurePoints)

        guard isNewPose(view.cameraPosition, target: t), t.views.count < Self.maxViews else { return }
        t.hull!.carve(view)
        t.views.append(view)
        t.newViews += 1
        guard t.views.count >= 4 else { return }

        // Refining costs the most; bags are big and settle slowly, so refine less often.
        let every = t.kind == .item ? 1 : 3
        guard t.newViews >= every || t.fit == nil else { return }
        t.newViews = 0
        guard let fit = HullFitter.fit(t.hull!, views: t.views, featurePoints: t.points, start: t.fit?.box) else { return }
        t.fit = fit
        t.history.append(fit.box)
        if t.history.count > 5 { t.history.removeFirst() }
        if fit.coverage.complete, settled(t.history, tolerance: t.kind == .item ? 0.008 : 0.015) { lock(&t) }
    }

    private func lock(_ t: inout Target) {
        t.locked = true
        guard case .bag(let expectTwo) = t.kind, let hull = t.hull, let fit = t.fit else { return }
        t.shells = ShellSplitter.split(hull, fit: fit.box, seed: [t.tapFloor.x, t.tapFloor.z], expectTwo: expectTwo, views: t.views)
    }

    /// The instance under the tap on the first frame; afterwards the one under the current
    /// box, which must cover most of the box's middle so a neighbour never takes over.
    private func instance(for t: Target, frame: HullFrame, labels: InstanceLabels) -> UInt8? {
        guard let fit = t.fit?.box ?? t.history.last else {
            guard let hull = t.hull else { return labels.instance(nearSensor: t.tapSensor) }
            // Before the first fit: a point just inside the outline's front edge.
            let a = hull.anchor ?? hull.seedXZ
            guard let n = frame.project([a.x, t.floorY + 0.01, a.y]) else { return nil }
            return labels.instance(nearSensor: n, radius: 0.04)
        }
        let mid = t.floorY + fit.height / 2
        let probes = [SIMD2<Float>(0, 0), [0.3, 0.3], [-0.3, 0.3], [0.3, -0.3], [-0.3, -0.3]].map { o in
            fit.rect.center + fit.rect.axisLong * (o.x * fit.rect.long) + fit.rect.axisShort * (o.y * fit.rect.short)
        }
        let sensor = probes.compactMap { frame.project([$0.x, mid, $0.y]) }
        guard sensor.count == probes.count, let centre = sensor.first,
              let label = labels.instance(nearSensor: centre, radius: 0.03) else { return nil }
        let hits = sensor.filter { labels.label(atSensor: $0) == label }.count
        return hits >= 3 ? label : nil
    }

    /// A grid around the object. Items: the outline's nearest floor point is a bottom
    /// edge, so the grid reaches back from it, away from the camera. Bags: centred on the tap.
    private func makeHull(_ t: Target, view: HullView, frame: HullFrame) -> VoxelHull? {
        switch t.kind {
        case .bag:
            let options = VoxelHull.Options(size: 1.8, maxHeight: 0.4, cell: 0.01, layer: 0.01)
            return VoxelHull(seed: t.tapFloor, floorY: t.floorY, options: options)
        case .item:
            guard let front = nearestFloorPoint(view: view, frame: frame, floorY: t.floorY) else { return nil }
            let cam = SIMD2(frame.cameraPosition.x, frame.cameraPosition.z)
            let f = SIMD2(front.x, front.z)
            let away = simd_length(f - cam) > 1e-3 ? simd_normalize(f - cam) : SIMD2<Float>(0, -1)
            let centre = f + away * 0.3
            let options = VoxelHull.Options(size: 1.0, maxHeight: 0.6)
            return VoxelHull(seed: [centre.x, t.floorY, centre.y], floorY: t.floorY, anchor: f + away * 0.01, options: options)
        }
    }

    /// The outline pixel whose floor point is nearest the camera: where the object meets
    /// the floor on the side facing the user.
    private func nearestFloorPoint(view: HullView, frame: HullFrame, floorY: Float) -> SIMD3<Float>? {
        let cam = SIMD2(frame.cameraPosition.x, frame.cameraPosition.z)
        var best: (SIMD3<Float>, Float)?
        for v in stride(from: 0, to: view.height, by: 2) {
            for u in stride(from: 0, to: view.width, by: 2) where view.mask[v * view.width + u] {
                let n = SIMD2((Float(u) + 0.5) / Float(view.width), (Float(v) + 0.5) / Float(view.height))
                guard let p = frame.floorPoint(atSensor: n, floorY: floorY) else { continue }
                let d = simd_distance(SIMD2(p.x, p.z), cam)
                if best == nil || d < best!.1 { best = (p, d) }
            }
        }
        return best?.0
    }

    private func collectPoints(_ t: inout Target, _ points: [SIMD3<Float>]) {
        guard let hull = t.hull, t.points.count < 3000 else { return }
        let lo = SIMD2(hull.origin.x, hull.origin.z), hi = lo + hull.options.size
        t.points += points.filter { $0.x >= lo.x && $0.x <= hi.x && $0.z >= lo.y && $0.z <= hi.y && $0.y > t.floorY }
    }

    private func isNewPose(_ camera: SIMD3<Float>, target t: Target) -> Bool {
        guard t.views.count >= 3, let hull = t.hull else { return true }
        let centre = SIMD3(hull.seedXZ.x, t.floorY, hull.seedXZ.y)
        let dir = simd_normalize(camera - centre)
        return t.views.allSatisfy { v in
            acos(min(max(dot(dir, simd_normalize(v.cameraPosition - centre)), -1), 1)) >= Self.minViewAngle
        }
    }

    private func settled(_ history: [BoxFit], tolerance: Float) -> Bool {
        let recent = history.suffix(3)
        guard recent.count == 3, let first = recent.first else { return false }
        return recent.allSatisfy { f in
            max(distance(f.rect.center, first.rect.center), abs(f.rect.long - first.rect.long),
                abs(f.rect.short - first.rect.short), abs(f.height - first.height)) <= tolerance
        }
    }

    private func hint(for t: Target) -> Hint {
        guard let c = t.fit?.coverage else { return t.misses > 0 ? .keepInView : .moveAround }
        if t.misses >= 3 { return .keepInView }
        if !c.hasTopView { return .lookFromAbove }
        if !c.hasLowView { return .lookFromLow }
        return .moveAround
    }
}
