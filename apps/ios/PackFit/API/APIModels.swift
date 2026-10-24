import Foundation
import PackFitSchemas

struct ItemAlternative: Codable, Sendable, Equatable, Hashable {
    var name: String
    var category: Category
}

struct ScanItemResponse: Codable, Sendable {
    var item: Item
    var alternatives: [ItemAlternative]
    var warnings: [String]
}

/// Normalized box in the photo: origin top-left, values 0-1 of the image size.
struct InventoryBox: Codable, Sendable, Equatable, Hashable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

struct InventoryDetection: Codable, Sendable {
    var item: Item
    var box: InventoryBox?
    var alternatives: [ItemAlternative]
    /// "box", "cylinder_upright" or "cylinder_lying"; picks the solid the app fits. Kept as a
    /// string so an unknown value never fails the whole response.
    var shape: String?
    /// The measured solid's outline, normalized 0-1 to the photo. Set on the phone, never sent.
    var outline: [SIMD2<Double>]? = nil

    var objectShape: ObjectShape? { shape.flatMap(ObjectShape.init(rawValue:)) }

    private enum CodingKeys: String, CodingKey {
        case item, box, alternatives, shape
    }
}

struct InventoryReference: Codable, Sendable {
    var box: InventoryBox
}

struct ScanInventoryResponse: Codable, Sendable {
    var detections: [InventoryDetection]
    var reference: InventoryReference?
    var warnings: [String]
}

struct RulesCheckResponse: Codable, Sendable {
    var flags: [RuleFlag]
    var summary: String
    var stale: Bool
    var rulesLastSynced: String?
}
