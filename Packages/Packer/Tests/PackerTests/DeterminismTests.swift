import PackFitSchemas
import Testing
@testable import Packer

@Suite struct DeterminismTests {
    @Test(arguments: try fixtureCases())
    func samePlanTwice(_ c: FixtureCase) {
        #expect(pack(c.items, into: c.container) == pack(c.items, into: c.container))
    }

    @Test(arguments: try fixtureCases())
    func inputOrderDoesNotMatter(_ c: FixtureCase) {
        let expected = pack(c.items, into: c.container)
        var rng = SplitMix64(seed: 42)
        for _ in 0..<10 {
            #expect(pack(c.items.shuffled(using: &rng), into: c.container) == expected)
        }
    }

    /// The committed plans match the current solver. If this fails after a solver change,
    /// rerun `swift run --package-path Packages/Packer GenPlans`.
    @Test(arguments: try fixtureCases())
    func matchesCommittedPlan(_ c: FixtureCase) throws {
        #expect(pack(c.items, into: c.container) == (try Fixtures.plan(named: c.name)))
    }

    @Test(arguments: try fixtureCases())
    func everyItemAccountedFor(_ c: FixtureCase) {
        let p = pack(c.items, into: c.container)
        #expect((p.placed.map(\.itemId) + p.unplaced).sorted() == c.items.map(\.id).sorted())
        #expect(p.placed.map(\.order) == Array(0..<p.placed.count))
        #expect(validatePlan(p, items: c.items, container: c.container) == [])
    }

    @Test func randomSetsAreOrderIndependent() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<50 {
            let items = randomItems(count: Int.random(in: 5...30, using: &rng), using: &rng)
            let a = pack(items, into: suitcase)
            #expect(pack(items.shuffled(using: &rng), into: suitcase) == a)
        }
    }
}
