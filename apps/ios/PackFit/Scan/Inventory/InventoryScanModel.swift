import CoreGraphics
import Foundation

/// One object Claude found in a photo, and whether it goes into the item list.
struct InventoryEntry: Identifiable {
    var item: Item
    /// Where it is in the photo: its segmented outline's bounds once measured, else Claude's box.
    var box: InventoryBox?
    /// The measured box or cylinder, drawn over the photo. Nil when not measured.
    var outline: [SIMD2<Double>]?
    var alternatives: [ItemAlternative]
    var thumbnail: CGImage?
    /// Which photo it came from (0-based).
    var photo: Int
    var included: Bool
    /// Same name as an object found in an earlier photo, probably the same thing seen twice.
    var likelyDuplicate: Bool

    var id: String { item.id }

    var measuredWithCard: Bool { item.measurement?.method == .reference }
}

enum InventoryMerge {
    /// Card-measured sizes onto Claude's detections. Drops detections that are the card itself.
    /// Boxes move to where segmentation found the object. Where height could not be seen
    /// (straight-down photo), Claude's height stays.
    static func applyCard(_ result: CardMeasurer.Result, to detections: [InventoryDetection]) -> [InventoryDetection] {
        detections.indices.compactMap { i in
            guard i < result.isCard.count, !result.isCard[i] else { return nil }
            var d = detections[i]
            if i < result.located.count, let located = result.located[i] { d.box = located }
            guard i < result.measured.count, let m = result.measured[i] else { return d }
            d.outline = m.outline
            d.item.w = m.w
            d.item.d = m.d
            if m.heightReliable { d.item.h = m.h }
            d.item.measurement = Measurement(method: .reference, confidence: m.confidence, deviceHasLidar: false)
            return d
        }
    }

    /// Lowercased letters and digits only, so "T-shirt" and "t shirt" match.
    static func key(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// New entries for one photo. Objects whose name matches one from an earlier photo start
    /// unticked; repeats within the same photo are separate objects and stay ticked.
    static func entries(
        for detections: [InventoryDetection],
        photo: Int,
        existing: [InventoryEntry],
        thumbnail: (InventoryBox) -> CGImage? = { _ in nil }
    ) -> [InventoryEntry] {
        let seen = Set(existing.filter { $0.photo != photo }.map { key($0.item.name) })
        return detections.map { d in
            let duplicate = seen.contains(key(d.item.name))
            return InventoryEntry(
                item: d.item,
                box: d.box,
                outline: d.outline,
                alternatives: d.alternatives,
                thumbnail: d.box.flatMap(thumbnail),
                photo: photo,
                included: !duplicate,
                likelyDuplicate: duplicate
            )
        }
    }

    /// Pixel rect for a normalized box, padded by `margin` of its size and clamped to the image.
    static func pixelRect(_ box: InventoryBox, width: Int, height: Int, margin: Double = 0.08) -> CGRect? {
        let w = Double(width), h = Double(height)
        let rect = CGRect(
            x: (box.x - box.w * margin) * w,
            y: (box.y - box.h * margin) * h,
            width: box.w * (1 + 2 * margin) * w,
            height: box.h * (1 + 2 * margin) * h
        ).integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        return rect.isNull || rect.width < 2 || rect.height < 2 ? nil : rect
    }
}

@MainActor
@Observable
final class InventoryScanModel {
    enum Phase: Equatable {
        case camera
        case identifying
        case results
        /// No credit card in the photo, so nothing could be measured.
        case noCard
        case failed(String)
    }

    private(set) var phase: Phase = .camera
    private(set) var entries: [InventoryEntry] = []
    /// The last photo, shown frozen with its boxes while and after identifying.
    private(set) var photo: CGImage?
    private(set) var photoCount = 0
    /// The app or the server answered with stub items, so the results are not from this photo.
    private(set) var isSampleData: Bool
    var cameraError: String?

    let camera = InventoryCamera()
    let cameraAvailable = InventoryCamera.isAvailable
    private let client: any APIClient

    init(client: any APIClient) {
        self.client = client
        isSampleData = client is MockAPIClient
    }

    var includedCount: Int { entries.filter(\.included).count }
    var latestEntries: [InventoryEntry] { entries.filter { $0.photo == photoCount - 1 } }

    func startCamera() async {
        guard cameraAvailable else { return }
        do {
            try await camera.start()
        } catch {
            cameraError = Copy.Inventory.cameraUnavailable
        }
    }

    func stopCamera() {
        camera.stop()
    }

    /// The last photo's detections, kept while the "no card" message is up so the user can
    /// still choose rough estimates.
    private var unmeasured: ScanInventoryResponse?
    /// The card in the last photo, corners normalized 0-1. Drawn on the frozen photo.
    private(set) var card: ImageQuad?
    /// The last photo looked almost straight down, so heights are Claude's guesses.
    private(set) var heightsGuessed = false

    /// Take a photo (or use the placeholder in the simulator), ask Claude what is in it, then
    /// measure each object against the credit card in the same photo.
    func captureAndIdentify() async {
        phase = .identifying
        card = nil
        heightsGuessed = false
        var shot: InventoryCamera.Shot?
        let base64: String
        if cameraAvailable {
            do {
                let still = try await camera.capture()
                shot = still
                guard let encoded = ImageCapture.jpegBase64(from: still.image) else {
                    phase = .failed(Copy.Inventory.failed)
                    return
                }
                base64 = encoded
            } catch {
                phase = .failed(Copy.Inventory.failed)
                return
            }
        } else {
            base64 = ImageCapture.placeholderBase64()
        }
        photo = shot?.image

        let response: ScanInventoryResponse
        do {
            response = try await client.scanInventory(imageBase64: base64, hint: nil, reference: "credit_card")
        } catch {
            phase = .failed(Copy.Inventory.failed)
            return
        }
        if response.warnings.contains("sample_data") { isSampleData = true }

        // No photo (simulator) means nothing to measure; sample data is shown as is.
        guard let shot else {
            add(response.detections)
            return
        }
        let measured: CardMeasurer.Result? = if let intrinsics = shot.intrinsics {
            await Self.measure(shot.image, intrinsics: intrinsics, response: response)
        } else {
            nil
        }
        if let jpeg = shot.jpeg {
            let record = ScanArchive.record(shot: shot, response: response, result: measured)
            Task { await ScanArchive.save(jpeg: jpeg, record: record) }
        }
        guard let result = measured else {
            unmeasured = response
            phase = .noCard
            return
        }
        card = ImageQuad(corners: result.card.corners.map {
            $0 / SIMD2(Double(shot.image.width), Double(shot.image.height))
        })
        heightsGuessed = result.measured.contains { $0.map { !$0.heightReliable } ?? false }
        add(InventoryMerge.applyCard(result, to: response.detections))
    }

    /// The user has no card handy: keep Claude's rough sizes.
    func useEstimates() {
        guard let response = unmeasured else { return }
        unmeasured = nil
        add(response.detections)
    }

    private func add(_ detections: [InventoryDetection]) {
        let image = photo
        let new = InventoryMerge.entries(for: detections, photo: photoCount, existing: entries) { box in
            guard let image, let rect = InventoryMerge.pixelRect(box, width: image.width, height: image.height) else {
                return nil
            }
            return image.cropping(to: rect)
        }
        photoCount += 1
        entries.append(contentsOf: new)
        phase = new.isEmpty ? .failed(Copy.Inventory.nothingFound) : .results
    }

    @concurrent
    private nonisolated static func measure(
        _ image: CGImage,
        intrinsics: CameraIntrinsics,
        response: ScanInventoryResponse
    ) async -> CardMeasurer.Result? {
        CardMeasurer.measure(
            image: image,
            intrinsics: intrinsics,
            boxes: response.detections.map(\.box),
            shapes: response.detections.map(\.objectShape),
            cardHint: response.reference?.box
        )
    }

    func showResults() {
        phase = .results
    }

    func scanAgain() {
        phase = .camera
    }

    func toggle(_ id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].included.toggle()
    }

    func update(_ item: Item) {
        guard let i = entries.firstIndex(where: { $0.id == item.id }) else { return }
        entries[i].item = item
        entries[i].included = true
    }

    func remove(_ id: String) {
        entries.removeAll { $0.id == id }
    }

    var itemsToAdd: [Item] { entries.filter(\.included).map(\.item) }
}
