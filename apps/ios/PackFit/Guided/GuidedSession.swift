import ARKit
import CoreImage
import Foundation
import RealityKit
import SwiftUI
import simd

/// The guided LiDAR flow: scan the open bag, sweep the items, identify them, pack, and show
/// the plan inside the real bag. Owns the one `ARSession` for the whole flow.
@MainActor
@Observable
final class GuidedSession {
    enum Phase: Equatable {
        case findFloor
        case bag
        case items
        case identifying
        case review
        case packing
        case overlay
    }

    struct TrackedItem: Identifiable, Equatable {
        let id: Int
        var number: Int
        var fit: BoxFit
        var floorY: Float
        var stable: Bool
        var confidence: Double

        static func == (a: TrackedItem, b: TrackedItem) -> Bool {
            a.id == b.id && a.number == b.number && a.fit == b.fit && a.stable == b.stable
        }
    }

    private(set) var phase: Phase = .findFloor
    private(set) var liveCavity: ScanWorker.CavityState?
    private(set) var lockedCavity: CavityFit?
    private(set) var bagTransform: simd_float4x4?
    private(set) var container: Container?
    private(set) var tracked: [TrackedItem] = []
    var items: [Item] = []
    private(set) var identifyProgress = 0
    private(set) var showCornerFallback = false
    private(set) var cornerTaps: [SIMD3<Float>] = []
    private(set) var isCornerMode = false
    private(set) var errorText: String?

    let session = ARSession()
    let stepper = PlanStepper(pastOpacity: 0.6)
    /// Live wireframes, in world coordinates.
    let worldRoot = AnchorEntity(world: matrix_identity_float4x4)

    private let worker = ScanWorker()
    private let client: any APIClient
    private var loop: Task<Void, Never>?
    private var bagPhaseStart = Date()
    private var cavityBox: WireBox?
    private var itemBoxes: [Int: WireBox] = [:]
    private var numbers: [Int: Int] = [:]
    private var crops: [Int: (area: CGFloat, image: CGImage)] = [:]
    private var overlayAnchor: AnchorEntity?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init(client: any APIClient) {
        self.client = client
    }

    // MARK: Lifecycle

    func start() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        session.run(config)
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        stepper.stopPlay()
        session.pause()
    }

    // MARK: Tick (5 Hz)

    private func tick() async {
        guard phase == .findFloor || phase == .bag || phase == .items, !isCornerMode,
              let frame = session.currentFrame,
              let snapshot = DepthSnapshot(frame: frame) else { return }
        let floorY = Self.floorY(frame)
        let mode: ScanWorker.Mode = phase == .items ? .items(bag: lockedCavity) : .bag
        let result = await worker.process(snapshot, mode: mode, planeFloorY: floorY)

        switch phase {
        case .findFloor:
            if result.floorY != nil {
                phase = .bag
                bagPhaseStart = Date()
            }
        case .bag:
            liveCavity = result.cavity
            updateCavityWire()
            if (result.cavity?.stable ?? false) == false, Date().timeIntervalSince(bagPhaseStart) > 8 {
                showCornerFallback = true
            }
        case .items:
            updateTracked(result.items)
            updateCrops(frame)
        default:
            break
        }
    }

    /// The lowest horizontal plane ARKit has found, preferring planes classified as floor.
    private static func floorY(_ frame: ARFrame) -> Float? {
        let planes = frame.anchors.compactMap { $0 as? ARPlaneAnchor }.filter { $0.alignment == .horizontal }
        let floors = planes.filter { $0.classification == .floor }
        let pool = floors.isEmpty ? planes : floors
        return pool.map { $0.transform.columns.3.y }.min()
    }

    // MARK: Bag

    private func updateCavityWire() {
        guard let state = liveCavity else {
            cavityBox?.entity.isEnabled = false
            return
        }
        let box = cavityBox ?? {
            let b = WireBox(name: "cavity")
            worldRoot.addChild(b.entity)
            cavityBox = b
            return b
        }()
        box.entity.isEnabled = true
        let fit = state.fit.box
        var t = WireBox.transform(for: fit, floorY: state.fit.floorY)
        t.columns.3.y = state.fit.floorY + fit.height / 2
        box.update(
            size: [fit.rect.long, fit.height, fit.rect.short],
            transform: t,
            color: state.stable ? .systemGreen : .systemYellow
        )
    }

    var canLockBag: Bool { liveCavity?.stable ?? false }

    /// Locks the scanned cavity as the bag and moves on to the items.
    func lockBag() {
        guard let state = liveCavity, let frame = session.currentFrame else { return }
        let camera = frame.camera.transform.columns.3
        let fit = state.fit
        lockedCavity = fit
        bagTransform = fit.transform(cameraXZ: [camera.x, camera.z])
        container = ContainerFactory.fromCavity(
            innerLongCm: Double(fit.box.rect.long * 100),
            innerShortCm: Double(fit.box.rect.short * 100),
            shellDepthCm: Double(fit.shellDepth * 100),
            confidence: state.confidence
        )
        cavityBox?.update(
            size: [fit.box.rect.long, fit.shellDepth, fit.box.rect.short],
            transform: { var t = WireBox.transform(for: fit.box, floorY: fit.floorY); t.columns.3.y = fit.floorY + fit.shellDepth / 2; return t }(),
            color: UIColor.white.withAlphaComponent(0.6)
        )
        enterItems()
    }

    /// Fallback when the cavity won't settle: tap the two inside back corners.
    func beginCornerTaps() {
        isCornerMode = true
        cornerTaps = []
        cavityBox?.entity.isEnabled = false
    }

    func cancelCornerTaps() {
        isCornerMode = false
        cornerTaps = []
        bagPhaseStart = Date()
    }

    /// Back-left then back-right inside corners, on the cavity floor. The other two inner
    /// sizes come from `preset` (the trip's bag).
    func handleCornerTap(_ point: SIMD3<Float>, preset: Container?) {
        cornerTaps.append(point)
        guard cornerTaps.count == 2 else { return }
        let a = cornerTaps[0], b = cornerTaps[1]
        var x = b - a
        x.y = 0
        let long = length(x)
        guard long > 0.2 else {
            cornerTaps = []
            errorText = Copy.Guided.cornersTooClose
            return
        }
        x = normalize(x)
        let y = SIMD3<Float>(0, 1, 0)
        let z = cross(x, y)
        let inner = preset?.compartments.first?.dims ?? [72, 26, 47]
        let short = Float(inner[2]) / 100, depth = Float(inner[1]) / 200
        let origin = SIMD3<Float>(a.x, min(a.y, b.y), a.z)
        bagTransform = simd_float4x4(SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(origin, 1))
        let centre = origin + x * (long / 2) + z * (short / 2)
        let yaw = OrientedRect.normalizedYaw(atan2(x.z, x.x))
        lockedCavity = CavityFit(
            box: BoxFit(rect: OrientedRect(center: [centre.x, centre.z], yaw: yaw, long: long, short: short), height: depth, cellCount: 0, fillRatio: 1),
            floorY: origin.y
        )
        container = ContainerFactory.fromCavity(
            innerLongCm: Double(long * 100),
            innerShortCm: inner[2],
            shellDepthCm: inner[1] / 2,
            confidence: 0.7
        )
        isCornerMode = false
        enterItems()
    }

    // MARK: Items

    private func enterItems() {
        phase = .items
        errorText = nil
        tracked = []
        numbers = [:]
        crops = [:]
        Task { await worker.resetItems() }
    }

    private func updateTracked(_ states: [ScanWorker.ItemState]) {
        var next: [TrackedItem] = []
        for s in states {
            if s.stable, numbers[s.id] == nil { numbers[s.id] = numbers.count + 1 }
            guard let number = numbers[s.id] else { continue }
            next.append(TrackedItem(id: s.id, number: number, fit: s.fit, floorY: s.floorY, stable: s.stable, confidence: s.confidence))
        }
        tracked = next.sorted { $0.number < $1.number }

        let live = Set(tracked.map(\.id))
        for (id, box) in itemBoxes where !live.contains(id) {
            box.entity.removeFromParent()
            itemBoxes[id] = nil
        }
        for t in tracked {
            let box = itemBoxes[t.id] ?? {
                let b = WireBox(name: "track-\(t.id)")
                b.setLabel("\(t.number)")
                worldRoot.addChild(b.entity)
                itemBoxes[t.id] = b
                return b
            }()
            box.update(
                size: [t.fit.rect.long, t.fit.height, t.fit.rect.short],
                transform: WireBox.transform(for: t.fit, floorY: t.floorY),
                color: t.stable ? .systemGreen : .systemYellow
            )
        }
    }

    /// Drops a false positive the user tapped.
    func dropItem(entityName: String) {
        guard entityName.hasPrefix("track-"), let id = Int(entityName.dropFirst(6)) else { return }
        itemBoxes[id]?.entity.removeFromParent()
        itemBoxes[id] = nil
        tracked.removeAll { $0.id == id }
        crops[id] = nil
        Task { await worker.suppressItem(id: id) }
    }

    /// Keeps the best photo of each item: fully in frame, largest on screen.
    private func updateCrops(_ frame: ARFrame) {
        let res = frame.camera.imageResolution
        var image: CIImage?
        for t in tracked {
            let corners = Self.corners(t.fit, floorY: t.floorY)
            let pts = corners.map { frame.camera.projectPoint($0, orientation: .landscapeRight, viewportSize: res) }
            let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
            let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
            guard minX > 0, minY > 0, maxX < res.width, maxY < res.height else { continue }
            // Behind the camera?
            let camToWorld = frame.camera.transform
            let viewDir = -SIMD3(camToWorld.columns.2.x, camToWorld.columns.2.y, camToWorld.columns.2.z)
            let camPos = SIMD3(camToWorld.columns.3.x, camToWorld.columns.3.y, camToWorld.columns.3.z)
            guard corners.allSatisfy({ dot($0 - camPos, viewDir) > 0.05 }) else { continue }
            let area = (maxX - minX) * (maxY - minY)
            if let best = crops[t.id], best.area * 1.1 >= area { continue }

            let source = image ?? CIImage(cvPixelBuffer: frame.capturedImage)
            image = source
            let mx = (maxX - minX) * 0.1, my = (maxY - minY) * 0.1
            // CIImage's origin is bottom-left.
            let rect = CGRect(x: minX - mx, y: res.height - maxY - my, width: maxX - minX + 2 * mx, height: maxY - minY + 2 * my)
                .intersection(CGRect(origin: .zero, size: res))
            let cropped = source.cropped(to: rect).oriented(.right)
            if let cg = ciContext.createCGImage(cropped, from: cropped.extent) {
                crops[t.id] = (area, cg)
            }
        }
    }

    private static func corners(_ fit: BoxFit, floorY: Float) -> [SIMD3<Float>] {
        fit.rect.corners.flatMap { c in
            [SIMD3(c.x, floorY, c.y), SIMD3(c.x, floorY + fit.height, c.y)]
        }
    }

    var canFinishItems: Bool { tracked.contains { $0.stable } }

    // MARK: Identify

    func identifyItems() async {
        let found = tracked.filter(\.stable)
        guard !found.isEmpty else { return }
        phase = .identifying
        identifyProgress = 0
        itemBoxes.values.forEach { $0.entity.isEnabled = false }

        struct Job: Sendable {
            var index: Int
            var image: String
            var dims: MeasuredDims
        }
        let jobs: [Job] = found.enumerated().map { index, t in
            let cm = t.fit.dimsCm
            let image = crops[t.id].flatMap { ImageCapture.jpegBase64(from: $0.image) } ?? ImageCapture.placeholderBase64()
            return Job(index: index, image: image, dims: MeasuredDims(w: cm.w, h: cm.h, d: cm.d, method: .lidar, confidence: t.confidence))
        }

        let client = self.client
        var results: [Int: Item] = [:]
        await withTaskGroup(of: (Int, Item?).self) { group in
            var next = 0
            func add() {
                guard next < jobs.count else { return }
                let job = jobs[next]
                next += 1
                group.addTask {
                    let response = try? await client.scanItem(imageBase64: job.image, measured: job.dims, reference: nil, hint: nil)
                    return (job.index, response?.item)
                }
            }
            for _ in 0..<min(4, jobs.count) { add() }
            for await (index, item) in group {
                results[index] = item
                identifyProgress += 1
                add()
            }
        }

        items = jobs.map { job in
            var item = results[job.index] ?? Item(
                id: UUID().uuidString,
                name: "\(Copy.Guided.unknownItem) \(job.index + 1)",
                w: job.dims.w, h: job.dims.h, d: job.dims.d,
                kg: 0.3,
                category: .other,
                confidence: 0.5,
                source: .scan
            )
            // LiDAR is the authority on size (rule 6).
            item.w = job.dims.w
            item.h = job.dims.h
            item.d = job.dims.d
            item.source = .scan
            item.measurement = Measurement(method: .lidar, confidence: job.dims.confidence, deviceHasLidar: true)
            return item
        }
        phase = .review
    }

    func backToItems() {
        itemBoxes.values.forEach { $0.entity.isEnabled = true }
        phase = .items
    }

    // MARK: Pack and overlay

    func pack(itemsStore: ItemsStore, tripStore: TripStore, planStore: PlanStore) async {
        guard let container, let bagTransform else { return }
        phase = .packing
        itemsStore.items = items
        tripStore.setBag(container)
        await planStore.computePlan(items: items, into: container)
        guard let plan = planStore.plan else {
            phase = .review
            return
        }
        worldRoot.isEnabled = false
        stepper.load(plan: plan, items: items, container: container, style: .wireframe)
        overlayAnchor?.removeFromParent()
        let anchor = AnchorEntity(world: bagTransform)
        anchor.addChild(stepper.root)
        overlayAnchor = anchor
        phase = .overlay
    }

    /// The overlay anchor, for the AR view to add once.
    var overlayEntity: AnchorEntity? { overlayAnchor }

    /// Shell depth in cm: items above it go under the lid.
    var shellDepthCm: Double? { lockedCavity.map { Double($0.shellDepth * 100) } }

    func restart() {
        stepper.stopPlay()
        overlayAnchor?.removeFromParent()
        overlayAnchor = nil
        worldRoot.isEnabled = true
        itemBoxes.values.forEach { $0.entity.removeFromParent() }
        itemBoxes = [:]
        cavityBox?.entity.removeFromParent()
        cavityBox = nil
        liveCavity = nil
        lockedCavity = nil
        bagTransform = nil
        container = nil
        tracked = []
        items = []
        showCornerFallback = false
        isCornerMode = false
        phase = .findFloor
        Task { await worker.reset() }
    }
}
