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

    /// Airport positions for the destination weather (copied from services/api/data/airports.json).
    static func coordinates(for code: String) -> (lat: Double, lon: Double)? {
        coords[code.uppercased()]
    }

    private static let coords: [String: (lat: Double, lon: Double)] = [
        "ADD": (8.9779, 38.7993), "AKL": (-37.0082, 174.785), "AMS": (52.3105, 4.7683), "ARN": (59.6498, 17.9238),
        "ATH": (37.9364, 23.9445), "ATL": (33.6407, -84.4277), "AUH": (24.433, 54.6511), "BCN": (41.2974, 2.0833),
        "BKK": (13.69, 100.7501), "BLR": (13.1986, 77.7066), "BNE": (-27.3842, 153.1175), "BOG": (4.7016, -74.1469),
        "BOM": (19.0896, 72.8656), "BOS": (42.3656, -71.0096), "BRU": (50.9014, 4.4844), "CAI": (30.1219, 31.4056),
        "CAN": (23.3924, 113.2988), "CCU": (22.6547, 88.4467), "CDG": (49.0097, 2.5479), "CGK": (-6.1256, 106.6559),
        "CMN": (33.3675, -7.5898), "CPH": (55.618, 12.656), "CTS": (42.7752, 141.6925), "DEL": (28.5562, 77.1),
        "DEN": (39.8561, -104.6737), "DFW": (32.8998, -97.0403), "DOH": (25.2731, 51.6081), "DUB": (53.4264, -6.2499),
        "DXB": (25.2532, 55.3657), "EWR": (40.6895, -74.1745), "EZE": (-34.8222, -58.5358), "FCO": (41.8003, 12.2389),
        "FRA": (50.0379, 8.5622), "GIG": (-22.809, -43.2506), "GMP": (37.5583, 126.7906), "GRU": (-23.4356, -46.4731),
        "HEL": (60.3172, 24.9633), "HKG": (22.308, 113.9185), "HND": (35.5494, 139.7798), "HYD": (17.2403, 78.4294),
        "IAD": (38.9531, -77.4565), "ICN": (37.4602, 126.4407), "IST": (41.2753, 28.7519), "JFK": (40.6413, -73.7781),
        "JNB": (-26.1392, 28.246), "KEF": (63.985, -22.6056), "KIX": (34.4347, 135.244), "KUL": (2.7456, 101.7099),
        "LAX": (33.9425, -118.408), "LGW": (51.1537, -0.1821), "LHR": (51.47, -0.4543), "LIM": (-12.0219, -77.1143),
        "LIS": (38.7742, -9.1342), "LOS": (6.5774, 3.3212), "MAA": (12.9941, 80.1709), "MAD": (40.4983, -3.5676),
        "MEL": (-37.669, 144.841), "MEX": (19.4361, -99.0719), "MIA": (25.7959, -80.287), "MNL": (14.5086, 121.0198),
        "MUC": (48.3538, 11.7861), "NBO": (-1.3192, 36.9278), "NRT": (35.772, 140.3929), "ORD": (41.9742, -87.9073),
        "OSL": (60.1976, 11.1004), "PEK": (40.0799, 116.6031), "PER": (-31.9403, 115.9669), "PVG": (31.1443, 121.8083),
        "SCL": (-33.393, -70.7858), "SEA": (47.4502, -122.3088), "SFO": (37.6213, -122.379), "SIN": (1.3644, 103.9915),
        "SYD": (-33.9399, 151.1753), "TLV": (32.0114, 34.8867), "TPE": (25.0797, 121.2342), "VIE": (48.1103, 16.5697),
        "WAW": (52.1657, 20.9671), "YVR": (49.1967, -123.1815), "YYC": (51.1215, -114.0076), "YYZ": (43.6777, -79.6248),
        "ZRH": (47.4582, 8.5555),
    ]

    static func isKnownAirport(_ code: String) -> Bool {
        all.contains { $0.code == code.uppercased() }
    }
}
