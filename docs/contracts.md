# Shared data contracts

Source of truth: `schemas/*.schema.json` (JSON Schema 2020-12), one file per type. Two
mirrors must match it exactly and are tested against the same fixtures:

- `Packages/PackFitSchemas/Sources/PackFitSchemas/*.swift` (Codable structs, Section 1)
- `services/api/src/schemas.ts` (zod, Section 3)

Field names are camelCase in JSON and identical in Swift and TypeScript, so no key mapping.

Fields marked `added` are additions to the outline's section 4, required by workstreams in
section 5. They are optional so the outline's base shape remains valid.

## Types

Shown as Swift; the TypeScript and JSON Schema follow the same names and optionality.
Units: centimetres and kilograms everywhere.

```swift
public enum Category: String, Codable, CaseIterable, Sendable {
    case clothing, shoes, toiletries, liquids, electronics, documents, medical, food, sharp, other
}

public enum MeasureMethod: String, Codable, Sendable {
    case lidar, reference, manual, catalog, estimate
}

/// added: how the dims were obtained; shown in the UI and sent to the scan endpoint
public struct Measurement: Codable, Sendable, Equatable {
    public var method: MeasureMethod
    public var confidence: Double        // 0-1; lidar >= 0.9 unless depth confidence was low
    public var deviceHasLidar: Bool
}

public struct Item: Codable, Identifiable, Sendable, Equatable {
    public var id: String                // uuid
    public var name: String
    public var w: Double                 // width, cm, as scanned (before orientation)
    public var h: Double                 // height, cm
    public var d: Double                 // depth, cm
    public var kg: Double
    public var fragile: Bool             // never place anything on top of it
    public var hardness: Double          // 0 (plush) to 1 (rigid)
    public var soft: Bool                // may compress 20% in the packer
    public var upright: Bool             // orientation locked: h stays vertical
    public var category: Category
    public var confidence: Double        // 0-1, overall; 1 for manual/fixture items
    public var neededAtSecurity: Bool?   // added: packer puts these on top
    public var source: ItemSource?       // added: scan | manual | suggested | fixture
    public var measurement: Measurement? // added
}

public enum ItemSource: String, Codable, Sendable { case scan, manual, suggested, fixture }

public struct Compartment: Codable, Sendable, Equatable {
    public var name: String                     // "main" | "front" | "laptop" | free text
    public var dims: [Double]                   // inner [w, h, d], exactly 3
    public var compressibility: Double          // 0-1
}

public struct Container: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var type: ContainerType              // suitcase | duffel | backpack
    public var outer: [Double]                  // [w, h, d] outer dims, exactly 3
    public var compartments: [Compartment]      // suitcases have exactly one: "main"
    public var weightLimitKg: Double            // 23 for the target user
    public var wheelsSide: WheelsSide?          // added: back | bottom; default bottom
    public var measurement: Measurement?        // added
}

public enum ContainerType: String, Codable, Sendable { case suitcase, duffel, backpack }
public enum WheelsSide: String, Codable, Sendable { case back, bottom }

public struct Placement: Codable, Sendable, Equatable {
    public var itemId: String
    public var x: Double, y: Double, z: Double  // min corner, cm (see coordinate convention)
    public var w: Double, h: Double, d: Double  // dims after orientation and compression
    public var order: Int                       // 0-based packing step
    public var compartment: String?             // added: Compartment.name; nil means "main"
}

public struct PlanStats: Codable, Sendable, Equatable {
    public var fillPct: Double       // 0-100
    public var kg: Double
    public var comHeightPct: Double  // centre-of-mass height as % of container height
}

public struct Plan: Codable, Sendable, Equatable {
    public var placed: [Placement]   // sorted by order
    public var unplaced: [String]    // itemIds that did not fit
    public var stats: PlanStats
}

public struct RuleFlag: Codable, Sendable, Equatable {
    public var itemId: String
    public var scope: RuleScope             // tsa | airline | country
    public var severity: RuleSeverity       // banned | restricted | check
    public var text: String                 // guidance, not authority
    public var sourceUrl: String            // required, a real page
    public var lastVerified: String         // ISO 8601 date; stale if older than 30 days
    public var ruleId: String?              // added
}

public enum RuleScope: String, Codable, Sendable { case tsa, airline, country }
public enum RuleSeverity: String, Codable, Sendable { case banned, restricted, check }

public struct Trip: Codable, Sendable, Equatable {
    public var from: String          // IATA airport, e.g. "SFO"
    public var to: String            // IATA airport, e.g. "DEL"
    public var airline: String       // IATA airline, e.g. "UA"
    public var nights: Int
    public var activities: [String]
    public var carryOn: Container
    public var checked: Container
    public var departDate: String?   // added: ISO date for the weather forecast
}
```

Swift notes: all types are `Sendable` and `Equatable` so they cross actor boundaries and
work in `@Observable` state. `dims` and `outer` are `[Double]` of length 3 rather than tuples
because tuples are not `Codable`; the JSON Schema enforces `minItems: 3, maxItems: 3`.

## Fixtures

`schemas/fixtures/` (owned by Section 1), plain JSON loaded by both the Swift package
(as a resource bundle) and the backend tests:

- `containers.json`: 3 bags. A 55x40x23 cm carry-on, a 75x50x30 cm checked suitcase with
  `weightLimitKg: 23`, and a 30x48x20 cm backpack with `main`, `front`, and `laptop`
  compartments. All with `measurement.method = "manual"`.
- `items.json`: 25 items with ground-truth dimensions measured with a tape, `_source` noted.
  Covers each `Category` at least once, at least 3 fragile, 5 soft, 2 upright, 3
  `neededAtSecurity`, and at least 2 that should trigger a rule flag (a full-size shampoo, a
  power bank over 100 Wh or a pocket knife). These same 25 physical items are what Section 2
  LiDAR-scans to measure accuracy and what Section 3 photographs for the vision test.
- `trips.json`: 5 trip scenarios. Must include SFO->DEL on a 23 kg limit (the target user),
  a short domestic trip, and a cold-weather destination.
- `plans/`: one pre-computed `Plan` per (container, item set) used in the demo so the viewer
  and voice coach run offline.

## Change protocol

1. Add a row to `docs/requests.md` with the field, type, reason, and which section asked.
2. Additive optional field: Section 1 edits the JSON Schema and the Swift mirror, posts in the
   team channel; Section 3 updates the zod mirror in the same day. `pnpm schemas:check` fails
   until both match.
3. Rename, removal, or type change: all four agree first. Avoid during the last third.
