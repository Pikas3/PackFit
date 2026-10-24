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

struct RulesCheckResponse: Codable, Sendable {
    var flags: [RuleFlag]
    var summary: String
    var stale: Bool
    var rulesLastSynced: String?
}
