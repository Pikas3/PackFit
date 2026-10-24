import Foundation
import Testing
import PackFitSchemas
@testable import Packer

/// Seeded PRNG for reproducible random trials.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A fixture packlist resolved to its items and bag.
struct FixtureCase: CustomTestStringConvertible, Sendable {
    var name: String
    var items: [Item]
    var container: Container
    var testDescription: String { name }
}

private struct PackList: Decodable { var tripId: String; var bag: String; var itemIds: [String] }

func fixtureCases() throws -> [FixtureCase] {
    let items = Dictionary(uniqueKeysWithValues: try Fixtures.items().map { ($0.id, $0) })
    let trips = try Fixtures.trips()
    let lists = try JSONDecoder().decode([PackList].self, from: Fixtures.data(named: "packlists"))
    return lists.map { list in
        let trip = trips.first { $0.id == list.tripId }!
        return FixtureCase(name: "\(list.tripId)-\(list.bag)",
                           items: list.itemIds.map { items[$0]! },
                           container: list.bag == "carryOn" ? trip.carryOn : trip.checked)
    }
}

func randomItems(count: Int, using rng: inout SplitMix64) -> [Item] {
    let categories = Category.allCases
    return (0..<count).map { i in
        Item(
            id: String(format: "r%03d", i),
            name: "random \(i)",
            w: Double.random(in: 2...50, using: &rng),
            h: Double.random(in: 2...50, using: &rng),
            d: Double.random(in: 2...50, using: &rng),
            kg: Double.random(in: 0.05...5, using: &rng),
            fragile: Double.random(in: 0...1, using: &rng) < 0.15,
            hardness: Double.random(in: 0...1, using: &rng),
            soft: Double.random(in: 0...1, using: &rng) < 0.3,
            upright: Double.random(in: 0...1, using: &rng) < 0.1,
            category: categories[Int.random(in: 0..<categories.count, using: &rng)],
            neededAtSecurity: Double.random(in: 0...1, using: &rng) < 0.1 ? true : nil
        )
    }
}

let suitcase = Container(
    id: "test-suitcase", name: "Test suitcase", type: .suitcase, outer: [60, 30, 40],
    compartments: [Compartment(name: "main", dims: [60, 30, 40])], weightLimitKg: 23, wheelsSide: .back)

let backpack = Container(
    id: "test-backpack", name: "Test backpack", type: .backpack, outer: [30, 48, 20],
    compartments: [
        Compartment(name: "main", dims: [28, 44, 12]),
        Compartment(name: "front", dims: [26, 28, 5]),
        Compartment(name: "laptop", dims: [29, 40, 3]),
    ], weightLimitKg: 7)

func item(
    _ id: String, _ w: Double, _ h: Double, _ d: Double, kg: Double = 1, hardness: Double = 0.5,
    fragile: Bool = false, soft: Bool = false, upright: Bool = false,
    category: PackFitSchemas.Category = .other, security: Bool = false
) -> Item {
    Item(id: id, name: id, w: w, h: h, d: d, kg: kg, fragile: fragile, hardness: hardness,
         soft: soft, upright: upright, category: category,
         neededAtSecurity: security ? true : nil)
}

func place(
    _ id: String, _ x: Double, _ y: Double, _ z: Double, _ w: Double, _ h: Double, _ d: Double,
    order: Int = 0, in compartment: String? = nil
) -> Placement {
    Placement(itemId: id, x: x, y: y, z: z, w: w, h: h, d: d, order: order, compartment: compartment)
}

func plan(_ placed: [Placement]) -> Plan {
    Plan(placed: placed, unplaced: [], stats: PlanStats(fillPct: 0, kg: 0, comHeightPct: 0))
}
