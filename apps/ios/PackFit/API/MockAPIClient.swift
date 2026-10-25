import Foundation

final class MockAPIClient: APIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var scanIndex = 0

    func scanItem(
        imageBase64: String,
        measured: MeasuredDims?,
        reference: String?,
        hint: String?
    ) async throws -> ScanItemResponse {
        _ = imageBase64
        _ = reference
        try await Task.sleep(for: .milliseconds(900))

        let index = lock.withLock {
            defer { scanIndex += 1 }
            return scanIndex
        }

        let fixtures = AppFixtures.items()
        guard !fixtures.isEmpty else {
            throw APIError.upstream("No fixture items available")
        }
        var item = fixtures[index % fixtures.count]
        item.id = UUID().uuidString
        item.source = .scan
        if let hint, !hint.isEmpty {
            item.name = hint
        }
        if let measured {
            item.w = measured.w
            item.h = measured.h
            item.d = measured.d
            item.measurement = Measurement(
                method: measured.method,
                confidence: measured.confidence,
                deviceHasLidar: measured.method == .lidar
            )
            item.confidence = measured.confidence
        } else {
            item.measurement = Measurement(
                method: .estimate,
                confidence: 0.65,
                deviceHasLidar: false
            )
            item.confidence = 0.65
        }

        let alternatives = [
            ItemAlternative(name: item.name, category: item.category),
            ItemAlternative(name: "Similar \(item.category.rawValue)", category: item.category)
        ]
        return ScanItemResponse(item: item, alternatives: alternatives, warnings: [])
    }

    func scanInventory(imageBase64: String, hint: String?, reference: String?) async throws -> ScanInventoryResponse {
        _ = imageBase64
        _ = hint
        try await Task.sleep(for: .milliseconds(1200))
        let fixtures = AppFixtures.items()
        guard !fixtures.isEmpty else {
            throw APIError.upstream("No fixture items available")
        }
        // Four items per photo, laid out in a 2×2 grid; a second scan returns the next four.
        let start = lock.withLock {
            defer { scanIndex += 4 }
            return scanIndex
        }
        let detections = (0..<4).map { i -> InventoryDetection in
            var item = fixtures[(start + i) % fixtures.count]
            item.id = UUID().uuidString
            item.source = .scan
            item.measurement = Measurement(method: .estimate, confidence: 0.5, deviceHasLidar: false)
            let box = InventoryBox(x: i % 2 == 0 ? 0.06 : 0.54, y: i < 2 ? 0.1 : 0.55, w: 0.4, h: 0.32)
            return InventoryDetection(
                item: item,
                box: box,
                alternatives: [ItemAlternative(name: "Similar \(item.category.rawValue)", category: item.category)]
            )
        }
        return ScanInventoryResponse(
            detections: detections,
            reference: reference == nil ? nil : InventoryReference(box: InventoryBox(x: 0.42, y: 0.44, w: 0.16, h: 0.08)),
            warnings: ["no_scale_reference", "sample_data"]
        )
    }

    func checkRules(items: [Item], trip: Trip, bag: String) async throws -> RulesCheckResponse {
        let flags = AppFixtures.sampleFlags(for: items, trip: trip, bag: bag)
        return RulesCheckResponse(
            flags: flags,
            summary: flags.isEmpty
                ? "No matching travel-rule flags for these items."
                : "One or more items need a closer look before security. Open each flag for the source.",
            stale: flags.contains { RuleFreshness.isStale($0.lastVerified) },
            rulesLastSynced: "2026-10-01T04:00:00Z"
        )
    }

    func suggestTrip(_ trip: Trip) async throws -> TripSuggestResponse {
        try await Task.sleep(for: .milliseconds(400))
        return AppFixtures.tripSuggestFallback(for: trip)
    }

    func lookupFlight(airline: String, flightNumber: String, departDate: String?) async throws -> FlightLookupResponse {
        try await Task.sleep(for: .milliseconds(300))
        guard let flight = AppFixtures.flightLookupFallback(airline: airline, flightNumber: flightNumber, departDate: departDate) else {
            throw APIError.badRequest(Copy.Trip.flightNotFound)
        }
        return flight
    }
}
