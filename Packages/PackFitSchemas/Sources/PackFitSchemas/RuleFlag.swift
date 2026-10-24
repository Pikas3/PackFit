public enum RuleScope: String, Codable, Sendable { case tsa, airline, country }
public enum RuleSeverity: String, Codable, Sendable { case banned, restricted, check }

public struct RuleFlag: Codable, Sendable, Equatable {
    public var itemId: String
    public var scope: RuleScope
    public var severity: RuleSeverity
    public var text: String                 // guidance, not authority
    public var sourceUrl: String            // required, a real page
    public var lastVerified: String         // ISO 8601 date; stale if older than 30 days
    public var ruleId: String?

    public init(
        itemId: String, scope: RuleScope, severity: RuleSeverity, text: String,
        sourceUrl: String, lastVerified: String, ruleId: String? = nil
    ) {
        self.itemId = itemId
        self.scope = scope
        self.severity = severity
        self.text = text
        self.sourceUrl = sourceUrl
        self.lastVerified = lastVerified
        self.ruleId = ruleId
    }
}
