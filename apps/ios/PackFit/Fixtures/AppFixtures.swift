import Foundation
import PackFitSchemas

/// App-side helpers over `PackFitSchemas.Fixtures`. Keeps call sites non-throwing for UI.
enum AppFixtures {
    static func containers() -> [Container] {
        (try? Fixtures.containers()) ?? []
    }

    static func items() -> [Item] {
        (try? Fixtures.items()) ?? []
    }

    static func trips() -> [Trip] {
        (try? Fixtures.trips()) ?? []
    }

    static func plan(named name: String) -> Plan? {
        try? Fixtures.plan(named: name)
    }

    /// Mock / offline rule flags until `/rules/check` is live.
    static func sampleFlags(for items: [Item]) -> [RuleFlag] {
        guard let liquids = items.first(where: {
            $0.category == .liquids || $0.name.localizedCaseInsensitiveContains("shampoo")
        }) ?? items.first else {
            return []
        }
        let knife = items.first(where: {
            $0.category == .sharp || $0.name.localizedCaseInsensitiveContains("knife")
        })
        var flags: [RuleFlag] = [
            RuleFlag(
                itemId: liquids.id,
                scope: .tsa,
                severity: .restricted,
                text: "Full-size liquids over 100 ml belong in checked baggage, not carry-on.",
                sourceUrl: "https://www.tsa.gov/travel/security-screening/whatcanibring/items/liquids-aerosols-and-gels",
                lastVerified: "2026-10-01",
                ruleId: "tsa-lag-100ml"
            )
        ]
        if let knife {
            flags.append(
                RuleFlag(
                    itemId: knife.id,
                    scope: .tsa,
                    severity: .banned,
                    text: "Pocket knives are not allowed in carry-on. Pack this in checked baggage.",
                    sourceUrl: "https://www.tsa.gov/travel/security-screening/whatcanibring/items/pocket-knife",
                    lastVerified: "2026-09-15",
                    ruleId: "tsa-pocket-knife"
                )
            )
        }
        return flags
    }
}

extension RuleFlag: Identifiable {
    public var id: String { "\(itemId)-\(ruleId ?? text)" }
}

extension RuleSeverity: CaseIterable {
    public static var allCases: [RuleSeverity] { [.banned, .restricted, .check] }
}
