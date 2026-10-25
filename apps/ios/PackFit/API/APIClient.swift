import Foundation

protocol APIClient: Sendable {
    func scanItem(
        imageBase64: String,
        measured: MeasuredDims?,
        reference: String?,
        hint: String?
    ) async throws -> ScanItemResponse

    /// Every packable object in one photo. Dims are model estimates.
    /// `reference: "credit_card"` asks Claude to locate the card and leave it out of the list.
    func scanInventory(imageBase64: String, hint: String?, reference: String?) async throws -> ScanInventoryResponse

    func checkRules(items: [Item], trip: Trip, bag: String) async throws -> RulesCheckResponse

    func suggestTrip(_ trip: Trip) async throws -> TripSuggestResponse

    func lookupFlight(airline: String, flightNumber: String, departDate: String?) async throws -> FlightLookupResponse
}

struct MeasuredDims: Codable, Sendable, Equatable {
    var w: Double
    var h: Double
    var d: Double
    var method: MeasureMethod
    var confidence: Double
}

enum APIError: Error, LocalizedError {
    case unauthorized
    case badRequest(String)
    case decoding
    case upstream(String)
    case network

    /// The server could not be reached at all, as opposed to answering with an error.
    var isNetwork: Bool {
        if case .network = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Unauthorized"
        case .badRequest(let m): return m
        case .decoding: return "Invalid response"
        case .upstream(let m): return m
        case .network: return Copy.Errors.network
        }
    }
}

enum APIClientFactory {
    @MainActor
    static func make(config: AppConfig = .shared) -> any APIClient {
        if config.mockAPI {
            return MockAPIClient()
        }
        return LiveAPIClient(config: config)
    }
}
