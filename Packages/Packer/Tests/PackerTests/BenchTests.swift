import Foundation
import PackFitSchemas
import Testing
@testable import Packer

@Suite struct BenchTests {
    /// 30 items in the checked suitcase: under 1,000 ms in debug, 300 ms in release.
    /// Judged on the best of 5 runs of this thread's CPU time: Swift Testing runs the other
    /// suites in parallel, and wall-clock time would count their load against the packer.
    @Test func thirtyItemsInCheckedSuitcase() throws {
        let checked = try #require(try Fixtures.containers().first { $0.id == "checked-75" })
        // The 25 fixture items plus 5 seeded random ones keeps sizes realistic.
        var rng = SplitMix64(seed: 30)
        let items = try Fixtures.items() + randomItems(count: 5, using: &rng).map {
            var i = $0
            (i.w, i.h, i.d) = (i.w / 2, i.h / 2, i.d / 2)
            return i
        }
        #expect(items.count == 30)

        _ = pack(items, into: checked)   // warm up
        let runs = 5
        var times: [Double] = []
        var plan: Plan?
        for _ in 0..<runs {
            let start = threadCPUMilliseconds()
            plan = pack(items, into: checked)
            times.append(threadCPUMilliseconds() - start)
        }
        let ms = times.min()!
        #if DEBUG
        let budget = 1_000.0, config = "debug"
        #else
        let budget = 300.0, config = "release"
        #endif
        print("BenchTests: 30 items, checked-75, \(config): best \(String(format: "%.1f", ms)) ms, worst \(String(format: "%.1f", times.max()!)) ms of \(runs), placed \(plan!.placed.count), fill \(String(format: "%.1f", plan!.stats.fillPct))%")
        #expect(ms < budget, "pack took \(ms) ms, budget \(budget) ms (\(config))")
        #expect(validatePlan(plan!, items: items, container: checked) == [])
    }
}

/// CPU time used by the calling thread, ms.
private func threadCPUMilliseconds() -> Double {
    var ts = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
    return Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1e6
}
