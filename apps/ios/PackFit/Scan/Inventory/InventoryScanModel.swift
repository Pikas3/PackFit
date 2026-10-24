import CoreGraphics
import Foundation

/// One object Claude found in a photo, and whether it goes into the item list.
struct InventoryEntry: Identifiable {
    var item: Item
    var box: InventoryBox?
    var alternatives: [ItemAlternative]
    var thumbnail: CGImage?
    /// Which photo it came from (0-based).
    var photo: Int
    var included: Bool
    /// Same name as an object found in an earlier photo, probably the same thing seen twice.
    var likelyDuplicate: Bool

    var id: String { item.id }
}

enum InventoryMerge {
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

    /// Take a photo (or use the placeholder in the simulator) and ask Claude what is in it.
    func captureAndIdentify() async {
        phase = .identifying
        var image: CGImage?
        let base64: String
        if cameraAvailable {
            do {
                let still = try await camera.capture()
                image = still
                guard let encoded = ImageCapture.jpegBase64(from: still) else {
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
        photo = image

        do {
            let response = try await client.scanInventory(imageBase64: base64, hint: nil)
            if response.warnings.contains("sample_data") { isSampleData = true }
            let index = photoCount
            let new = InventoryMerge.entries(for: response.detections, photo: index, existing: entries) { box in
                guard let image, let rect = InventoryMerge.pixelRect(box, width: image.width, height: image.height) else {
                    return nil
                }
                return image.cropping(to: rect)
            }
            photoCount += 1
            entries.append(contentsOf: new)
            phase = new.isEmpty ? .failed(Copy.Inventory.nothingFound) : .results
        } catch {
            phase = .failed(Copy.Inventory.failed)
        }
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
