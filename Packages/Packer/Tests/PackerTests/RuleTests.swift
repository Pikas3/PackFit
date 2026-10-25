import PackFitSchemas
import Testing
@testable import Packer

/// For each rule: an obviously wrong placement that validatePlan rejects, and a correct one
/// it accepts. Rules without a violation case (5, 7) are checked through `pack`.
@Suite struct RuleTests {
    // MARK: Geometry (overlap, bounds, support)

    @Test func overlapIsRejected() {
        let items = [item("a", 10, 10, 10), item("b", 10, 10, 10)]
        let bad = plan([place("a", 0, 0, 0, 10, 10, 10), place("b", 5, 0, 5, 10, 10, 10, order: 1)])
        #expect(validatePlan(bad, items: items, container: suitcase) == [.overlap(a: "a", b: "b")])
        let good = plan([place("a", 0, 0, 0, 10, 10, 10), place("b", 10, 0, 0, 10, 10, 10, order: 1)])
        #expect(validatePlan(good, items: items, container: suitcase) == [])
    }

    @Test func outOfBoundsIsRejected() {
        let items = [item("a", 10, 10, 10)]
        #expect(validatePlan(plan([place("a", 55, 0, 0, 10, 10, 10)]), items: items, container: suitcase)
            == [.outOfBounds(itemId: "a")])
        #expect(validatePlan(plan([place("a", 50, 0, 30, 10, 10, 10)]), items: items, container: suitcase) == [])
    }

    @Test func floatingIsRejected() {
        let items = [item("a", 10, 10, 10, kg: 2), item("b", 10, 10, 10, kg: 1)]
        // b hangs 70% off a: 30% support < 60%.
        let bad = plan([place("a", 0, 0, 0, 10, 10, 10), place("b", 7, 10, 0, 10, 10, 10, order: 1)])
        #expect(validatePlan(bad, items: items, container: suitcase) == [.floating(itemId: "b", supportPct: 30)])
        let good = plan([place("a", 0, 0, 0, 10, 10, 10), place("b", 3, 10, 0, 10, 10, 10, order: 1)])
        #expect(validatePlan(good, items: items, container: suitcase) == [])
    }

    // MARK: Rule 3, fragile never under

    @Test func fragileWithSomethingAboveIsRejected() {
        let items = [item("vase", 20, 10, 20, kg: 2, fragile: true), item("book", 10, 2, 10, kg: 0.5)]
        let bad = plan([place("vase", 0, 0, 0, 20, 10, 20), place("book", 0, 10, 0, 10, 2, 10, order: 1)])
        #expect(validatePlan(bad, items: items, container: suitcase)
            == [.fragileUnder(fragileId: "vase", aboveId: "book")])
        let good = plan([place("vase", 0, 0, 0, 20, 10, 20), place("book", 20, 0, 0, 10, 2, 10, order: 1)])
        #expect(validatePlan(good, items: items, container: suitcase) == [])
    }

    @Test func packerNeverStacksOnFragile() {
        let items = [item("glass", 60, 5, 40, kg: 1, fragile: true), item("shirt", 30, 5, 20, kg: 0.2)]
        let p = pack(items, into: suitcase)
        #expect(validatePlan(p, items: items, container: suitcase) == [])
        let glass = p.placed.first { $0.itemId == "glass" }!
        #expect(!p.placed.contains { isAbove($0, glass) })
    }

    @Test func lightSoftItemsMayCushionFragile() {
        let items = [item("laptop", 30, 2, 20, kg: 1.5, hardness: 0.9, fragile: true),
                     item("tee", 30, 3, 20, kg: 0.2, hardness: 0.1, soft: true),
                     item("book", 20, 3, 15, kg: 0.15, hardness: 0.8)]
        let tee = plan([place("laptop", 0, 0, 0, 30, 2, 20), place("tee", 0, 2, 0, 30, 3, 20, order: 1)])
        #expect(validatePlan(tee, items: items, container: suitcase) == [])
        // Rigid items stay off the column, even resting on the cushion.
        let book = plan([place("laptop", 0, 0, 0, 30, 2, 20), place("tee", 0, 2, 0, 30, 3, 20, order: 1),
                         place("book", 0, 5, 0, 20, 3, 15, order: 2)])
        #expect(validatePlan(book, items: items, container: suitcase)
            == [.fragileUnder(fragileId: "laptop", aboveId: "book")])
    }

    // MARK: Rule 4, no heavy on light

    @Test func heavyRigidOnLightSoftIsRejected() {
        let items = [item("jumper", 20, 5, 20, kg: 0.4, hardness: 0.1), item("brick", 20, 5, 20, kg: 3, hardness: 1)]
        let bad = plan([place("jumper", 0, 0, 0, 20, 5, 20), place("brick", 0, 5, 0, 20, 5, 20, order: 1)])
        #expect(validatePlan(bad, items: items, container: suitcase)
            == [.heavyOnLight(heavyId: "brick", lightId: "jumper")])
        let good = plan([place("brick", 0, 0, 0, 20, 5, 20), place("jumper", 0, 5, 0, 20, 5, 20, order: 1)])
        #expect(validatePlan(good, items: items, container: suitcase) == [])
    }

    // MARK: Rule 5, flat first and soft compression

    @Test func flatFirstAndSoftCompresses() {
        let items = [item("tee", 30, 20, 4, kg: 0.2, hardness: 0.1, soft: true), item("box", 20, 15, 5, kg: 0.5)]
        let p = pack(items, into: suitcase)
        let tee = p.placed.first { $0.itemId == "tee" }!
        let box = p.placed.first { $0.itemId == "box" }!
        #expect(abs(tee.h - 4 * 0.8) < 1e-9, "soft item lies flat and compresses 20%")
        #expect(abs(box.h - 5) < 1e-9, "rigid item lies flat, uncompressed")

        var options = PackOptions()
        options.compressSoftPct = 0
        #expect(abs(pack(items, into: suitcase, options: options).placed.first { $0.itemId == "tee" }!.h - 4) < 1e-9)
    }

    // MARK: Rule 6, upright lock and orientation toggle

    @Test func uprightLyingDownIsRejected() {
        let items = [item("bottle", 7, 21, 5, upright: true)]
        #expect(validatePlan(plan([place("bottle", 0, 0, 0, 21, 5, 7)]), items: items, container: suitcase)
            == [.uprightBroken(itemId: "bottle")])
        #expect(validatePlan(plan([place("bottle", 0, 0, 0, 5, 21, 7)]), items: items, container: suitcase) == [])
    }

    @Test func packerKeepsUprightItemsUpright() {
        let items = [item("bottle", 7, 21, 5, upright: true), item("jar", 9, 11, 9, upright: true)]
        let p = pack(items, into: suitcase)
        #expect(p.placed.count == 2)
        #expect(abs(p.placed.first { $0.itemId == "bottle" }!.h - 21) < 1e-9)
        #expect(validatePlan(p, items: items, container: suitcase) == [])
    }

    @Test func uprightItemTooTallForTheBagLiesDown() {
        // The test suitcase is 30 cm tall inside.
        let items = [item("flask", 8, 34, 8, upright: true)]
        let p = pack(items, into: suitcase)
        #expect(p.unplaced.isEmpty)
        #expect(abs(p.placed[0].h - 8) < 1e-9)
        #expect(validatePlan(p, items: items, container: suitcase) == [])
        let notes = describeStep(p, items: items, order: 0, container: suitcase)!.notes
        #expect(notes.contains("too tall to stand, close it tightly and lay it flat"))
    }

    @Test func twoOrientationModeOnlyLiesFlat() {
        // A 4 cm thick board that only fits this narrow bag standing up.
        let board = [item("board", 45, 4, 32)]
        let short = Container(id: "s", name: "s", type: .suitcase, outer: [40, 50, 10],
                              compartments: [Compartment(name: "main", dims: [40, 50, 10])], weightLimitKg: 23)
        #expect(pack(board, into: short).placed.count == 1)
        var flatOnly = PackOptions()
        flatOnly.orientations = 2
        #expect(pack(board, into: short, options: flatOnly).unplaced == ["board"])
    }

    // MARK: Rule 7, heavy near the wheels

    @Test func heavyItemsGoLowAndBack() {
        // Four folded clothes exactly cover the 60 x 40 floor.
        let clothes = (0..<4).map { item("c\($0)", 30, 5, 20, kg: 0.5, hardness: 0.1, soft: true) }
        let items = clothes + [item("sandbag", 10, 10, 10, kg: 4, hardness: 0.1)]
        let biased = pack(items, into: suitcase)
        let heavy = biased.placed.first { $0.itemId == "sandbag" }!
        #expect(heavy.y < 1e-9 && heavy.z < 1e-9, "heavy item on the floor at the wheel end")
        #expect(validatePlan(biased, items: items, container: suitcase) == [])

        var options = PackOptions()
        options.heavyBias = .none
        let unbiased = pack(items, into: suitcase, options: options)
        #expect(unbiased.placed.first { $0.itemId == "sandbag" }!.y > 1)
        #expect(biased.stats.comHeightPct < unbiased.stats.comHeightPct)
    }

    // MARK: Rule 8, security items on top or at the opening

    @Test func buriedSecurityItemIsRejected() {
        let items = [item("laptop", 30, 2, 20, kg: 1.2, hardness: 0.9, security: true), item("jumper", 30, 5, 20, kg: 0.4)]
        let buried = plan([place("laptop", 0, 0, 0, 30, 2, 20), place("jumper", 0, 2, 0, 30, 5, 20, order: 1)])
        #expect(validatePlan(buried, items: items, container: suitcase) == [.securityNotOnTop(itemId: "laptop")])
        // Touching the lid (max z) is reachable even with something on top.
        let atLid = plan([place("laptop", 0, 0, 20, 30, 2, 20), place("jumper", 0, 2, 20, 30, 5, 20, order: 1)])
        #expect(validatePlan(atLid, items: items, container: suitcase) == [])
        var off = PackOptions()
        off.securityOnTop = false
        #expect(validatePlan(buried, items: items, container: suitcase, options: off) == [])
    }

    @Test func backpackSecurityItemNeedsTopOrOpening() {
        let items = [item("passport", 12, 9, 1, kg: 0.05, security: true), item("book", 12, 9, 1, kg: 0.04)]
        let bad = plan([place("passport", 0, 0, 0, 12, 9, 1), place("book", 0, 9, 0, 12, 9, 1, order: 1)])
        #expect(validatePlan(bad, items: items, container: backpack) == [.securityNotOnTop(itemId: "passport")])
        let good = plan([place("book", 0, 0, 0, 12, 9, 1), place("passport", 0, 9, 0, 12, 9, 1, order: 1)])
        #expect(validatePlan(good, items: items, container: backpack) == [])
    }

    @Test func packerPutsSecurityItemsLastAndOnTop() {
        let items = [
            item("passport", 12.5, 0.5, 8.8, kg: 0.04, security: true),
            item("jeans", 35, 5, 25, kg: 0.65, hardness: 0.1, soft: true),
            item("hoodie", 35, 8, 30, kg: 0.6, hardness: 0.1, soft: true),
        ]
        let p = pack(items, into: suitcase)
        #expect(p.placed.last?.itemId == "passport")
        #expect(validatePlan(p, items: items, container: suitcase) == [])
    }

    // MARK: Rule 9, backpack compartments

    @Test func wrongCompartmentIsRejected() {
        let items = [
            item("laptop", 30, 1.2, 21, kg: 1.2, hardness: 0.9, category: .electronics),
            item("hoodie", 30, 8, 25, kg: 0.6, hardness: 0.1, soft: true, category: .clothing),
        ]
        let bad = plan([place("hoodie", 0, 0, 0, 25, 30, 2, in: "laptop")])
        #expect(validatePlan(bad, items: items, container: backpack) == [.wrongCompartment(itemId: "hoodie", compartment: "laptop")])
        let missing = plan([place("hoodie", 0, 0, 0, 25, 30, 2, in: "roof")])
        #expect(validatePlan(missing, items: items, container: backpack) == [.wrongCompartment(itemId: "hoodie", compartment: "roof")])
        let good = plan([place("laptop", 0, 0, 0, 21, 30, 1.2, in: "laptop")])
        #expect(validatePlan(good, items: items, container: backpack) == [])
    }

    @Test func packerUsesCompartments() {
        let items = [
            item("laptop", 30.41, 1.13, 21.5, kg: 1.24, hardness: 0.9, category: .electronics),
            item("passport", 12.5, 0.5, 8.8, kg: 0.04, category: .documents),
            item("hoodie", 25, 8, 20, kg: 0.6, hardness: 0.1, soft: true, category: .clothing),
        ]
        let p = pack(items, into: backpack)
        let where_ = Dictionary(uniqueKeysWithValues: p.placed.map { ($0.itemId, $0.compartment ?? "main") })
        #expect(where_ == ["laptop": "laptop", "passport": "front", "hoodie": "main"])
        // Steps follow the container's compartment order: main, front, laptop.
        #expect(p.placed.map(\.itemId) == ["hoodie", "passport", "laptop"])
        #expect(validatePlan(p, items: items, container: backpack) == [])
    }

    // MARK: Rule 10, never drop an item

    @Test func unplaceableItemsAreReported() {
        let items = [item("surfboard", 200, 10, 50), item("sock", 10, 2, 10), item("sock", 10, 2, 10)]
        let p = pack(items, into: suitcase)
        #expect(p.placed.map(\.itemId) == ["sock"])
        #expect(p.unplaced.sorted() == ["sock", "surfboard"])
    }

    @Test func unplacedItemsAreExplained() {
        let items = [item("surfboard", 200, 10, 50), item("glass", 60, 5, 40, kg: 1, fragile: true),
                     item("box", 20, 20, 20, hardness: 1)]
        let full = Container(id: "f", name: "f", type: .suitcase, outer: [60, 30, 40],
                             compartments: [Compartment(name: "main", dims: [60, 25, 40])], weightLimitKg: 23)
        let p = pack(items, into: full)
        let reasons = explainUnplaced(p, items: items, container: full)
        #expect(reasons["surfboard"] == .tooLarge)
        // The glass (more volume) wins the floor, so the rigid box could only go above it.
        #expect(reasons["box"] == .fragileInTheWay)
        #expect(Set(reasons.keys) == Set(p.unplaced))
    }

    // MARK: Stats

    @Test func statsAreComputedOverPlacedItems() {
        let items = [item("a", 60, 15, 40, kg: 3, hardness: 1), item("b", 60, 15, 40, kg: 1, hardness: 1)]
        let p = pack(items, into: suitcase)
        #expect(abs(p.stats.fillPct - 100) < 1e-9)
        #expect(abs(p.stats.kg - 4) < 1e-9)
        // a at the bottom (centre 25%), b on top (centre 75%): (3*25 + 1*75) / 4 = 37.5.
        #expect(abs(p.stats.comHeightPct - 37.5) < 1e-9)
    }
}
