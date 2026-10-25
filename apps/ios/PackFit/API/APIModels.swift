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

/// Destination packing suggestion (API DTO; not in schemas/*.schema.json — see docs/requests.md).
struct Suggestion: Identifiable, Codable, Sendable, Equatable {
    var id: String
    var name: String
    var reason: String
    var category: Category
    var estDims: [Double]
    var estKg: Double
    var fragile: Bool
    var soft: Bool
    var essential: Bool

    func asItem() -> Item {
        Item(
            id: id.isEmpty ? UUID().uuidString : id,
            name: name,
            w: estDims.count > 0 ? estDims[0] : 20,
            h: estDims.count > 1 ? estDims[1] : 5,
            d: estDims.count > 2 ? estDims[2] : 15,
            kg: estKg,
            fragile: fragile,
            hardness: soft ? 0.2 : 0.6,
            soft: soft,
            upright: false,
            category: category,
            confidence: 0.55,
            source: .suggested,
            measurement: Measurement(method: .estimate, confidence: 0.55, deviceHasLidar: false)
        )
    }
}

struct WeatherSummary: Codable, Sendable, Equatable {
    var summary: String
    var lowC: Double
    var highC: Double
    var precipChance: Double
    var sourceUrl: String
}

struct BeforeYouGoTip: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(text)-\(sourceUrl)" }
    var text: String
    var sourceUrl: String
    var lastVerified: String
}

struct BeforeYouGoPanel: Codable, Sendable, Equatable {
    var pack: [BeforeYouGoTip]
    var leaveOrDeclare: [BeforeYouGoTip]
    var medicationFood: [BeforeYouGoTip]
}

enum TripWarning: Codable, Sendable, Equatable {
    case overweight(bag: String, estimatedKg: Double, limitKg: Double)
    case souvenirSpace(reservedLitres: Double)
    case weatherUnavailable(message: String)
    case unknownAirline(message: String)

    enum CodingKeys: String, CodingKey {
        case kind, bag, estimatedKg, limitKg, reservedLitres, message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "overweight":
            self = .overweight(
                bag: try c.decode(String.self, forKey: .bag),
                estimatedKg: try c.decode(Double.self, forKey: .estimatedKg),
                limitKg: try c.decode(Double.self, forKey: .limitKg)
            )
        case "souvenir_space":
            self = .souvenirSpace(reservedLitres: try c.decode(Double.self, forKey: .reservedLitres))
        case "weather_unavailable":
            self = .weatherUnavailable(message: try c.decode(String.self, forKey: .message))
        case "unknown_airline":
            self = .unknownAirline(message: try c.decode(String.self, forKey: .message))
        default:
            self = .weatherUnavailable(message: kind)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .overweight(let bag, let estimatedKg, let limitKg):
            try c.encode("overweight", forKey: .kind)
            try c.encode(bag, forKey: .bag)
            try c.encode(estimatedKg, forKey: .estimatedKg)
            try c.encode(limitKg, forKey: .limitKg)
        case .souvenirSpace(let litres):
            try c.encode("souvenir_space", forKey: .kind)
            try c.encode(litres, forKey: .reservedLitres)
        case .weatherUnavailable(let message):
            try c.encode("weather_unavailable", forKey: .kind)
            try c.encode(message, forKey: .message)
        case .unknownAirline(let message):
            try c.encode("unknown_airline", forKey: .kind)
            try c.encode(message, forKey: .message)
        }
    }

    var plainLanguage: String {
        switch self {
        case .overweight(_, let kg, let limit):
            return "Suggested items weigh about \(kg) kg; your checked limit is \(Int(limit)) kg."
        case .souvenirSpace(let litres):
            return "Leave about \(Int(litres)) L free for souvenirs on the way home."
        case .weatherUnavailable(let message):
            return message
        case .unknownAirline(let message):
            return message
        }
    }
}

struct TripSuggestResponse: Codable, Sendable {
    var suggestions: [Suggestion]
    var weather: WeatherSummary
    var warnings: [TripWarning]
    var beforeYouGo: BeforeYouGoPanel?
    var destinationCountry: String?
}

struct RouteNotice: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(scope)-\(text)" }
    var text: String
    var sourceUrl: String
    var lastVerified: String
    var scope: String
}

struct FlightLookupResponse: Codable, Sendable, Equatable {
    var airline: String
    var flightNumber: String
    var flightLabel: String
    var from: String
    var to: String
    var fromName: String
    var toName: String
    var fromCountry: String?
    var toCountry: String?
    var departDate: String?
    var international: Bool
    var source: String
    /// Set when the route is inferred for the date (schedule not published yet) rather than that day's own flight.
    var routeNote: String? = nil
    var routeNotices: [RouteNotice]
}
