import Foundation

/// Offline airport lookup for trip setup autocomplete (mirrors services/api/data/airports.json).
struct AirportInfo: Identifiable, Hashable, Sendable {
    var id: String { code }
    var code: String
    var name: String
    var country: String
}

enum AirportCatalog {
    static let all: [AirportInfo] = [
        .init(code: "SFO", name: "San Francisco", country: "US"),
        .init(code: "LAX", name: "Los Angeles", country: "US"),
        .init(code: "JFK", name: "New York JFK", country: "US"),
        .init(code: "SEA", name: "Seattle", country: "US"),
        .init(code: "ORD", name: "Chicago O'Hare", country: "US"),
        .init(code: "ATL", name: "Atlanta", country: "US"),
        .init(code: "BOS", name: "Boston", country: "US"),
        .init(code: "DEL", name: "Delhi", country: "IN"),
        .init(code: "BOM", name: "Mumbai", country: "IN"),
        .init(code: "BLR", name: "Bengaluru", country: "IN"),
        .init(code: "LHR", name: "London Heathrow", country: "GB"),
        .init(code: "CDG", name: "Paris CDG", country: "FR"),
        .init(code: "FRA", name: "Frankfurt", country: "DE"),
        .init(code: "AMS", name: "Amsterdam", country: "NL"),
        .init(code: "ICN", name: "Seoul Incheon", country: "KR"),
        .init(code: "NRT", name: "Tokyo Narita", country: "JP"),
        .init(code: "HKG", name: "Hong Kong", country: "HK"),
        .init(code: "SIN", name: "Singapore", country: "SG"),
        .init(code: "DXB", name: "Dubai", country: "AE"),
        .init(code: "KEF", name: "Reykjavik Keflavik", country: "IS"),
        .init(code: "PEK", name: "Beijing Capital", country: "CN"),
        .init(code: "SYD", name: "Sydney", country: "AU"),
    ]

    static let knownAirlines: Set<String> = [
        "UA", "AA", "DL", "WN", "B6", "AS", "NK", "F9",
        "BA", "LH", "AF", "KL", "EK", "QR", "SQ", "CX", "NH", "KE", "AI", "UK",
    ]

    static func match(_ query: String) -> [AirportInfo] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return Array(all.prefix(8)) }
        return all.filter {
            $0.code.hasPrefix(q)
                || $0.name.uppercased().contains(q)
                || $0.country.uppercased() == q
        }.prefix(8).map { $0 }
    }

    static func name(for code: String) -> String? {
        all.first { $0.code == code.uppercased() }?.name
    }

    static func country(for code: String) -> String? {
        all.first { $0.code == code.uppercased() }?.country
    }

    static func isKnownAirport(_ code: String) -> Bool {
        all.contains { $0.code == code.uppercased() }
    }
}
