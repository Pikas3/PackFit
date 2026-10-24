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
}

struct ScanInventoryResponse: Codable, Sendable {
    var detections: [InventoryDetection]
    var warnings: [String]
}

struct RulesCheckResponse: Codable, Sendable {
    var flags: [RuleFlag]
    var summary: String
    var stale: Bool
    var rulesLastSynced: String?
}
