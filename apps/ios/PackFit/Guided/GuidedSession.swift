import AVFoundation
import CoreImage
import Foundation
import RealityKit
import SwiftUI
import simd

/// Guided LiDAR flow using AVFoundation `builtInLiDARDepthCamera` (no ARKit).
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
    var presetBag: Container?

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

    let hasDepth: Bool
    private(set) var isTapMeasuring = false
    private(set) var itemTaps: [SIMD3<Float>] = []
    var draft: TapDraft?
    private(set) var floorY: Float?
    private(set) var liveWires: [LiveWire] = []
    private(set) var latestSnapshot: DepthSnapshot?

    let capture = LidarCaptureSession()
    let pose = GravityPose()
    let stepper = PlanStepper(pastOpacity: 0.6)

    private let worker = ScanWorker()
    private let client: any APIClient
    private var loop: Task<Void, Never>?
    private var bagSeed: SIMD2<Float>?
    private var bagTapTime: Date?
    private(set) var measuring: Set<Int> = []
    private var removedIDs: Set<Int> = []
    private var labeledIDs: Set<Int> = []
    private var numbers: [Int: Int] = [:]
    private var crops: [Int: (area: CGFloat, image: CGImage)] = [:]
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var tapTracked: [TrackedItem] = []
    private var lastItemStates: [ScanWorker.ItemState] = []
    private var nextTapID = 100_000
    private var tapMeasuredItemIDs: Set<String> = []
    private var cavityWireID = "cavity"
    private var draftWireID = "draft"
    private var itemWireLabels: [Int: String] = [:]

    init(client: any APIClient) {
        self.client = client
        hasDepth = LidarCaptureSession.isLiDARAvailable
    }

    // MARK: Lifecycle

    func start() {
        guard hasDepth else {
            errorText = Copy.Guided.noLidar
            return
        }
        pose.start()
        do {
            try capture.start()
        } catch {
            errorText = Copy.Guided.lidarStartFailed
            return
        }
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
        capture.stop()
        pose.stop()
    }

    // MARK: Tick (5 Hz)

    private func tick() async {
        guard phase == .findFloor || phase == .bag || phase == .items,
              let frame = capture.latest else { return }

        guard !isCornerMode, !isTapMeasuring else { return }
        let cameraToWorld = pose.cameraToWorld()
        guard let snapshot = DepthSnapshot(
            depthData: frame.depthData,
            videoBuffer: frame.videoBuffer,
            cameraToWorld: cameraToWorld,
            timestamp: frame.timestamp
        ) else { return }
        latestSnapshot = snapshot

        let mode: ScanWorker.Mode = phase == .items ? .items : .bag(seed: bagSeed)
        let image = phase == .items && !measuring.isEmpty ? uprightImage(frame.videoBuffer) : nil
        // Floor from the height map (no ARKit planes).
        let result = await worker.process(snapshot, image: image, mode: mode, planeFloorY: floorY)
        if floorY == nil { floorY = result.floorY }

        switch phase {
        case .findFloor:
            if result.floorY != nil {
                floorY = result.floorY
                phase = .bag
            }
        case .bag:
            guard let tapped = bagTapTime else { break }
            liveCavity = result.cavity
            refreshWires()
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
            updateCrops(snapshot: snapshot, video: frame.videoBuffer)
        default:
            break
        }
    }

    // MARK: Bag

    var canLockBag: Bool { liveCavity?.stable ?? false }
    var hasBagSeed: Bool { bagSeed != nil }

    func lockBag() {
        guard let state = liveCavity, let snapshot = latestSnapshot else { return }
        let camera = snapshot.cameraPosition
        let fit = state.fit
        lockedCavity = fit
        bagTransform = fit.transform(cameraXZ: [camera.x, camera.z])
        container = ContainerFactory.fromCavity(
            innerLongCm: Double(fit.box.rect.long * 100),
            innerShortCm: Double(fit.box.rect.short * 100),
            shellDepthCm: Double(fit.shellDepth * 100),
            confidence: state.confidence
        )
        enterItems()
        refreshWires()
    }

    func beginCornerTaps() {
        isCornerMode = true
        cornerTaps = []
        errorText = nil
        refreshWires()
    }

    func cancelCornerTaps() {
        guard hasDepth else {
            cornerTaps = []
            return
        }
        isCornerMode = false
        cornerTaps = []
        bagTapTime = bagSeed == nil ? nil : Date()
    }

    func handleCornerTap(_ point: SIMD3<Float>) {
        cornerTaps.append(point)
        errorText = nil
        guard cornerTaps.count == 3 else { return }
        guard let rect = TapMeasure.footprint(cornerTaps[0], cornerTaps[1], cornerTaps[2]), rect.short > 0.15 else {
            cornerTaps = []
            errorText = Copy.Guided.cornersTooClose
            return
        }
        // Closed thickness: sum of side depths for a zipper bag, else the single cavity's y.
        let sideDepths: [Double] = presetBag?.compartments.compactMap { $0.dims.count == 3 ? $0.dims[1] : nil } ?? []
        let depthSum: Double = sideDepths.reduce(0, +)
        let closedY: Double = depthSum > 0 ? depthSum : 26.0
        let floor = cornerTaps.map(\.y).min() ?? 0
        let fit = CavityFit(box: BoxFit(rect: rect, height: Float(closedY) / 200, cellCount: 0, fillRatio: 1), floorY: floor)
        let camera = latestSnapshot?.cameraPosition ?? SIMD3(rect.center.x, 0, rect.center.y + 1)
        lockedCavity = fit
        bagTransform = fit.transform(cameraXZ: [camera.x, camera.z])
        container = ContainerFactory.fromCavity(
            innerLongCm: Double(rect.long * 100),
            innerShortCm: Double(rect.short * 100),
            shellDepthCm: closedY / 2,
            confidence: 0.7,
            method: .manual
        )
        isCornerMode = false
        cornerTaps = []
        enterItems()
        refreshWires()
    }

    // MARK: Taps

    func handleTap(at point: CGPoint, in size: CGSize) {
        if isCornerMode {
            if let p = worldPoint(at: point, in: size) { handleCornerTap(p) }
            else { errorText = Copy.Guided.tapNoDepth }
            return
        }
        switch phase {
        case .bag where hasDepth:
            seedBag(at: point, in: size)
        case .items:
            if isTapMeasuring {
                handleItemTap(at: point, in: size)
            } else {
                measureItem(at: point, in: size)
            }
        default:
            break
        }
    }

    private func seedBag(at point: CGPoint, in size: CGSize) {
        guard let p = worldPoint(at: point, in: size) else {
            errorText = Copy.Guided.tapNoDepth
            return
        }
        bagSeed = [p.x, p.z]
        bagTapTime = Date()
        errorText = nil
        liveCavity = nil
        showCornerFallback = false
        Task { await worker.resetCavity() }
        refreshWires()
    }

    private func measureItem(at point: CGPoint, in size: CGSize) {
        guard let p = worldPoint(at: point, in: size) else {
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

    private func worldPoint(at point: CGPoint, in size: CGSize) -> SIMD3<Float>? {
        guard let snapshot = latestSnapshot else { return nil }
        let portrait = SIMD2(Float(point.x / size.width), Float(point.y / size.height))
        let sensor = snapshot.sensorUV(fromPortraitNormalized: portrait)
        return snapshot.worldPoint(atNormalized: sensor)
    }

    private func uprightImage(_ buffer: CVPixelBuffer) -> UprightImage? {
        // Video connection is already portrait-oriented.
        let image = CIImage(cvPixelBuffer: buffer)
        let scale = 720 / image.extent.width
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UprightImage(cgImage: cg)
    }

    var tapStep: TapStep {
        if itemTaps.count < 3 { return .corner(itemTaps.count + 1) }
        return draft?.hasHeight == true ? .adjust : .top
    }

    func startTapMeasuring() {
        isTapMeasuring = true
        resetDraft()
    }

    func stopTapMeasuring() {
        resetDraft()
        if hasDepth { isTapMeasuring = false }
    }

    func resetDraft() {
        itemTaps = []
        draft = nil
        errorText = nil
        refreshWires()
    }

    private func handleItemTap(at point: CGPoint, in size: CGSize) {
        errorText = nil
        switch tapStep {
        case .corner:
            guard let p = worldPoint(at: point, in: size) else {
                errorText = Copy.Guided.tapMissed
                return
            }
            // Snap to floor height for base corners.
            var floorPoint = p
            if let fy = floorY { floorPoint.y = fy }
            itemTaps.append(floorPoint)
            guard itemTaps.count == 3 else { return }
            guard let rect = TapMeasure.footprint(itemTaps[0], itemTaps[1], itemTaps[2]) else {
                itemTaps = []
                errorText = Copy.Guided.cornersTooClose
                return
            }
            let floor = floorY ?? (itemTaps.map(\.y).reduce(0, +) / 3)
            draft = TapDraft(rect: rect, floorY: floor, longCm: round1(rect.long * 100), shortCm: round1(rect.short * 100))
            refreshWires()

        case .top:
            guard var d = draft, let p = worldPoint(at: point, in: size) else {
                errorText = Copy.Guided.heightMissed
                return
            }
            var height = TapMeasure.heightFromSurfaceHit(p, footprint: d.rect, floorY: d.floorY)
            var fromSurface = height != nil
            if height == nil, let snapshot = latestSnapshot {
                let origin = snapshot.cameraPosition
                let direction = simd_normalize(p - origin)
                height = TapMeasure.heightFromEdgeRay(origin: origin, direction: direction, footprint: d.rect, floorY: d.floorY)
                fromSurface = false
            }
            guard let height else {
                errorText = Copy.Guided.heightMissed
                return
            }
            d.heightCm = round1(height * 100)
            d.hasHeight = true
            d.heightFromSurface = fromSurface
            draft = d
            refreshWires()

        case .adjust:
            break
        }
    }

    func refreshDraftWire() { refreshWires() }

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
        if let snapshot = latestSnapshot, let video = capture.latestVideoBuffer {
            updateCrops(snapshot: snapshot, video: video)
        }
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
        itemWireLabels = [:]
        isTapMeasuring = !hasDepth
        resetDraft()
        Task { await worker.resetItems() }
    }

    private func updateTracked(_ states: [ScanWorker.ItemState]) {
        var next: [TrackedItem] = []
        for s in states {
            if s.stable, numbers[s.id] == nil { numbers[s.id] = numbers.count + 1 }
            next.append(TrackedItem(id: s.id, number: numbers[s.id] ?? 0, fit: s.fit, floorY: s.floorY, stable: s.stable, confidence: s.confidence))
        }
        next.append(contentsOf: tapTracked)
        tracked = next.sorted { ($0.number == 0 ? Int.max : $0.number, $0.id) < ($1.number == 0 ? Int.max : $1.number, $1.id) }
        for t in tracked where t.stable {
            if labeledIDs.insert(t.id).inserted {
                itemWireLabels[t.id] = "\(t.number)"
            }
        }
        refreshWires()
    }

    func removeItem(id: Int) {
        tracked.removeAll { $0.id == id }
        tapTracked.removeAll { $0.id == id }
        lastItemStates.removeAll { $0.id == id }
        crops[id] = nil
        measuring.remove(id)
        labeledIDs.remove(id)
        itemWireLabels[id] = nil
        removedIDs.insert(id)
        Task { await worker.removeTarget(id: id) }
        refreshWires()
    }

    private func updateCrops(snapshot: DepthSnapshot, video: CVPixelBuffer) {
        let res = CGSize(width: CVPixelBufferGetWidth(video), height: CVPixelBufferGetHeight(video))
        var image: CIImage?
        for t in tracked {
            let corners = Self.corners(t.fit, floorY: t.floorY)
            let pts = corners.compactMap { snapshot.project($0) }.map {
                // Landscape UV → portrait video pixels (video is portrait-oriented).
                CGPoint(x: CGFloat(1 - $0.y) * res.width, y: CGFloat($0.x) * res.height)
            }
            guard pts.count == corners.count else { continue }
            let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
            let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
            guard minX > 0, minY > 0, maxX < res.width, maxY < res.height else { continue }
            let camPos = snapshot.cameraPosition
            let viewDir = -SIMD3(
                snapshot.cameraToWorld.columns.2.x,
                snapshot.cameraToWorld.columns.2.y,
                snapshot.cameraToWorld.columns.2.z
            )
            guard corners.allSatisfy({ dot($0 - camPos, viewDir) > 0.05 }) else { continue }
            let area = (maxX - minX) * (maxY - minY)
            if let best = crops[t.id], best.area * 1.1 >= area { continue }

            let source = image ?? CIImage(cvPixelBuffer: video)
            image = source
            let mx = (maxX - minX) * 0.1, my = (maxY - minY) * 0.1
            let rect = CGRect(x: minX - mx, y: res.height - maxY - my, width: maxX - minX + 2 * mx, height: maxY - minY + 2 * my)
                .intersection(CGRect(origin: .zero, size: res))
            let cropped = source.cropped(to: rect)
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

    // MARK: Wires

    private func refreshWires() {
        var wires: [LiveWire] = []
        if let state = liveCavity, !isCornerMode, phase == .bag {
            let fit = state.fit.box
            var t = LiveWire.transform(for: fit, floorY: state.fit.floorY)
            t.columns.3.y = state.fit.floorY + fit.height / 2
            wires.append(LiveWire(
                id: cavityWireID,
                size: [fit.rect.long, fit.height, fit.rect.short],
                transform: t,
                color: state.stable ? WireColors.stable : WireColors.measuring,
                label: nil
            ))
        } else if let fit = lockedCavity, phase == .items || phase == .identifying || phase == .review {
            var t = LiveWire.transform(for: fit.box, floorY: fit.floorY)
            t.columns.3.y = fit.floorY + fit.shellDepth / 2
            wires.append(LiveWire(
                id: cavityWireID,
                size: [fit.box.rect.long, fit.shellDepth, fit.box.rect.short],
                transform: t,
                color: WireColors.locked,
                label: nil
            ))
        }
        for t in tracked {
            wires.append(LiveWire(
                id: "item-\(t.id)",
                size: [t.fit.rect.long, t.fit.height, t.fit.rect.short],
                transform: LiveWire.transform(for: t.fit, floorY: t.floorY),
                color: t.stable ? WireColors.stable : WireColors.measuring,
                label: itemWireLabels[t.id]
            ))
        }
        if let d = draft {
            var rect = d.rect
            rect.long = Float(d.longCm / 100)
            rect.short = Float(d.shortCm / 100)
            let h = d.hasHeight ? Float(d.heightCm / 100) : 0.005
            let fit = BoxFit(rect: rect, height: h, cellCount: 0, fillRatio: 1)
            wires.append(LiveWire(
                id: draftWireID,
                size: [rect.long, h, rect.short],
                transform: LiveWire.transform(for: fit, floorY: d.floorY),
                color: WireColors.draft,
                label: nil
            ))
        }
        liveWires = wires
    }

    // MARK: Identify

    func identifyItems() async {
        let found = tracked.filter(\.stable)
        guard !found.isEmpty else { return }
        phase = .identifying
        identifyProgress = 0

        struct Job: Sendable {
            var index: Int
            var image: String
            var dims: MeasuredDims
        }
        let tapIDs = Set(tapTracked.map(\.id))
        let jobs: [Job] = found.enumerated().map { index, t in
            let cm = t.fit.dimsCm
            let image = crops[t.id].flatMap { ImageCapture.jpegBase64(from: $0.image) } ?? ImageCapture.placeholderBase64()
            let method: MeasureMethod = tapIDs.contains(t.id) ? .manual : .lidar
            return Job(index: index, image: image, dims: MeasuredDims(w: cm.w, h: cm.h, d: cm.d, method: method, confidence: t.confidence))
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
            item.w = job.dims.w
            item.h = job.dims.h
            item.d = job.dims.d
            item.source = .scan
            item.measurement = Measurement(method: job.dims.method, confidence: job.dims.confidence, deviceHasLidar: hasDepth)
            if job.dims.method != .lidar { tapMeasuredItemIDs.insert(item.id) }
            return item
        }
        phase = .review
    }

    func backToItems() {
        phase = .items
        refreshWires()
    }

    // MARK: Pack and overlay

    func pack(itemsStore: ItemsStore, tripStore: TripStore, planStore: PlanStore) async {
        guard let container else { return }
        phase = .packing
        itemsStore.items = items
        itemsStore.tapMeasuredIDs = tapMeasuredItemIDs.intersection(items.map(\.id))
        tripStore.setBag(container)
        await planStore.computePlan(items: items, into: container)
        guard let plan = planStore.plan else {
            phase = .review
            return
        }
        // No AR world anchor — show the plan in a non-AR RealityKit viewer.
        stepper.load(plan: plan, items: items, container: container, style: .volume)
        phase = .overlay
    }

    var shellDepthCm: Double? { lockedCavity.map { Double($0.shellDepth * 100) } }

    func restart() {
        stepper.stopPlay()
        bagSeed = nil
        bagTapTime = nil
        measuring = []
        labeledIDs = []
        itemWireLabels = [:]
        liveCavity = nil
        lockedCavity = nil
        bagTransform = nil
        container = nil
        tracked = []
        tapTracked = []
        lastItemStates = []
        items = []
        liveWires = []
        latestSnapshot = nil
        resetDraft()
        isTapMeasuring = false
        showCornerFallback = false
        isCornerMode = false
        floorY = nil
        phase = .findFloor
        Task { await worker.reset() }
    }
}
