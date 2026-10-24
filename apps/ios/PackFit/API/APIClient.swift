import Foundation

protocol APIClient: Sendable {
    func scanItem(
        imageBase64: String,
        measured: MeasuredDims?,
        reference: String?,
        hint: String?
    ) async throws -> ScanItemResponse

    func checkRules(items: [Item], trip: Trip, bag: String) async throws -> RulesCheckResponse
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
