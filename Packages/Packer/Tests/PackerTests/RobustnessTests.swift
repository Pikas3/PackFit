import PackFitSchemas
import Testing
@testable import Packer

/// Measured sizes may be a little off; the packer leaves room for that and warns about
/// weight instead of refusing.
@Suite struct RobustnessTests {
    private func measured(_ item: Item, _ method: MeasureMethod, _ confidence: Double) -> Item {
        var i = item
        i.measurement = Measurement(method: method, confidence: confidence, deviceHasLidar: method == .lidar)
        return i
    }

    @Test func uncertainSizesGetRoom() {
        let box = measured(item("box", 20, 10, 15, hardness: 0.9), .ar, 0.5)
        let p = pack([box], into: suitcase).placed[0]
        #expect(abs(p.w * p.d - (20 + 1.5) * (15 + 1.5)) < 1e-6, "padded footprint, got \(p.w) × \(p.d)")
        #expect(abs(p.h - 10) < 1e-6, "height never padded")

        let sure = measured(item("sure", 20, 10, 15, hardness: 0.9), .lidar, 1)
        let q = pack([sure], into: suitcase).placed[0]
        #expect(abs(q.w * q.d - 20 * 15) < 1e-6)
    }

    @Test func manualAndSoftItemsAreNotPadded() {
        let manual = measured(item("m", 20, 10, 15), .manual, 0.5)
        let soft = measured(item("s", 20, 10, 15, hardness: 0.1, soft: true), .ar, 0.5)
        let plan = pack([manual, soft], into: suitcase)
        for p in plan.placed { #expect(abs(p.w * p.d - 20 * 15) < 1e-6, "\(p.itemId)") }
    }

    @Test func paddedUprightItemStaysValid() {
        let bottle = measured(item("bottle", 7, 25, 7, upright: true), .ar, 0.6)
        let plan = pack([bottle], into: suitcase)
        #expect(plan.unplaced.isEmpty)
        #expect(validatePlan(plan, items: [bottle], container: suitcase) == [])
        #expect(abs(plan.placed[0].h - 25) < 1e-6)
    }

    @Test func padsCanBeTurnedOff() {
        var options = PackOptions()
        options.uncertaintyGapCm = 0
        let box = measured(item("box", 20, 10, 15), .ar, 0.5)
        let p = pack([box], into: suitcase, options: options).placed[0]
        #expect(abs(p.w * p.d - 20 * 15) < 1e-6)
    }

    @Test func paddedPackingIsDeterministic() {
        var rng = SplitMix64(seed: 42)
        let items = randomItems(count: 20, using: &rng).enumerated().map { i, it in
            measured(it, i % 2 == 0 ? .ar : .lidar, Double(i % 5) / 10 + 0.5)
        }
        let a = pack(items, into: suitcase)
        let b = pack(items.reversed(), into: suitcase)
        #expect(a == b)
    }

    /// Random measured items in every fixture bag: padded plans still break no rule.
    @Test(arguments: try Fixtures.containers().map(\.id))
    func paddedRandomTrialsAreValid(containerId: String) throws {
        let container = try #require(try Fixtures.containers().first { $0.id == containerId })
        var rng = SplitMix64(seed: 0xBADC0DE)
        var failures = 0
        for trial in 0..<200 {
            let items = randomItems(count: Int.random(in: 5...25, using: &rng), using: &rng).map { it in
                measured(it, [.ar, .lidar, .estimate][Int.random(in: 0..<3, using: &rng)], Double.random(in: 0.4...1, using: &rng))
            }
            let plan = pack(items, into: container)
            let violations = validatePlan(plan, items: items, container: container)
            let accounted = (plan.placed.map(\.itemId) + plan.unplaced).sorted() == items.map(\.id).sorted()
            if !violations.isEmpty || !accounted {
                failures += 1
                if failures <= 3 { Issue.record("trial \(trial): \(violations), accounted: \(accounted)") }
            }
        }
        #expect(failures == 0)
    }

    @Test func heavyItemsGoToTheWheelEnd() {
        var bag = suitcase
        bag.wheelsSide = .bottom
        let clothes = (0..<3).map { item("c\($0)", 10, 5, 40, kg: 0.3, hardness: 0.1, soft: true) }
        let items = clothes + [item("books", 10, 5, 20, kg: 4, hardness: 0.9)]
        let plan = pack(items, into: bag)
        let heavy = plan.placed.first { $0.itemId == "books" }!
        #expect(heavy.x < 1e-9 && heavy.y < 1e-9, "heavy item at the wheel end, on the bottom: \(heavy)")
        #expect(validatePlan(plan, items: items, container: bag) == [])
    }

    @Test func weightWarnings() {
        let heavy = (0..<5).map { item("h\($0)", 20, 10, 15, kg: 5) }
        let over = pack(heavy, into: suitcase)
        #expect(planWarnings(over, container: suitcase) == [.overWeight(kg: 25, limitKg: 23)])

        let near = pack(Array(heavy.prefix(4)), into: suitcase)
        #expect(planWarnings(near, container: suitcase, bagKg: 1) == [.nearWeightLimit(kg: 21, limitKg: 23)])
        #expect(planWarnings(near, container: suitcase) == [])

        let huge = [item("huge", 100, 100, 100, kg: 1)]
        #expect(planWarnings(pack(huge, into: suitcase), container: suitcase) == [.unplaced(count: 1)])
    }
}
