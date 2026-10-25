import Foundation

@Observable
@MainActor
final class RulesStore {
    var flags: [RuleFlag] = []
    var summary: String = ""
    var stale: Bool = false
    var isLoading = false
    var errorMessage: String?

    /// Each item as it was when its flags were fetched, and the trip and bag they were for.
    /// An item missing here, or different from it, still needs checking.
    @ObservationIgnored private var checked: [String: Item] = [:]
    @ObservationIgnored private var checkedContext: String?
    /// One request at a time, so a later answer never lands under an earlier one.
    @ObservationIgnored private var last: Task<Void, Never>?

    /// Checks every item from scratch. Packing uses this so the bag-weight flag is current.
    func check(items: [Item], trip: Trip, bag: String, client: any APIClient) async {
        await serial { await self.checkAll(items: items, trip: trip, bag: bag, client: client) }
    }

    /// Checks only items that are new or edited since their last check and adds their flags
    /// to the rest. Removed items lose their flags. A different trip or bag checks everything.
    func sync(items: [Item], trip: Trip, bag: String, client: any APIClient) async {
        await serial { await self.checkChanged(items: items, trip: trip, bag: bag, client: client) }
    }

    func flags(for itemId: String) -> [RuleFlag] {
        flags.filter { $0.itemId == itemId }
    }

    private func serial(_ work: @escaping @MainActor () async -> Void) async {
        let previous = last
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        last = task
        await task.value
    }

    private func checkAll(items: [Item], trip: Trip, bag: String, client: any APIClient) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await client.checkRules(items: items, trip: trip, bag: bag)
            flags = response.flags
            summary = response.summary
            stale = response.stale || flags.contains { RuleFreshness.isStale($0.lastVerified) }
            checked = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            checkedContext = Self.context(trip, bag)
        } catch {
            flags = AppFixtures.sampleFlags(for: items, trip: trip, bag: bag)
            summary = Copy.Errors.network
            stale = flags.contains { RuleFreshness.isStale($0.lastVerified) }
            errorMessage = Copy.Errors.network
            // Nothing counts as checked, so the next sync asks the server again.
            checked = [:]
            checkedContext = nil
        }
    }

    private func checkChanged(items: [Item], trip: Trip, bag: String, client: any APIClient) async {
        guard !items.isEmpty else {
            flags = []
            summary = ""
            stale = false
            checked = [:]
            return
        }
        guard Self.context(trip, bag) == checkedContext else {
            await checkAll(items: items, trip: trip, bag: bag, client: client)
            return
        }

        let ids = Set(items.map(\.id))
        checked = checked.filter { ids.contains($0.key) }
        flags.removeAll { $0.itemId != RuleFlag.bagItemId && !ids.contains($0.itemId) }
        let changed = items.filter { checked[$0.id] != $0 }
        guard !changed.isEmpty else {
            summary = Self.summary(flags)
            return
        }

        let changedIds = Set(changed.map(\.id))
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await client.checkRules(items: changed, trip: trip, bag: bag)
            // The bag-weight flag needs every item, so it only comes from a full check.
            flags = flags.filter { !changedIds.contains($0.itemId) }
                + response.flags.filter { $0.itemId != RuleFlag.bagItemId }
            for item in changed { checked[item.id] = item }
            summary = Self.summary(flags)
            stale = flags.contains { RuleFreshness.isStale($0.lastVerified) }
        } catch {
            flags = flags.filter { !changedIds.contains($0.itemId) }
                + AppFixtures.sampleFlags(for: changed, trip: trip, bag: bag)
                    .filter { $0.itemId != RuleFlag.bagItemId }
            summary = Copy.Errors.network
            stale = flags.contains { RuleFreshness.isStale($0.lastVerified) }
            errorMessage = Copy.Errors.network
        }
    }

    private static func context(_ trip: Trip, _ bag: String) -> String {
        "\(trip.from)-\(trip.to)-\(trip.airline)-\(bag)"
    }

    /// Same wording as the server's summary, for flags merged from several checks.
    private static func summary(_ flags: [RuleFlag]) -> String {
        if flags.isEmpty { return Copy.Rules.noFlags }
        let banned = flags.filter { $0.severity == .banned }.count
        let restricted = flags.filter { $0.severity == .restricted }.count
        return Copy.Rules.summary(flags.count, banned: banned, restricted: restricted)
    }
}
