import Foundation

/// Builds custom `Container`s from measured or entered sizes. Suitcases lie open:
/// `outer = [length, thickness, width]`, matching the fixtures.
enum ContainerFactory {
    static let wallInsetCm: Double = 3

    /// Bags the guided scan knows how to turn into a container. Backpacks use the presets
    /// and the compartment editor.
    enum BagKind: String, CaseIterable, Identifiable, Sendable {
        /// Two rigid halves that both hold things.
        case hardShell
        /// One shell with a flat zip lid.
        case softShell

        var id: String { rawValue }

        var label: String {
            switch self {
            case .hardShell: return Copy.Guided.bagHardShell
            case .softShell: return Copy.Guided.bagSoftShell
            }
        }

        /// Lid depth as a share of the base's, when the lid can't be measured.
        var lidFraction: Double { self == .hardShell ? 1 : 0 }

        /// Outer to inner allowances, cm in total per axis. The long axis loses the wheel
        /// and handle housings; hard shells have thin walls, soft ones padding.
        var allowance: (long: Double, short: Double, shell: Double) {
            switch self {
            case .hardShell: return (6, 2, 1)
            case .softShell: return (6, 3, 1.5)
            }
        }

        var compressibility: Double { self == .hardShell ? 0.05 : 0.25 }
    }

    /// Margin taken off each inner axis when the size came from the camera alone, so the
    /// plan still fits a bag measured a little large.
    static let cameraMarginCm: Double = 1

    static func custom(
        outer: [Double],
        method: MeasureMethod,
        confidence: Double,
        weightLimit: Double = 23,
        wheelsSide: WheelsSide = .bottom
    ) -> Container {
        let inner = outer.map { max(1, $0 - wallInsetCm * 2) }
        return make(outer: outer, inner: inner, method: method, confidence: confidence, weightLimit: weightLimit, wheelsSide: wheelsSide)
    }

    /// From a scanned or tapped open shell. The lid adds `lidFraction` of the shell depth
    /// (1 for a 50/50 clamshell). Inner is measured directly; outer adds the wall inset on
    /// every side.
    static func fromCavity(
        innerLongCm: Double,
        innerShortCm: Double,
        shellDepthCm: Double,
        confidence: Double,
        method: MeasureMethod = .lidar,
        weightLimit: Double = 23,
        lidFraction: Double = 1
    ) -> Container {
        let inner = [innerLongCm, (1 + lidFraction) * shellDepthCm, innerShortCm].map { ($0 * 10).rounded() / 10 }
        let outer = inner.map { $0 + wallInsetCm * 2 }
        return make(outer: outer, inner: inner, method: method, confidence: confidence, weightLimit: weightLimit, wheelsSide: .back)
    }

    /// From the outer size of an open bag measured by its outline (no LiDAR): the tapped
    /// base shell, plus the lid's depth when the other half was measured too.
    static func fromShells(
        outerLongCm: Double,
        outerShortCm: Double,
        baseDepthCm: Double,
        lidDepthCm: Double?,
        kind: BagKind,
        confidence: Double,
        weightLimit: Double = 23
    ) -> Container {
        let a = kind.allowance
        let lid = lidDepthCm ?? baseDepthCm * kind.lidFraction
        let depth = baseDepthCm + lid - a.shell * (lid > 0 ? 2 : 1)
        let inner = [outerLongCm - a.long, depth, outerShortCm - a.short]
            .map { (max(1, $0 - cameraMarginCm) * 10).rounded() / 10 }
        let outer = [outerLongCm, baseDepthCm + lid, outerShortCm].map { ($0 * 10).rounded() / 10 }
        var container = make(outer: outer, inner: inner, method: .ar, confidence: confidence, weightLimit: weightLimit, wheelsSide: .back)
        container.name = "Scanned bag"
        container.compartments[0].compressibility = kind.compressibility
        return container
    }

    private static func make(
        outer: [Double],
        inner: [Double],
        method: MeasureMethod,
        confidence: Double,
        weightLimit: Double,
        wheelsSide: WheelsSide
    ) -> Container {
        Container(
            id: UUID().uuidString,
            name: method == .lidar || wheelsSide == .back ? "Scanned bag" : "Custom bag",
            type: .suitcase,
            outer: outer,
            compartments: [Compartment(name: "main", dims: inner, compressibility: 0.1)],
            weightLimitKg: weightLimit,
            wheelsSide: wheelsSide,
            measurement: Measurement(method: method, confidence: confidence, deviceHasLidar: method == .lidar)
        )
    }
}
