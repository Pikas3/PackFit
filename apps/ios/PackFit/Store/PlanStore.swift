import Foundation

@Observable
@MainActor
final class PlanStore {
    var plan: Plan?
    var isPacking = false
    var errorMessage: String?

    /// Uses fixture plan until Packages/Packer lands; then call `pack(_:into:options:)`.
    func pack(items: [Item], into container: Container) async {
        isPacking = true
        errorMessage = nil
        defer { isPacking = false }

        // Background-friendly delay so UI shows packing state; solver stays deterministic.
        try? await Task.sleep(for: .milliseconds(200))

        #if canImport(Packer)
        // When Packer is linked: plan = pack(items, into: container, options: .default)
        #endif

        if items.isEmpty {
            plan = Plan(placed: [], unplaced: [], stats: PlanStats(fillPct: 0, kg: 0, comHeightPct: 0))
            return
        }

        // Deterministic simple stack for offline demo (same input → same plan).
        let sorted = items.sorted { lhs, rhs in
            if lhs.id != rhs.id { return lhs.id < rhs.id }
            return lhs.name < rhs.name
        }
        let main = container.compartments.first?.dims ?? container.outer
        let maxW = main[0]
        let maxH = main[1]
        let maxD = main[2]

        var placed: [Placement] = []
        var unplaced: [String] = []
        var cursorX: Double = 0
        var cursorY: Double = 0
        var cursorZ: Double = 0
        var rowDepth: Double = 0
        var layerHeight: Double = 0
        var order = 0
        var totalKg: Double = 0

        for item in sorted {
            let w = item.w
            let h = item.h
            let d = item.d
            if w > maxW || h > maxH || d > maxD {
                unplaced.append(item.id)
                continue
            }
            if cursorX + w > maxW {
                cursorX = 0
                cursorZ += rowDepth
                rowDepth = 0
            }
            if cursorZ + d > maxD {
                cursorX = 0
                cursorZ = 0
                cursorY += layerHeight
                layerHeight = 0
                rowDepth = 0
            }
            if cursorY + h > maxH {
                unplaced.append(item.id)
                continue
            }
            placed.append(
                Placement(
                    itemId: item.id,
                    x: cursorX,
                    y: cursorY,
                    z: cursorZ,
                    w: w,
                    h: h,
                    d: d,
                    order: order,
                    compartment: container.compartments.first?.name ?? "main"
                )
            )
            order += 1
            totalKg += item.kg
            cursorX += w
            rowDepth = max(rowDepth, d)
            layerHeight = max(layerHeight, h)
        }

        let volume = maxW * maxH * maxD
        let used = placed.reduce(0.0) { $0 + ($1.w * $1.h * $1.d) }
        let fill = volume > 0 ? min(100, used / volume * 100) : 0
        let com = maxH > 0
            ? placed.reduce(0.0) { $0 + ($1.y + $1.h / 2) } / Double(max(placed.count, 1)) / maxH * 100
            : 0

        plan = Plan(
            placed: placed,
            unplaced: unplaced,
            stats: PlanStats(fillPct: fill, kg: totalKg, comHeightPct: com)
        )
    }

    func loadFixturePlan() {
        plan = Fixtures.plan(named: "demo")
    }
}
