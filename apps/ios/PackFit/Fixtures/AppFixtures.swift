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

extension AppFixtures {
    /// Offline `/trip/lookup` for airline + flight number.
    /// A demo flight's route, offline. Nil for any other flight: never guess a route.
    static func flightLookupFallback(airline: String, flightNumber: String, departDate: String?) -> FlightLookupResponse? {
        let a = airline.uppercased().filter(\.isLetter)
        let n = flightNumber.filter(\.isNumber)
        let key = "\(String(a.prefix(2)))\(n)"
        let table: [String: (String, String, String, String)] = [
            "UA88": ("SFO", "DEL", "San Francisco", "Delhi"),
            "AI173": ("SFO", "DEL", "San Francisco", "Delhi"),
            "AS204": ("SEA", "KEF", "Seattle", "Reykjavik"),
            "DL188": ("LAX", "ICN", "Los Angeles", "Seoul Incheon"),
            "BA178": ("JFK", "LHR", "New York JFK", "London Heathrow"),
            "AA100": ("SFO", "LAX", "San Francisco", "Los Angeles"),
            "UA900": ("SFO", "NRT", "San Francisco", "Tokyo Narita"),
        ]
        guard let hit = table[key] else { return nil }
        let fromCountry = AirportCatalog.country(for: hit.0)
        let toCountry = AirportCatalog.country(for: hit.1)
        var notices: [RouteNotice] = []
        if fromCountry == "US" || toCountry == "US" {
            notices.append(RouteNotice(
                text: "TSA liquid and battery rules apply for US security screening.",
                sourceUrl: "https://www.tsa.gov/travel/security-screening/whatcanibring",
                lastVerified: "2026-09-20",
                scope: "tsa"
            ))
        }
        if let toCountry, fromCountry != toCountry {
            notices.append(contentsOf: countryTips(for: toCountry).map {
                RouteNotice(text: $0.text, sourceUrl: $0.sourceUrl, lastVerified: $0.lastVerified, scope: "country")
            })
        }
        return FlightLookupResponse(
            airline: String(a.prefix(2)),
            flightNumber: n.isEmpty ? "88" : n,
            flightLabel: key.isEmpty ? "UA88" : key,
            from: hit.0,
            to: hit.1,
            fromName: hit.2,
            toName: hit.3,
            fromCountry: fromCountry,
            toCountry: toCountry,
            departDate: departDate ?? "2026-11-01",
            international: fromCountry != toCountry,
            source: "fixture",
            routeNotices: notices
        )
    }

    /// Offline `/trip/suggest` payload so trip setup and suggestions work without the network.
    static func tripSuggestFallback(for trip: Trip) -> TripSuggestResponse {
        let country = AirportCatalog.country(for: trip.to) ?? "US"
        let cold = trip.activities.contains { $0.localizedCaseInsensitiveContains("ski") || $0.localizedCaseInsensitiveContains("cold") }
            || trip.to == "KEF"
        var suggestions: [Suggestion] = [
            Suggestion(id: UUID().uuidString, name: "T-shirt stack", reason: "Everyday tops for \(trip.nights) nights", category: .clothing, estDims: [28, 4, 22], estKg: 0.4, fragile: false, soft: true, essential: true),
            Suggestion(id: UUID().uuidString, name: "Toiletry pouch", reason: "Basics for the trip length", category: .toiletries, estDims: [20, 8, 12], estKg: 0.3, fragile: false, soft: true, essential: true),
            Suggestion(id: UUID().uuidString, name: "Phone charger cable", reason: "Keep devices charged on the road", category: .electronics, estDims: [12, 2, 8], estKg: 0.1, fragile: false, soft: true, essential: true),
            Suggestion(id: UUID().uuidString, name: "Passport wallet", reason: "International trip documents", category: .documents, estDims: [14, 2, 10], estKg: 0.15, fragile: false, soft: true, essential: true),
        ]
        if cold {
            suggestions.append(Suggestion(id: UUID().uuidString, name: "Warm sweater", reason: "Cool destination forecast", category: .clothing, estDims: [35, 8, 28], estKg: 0.6, fragile: false, soft: true, essential: false))
        }
        if trip.activities.contains(where: { $0.localizedCaseInsensitiveContains("hike") }) {
            suggestions.append(Suggestion(id: UUID().uuidString, name: "Hiking socks", reason: "Activity: hike", category: .clothing, estDims: [18, 4, 12], estKg: 0.2, fragile: false, soft: true, essential: false))
        }
        let weather = WeatherSummary(
            summary: cold
                ? "Cool trip — pack layers. Offline forecast estimate."
                : "Mild temperate weather expected. Offline forecast estimate.",
            lowC: cold ? 2 : 14,
            highC: cold ? 12 : 26,
            precipChance: 0.3,
            sourceUrl: "https://open-meteo.com/"
        )
        var warnings: [TripWarning] = []
        if !AirportCatalog.knownAirlines.contains(trip.airline.uppercased()) {
            warnings.append(.unknownAirline(message: "Airline \(trip.airline) isn’t in our short list — baggage limits may be wrong. Double-check the airline site."))
        }
        if trip.departDate == nil {
            warnings.append(.weatherUnavailable(message: "No departure date — showing a generic weather summary."))
        }
        let before = BeforeYouGoPanel(
            pack: [
                BeforeYouGoTip(text: "Pack a power adapter for \(country) outlets and check voltage on chargers.", sourceUrl: "https://www.iatatravelcentre.com/", lastVerified: "2026-09-20"),
                BeforeYouGoTip(text: "Carry your passport and any visas in your cabin bag.", sourceUrl: "https://travel.state.gov/", lastVerified: "2026-09-20"),
            ],
            leaveOrDeclare: countryTips(for: country),
            medicationFood: [
                BeforeYouGoTip(text: "Keep prescription meds in original packaging with a copy of the prescription.", sourceUrl: "https://www.tsa.gov/travel/security-screening/whatcanibring/items/medications", lastVerified: "2026-09-18"),
            ]
        )
        return TripSuggestResponse(
            suggestions: suggestions,
            weather: weather,
            warnings: warnings,
            beforeYouGo: before,
            destinationCountry: country
        )
    }

    private static func countryTips(for country: String) -> [BeforeYouGoTip] {
        switch country {
        case "IN":
            return [BeforeYouGoTip(text: "Declare or skip many animal-origin foods for India.", sourceUrl: "https://www.cbic.gov.in/", lastVerified: "2026-09-10")]
        case "KR":
            return [BeforeYouGoTip(text: "Meat, fruit, and many agricultural products are tightly controlled in South Korea.", sourceUrl: "https://www.customs.go.kr/", lastVerified: "2026-09-14")]
        case "IS":
            return [BeforeYouGoTip(text: "Iceland restricts meat and many dairy imports for travelers.", sourceUrl: "https://www.mast.is/en/import-export", lastVerified: "2026-09-11")]
        default:
            return [BeforeYouGoTip(text: "Check destination customs for food, plants, drones, and cash limits before you fly.", sourceUrl: "https://www.iatatravelcentre.com/", lastVerified: "2026-09-20")]
        }
    }
}
