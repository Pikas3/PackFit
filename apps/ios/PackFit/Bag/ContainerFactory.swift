import Foundation
import simd

/// How a suitcase’s packing volume is split.
enum SuitcaseShell: String, CaseIterable, Sendable {
    /// One open cavity (current presets).
    case single
    /// Zipper clamshell: base (wheels) side and lid side, packed separately.
    case twoSided
}

/// Builds custom `Container`s from measured or entered sizes. Suitcases lie open:
/// `outer = [length, thickness, width]`, matching the fixtures.
enum ContainerFactory {
    static let wallInsetCm: Double = 3
    /// Gap between base and lid in the open 3D layout (hinge), cm.
    static let openHingeCm: Double = 4

    static func custom(
        outer: [Double],
        method: MeasureMethod,
        confidence: Double,
        weightLimit: Double = 23,
        wheelsSide: WheelsSide = .bottom,
        shell: SuitcaseShell = .single
    ) -> Container {
        let inner = outer.map { max(1, $0 - wallInsetCm * 2) }
        return make(
            outer: outer,
            inner: inner,
            method: method,
            confidence: confidence,
            weightLimit: weightLimit,
            wheelsSide: wheelsSide,
            shell: shell
        )
    }

    /// From a scanned or tapped open shell. Assumes a 50/50 clamshell: each half is
    /// `shellDepthCm` deep. `shell: .twoSided` keeps both sides; `.single` merges them.
    static func fromCavity(
        innerLongCm: Double,
        innerShortCm: Double,
        shellDepthCm: Double,
        confidence: Double,
        method: MeasureMethod = .lidar,
        weightLimit: Double = 23,
        shell: SuitcaseShell = .twoSided
    ) -> Container {
        let half = (shellDepthCm * 10).rounded() / 10
        let long = (innerLongCm * 10).rounded() / 10
        let short = (innerShortCm * 10).rounded() / 10
        let closedY = half * 2
        let inner = [long, closedY, short]
        let outer = inner.map { $0 + wallInsetCm * 2 }
        return make(
            outer: outer,
            inner: inner,
            method: method,
            confidence: confidence,
            weightLimit: weightLimit,
            wheelsSide: .back,
            shell: shell
        )
    }

    /// Rebuild a suitcase with a different shell split. Backpacks and duffels are unchanged.
    static func applying(_ shell: SuitcaseShell, to bag: Container) -> Container {
        guard bag.type == .suitcase, let primary = bag.compartments.first, primary.dims.count == 3 else {
            return bag
        }
        var next = bag
        next.compartments = compartments(inner: mergedInner(of: bag), shell: shell)
        if shell == .twoSided, !next.name.localizedCaseInsensitiveContains("zipper") {
            next.name = bag.name.hasSuffix("(2 sides)") ? bag.name : "\(bag.name) · 2 sides"
        }
        if shell == .single {
            next.name = bag.name
                .replacingOccurrences(of: " · 2 sides", with: "")
                .replacingOccurrences(of: " (2 sides)", with: "")
        }
        return next
    }

    /// World-space offset (cm) of a compartment’s local origin in the open-flat layout.
    /// Base/main at the origin; lid sits past the base along +z with a hinge gap.
    static func openOffsetCm(for compartmentName: String?, in bag: Container) -> SIMD3<Double> {
        let comps = bag.compartments
        guard comps.count >= 2 else { return .zero }
        let name = compartmentName ?? comps.first?.name
        guard let name, let index = comps.firstIndex(where: { $0.name == name }), index > 0 else {
            return .zero
        }
        var z = 0.0
        for i in 0..<index {
            z += comps[i].dims[2] + openHingeCm
        }
        return SIMD3(0, 0, z)
    }

    /// Axis-aligned bounds (cm) of the open layout: [w, h, total depth including hinge].
    static func openBoundsCm(of bag: Container) -> [Double] {
        let comps = bag.compartments.filter { $0.dims.count == 3 }
        guard let first = comps.first else { return bag.outer }
        guard comps.count >= 2 else { return first.dims }
        let w = comps.map { $0.dims[0] }.max() ?? first.dims[0]
        let h = comps.map { $0.dims[1] }.max() ?? first.dims[1]
        let d = comps.map(\.dims[2]).reduce(0, +) + openHingeCm * Double(comps.count - 1)
        return [w, h, d]
    }

    private static func make(
        outer: [Double],
        inner: [Double],
        method: MeasureMethod,
        confidence: Double,
        weightLimit: Double,
        wheelsSide: WheelsSide,
        shell: SuitcaseShell
    ) -> Container {
        let two = shell == .twoSided
        return Container(
            id: UUID().uuidString,
            name: method == .lidar || wheelsSide == .back
                ? (two ? "Scanned bag · 2 sides" : "Scanned bag")
                : (two ? "Custom bag · 2 sides" : "Custom bag"),
            type: .suitcase,
            outer: outer,
            compartments: compartments(inner: inner, shell: shell),
            weightLimitKg: weightLimit,
            wheelsSide: wheelsSide,
            measurement: Measurement(method: method, confidence: confidence, deviceHasLidar: method == .lidar)
        )
    }

    /// Closed-bag inner [w, h, d]; for an existing two-sided bag, h is the sum of both depths.
    private static func mergedInner(of bag: Container) -> [Double] {
        let comps = bag.compartments.filter { $0.dims.count == 3 }
        guard let first = comps.first else {
            return bag.outer.map { max(1, $0 - wallInsetCm * 2) }
        }
        if comps.count == 1 { return first.dims }
        let w = comps.map { $0.dims[0] }.max() ?? first.dims[0]
        let h = comps.map { $0.dims[1] }.reduce(0, +)
        let d = comps.map { $0.dims[2] }.max() ?? first.dims[2]
        return [w, h, d]
    }

    private static func compartments(inner: [Double], shell: SuitcaseShell) -> [Compartment] {
        guard shell == .twoSided, inner.count == 3 else {
            return [Compartment(name: "main", dims: inner, compressibility: 0.1)]
        }
        let half = max(1, (inner[1] / 2 * 10).rounded() / 10)
        let dims = [inner[0], half, inner[2]]
        return [
            Compartment(name: "base", dims: dims, compressibility: 0.1),
            Compartment(name: "lid", dims: dims, compressibility: 0.1),
        ]
    }
}
