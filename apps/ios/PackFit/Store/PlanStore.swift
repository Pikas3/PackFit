import Foundation
import Packer
import PackFitSchemas

@Observable
@MainActor
final class PlanStore {
    var plan: Plan?
    /// Why each id in `plan.unplaced` didn't fit. Empty for fixture plans.
    var unplacedReasons: [String: UnplacedReason] = [:]
    var isPacking = false
    var errorMessage: String?

    func computePlan(items: [Item], into container: Container) async {
        isPacking = true
        errorMessage = nil
        defer { isPacking = false }

        unplacedReasons = [:]
        if items.isEmpty {
            plan = Plan(placed: [], unplaced: [], stats: PlanStats(fillPct: 0, kg: 0, comHeightPct: 0))
            return
        }

        let snapshot = items
        let bag = container
        let (packed, reasons) = await Task.detached(priority: .userInitiated) {
            // Section 1 solver (Packages/Packer).
            let options = PackOptions()
            let plan = pack(snapshot, into: bag, options: options)
            return (plan, explainUnplaced(plan, items: snapshot, container: bag, options: options))
        }.value
        unplacedReasons = reasons
        plan = packed
    }

    func loadFixturePlan(named name: String = "sfo-del-checked") {
        unplacedReasons = [:]
        plan = AppFixtures.plan(named: name)
    }
}
