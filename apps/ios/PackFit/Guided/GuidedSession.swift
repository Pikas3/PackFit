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
        /// Packed on a phone without LiDAR: the plan opens in the 3D viewer.
        case packed
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
    /// The trip's bag; tap-measured bags take their depth from it.
    var presetBag: Container?
    /// What kind of bag is being scanned; sets the lid depth and the wall allowance.
    var bagKind: ContainerFactory.BagKind = .hardShell
    /// Without LiDAR: the open bag measured from outlines, live until locked.
    private(set) var liveBag: HullWorker.State?
    /// Without LiDAR: what the user should do to finish the views.
    private(set) var hullHint: HullWorker.Hint?

    /// Item being measured by taps: three base corners, then the top edge.
    struct TapDraft: Equatable {
        var rect: OrientedRect
        var floorY: Float
        var longCm: Double
        var shortCm: Double
        var heightCm: Double = 0
        var hasHeight = false
        var heightFromSurface = false
    }

    enum TapStep: Equatable {
        case corner(Int)
        case top
        case adjust
    }

    /// LiDAR depth is available. Without it the flow runs on ARKit tracking and taps.
    let hasDepth: Bool
    private(set) var isTapMeasuring = false
    private(set) var itemTaps: [SIMD3<Float>] = []
    var draft: TapDraft?
    private(set) var floorY: Float?

    let session = ARSession()
    let stepper = PlanStepper(pastOpacity: 0.6)
    /// Live wireframes, in world coordinates.
    let worldRoot = AnchorEntity(world: matrix_identity_float4x4)

    private let worker = ScanWorker()
    private let hullWorker = HullWorker()
    /// Targets the hull worker is still measuring; frames are only segmented while true.
    private var hullActive = false
    private let bagHullID = 1
    private let client: any APIClient
    private var loop: Task<Void, Never>?
    /// Floor (x, z) the user tapped inside the open bag.
    private var bagSeed: SIMD2<Float>?
    private var bagTapTime: Date?
    /// Tapped items the worker is still refining.
    private(set) var measuring: Set<Int> = []
    private var removedIDs: Set<Int> = []
    private var labeledIDs: Set<Int> = []
    private var cavityBox: WireBox?
    private var itemBoxes: [Int: WireBox] = [:]
    private var numbers: [Int: Int] = [:]
    private var crops: [Int: (area: CGFloat, image: CGImage)] = [:]
    private var overlayAnchor: AnchorEntity?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var tapTracked: [TrackedItem] = []
    private var lastItemStates: [ScanWorker.ItemState] = []
    private var draftBox: WireBox?
    private var nextTapID = 100_000
    private var tapMeasuredItemIDs: Set<String> = []

    init(client: any APIClient) {
        self.client = client
        hasDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    // MARK: Lifecycle

    func start() {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        if hasDepth {
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }
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
        guard phase == .findFloor || phase == .bag || phase == .items,
              let frame = session.currentFrame else { return }
        let planeFloorY = Self.floorY(frame)
        if let planeFloorY { floorY = planeFloorY }

        // Without LiDAR: wait for ARKit's floor plane, then measure from outlines.
        guard hasDepth else {
            if phase == .findFloor, planeFloorY != nil { phase = .bag }
            if hullActive, !isCornerMode, !isTapMeasuring { await tickHull(frame) }
            return
        }

        guard !isCornerMode, !isTapMeasuring, let snapshot = DepthSnapshot(frame: frame) else { return }
        let mode: ScanWorker.Mode = phase == .items ? .items : .bag(seed: bagSeed)
        // Segmenting costs ~50 ms, so only while a tapped item is still being measured.
        let image = phase == .items && !measuring.isEmpty ? uprightImage(frame) : nil
        let result = await worker.process(snapshot, image: image, mode: mode, planeFloorY: planeFloorY)
        if floorY == nil { floorY = result.floorY }

        switch phase {
        case .findFloor:
            if result.floorY != nil { phase = .bag }
        case .bag:
            guard let tapped = bagTapTime else { break }
            liveCavity = result.cavity
            updateCavityWire()
            let elapsed = Date().timeIntervalSince(tapped)
            if result.cavity != nil {
                errorText = nil
            } else if let failure = result.cavityFailure, elapsed > 2 {
                errorText = Copy.Guided.bagFailure(failure)
            }
            if (result.cavity?.stable ?? false) == false, elapsed > 6 {
                showCornerFallback = true
            }
        case .items:
            let states = result.items.filter { !removedIDs.contains($0.id) }
            lastItemStates = states
            for s in states where s.stable { measuring.remove(s.id) }
            if !result.failedItems.isEmpty {
                result.failedItems.forEach { measuring.remove($0) }
                errorText = Copy.Guided.itemNotFound
            }
            updateTracked(states)
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

    // MARK: Without LiDAR

    private func tickHull(_ frame: ARFrame) async {
        guard let image = uprightImage(frame) else { return }
        let result = await hullWorker.process(HullFrame(frame: frame, image: image))
        hullActive = await hullWorker.isMeasuring
        hullHint = result.hint
        switch phase {
        case .bag:
            liveBag = result.states.first { $0.id == bagHullID }
            if result.failed.contains(bagHullID) { errorText = Copy.Guided.bagNotFound }
            updateBagHullWire()
        case .items:
            let states = result.states.filter { $0.kind == .item && !removedIDs.contains($0.id) }
                .map { ScanWorker.ItemState(id: $0.id, fit: $0.fit, floorY: $0.floorY, stable: $0.stable, confidence: $0.confidence) }
            lastItemStates = states
            for s in states where s.stable { measuring.remove(s.id) }
            if !result.failed.isEmpty {
                result.failed.forEach { measuring.remove($0) }
                errorText = Copy.Guided.itemNotFound
            }
            updateTracked(states)
            updateCrops(frame)
        default:
            break
        }
    }

    /// Normalized sensor coordinates under a screen point.
    private func sensorPoint(_ point: CGPoint, in view: ARView, frame: ARFrame) -> SIMD2<Float> {
        let size = view.bounds.size
        let toImage = frame.displayTransform(for: .portrait, viewportSize: size).inverted()
        let n = CGPoint(x: point.x / size.width, y: point.y / size.height).applying(toImage)
        return [Float(n.x), Float(n.y)]
    }

    /// One tap on an item or inside the open bag starts measuring it from its outline.
    private func startHull(at point: CGPoint, in view: ARView, kind: HullWorker.Kind, id: Int) -> Bool {
        guard let frame = session.currentFrame, let floor = floorY else {
            errorText = Copy.Guided.findFloor
            return false
        }
        guard let hit = Self.hit(view, point, floorFirst: true) else {
            errorText = Copy.Guided.tapMissed
            return false
        }
        let sensor = sensorPoint(point, in: view, frame: frame)
        errorText = nil
        hullActive = true
        Task { await hullWorker.add(id: id, kind: kind, tapSensor: sensor, tapFloor: [hit.x, floor, hit.z], floorY: floor) }
        return true
    }

    private func seedBagHull(at point: CGPoint, in view: ARView) {
        liveBag = nil
        cavityBox?.entity.isEnabled = false
        Task { await hullWorker.remove(id: bagHullID) }
        _ = startHull(at: point, in: view, kind: .bag(expectTwo: bagKind == .hardShell), id: bagHullID)
    }

    private func updateBagHullWire() {
        guard let state = liveBag else {
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
        let fit = state.fit
        box.update(
            size: [fit.rect.long, fit.height, fit.rect.short],
            transform: WireBox.transform(for: fit, floorY: state.floorY),
            color: state.stable ? .systemGreen : .systemYellow
        )
    }

    /// Locks the outline-measured bag: the tapped half is the base, the other the lid.
    private func lockHullBag() {
        guard let state = liveBag, state.stable, let frame = session.currentFrame else { return }
        let shells = state.shells ?? ShellSplitter.Shells(base: state.fit, lid: nil)
        let container = ContainerFactory.fromShells(
            outerLongCm: Double(shells.base.rect.long * 100),
            outerShortCm: Double(shells.base.rect.short * 100),
            baseDepthCm: Double(shells.base.height * 100),
            lidDepthCm: shells.lid.map { Double($0.height * 100) },
            kind: bagKind,
            confidence: state.confidence
        )
        self.container = container
        // The plan's frame sits on the inside of the base shell.
        let inner = container.compartments[0].dims
        var rect = shells.base.rect
        rect.long = Float(inner[0] / 100)
        rect.short = Float(inner[2] / 100)
        let fit = CavityFit(box: BoxFit(rect: rect, height: shells.base.height, cellCount: 0, fillRatio: 1), floorY: state.floorY)
        lockedCavity = fit
        let camera = frame.camera.transform.columns.3
        bagTransform = fit.transform(cameraXZ: [camera.x, camera.z])
        showLockedCavity(fit)
        enterItems()
    }

    var hullBagReady: Bool { liveBag?.stable ?? false }

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

    var canLockBag: Bool { hasDepth ? (liveCavity?.stable ?? false) : hullBagReady }
    var hasBagSeed: Bool { hasDepth ? bagSeed != nil : liveBag != nil || hullActive }

    /// Locks the scanned cavity as the bag and moves on to the items.
    func lockBag() {
        guard hasDepth else { return lockHullBag() }
        guard let state = liveCavity, let frame = session.currentFrame else { return }
        let camera = frame.camera.transform.columns.3
        let fit = state.fit
        lockedCavity = fit
        bagTransform = fit.transform(cameraXZ: [camera.x, camera.z])
        container = ContainerFactory.fromCavity(
            innerLongCm: Double(fit.box.rect.long * 100),
            innerShortCm: Double(fit.box.rect.short * 100),
            shellDepthCm: Double(fit.shellDepth * 100),
            confidence: state.confidence,
            lidFraction: bagKind.lidFraction
        )
        showLockedCavity(fit)
        enterItems()
    }

    private func showLockedCavity(_ fit: CavityFit) {
        let box = cavityBox ?? {
            let b = WireBox(name: "cavity")
            worldRoot.addChild(b.entity)
            cavityBox = b
            return b
        }()
        box.entity.isEnabled = true
        var t = WireBox.transform(for: fit.box, floorY: fit.floorY)
        t.columns.3.y = fit.floorY + fit.shellDepth / 2
        box.update(size: [fit.box.rect.long, fit.shellDepth, fit.box.rect.short], transform: t, color: UIColor.white.withAlphaComponent(0.6))
    }

    /// Fallback when the cavity won't settle: tap the two inside back corners.
    func beginCornerTaps() {
        isCornerMode = true
        cornerTaps = []
        errorText = nil
        cavityBox?.entity.isEnabled = false
    }

    func cancelCornerTaps() {
        isCornerMode = false
        cornerTaps = []
        bagTapTime = bagSeed == nil ? nil : Date()
    }

    /// Three inside corners of the open shell: back-left, back-right, then a front corner.
    /// The shell depth comes from the trip's bag.
    func handleCornerTap(_ point: SIMD3<Float>) {
        cornerTaps.append(point)
        errorText = nil
        guard cornerTaps.count == 3 else { return }
        guard let rect = TapMeasure.footprint(cornerTaps[0], cornerTaps[1], cornerTaps[2]), rect.short > 0.15 else {
            cornerTaps = []
            errorText = Copy.Guided.cornersTooClose
            return
        }
        let inner = presetBag?.compartments.first?.dims ?? [72, 26, 47]
        let floor = cornerTaps.map(\.y).min() ?? 0
        let fit = CavityFit(box: BoxFit(rect: rect, height: Float(inner[1]) / 200, cellCount: 0, fillRatio: 1), floorY: floor)
        let camera = session.currentFrame?.camera.transform.columns.3 ?? SIMD4(rect.center.x, 0, rect.center.y + 1, 1)
        lockedCavity = fit
        bagTransform = fit.transform(cameraXZ: [camera.x, camera.z])
        container = ContainerFactory.fromCavity(
            innerLongCm: Double(rect.long * 100),
            innerShortCm: Double(rect.short * 100),
            shellDepthCm: inner[1] / 2,
            confidence: 0.7,
            method: .ar,
            lidFraction: bagKind.lidFraction
        )
        isCornerMode = false
        cornerTaps = []
        showLockedCavity(fit)
        enterItems()
    }

    // MARK: Taps

    /// Routes a tap on the AR view to whatever the current step needs.
    func handleTap(at point: CGPoint, in view: ARView) {
        if isCornerMode {
            if let p = Self.hit(view, point, floorFirst: false) { handleCornerTap(p) }
            return
        }
        switch phase {
        case .bag where hasDepth:
            seedBag(at: point, in: view)
        case .bag:
            seedBagHull(at: point, in: view)
        case .items:
            if isTapMeasuring {
                handleItemTap(at: point, in: view)
            } else {
                measureItem(at: point, in: view)
            }
        default:
            break
        }
    }

    /// One tap inside the open shell: the cavity is grown from there.
    private func seedBag(at point: CGPoint, in view: ARView) {
        guard let p = worldPoint(at: point, in: view) else {
            errorText = Copy.Guided.tapNoDepth
            return
        }
        bagSeed = [p.x, p.z]
        bagTapTime = Date()
        errorText = nil
        liveCavity = nil
        showCornerFallback = false
        cavityBox?.entity.isEnabled = false
        Task { await worker.resetCavity() }
    }

    /// One tap on an item: the worker finds its outline and measures it over a few frames.
    /// Tapping an item that already has a box measures it again.
    private func measureItem(at point: CGPoint, in view: ARView) {
        guard hasDepth else { return measureItemHull(at: point, in: view) }
        guard let p = worldPoint(at: point, in: view) else {
            errorText = Copy.Guided.tapNoDepth
            return
        }
        errorText = nil
        let hit = SIMD2(p.x, p.z)
        for t in tracked where t.fit.rect.contains(hit, margin: 0.01) { removeItem(id: t.id) }
        let id = nextTapID
        nextTapID += 1
        measuring.insert(id)
        Task { await worker.addTarget(id: id, seed: p) }
    }

    /// Without LiDAR: one tap starts measuring the item from its outline while the user
    /// moves around it. Tapping a measured item measures it again.
    private func measureItemHull(at point: CGPoint, in view: ARView) {
        if let hit = Self.hit(view, point, floorFirst: true) {
            for t in tracked where t.fit.rect.contains(SIMD2(hit.x, hit.z), margin: 0.01) { removeItem(id: t.id) }
        }
        let id = nextTapID
        if startHull(at: point, in: view, kind: .item, id: id) {
            nextTapID += 1
            measuring.insert(id)
        }
    }

    /// The world point under a screen tap, read straight from the depth map so a thin item's
    /// top isn't mistaken for the floor. Falls back to ARKit's raycast.
    private func worldPoint(at point: CGPoint, in view: ARView) -> SIMD3<Float>? {
        if let frame = session.currentFrame, let snapshot = DepthSnapshot(frame: frame) {
            let size = view.bounds.size
            let toImage = frame.displayTransform(for: .portrait, viewportSize: size).inverted()
            let n = CGPoint(x: point.x / size.width, y: point.y / size.height).applying(toImage)
            if let p = snapshot.worldPoint(atNormalized: [Float(n.x), Float(n.y)]) { return p }
        }
        if let r = view.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first {
            let c = r.worldTransform.columns.3
            return [c.x, c.y, c.z]
        }
        return nil
    }

    /// The camera image turned upright and scaled to 720 px wide, for segmentation.
    private func uprightImage(_ frame: ARFrame) -> UprightImage? {
        let image = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        let scale = 720 / image.extent.width
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UprightImage(cgImage: cg)
    }

    /// A horizontal hit. Item corners sit on the floor, so they prefer the floor plane;
    /// the bag's inside corners prefer the surface ARKit estimates under the tap.
    private static func hit(_ view: ARView, _ point: CGPoint, floorFirst: Bool) -> SIMD3<Float>? {
        let order: [ARRaycastQuery.Target] = floorFirst ? [.existingPlaneInfinite, .estimatedPlane] : [.estimatedPlane, .existingPlaneInfinite]
        for target in order {
            if let r = view.raycast(from: point, allowing: target, alignment: .horizontal).first {
                let c = r.worldTransform.columns.3
                return [c.x, c.y, c.z]
            }
        }
        return nil
    }

    var tapStep: TapStep {
        if itemTaps.count < 3 { return .corner(itemTaps.count + 1) }
        return draft?.hasHeight == true ? .adjust : .top
    }

    func startTapMeasuring() {
        isTapMeasuring = true
        resetDraft()
    }

    /// Back to one-tap measuring.
    func stopTapMeasuring() {
        resetDraft()
        isTapMeasuring = false
    }

    func resetDraft() {
        itemTaps = []
        draft = nil
        errorText = nil
        draftBox?.entity.removeFromParent()
        draftBox = nil
    }

    private func handleItemTap(at point: CGPoint, in view: ARView) {
        errorText = nil
        switch tapStep {
        case .corner:
            guard let p = Self.hit(view, point, floorFirst: true) else {
                errorText = Copy.Guided.tapMissed
                return
            }
            itemTaps.append(p)
            guard itemTaps.count == 3 else { return }
            guard let rect = TapMeasure.footprint(itemTaps[0], itemTaps[1], itemTaps[2]) else {
                itemTaps = []
                errorText = Copy.Guided.cornersTooClose
                return
            }
            let floor = floorY ?? (itemTaps.map(\.y).reduce(0, +) / 3)
            draft = TapDraft(rect: rect, floorY: floor, longCm: round1(rect.long * 100), shortCm: round1(rect.short * 100))
            refreshDraftWire()

        case .top:
            guard var d = draft else { return }
            var height: Float?
            var fromSurface = false
            if let r = view.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first {
                let c = r.worldTransform.columns.3
                height = TapMeasure.heightFromSurfaceHit([c.x, c.y, c.z], footprint: d.rect, floorY: d.floorY)
                fromSurface = height != nil
            }
            if height == nil, let ray = view.ray(through: point) {
                height = TapMeasure.heightFromEdgeRay(origin: ray.origin, direction: ray.direction, footprint: d.rect, floorY: d.floorY)
            }
            guard let height else {
                errorText = Copy.Guided.heightMissed
                return
            }
            d.heightCm = round1(height * 100)
            d.hasHeight = true
            d.heightFromSurface = fromSurface
            draft = d
            refreshDraftWire()

        case .adjust:
            break
        }
    }

    /// Redraws the draft box after taps or size edits.
    func refreshDraftWire() {
        guard let d = draft else { return }
        let box = draftBox ?? {
            let b = WireBox(name: "draft")
            worldRoot.addChild(b.entity)
            draftBox = b
            return b
        }()
        var rect = d.rect
        rect.long = Float(d.longCm / 100)
        rect.short = Float(d.shortCm / 100)
        let h = d.hasHeight ? Float(d.heightCm / 100) : 0.005
        let fit = BoxFit(rect: rect, height: h, cellCount: 0, fillRatio: 1)
        box.update(size: [rect.long, h, rect.short], transform: WireBox.transform(for: fit, floorY: d.floorY), color: .systemYellow)
    }

    /// Adds the measured draft as a found item.
    func addDraftItem() {
        guard let d = draft, d.hasHeight, d.longCm > 0, d.shortCm > 0, d.heightCm > 0 else { return }
        var rect = d.rect
        rect.long = Float(d.longCm / 100)
        rect.short = Float(d.shortCm / 100)
        let id = nextTapID
        nextTapID += 1
        numbers[id] = numbers.count + 1
        tapTracked.append(TrackedItem(
            id: id,
            number: numbers[id]!,
            fit: BoxFit(rect: rect, height: Float(d.heightCm / 100), cellCount: 0, fillRatio: 1),
            floorY: d.floorY,
            stable: true,
            confidence: TapMeasure.confidence(heightFromSurface: d.heightFromSurface)
        ))
        resetDraft()
        updateTracked(lastItemStates)
        if let frame = session.currentFrame { updateCrops(frame) }
    }

    private func round1(_ v: Float) -> Double { (Double(v) * 10).rounded() / 10 }

    // MARK: Items

    private func enterItems() {
        phase = .items
        errorText = nil
        tracked = []
        tapTracked = []
        lastItemStates = []
        numbers = [:]
        crops = [:]
        measuring = []
        labeledIDs = []
        isTapMeasuring = false
        resetDraft()
        hullActive = false
        hullHint = nil
        Task {
            await worker.resetItems()
            await hullWorker.reset()
        }
    }

    private func updateTracked(_ states: [ScanWorker.ItemState]) {
        var next: [TrackedItem] = []
        for s in states {
            if s.stable, numbers[s.id] == nil { numbers[s.id] = numbers.count + 1 }
            // Number 0 while still measuring; it gets a number once it settles.
            next.append(TrackedItem(id: s.id, number: numbers[s.id] ?? 0, fit: s.fit, floorY: s.floorY, stable: s.stable, confidence: s.confidence))
        }
        next.append(contentsOf: tapTracked)
        tracked = next.sorted { ($0.number == 0 ? Int.max : $0.number, $0.id) < ($1.number == 0 ? Int.max : $1.number, $1.id) }

        let live = Set(tracked.map(\.id))
        for (id, box) in itemBoxes where !live.contains(id) {
            box.entity.removeFromParent()
            itemBoxes[id] = nil
        }
        for t in tracked {
            let box = itemBoxes[t.id] ?? {
                let b = WireBox(name: "track-\(t.id)")
                worldRoot.addChild(b.entity)
                itemBoxes[t.id] = b
                return b
            }()
            if t.stable, labeledIDs.insert(t.id).inserted { box.setLabel("\(t.number)") }
            box.update(
                size: [t.fit.rect.long, t.fit.height, t.fit.rect.short],
                transform: WireBox.transform(for: t.fit, floorY: t.floorY),
                color: t.stable ? .systemGreen : .systemYellow
            )
        }
    }

    /// Removes a measured item, or one still being measured.
    func removeItem(id: Int) {
        itemBoxes[id]?.entity.removeFromParent()
        itemBoxes[id] = nil
        tracked.removeAll { $0.id == id }
        tapTracked.removeAll { $0.id == id }
        lastItemStates.removeAll { $0.id == id }
        crops[id] = nil
        measuring.remove(id)
        labeledIDs.remove(id)
        removedIDs.insert(id)
        Task {
            await worker.removeTarget(id: id)
            await hullWorker.remove(id: id)
        }
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
            var tapped: Bool
        }
        let tapIDs = Set(tapTracked.map(\.id))
        let jobs: [Job] = found.enumerated().map { index, t in
            let cm = t.fit.dimsCm
            let image = crops[t.id].flatMap { ImageCapture.jpegBase64(from: $0.image) } ?? ImageCapture.placeholderBase64()
            // Without depth, sizes come from the camera's pose and the item's outline or taps.
            let method: MeasureMethod = hasDepth && !tapIDs.contains(t.id) ? .lidar : .ar
            return Job(index: index, image: image, dims: MeasuredDims(w: cm.w, h: cm.h, d: cm.d, method: method, confidence: t.confidence),
                       tapped: tapIDs.contains(t.id))
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

        tapMeasuredItemIDs = []
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
            // The device measurement is the authority on size (rule 6).
            item.w = job.dims.w
            item.h = job.dims.h
            item.d = job.dims.d
            item.source = .scan
            item.measurement = Measurement(method: job.dims.method, confidence: job.dims.confidence, deviceHasLidar: hasDepth)
            if job.tapped { tapMeasuredItemIDs.insert(item.id) }
            return item
        }
        phase = .review
    }

    /// Back from the 3D viewer: the list stays editable for another try.
    func returnedFromViewer() {
        if phase == .packed { phase = .review }
    }

    func isTapMeasured(_ itemID: String) -> Bool { tapMeasuredItemIDs.contains(itemID) }

    func backToItems() {
        itemBoxes.values.forEach { $0.entity.isEnabled = true }
        phase = .items
    }

    // MARK: Pack and overlay

    func pack(itemsStore: ItemsStore, tripStore: TripStore, planStore: PlanStore) async {
        guard let container, let bagTransform else { return }
        phase = .packing
        itemsStore.items = items
        itemsStore.tapMeasuredIDs = tapMeasuredItemIDs.intersection(items.map(\.id))
        tripStore.setBag(container)
        await planStore.computePlan(items: items, into: container)
        guard let plan = planStore.plan else {
            phase = .review
            return
        }
        // Without LiDAR the overlay can't be anchored tightly enough; show the 3D viewer.
        guard hasDepth else {
            phase = .packed
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
        bagSeed = nil
        bagTapTime = nil
        measuring = []
        labeledIDs = []
        liveCavity = nil
        lockedCavity = nil
        bagTransform = nil
        container = nil
        tracked = []
        tapTracked = []
        lastItemStates = []
        items = []
        resetDraft()
        isTapMeasuring = false
        showCornerFallback = false
        isCornerMode = false
        liveBag = nil
        hullActive = false
        hullHint = nil
        phase = .findFloor
        Task {
            await worker.reset()
            await hullWorker.reset()
        }
    }
}
