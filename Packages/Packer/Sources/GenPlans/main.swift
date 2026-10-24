// Writes schemas/fixtures/plans/<trip-id>-<bag>.json for every entry in
// schemas/fixtures/packlists.json. Run: swift run --package-path Packages/Packer GenPlans
import Foundation
import PackFitSchemas
import Packer

struct PackList: Decodable {
    var tripId: String
    var bag: String
    var itemIds: [String]
}

// Packages/Packer/Sources/GenPlans/main.swift -> repo root. Read and write the source tree,
// not the bundled copy.
let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let fixtures = repo.appendingPathComponent("schemas/fixtures")

func load<T: Decodable>(_ name: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(contentsOf: fixtures.appendingPathComponent(name)))
}

let items: [Item] = try load("items.json")
let trips: [Trip] = try load("trips.json")
let packLists: [PackList] = try load("packlists.json")
let itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

var failed = false
for list in packLists {
    let name = "\(list.tripId)-\(list.bag)"
    guard let trip = trips.first(where: { $0.id == list.tripId }) else {
        print("\(name): unknown trip"); failed = true; continue
    }
    let container = list.bag == "carryOn" ? trip.carryOn : trip.checked
    let bagItems = list.itemIds.compactMap { itemsById[$0] }
    let plan = pack(bagItems, into: container)
    let violations = validatePlan(plan, items: bagItems, container: container)
    if !violations.isEmpty { print("\(name): INVALID \(violations)"); failed = true }

    var data = try encoder.encode(plan)
    data.append(0x0A)
    try data.write(to: fixtures.appendingPathComponent("plans/\(name).json"))
    let s = plan.stats
    print(String(format: "%@: %d placed, %d unplaced, fill %.1f%%, %.2f kg, CoM %.1f%%",
                 name, plan.placed.count, plan.unplaced.count, s.fillPct, s.kg, s.comHeightPct))
}
if failed { exit(1) }
