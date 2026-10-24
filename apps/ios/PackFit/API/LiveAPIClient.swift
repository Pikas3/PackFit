import Foundation

struct LiveAPIClient: APIClient, Sendable {
    let config: AppConfig
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func scanItem(
        imageBase64: String,
        measured: MeasuredDims?,
        reference: String?,
        hint: String?
    ) async throws -> ScanItemResponse {
        struct Body: Encodable {
            var imageBase64: String
            var measured: MeasuredDims?
            var reference: String?
            var hint: String?
        }
        struct Envelope: Decodable {
            var item: Item
            var alternatives: [ItemAlternative]
            var warnings: [String]
        }
        let envelope: Envelope = try await post(
            path: "/scan/item",
            body: Body(imageBase64: imageBase64, measured: measured, reference: reference, hint: hint)
        )
        return ScanItemResponse(
            item: envelope.item,
            alternatives: envelope.alternatives,
            warnings: envelope.warnings
        )
    }

    func scanInventory(imageBase64: String, hint: String?) async throws -> ScanInventoryResponse {
        struct Body: Encodable {
            var imageBase64: String
            var hint: String?
        }
        return try await post(path: "/scan/inventory", body: Body(imageBase64: imageBase64, hint: hint))
    }

    func checkRules(items: [Item], trip: Trip, bag: String) async throws -> RulesCheckResponse {
        struct TripSlim: Encodable {
            var from: String
            var to: String
            var airline: String
        }
        struct Body: Encodable {
            var items: [Item]
            var trip: TripSlim
            var bag: String
        }
        return try await post(
            path: "/rules/check",
            body: Body(
                items: items,
                trip: TripSlim(from: trip.from, to: trip.to, airline: trip.airline),
                bag: bag
            )
        )
    }

    private func post<B: Encodable, R: Decodable>(path: String, body: B) async throws -> R {
        var request = URLRequest(url: config.apiBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.appToken, forHTTPHeaderField: "x-packfit-token")
        request.httpBody = try encoder.encode(body)
        request.timeoutInterval = 25

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.network }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.upstream("HTTP \(http.statusCode)")
        }
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}
