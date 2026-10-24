import Foundation

// Temporary mirror of docs/contracts.md until Packages/PackFitSchemas lands on master.
// Delete this file and `import PackFitSchemas` everywhere the moment the package is available.

public enum Category: String, Codable, CaseIterable, Sendable {
    case clothing, shoes, toiletries, liquids, electronics, documents, medical, food, sharp, other
}

public enum MeasureMethod: String, Codable, Sendable {
    case lidar, reference, manual, catalog, estimate
}

public struct Measurement: Codable, Sendable, Equatable {
    public var method: MeasureMethod
    public var confidence: Double
    public var deviceHasLidar: Bool

    public init(method: MeasureMethod, confidence: Double, deviceHasLidar: Bool) {
        self.method = method
        self.confidence = confidence
        self.deviceHasLidar = deviceHasLidar
    }
}

public enum ItemSource: String, Codable, Sendable {
    case scan, manual, suggested, fixture
}

public struct Item: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var w: Double
    public var h: Double
    public var d: Double
    public var kg: Double
    public var fragile: Bool
    public var hardness: Double
    public var soft: Bool
    public var upright: Bool
    public var category: Category
    public var confidence: Double
    public var neededAtSecurity: Bool?
    public var source: ItemSource?
    public var measurement: Measurement?

    public init(
        id: String = UUID().uuidString,
        name: String,
        w: Double,
        h: Double,
        d: Double,
        kg: Double,
        fragile: Bool = false,
        hardness: Double = 0.5,
        soft: Bool = false,
        upright: Bool = false,
        category: Category,
        confidence: Double = 1,
        neededAtSecurity: Bool? = nil,
        source: ItemSource? = nil,
        measurement: Measurement? = nil
    ) {
        self.id = id
        self.name = name
        self.w = w
        self.h = h
        self.d = d
        self.kg = kg
        self.fragile = fragile
        self.hardness = hardness
        self.soft = soft
        self.upright = upright
        self.category = category
        self.confidence = confidence
        self.neededAtSecurity = neededAtSecurity
        self.source = source
        self.measurement = measurement
    }
}

public struct Compartment: Codable, Sendable, Equatable {
    public var name: String
    public var dims: [Double]
    public var compressibility: Double

    public init(name: String, dims: [Double], compressibility: Double) {
        self.name = name
        self.dims = dims
        self.compressibility = compressibility
    }
}

public enum ContainerType: String, Codable, Sendable {
    case suitcase, duffel, backpack
}

public enum WheelsSide: String, Codable, Sendable {
    case back, bottom
}

public struct Container: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var type: ContainerType
    public var outer: [Double]
    public var compartments: [Compartment]
    public var weightLimitKg: Double
    public var wheelsSide: WheelsSide?
    public var measurement: Measurement?

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: ContainerType,
        outer: [Double],
        compartments: [Compartment],
        weightLimitKg: Double,
        wheelsSide: WheelsSide? = .bottom,
        measurement: Measurement? = nil
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

public struct Placement: Codable, Sendable, Equatable {
    public var itemId: String
    public var x: Double
    public var y: Double
    public var z: Double
    public var w: Double
    public var h: Double
    public var d: Double
    public var order: Int
    public var compartment: String?

    public init(
        itemId: String,
        x: Double,
        y: Double,
        z: Double,
        w: Double,
        h: Double,
        d: Double,
        order: Int,
        compartment: String? = nil
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
    public var fillPct: Double
    public var kg: Double
    public var comHeightPct: Double

    public init(fillPct: Double, kg: Double, comHeightPct: Double) {
        self.fillPct = fillPct
        self.kg = kg
        self.comHeightPct = comHeightPct
    }
}

public struct Plan: Codable, Sendable, Equatable {
    public var placed: [Placement]
    public var unplaced: [String]
    public var stats: PlanStats

    public init(placed: [Placement], unplaced: [String], stats: PlanStats) {
        self.placed = placed
        self.unplaced = unplaced
        self.stats = stats
    }
}

public enum RuleScope: String, Codable, Sendable {
    case tsa, airline, country
}

public enum RuleSeverity: String, Codable, Sendable, CaseIterable {
    case banned, restricted, check
}

public struct RuleFlag: Codable, Sendable, Equatable, Identifiable {
    public var itemId: String
    public var scope: RuleScope
    public var severity: RuleSeverity
    public var text: String
    public var sourceUrl: String
    public var lastVerified: String
    public var ruleId: String?

    public var id: String { "\(itemId)-\(ruleId ?? text)" }

    public init(
        itemId: String,
        scope: RuleScope,
        severity: RuleSeverity,
        text: String,
        sourceUrl: String,
        lastVerified: String,
        ruleId: String? = nil
    ) {
        self.itemId = itemId
        self.scope = scope
        self.severity = severity
        self.text = text
        self.sourceUrl = sourceUrl
        self.lastVerified = lastVerified
        self.ruleId = ruleId
    }
}

public struct Trip: Codable, Sendable, Equatable {
    public var from: String
    public var to: String
    public var airline: String
    public var nights: Int
    public var activities: [String]
    public var carryOn: Container
    public var checked: Container
    public var departDate: String?

    public init(
        from: String,
        to: String,
        airline: String,
        nights: Int,
        activities: [String] = [],
        carryOn: Container,
        checked: Container,
        departDate: String? = nil
    ) {
        self.from = from
        self.to = to
        self.airline = airline
        self.nights = nights
        self.activities = activities
        self.carryOn = carryOn
        self.checked = checked
        self.departDate = departDate
    }
}

public struct ItemAlternative: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var category: Category

    public init(name: String, category: Category) {
        self.name = name
        self.category = category
    }
}

public struct ScanItemResponse: Codable, Sendable {
    public var item: Item
    public var alternatives: [ItemAlternative]
    public var warnings: [String]
}

public struct RulesCheckResponse: Codable, Sendable {
    public var flags: [RuleFlag]
    public var summary: String
    public var stale: Bool
    public var rulesLastSynced: String?
}
