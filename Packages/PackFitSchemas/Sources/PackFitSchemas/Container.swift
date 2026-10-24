public enum ContainerType: String, Codable, Sendable { case suitcase, duffel, backpack }
public enum WheelsSide: String, Codable, Sendable { case back, bottom }

public struct Compartment: Codable, Sendable, Equatable {
    public var name: String                     // "main" | "front" | "laptop" | free text
    public var dims: [Double]                   // inner [w, h, d], exactly 3
    public var compressibility: Double          // 0-1

    public init(name: String, dims: [Double], compressibility: Double = 0) {
        self.name = name
        self.dims = dims
        self.compressibility = compressibility
    }
}

public struct Container: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var type: ContainerType
    public var outer: [Double]                  // [w, h, d] outer dims, exactly 3
    public var compartments: [Compartment]      // suitcases have exactly one: "main"
    public var weightLimitKg: Double            // 23 for the target user
    public var wheelsSide: WheelsSide?          // default bottom
    public var measurement: Measurement?

    public init(
        id: String, name: String, type: ContainerType, outer: [Double], compartments: [Compartment],
        weightLimitKg: Double, wheelsSide: WheelsSide? = nil, measurement: Measurement? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.outer = outer
        self.compartments = compartments
        self.weightLimitKg = weightLimitKg
        self.wheelsSide = wheelsSide
        self.measurement = measurement
    }
}
