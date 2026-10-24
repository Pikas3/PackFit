import Foundation

/// Local fixture loaders until `PackFitSchemas.Fixtures` lands.
enum Fixtures {
    static func containers() -> [Container] {
        [
            Container(
                id: "carry-on",
                name: "Carry-on",
                type: .suitcase,
                outer: [55, 40, 23],
                compartments: [Compartment(name: "main", dims: [52, 37, 20], compressibility: 0.1)],
                weightLimitKg: 10,
                wheelsSide: .bottom,
                measurement: Measurement(method: .manual, confidence: 1, deviceHasLidar: false)
            ),
            Container(
                id: "checked-23",
                name: "Checked 23 kg",
                type: .suitcase,
                outer: [75, 50, 30],
                compartments: [Compartment(name: "main", dims: [72, 47, 27], compressibility: 0.1)],
                weightLimitKg: 23,
                wheelsSide: .bottom,
                measurement: Measurement(method: .manual, confidence: 1, deviceHasLidar: false)
            ),
            Container(
                id: "backpack",
                name: "Travel backpack",
                type: .backpack,
                outer: [30, 48, 20],
                compartments: [
                    Compartment(name: "main", dims: [28, 44, 18], compressibility: 0.2),
                    Compartment(name: "front", dims: [26, 30, 6], compressibility: 0.15),
                    Compartment(name: "laptop", dims: [26, 38, 3], compressibility: 0)
                ],
                weightLimitKg: 12,
                wheelsSide: nil,
                measurement: Measurement(method: .manual, confidence: 1, deviceHasLidar: false)
            )
        ]
    }

    static func items() -> [Item] {
        demoItems
    }

    static func trips() -> [Trip] {
        let bags = containers()
        let carry = bags[0]
        let checked = bags[1]
        return [
            Trip(from: "SFO", to: "DEL", airline: "UA", nights: 21, activities: ["home", "family"], carryOn: carry, checked: checked, departDate: "2026-12-15"),
            Trip(from: "ATL", to: "JFK", airline: "DL", nights: 3, activities: ["weekend"], carryOn: carry, checked: checked, departDate: "2026-11-01"),
            Trip(from: "SFO", to: "YYC", airline: "AC", nights: 7, activities: ["ski"], carryOn: carry, checked: checked, departDate: "2027-01-10"),
            Trip(from: "LAX", to: "NRT", airline: "NH", nights: 10, activities: ["city"], carryOn: carry, checked: checked, departDate: "2026-11-20"),
            Trip(from: "ORD", to: "LHR", airline: "BA", nights: 5, activities: ["conference"], carryOn: carry, checked: checked, departDate: "2026-10-28")
        ]
    }

    /// Demo plan for the SFO→DEL checked bag with the first three items (offline spine).
    static func plan(named name: String = "demo") -> Plan {
        _ = name
        let items = Array(demoItems.prefix(3))
        var placed: [Placement] = []
        var y: Double = 0
        for (index, item) in items.enumerated() {
            placed.append(
                Placement(
                    itemId: item.id,
                    x: 2,
                    y: y,
                    z: 2,
                    w: item.w,
                    h: item.h,
                    d: item.d,
                    order: index,
                    compartment: "main"
                )
            )
            y += item.h + 0.5
        }
        let kg = items.reduce(0) { $0 + $1.kg }
        return Plan(
            placed: placed,
            unplaced: [],
            stats: PlanStats(fillPct: 18, kg: kg, comHeightPct: 35)
        )
    }

    static func sampleFlags(for items: [Item]) -> [RuleFlag] {
        guard let liquids = items.first(where: { $0.category == .liquids || $0.name.localizedCaseInsensitiveContains("shampoo") })
                ?? items.first else {
            return []
        }
        let knife = items.first(where: { $0.category == .sharp || $0.name.localizedCaseInsensitiveContains("knife") })
        var flags: [RuleFlag] = [
            RuleFlag(
                itemId: liquids.id,
                scope: .tsa,
                severity: .restricted,
                text: "Full-size liquids over 100 ml belong in checked baggage, not carry-on.",
                sourceUrl: "https://www.tsa.gov/travel/security-screening/whatcanibring/items/liquids-aerosols-and-gels",
                lastVerified: "2026-10-01",
                ruleId: "tsa-lag-100ml"
            )
        ]
        if let knife {
            flags.append(
                RuleFlag(
                    itemId: knife.id,
                    scope: .tsa,
                    severity: .banned,
                    text: "Pocket knives are not allowed in carry-on. Pack this in checked baggage.",
                    sourceUrl: "https://www.tsa.gov/travel/security-screening/whatcanibring/items/pocket-knife",
                    lastVerified: "2026-09-15",
                    ruleId: "tsa-pocket-knife"
                )
            )
        }
        return flags
    }

    // Ground-truth-ish demo set (25). Tape-measured later by Section 2 for LiDAR MAE.
    private static let demoItems: [Item] = [
        Item(id: "item-01", name: "T-shirt stack", w: 28, h: 6, d: 22, kg: 0.4, soft: true, category: .clothing, source: .fixture),
        Item(id: "item-02", name: "Jeans", w: 30, h: 4, d: 24, kg: 0.6, soft: true, category: .clothing, source: .fixture),
        Item(id: "item-03", name: "Running shoes", w: 32, h: 12, d: 22, kg: 0.8, category: .shoes, source: .fixture),
        Item(id: "item-04", name: "Toiletry pouch", w: 22, h: 8, d: 12, kg: 0.35, soft: true, category: .toiletries, source: .fixture),
        Item(id: "item-05", name: "Shampoo 250 ml", w: 6, h: 18, d: 6, kg: 0.28, upright: true, category: .liquids, source: .fixture),
        Item(id: "item-06", name: "Laptop 14\"", w: 32, h: 2, d: 22, kg: 1.4, fragile: true, hardness: 0.9, category: .electronics, neededAtSecurity: true, source: .fixture),
        Item(id: "item-07", name: "Charger brick", w: 7, h: 7, d: 3, kg: 0.2, hardness: 0.8, category: .electronics, source: .fixture),
        Item(id: "item-08", name: "Passport wallet", w: 14, h: 2, d: 10, kg: 0.1, category: .documents, neededAtSecurity: true, source: .fixture),
        Item(id: "item-09", name: "Vitamins", w: 5, h: 10, d: 5, kg: 0.15, upright: true, category: .medical, source: .fixture),
        Item(id: "item-10", name: "Snack bars", w: 18, h: 4, d: 12, kg: 0.25, soft: true, category: .food, source: .fixture),
        Item(id: "item-11", name: "Pocket knife", w: 10, h: 2, d: 3, kg: 0.12, hardness: 0.95, category: .sharp, source: .fixture),
        Item(id: "item-12", name: "Hoodie", w: 30, h: 8, d: 24, kg: 0.5, soft: true, category: .clothing, source: .fixture),
        Item(id: "item-13", name: "Socks pack", w: 16, h: 5, d: 12, kg: 0.2, soft: true, category: .clothing, source: .fixture),
        Item(id: "item-14", name: "Flip flops", w: 28, h: 3, d: 12, kg: 0.2, category: .shoes, source: .fixture),
        Item(id: "item-15", name: "Toothbrush kit", w: 4, h: 20, d: 4, kg: 0.08, upright: true, category: .toiletries, source: .fixture),
        Item(id: "item-16", name: "Face cream", w: 7, h: 7, d: 7, kg: 0.18, category: .liquids, source: .fixture),
        Item(id: "item-17", name: "Power bank 20000 mAh", w: 14, h: 2.5, d: 7, kg: 0.35, fragile: true, hardness: 0.85, category: .electronics, neededAtSecurity: true, source: .fixture),
        Item(id: "item-18", name: "Headphones", w: 18, h: 8, d: 16, kg: 0.25, fragile: true, soft: true, category: .electronics, source: .fixture),
        Item(id: "item-19", name: "Notebook", w: 21, h: 1.5, d: 15, kg: 0.3, category: .documents, source: .fixture),
        Item(id: "item-20", name: "Ibuprofen", w: 5, h: 8, d: 5, kg: 0.05, category: .medical, source: .fixture),
        Item(id: "item-21", name: "Instant noodles", w: 12, h: 12, d: 12, kg: 0.2, category: .food, source: .fixture),
        Item(id: "item-22", name: "Belt", w: 12, h: 4, d: 12, kg: 0.15, soft: true, category: .other, source: .fixture),
        Item(id: "item-23", name: "Umbrella compact", w: 6, h: 28, d: 6, kg: 0.3, hardness: 0.7, category: .other, source: .fixture),
        Item(id: "item-24", name: "Sweater", w: 32, h: 7, d: 26, kg: 0.55, soft: true, category: .clothing, source: .fixture),
        Item(id: "item-25", name: "Phone charger cable", w: 10, h: 3, d: 10, kg: 0.05, soft: true, category: .electronics, source: .fixture)
    ]
}
