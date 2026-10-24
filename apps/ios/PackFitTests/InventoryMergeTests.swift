import CoreGraphics
import Foundation
import Testing
@testable import PackFit

struct InventoryMergeTests {
    private func detection(_ name: String) -> InventoryDetection {
        var item = AppFixtures.items()[0]
        item.id = UUID().uuidString
        item.name = name
        return InventoryDetection(item: item, box: InventoryBox(x: 0.1, y: 0.1, w: 0.2, h: 0.2), alternatives: [])
    }

    @Test func namesMatchIgnoringCaseAndPunctuation() {
        #expect(InventoryMerge.key("T-Shirt") == InventoryMerge.key("t shirt"))
        #expect(InventoryMerge.key("Shampoo 250 ml") != InventoryMerge.key("Shampoo 400 ml"))
    }

    @Test func repeatsInOnePhotoAreSeparateObjects() {
        let entries = InventoryMerge.entries(for: [detection("Sock"), detection("Sock")], photo: 0, existing: [])
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.included && !$0.likelyDuplicate })
    }

    @Test func nameSeenInEarlierPhotoStartsUnticked() {
        let first = InventoryMerge.entries(for: [detection("Laptop"), detection("Sneakers")], photo: 0, existing: [])
        let second = InventoryMerge.entries(for: [detection("laptop"), detection("Charger")], photo: 1, existing: first)
        #expect(second[0].likelyDuplicate && !second[0].included)
        #expect(!second[1].likelyDuplicate && second[1].included)
    }

    @Test func pixelRectPadsAndClamps() throws {
        let rect = try #require(InventoryMerge.pixelRect(InventoryBox(x: 0.9, y: 0, w: 0.2, h: 0.5), width: 1000, height: 800))
        #expect(rect.maxX <= 1000)
        #expect(rect.minY == 0)
        #expect(rect.minX < 900)
        #expect(InventoryMerge.pixelRect(InventoryBox(x: 1, y: 1, w: 0, h: 0), width: 1000, height: 800) == nil)
    }

    @Test func cardSizesReplaceGuessesAndCardIsDropped() {
        let detections = [detection("Water bottle"), detection("Credit card"), detection("Hoodie")]
        let result = CardMeasurer.Result(
            card: ImageQuad(corners: [[0, 0], [1, 0], [1, 1], [0, 1]]),
            measured: [
                .init(w: 7.2, h: 24.5, d: 7.0, confidence: 0.8, heightReliable: true),
                nil,
                .init(w: 30, h: 3, d: 25, confidence: 0.6, heightReliable: false),
            ],
            isCard: [false, true, false],
            viewElevation: 45,
            located: [InventoryBox(x: 0.5, y: 0.5, w: 0.1, h: 0.3), nil, nil]
        )
        let out = InventoryMerge.applyCard(result, to: detections)
        // The box moves to where segmentation found the object.
        #expect(out[0].box == InventoryBox(x: 0.5, y: 0.5, w: 0.1, h: 0.3))
        #expect(out[1].box == detections[2].box)
        #expect(out.map(\.item.name) == ["Water bottle", "Hoodie"])
        #expect(out[0].item.h == 24.5 && out[0].item.measurement?.method == .reference)
        // Height not visible from straight above: keep Claude's guess.
        #expect(out[1].item.h == detections[2].item.h && out[1].item.w == 30)
    }
}
