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

    /// Offline `/rules/check`, mirroring the server: an item is flagged only when it breaks a
    /// rule in the bag it is packed in, and weight is checked once for the whole bag.
    static func sampleFlags(for items: [Item], trip: Trip?, bag: String) -> [RuleFlag] {
        let carryOn = bag == "carryOn"
        var flags: [RuleFlag] = []
        for item in items {
            let name = item.name.lowercased()
            if carryOn, item.category == .liquids || name.contains("shampoo"), upperBoundMl(item) > 100 {
                flags.append(RuleFlag(
                    itemId: item.id,
                    scope: .tsa,
                    severity: .restricted,
                    text: "Liquids over 3.4 oz (100 ml) are not allowed in carry-on. Pack this in checked baggage.",
                    sourceUrl: "https://www.tsa.gov/travel/security-screening/liquids-aerosols-gels-rule",
                    lastVerified: "2026-10-24",
                    ruleId: "tsa:liquids-100ml"
                ))
            }
            if carryOn, item.category == .sharp || name.contains("knife") {
                flags.append(RuleFlag(
                    itemId: item.id,
                    scope: .tsa,
                    severity: .banned,
                    text: "Knives are not allowed in carry-on bags, except round-bladed butter knives and plastic cutlery. Pack them in checked baggage.",
                    sourceUrl: "https://www.tsa.gov/travel/security-screening/whatcanibring/items/knives",
                    lastVerified: "2026-10-24",
                    ruleId: "tsa:pocket-knife"
                ))
            }
            if !carryOn, name.contains("power bank") || name.contains("portable charger") {
                flags.append(RuleFlag(
                    itemId: item.id,
                    scope: .tsa,
                    severity: .banned,
                    text: "Spare lithium batteries and power banks must go in carry-on, not checked baggage.",
                    sourceUrl: "https://www.tsa.gov/travel/security-screening/whatcanibring/items/power-banks",
                    lastVerified: "2026-10-24",
                    ruleId: "tsa:lithium-battery-spare"
                ))
            }
        }
        if let weight = bagWeightFlag(items: items, airline: trip?.airline, bag: bag) {
            flags.append(weight)
        }
        return flags
    }

    /// One flag for the whole bag when the items are over the airline's checked limit.
    private static func bagWeightFlag(items: [Item], airline: String?, bag: String) -> RuleFlag? {
        let limits: [String: (url: String, verified: String)] = [
            "UA": ("https://www.united.com/ual/en/us/fly/baggage/checked-bags.html", "2026-10-01"),
            "AA": ("https://www.aa.com/i18n/travel-info/baggage/checked-baggage.jsp", "2026-09-25"),
            "AI": ("https://www.airindia.com/in/en/book/baggage-information.html", "2026-09-20"),
        ]
        guard bag == "checked", let airline, let source = limits[airline] else { return nil }
        let totalKg = items.reduce(0) { $0 + $1.kg }
        guard totalKg > 23 else { return nil }
        return RuleFlag(
            itemId: RuleFlag.bagItemId,
            scope: .airline,
            severity: .restricted,
            text: String(format: "Your items weigh about %.1f kg, over the %@ 23 kg checked-bag limit. Excess weight fees may apply.", totalKg, airline),
            sourceUrl: source.url,
            lastVerified: source.verified,
            ruleId: "airline:\(airline.lowercased())-checked-23kg"
        )
    }

    /// Most the item can hold: the volume in its name ("400 ml") when given, else its box.
    static func upperBoundMl(_ item: Item) -> Double {
        let name = item.name.lowercased()
        if let match = name.firstMatch(of: /(\d+(?:\.\d+)?)\s*ml\b/), let ml = Double(match.1) {
            return ml
        }
        if let match = name.firstMatch(of: /(\d+(?:\.\d+)?)\s*(?:fl\.?\s*)?oz\b/), let oz = Double(match.1) {
            return (oz * 29.5735).rounded(.down)
        }
        return item.w * item.h * item.d
    }
}

extension RuleFlag: Identifiable {
    public var id: String { "\(itemId)-\(ruleId ?? text)" }

    /// `itemId` of a flag about the whole bag (its weight) rather than one item.
    static let bagItemId = "bag"
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
