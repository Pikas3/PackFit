public enum MeasureMethod: String, Codable, Sendable {
    case lidar, reference, manual, catalog, estimate
}

/// How the dims were obtained; shown in the UI and sent to the scan endpoint.
public struct Measurement: Codable, Sendable, Equatable {
    public var method: MeasureMethod
    public var confidence: Double        // 0-1; lidar >= 0.9 unless depth confidence was low
    public var deviceHasLidar: Bool

    public init(method: MeasureMethod, confidence: Double, deviceHasLidar: Bool) {
        self.method = method
        self.confidence = confidence
        self.deviceHasLidar = deviceHasLidar
    }
}
