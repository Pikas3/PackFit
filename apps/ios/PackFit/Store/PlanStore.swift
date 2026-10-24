import Foundation
import Packer
import PackFitSchemas

@Observable
@MainActor
final class PlanStore {
    var plan: Plan?
    var isPacking = false
    var errorMessage: String?

    func computePlan(items: [Item], into container: Container) async {
        isPacking = true
        errorMessage = nil
        defer { isPacking = false }

        if items.isEmpty {
            plan = Plan(placed: [], unplaced: [], stats: PlanStats(fillPct: 0, kg: 0, comHeightPct: 0))
            return
        }

        let snapshot = items
        let bag = container
        plan = await Task.detached(priority: .userInitiated) {
            // Section 1 solver (Packages/Packer).
            pack(snapshot, into: bag, options: PackOptions())
        }.value
    }

    func loadFixturePlan(named name: String = "sfo-del-checked") {
        plan = AppFixtures.plan(named: name)
    }
}
