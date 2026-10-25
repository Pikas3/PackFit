import Foundation
import Testing
@testable import PackFit

/// Flags one restricted rule per item it is asked about, plus a bag-weight flag, and records
/// which items each request carried.
private final class RecordingRulesClient: APIClient, @unchecked Sendable {
    var requests: [[String]] = []

    func checkRules(items: [Item], trip: Trip, bag: String) async throws -> RulesCheckResponse {
        requests.append(items.map(\.id))
        let flags = items.map {
            RuleFlag(itemId: $0.id, scope: .tsa, severity: .restricted, text: "Check \($0.name)",
                     sourceUrl: "https://www.tsa.gov", lastVerified: "2026-10-20", ruleId: "tsa:\($0.id)")
        } + [RuleFlag(itemId: RuleFlag.bagItemId, scope: .airline, severity: .restricted,
                      text: "Bag over \(items.count) items", sourceUrl: "https://www.united.com",
                      lastVerified: "2026-10-20", ruleId: "ua:weight")]
        return RulesCheckResponse(flags: flags, summary: "server", stale: false, rulesLastSynced: nil)
    }

    func scanItem(imageBase64: String, measured: MeasuredDims?, reference: String?, hint: String?) async throws -> ScanItemResponse {
        throw URLError(.unsupportedURL)
    }
    func scanInventory(imageBase64: String, hint: String?, reference: String?) async throws -> ScanInventoryResponse {
        throw URLError(.unsupportedURL)
    }
    func suggestTrip(_ trip: Trip) async throws -> TripSuggestResponse { throw URLError(.unsupportedURL) }
    func lookupFlight(airline: String, flightNumber: String, departDate: String?) async throws -> FlightLookupResponse {
        throw URLError(.unsupportedURL)
    }
}

@MainActor
struct RulesSyncTests {
    private let trip = AppFixtures.trips()[0]
    private let items = Array(AppFixtures.items().prefix(4))

    @Test func newItemIsCheckedAloneAndItsFlagAdded() async {
        let client = RecordingRulesClient()
        let store = RulesStore()
        await store.sync(items: Array(items.prefix(3)), trip: trip, bag: "checked", client: client)
        await store.sync(items: items, trip: trip, bag: "checked", client: client)

        #expect(client.requests == [items.prefix(3).map(\.id), [items[3].id]])
        #expect(Set(store.flags.map(\.itemId)) == Set(items.map(\.id) + [RuleFlag.bagItemId]))
        // The bag-weight flag is from the full check, not the one-item request.
        #expect(store.flags.filter { $0.itemId == RuleFlag.bagItemId }.map(\.text) == ["Bag over 3 items"])
    }

    @Test func editedItemIsRecheckedAndRemovedItemLosesFlags() async {
        let client = RecordingRulesClient()
        let store = RulesStore()
        await store.sync(items: items, trip: trip, bag: "checked", client: client)

        var edited = items
        edited[0].name = "Renamed"
        edited.remove(at: 1)
        await store.sync(items: edited, trip: trip, bag: "checked", client: client)

        #expect(client.requests.last == [items[0].id])
        #expect(!store.flags.contains { $0.itemId == items[1].id })
        #expect(store.flags.contains { $0.itemId == items[0].id && $0.text == "Check Renamed" })
        #expect(store.flags.filter { $0.itemId == items[0].id }.count == 1)
    }

    @Test func nothingChangedSendsNoRequest() async {
        let client = RecordingRulesClient()
        let store = RulesStore()
        await store.sync(items: items, trip: trip, bag: "checked", client: client)
        await store.sync(items: items, trip: trip, bag: "checked", client: client)
        #expect(client.requests.count == 1)
    }

    @Test func otherBagChecksEverythingAgain() async {
        let client = RecordingRulesClient()
        let store = RulesStore()
        await store.sync(items: items, trip: trip, bag: "checked", client: client)
        await store.sync(items: items, trip: trip, bag: "carryOn", client: client)
        #expect(client.requests == [items.map(\.id), items.map(\.id)])
    }
}
