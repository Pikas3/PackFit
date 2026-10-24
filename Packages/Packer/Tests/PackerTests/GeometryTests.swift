import PackFitSchemas
import Testing
@testable import Packer

@Suite struct GeometryTests {
    static let trials = 1_000

    /// 1,000 random item sets per fixture container: no overlaps, nothing floating, no rule
    /// broken, nothing dropped.
    @Test(arguments: try Fixtures.containers().map(\.id))
    func randomTrialsAreValid(containerId: String) throws {
        let container = try #require(try Fixtures.containers().first { $0.id == containerId })
        var rng = SplitMix64(seed: 0xC0FFEE ^ UInt64(containerId.utf8.reduce(0) { $0 &* 31 &+ Int($1) }.magnitude))
        var failures = 0
        var placedTotal = 0
        for trial in 0..<Self.trials {
            let items = randomItems(count: Int.random(in: 5...30, using: &rng), using: &rng)
            var options = PackOptions()
            options.orientations = trial % 4 == 3 ? 2 : 6
            let plan = pack(items, into: container, options: options)
            placedTotal += plan.placed.count

            let violations = validatePlan(plan, items: items, container: container, options: options)
            let accounted = (plan.placed.map(\.itemId) + plan.unplaced).sorted() == items.map(\.id).sorted()
            if !violations.isEmpty || !accounted {
                failures += 1
                if failures <= 3 {
                    Issue.record("trial \(trial): \(violations), accounted: \(accounted)")
                }
            }
        }
        #expect(failures == 0, "\(failures) of \(Self.trials) trials invalid in \(containerId)")
        #expect(placedTotal > 0)
    }
}
