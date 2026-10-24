import Foundation

/// Builds custom `Container`s from measured or entered sizes. Suitcases lie open:
/// `outer = [length, thickness, width]`, matching the fixtures.
enum ContainerFactory {
    static let wallInsetCm: Double = 3

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

    /// From a scanned or tapped open shell. Assumes a 50/50 clamshell, so the lid half doubles
    /// the depth. Inner is measured directly; outer adds the wall inset on every side.
    static func fromCavity(
        innerLongCm: Double,
        innerShortCm: Double,
        shellDepthCm: Double,
        confidence: Double,
        method: MeasureMethod = .lidar,
        weightLimit: Double = 23
    ) -> Container {
        let inner = [innerLongCm, 2 * shellDepthCm, innerShortCm].map { ($0 * 10).rounded() / 10 }
        let outer = inner.map { $0 + wallInsetCm * 2 }
        return make(outer: outer, inner: inner, method: method, confidence: confidence, weightLimit: weightLimit, wheelsSide: .back)
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
