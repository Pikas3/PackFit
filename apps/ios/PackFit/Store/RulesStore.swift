import Foundation

@Observable
@MainActor
final class RulesStore {
    var flags: [RuleFlag] = []
    var summary: String = ""
    var stale: Bool = false
    var isLoading = false
    var errorMessage: String?

    func check(items: [Item], trip: Trip, bag: String, client: any APIClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await client.checkRules(items: items, trip: trip, bag: bag)
            flags = response.flags
            summary = response.summary
            stale = response.stale || flags.contains { RuleFreshness.isStale($0.lastVerified) }
        } catch {
            flags = Fixtures.sampleFlags(for: items)
            summary = Copy.Errors.network
            stale = flags.contains { RuleFreshness.isStale($0.lastVerified) }
            errorMessage = Copy.Errors.network
        }
    }

    func flags(for itemId: String) -> [RuleFlag] {
        flags.filter { $0.itemId == itemId }
    }
}
