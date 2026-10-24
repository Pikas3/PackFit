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

        let fixtures = Fixtures.items()
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

    func checkRules(items: [Item], trip: Trip, bag: String) async throws -> RulesCheckResponse {
        _ = trip
        _ = bag
        let flags = Fixtures.sampleFlags(for: items)
        return RulesCheckResponse(
            flags: flags,
            summary: flags.isEmpty
                ? "No matching travel-rule flags for these items."
                : "One or more items need a closer look before security. Open each flag for the source.",
            stale: flags.contains { RuleFreshness.isStale($0.lastVerified) },
            rulesLastSynced: "2026-10-01T04:00:00Z"
        )
    }
}
