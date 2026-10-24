import Foundation
import PackFitSchemas

/// The backend's rule records, bundled so the rule check works offline. Same candidate
/// search as `services/api/src/rules/store.ts`, but without the model to judge context, a
/// flag needs a keyword in the item's name: a category alone (every electronics item for
/// the spare-battery rule) would flag too much. Guidance, never authority (rule 4).
struct LocalRules: Sendable {
    struct Record: Codable, Sendable, Equatable {
        var ruleId: String
        var scope: RuleScope
        var subject: String
        var keywords: [String]
        var categories: [Category]
        var severity: RuleSeverity
        var carryOn: String
        var checked: String
        var text: String
        var sourceUrl: String
        var lastVerified: String
    }

    let records: [Record]
    let airportCountries: [String: String]

    static let shared: LocalRules = {
        struct File: Decodable { var rules: [Record] }
        func load<T: Decodable>(_ name: String, as: T.Type) -> T? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        return LocalRules(
            records: load("rules", as: File.self)?.rules ?? [],
            airportCountries: load("airport_countries", as: [String: String].self) ?? [:]
        )
    }()

    func flags(for items: [Item], trip: Trip, bag: String) -> [RuleFlag] {
        let country = airportCountries[trip.to.uppercased()]
        var out: [RuleFlag] = []
        for item in items {
            let name = " " + TravelCatalog.words(item.name).joined(separator: " ") + " "
            for r in records {
                switch r.scope {
                case .airline where r.subject != trip.airline: continue
                case .country where r.subject != country: continue
                default: break
                }
                let keyword = r.keywords.contains { name.contains(" " + TravelCatalog.words($0).joined(separator: " ") + " ") }
                guard keyword else { continue }
                let verdict = bag == "carryOn" ? r.carryOn : r.checked
                // Country rules apply whichever bag it is in.
                guard verdict != "ok" || r.scope == .country else { continue }
                out.append(RuleFlag(
                    itemId: item.id,
                    scope: r.scope,
                    severity: verdict == "banned" ? .banned : r.severity,
                    text: r.text,
                    sourceUrl: r.sourceUrl,
                    lastVerified: r.lastVerified,
                    ruleId: r.ruleId
                ))
            }
        }
        return out
    }
}
