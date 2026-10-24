public struct Placement: Codable, Sendable, Equatable {
    public var itemId: String
    public var x: Double, y: Double, z: Double  // min corner, cm (see coordinate convention)
    public var w: Double, h: Double, d: Double  // dims after orientation and compression
    public var order: Int                       // 0-based packing step
    public var compartment: String?             // Compartment.name; nil means "main"

    public init(
        itemId: String, x: Double, y: Double, z: Double, w: Double, h: Double, d: Double,
        order: Int, compartment: String? = nil
    ) {
        self.itemId = itemId
        self.x = x
        self.y = y
        self.z = z
        self.w = w
        self.h = h
        self.d = d
        self.order = order
        self.compartment = compartment
    }
}

public struct PlanStats: Codable, Sendable, Equatable {
    public var fillPct: Double       // 0-100
    public var kg: Double
    public var comHeightPct: Double  // centre-of-mass height as % of container height

    public init(fillPct: Double, kg: Double, comHeightPct: Double) {
        self.fillPct = fillPct
        self.kg = kg
        self.comHeightPct = comHeightPct
    }
}

public struct Plan: Codable, Sendable, Equatable {
    public var placed: [Placement]   // sorted by order
    public var unplaced: [String]    // itemIds that did not fit
    public var stats: PlanStats

    public init(placed: [Placement], unplaced: [String], stats: PlanStats) {
        self.placed = placed
        self.unplaced = unplaced
        self.stats = stats
    }
}
