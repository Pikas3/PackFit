import Foundation
import Testing
@testable import PackFitSchemas

/// Every fixture file decodes, re-encodes, and round-trips to equal JSON (key order and
/// fixture-only `_` keys aside). The Swift half of `pnpm schemas:check`.
@Suite struct DecodeTests {
    @Test func items() throws {
        let items = try Fixtures.items()
        #expect(items.count == 25)
        try expectRoundTrip(items, file: "items")
    }

    @Test func containers() throws {
        let containers = try Fixtures.containers()
        #expect(containers.count == 3)
        try expectRoundTrip(containers, file: "containers")
    }

    @Test func trips() throws {
        let trips = try Fixtures.trips()
        #expect(trips.count == 5)
        #expect(trips.contains { $0.from == "SFO" && $0.to == "DEL" && $0.checked.weightLimitKg == 23 })
        try expectRoundTrip(trips, file: "trips")
    }

    @Test(arguments: try planNames())
    func plan(name: String) throws {
        let plan = try Fixtures.plan(named: name)
        #expect(plan.placed.map(\.order) == plan.placed.map(\.order).sorted())
        try expectRoundTrip(plan, file: name)
    }

    @Test func missingFixtureThrows() {
        #expect(throws: FixtureError.notFound("nope")) { try Fixtures.data(named: "nope") }
    }
}

private struct PackList: Decodable { var tripId: String; var bag: String }

private func planNames() throws -> [String] {
    try JSONDecoder().decode([PackList].self, from: Fixtures.data(named: "packlists"))
        .map { "\($0.tripId)-\($0.bag)" }
}

private func expectRoundTrip<T: Codable>(_ value: T, file: String) throws {
    let original = stripFixtureKeys(try JSONSerialization.jsonObject(with: Fixtures.data(named: file)))
    let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    #expect((original as AnyObject).isEqual(reencoded), "\(file).json does not round-trip")
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let again = try JSONDecoder().decode(T.self, from: encoder.encode(value))
    #expect(try encoder.encode(again) == encoder.encode(value))
}

private func stripFixtureKeys(_ json: Any) -> Any {
    switch json {
    case let dict as [String: Any]:
        return dict.filter { !$0.key.hasPrefix("_") }.mapValues(stripFixtureKeys)
    case let array as [Any]:
        return array.map(stripFixtureKeys)
    default:
        return json
    }
}
