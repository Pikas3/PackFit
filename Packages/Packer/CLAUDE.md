# Section 1: Core (schemas, packing engine, fixtures)

You own `schemas/`, `Packages/PackFitSchemas` and `Packages/Packer`. Workstreams WS1 and
WS10. Read the root `CLAUDE.md`, then `docs/contracts.md`. The other three sections are
blocked on your schemas, so ship those in your first hour.

The solver runs on the phone, so it is a pure Swift package. The outline's web prototype
(`pack()` in JavaScript) is the reference implementation to port; if the file is not in the
repo, ask for it once and in the meantime implement from the rules below.

## Deliverables, in order

### 1. `schemas/` and `Packages/PackFitSchemas` (first hour)

- `schemas/item.schema.json`, `container.schema.json`, `plan.schema.json`,
  `ruleflag.schema.json`, `trip.schema.json`: JSON Schema 2020-12 matching
  `docs/contracts.md`. `additionalProperties: false` on every object. Enums for the string
  unions. `dims` and `outer` are `minItems: 3, maxItems: 3`.
- `schemas/fixtures/containers.json`, `items.json`, `trips.json` per the spec in
  `docs/contracts.md`. Dimensions must be real measurements, not guesses; weigh and measure
  the 25 physical items (they are the same items Sections 2 and 3 use for accuracy tests),
  and record provenance in a `_source` field. The JSON Schema allows `_source` only on
  fixture files via a separate `fixtures.schema.json` that extends the base.
- `Packages/PackFitSchemas`: SwiftPM library, iOS 18 and macOS 15 platforms (macOS so
  `swift test` runs on the Mac). `Sources/PackFitSchemas/` with one file per type exactly as
  in `docs/contracts.md`, plus `Fixtures.swift`:

  ```swift
  public enum Fixtures {
      public static func items() throws -> [Item]
      public static func containers() throws -> [Container]
      public static func trips() throws -> [Trip]
      public static func plan(named: String) throws -> Plan
  }
  ```

  Fixture JSON is included as package resources. Use a symlink from
  `Packages/PackFitSchemas/Sources/PackFitSchemas/Resources/fixtures` to
  `../../../../../schemas/fixtures` so there is one copy; if SwiftPM resource handling
  rejects the symlink, copy in a build script and say so in `docs/status.md`.
- `Tests/PackFitSchemasTests/DecodeTests.swift`: every fixture file decodes, re-encodes, and
  round-trips to equal JSON (key order aside). This is half of `pnpm schemas:check`; Section 3
  owns the zod half.
- Merge to `master` and tell the team. Everything else rebases on this.

### 2. `Packages/Packer`

Pure Swift. Depends only on `PackFitSchemas` and Foundation. No UIKit, no RealityKit, no
Combine. Public API:

```swift
public struct PackOptions: Sendable {
    public var orientations: Int = 6           // 6, or 2 for flat and flat-rotated only
    public var compressSoftPct: Double = 20
    public var supportPct: Double = 60
    public var heavyBias: HeavyBias = .wheels  // .wheels | .none
    public var securityOnTop: Bool = true
    public init()
}

public func pack(_ items: [Item], into container: Container, options: PackOptions = .init()) -> Plan
public func validatePlan(_ plan: Plan, items: [Item], container: Container) -> [PlanViolation]
public func describeStep(_ plan: Plan, items: [Item], order: Int) -> StepDescription?

public struct StepDescription: Sendable, Equatable {
    public var order: Int
    public var item: Item
    public var placement: Placement
    public var position: VerticalPosition      // .bottom | .middle | .top
    public var region: String                  // "back left corner", "front centre", ...
    public var near: [String]                  // names of touching already-placed items
    public var notes: [String]                 // "fragile, nothing goes on top", "keep accessible for security"
}

public enum PlanViolation: Sendable, Equatable {
    case overlap(a: String, b: String)
    case outOfBounds(itemId: String)
    case floating(itemId: String, supportPct: Double)
    case fragileUnder(fragileId: String, aboveId: String)
    case heavyOnLight(heavyId: String, lightId: String)
    case uprightBroken(itemId: String)
    case securityNotOnTop(itemId: String)
    case wrongCompartment(itemId: String, compartment: String)
}
```

Section 4 reads `StepDescription` aloud; keep it phrase-ready but not prose.

Rules the solver must enforce (the existing prototype covers the first five):

1. Extreme-point heuristic, items sorted largest-footprint first then heaviest, with `id` as
   the final tie-break so the order is total. Swift's `sort` is not guaranteed stable; never
   rely on input order.
2. Support: at least `supportPct` of the footprint rests on the floor or other items.
3. Fragile never under: nothing placed with any overlap above a fragile item.
4. No heavy on light: an item may not rest on an item with lower `hardness` if the upper
   item is heavier. Only crushable lower items count: not `soft` (clothes cushion) and
   `hardness < 0.5` (a folder or a book bears a laptop).
5. Flat-first orientation; soft items shrink `h` by `compressSoftPct`.
6. **New:** 6-orientation toggle. `upright == true` items only try orientations that keep
   their original `h` vertical.
7. **New:** heavy near wheels. For `.suitcase`, bias items with `kg` in the top quartile
   toward low `y` and, when `wheelsSide == .back`, low `z`. `.bottom` means the bag's frame
   puts the wheel end at x = 0 (the guided scan asks which end and orients the frame), so
   heavy items also prefer low `x`.
8. **New:** `neededAtSecurity == true` items are placed last and must be on the top layer or
   touching the opening (max `y`; see rule 12).
9. **New:** compartments. For backpacks, `laptop` accepts only `category == .electronics`
   with `hardness >= 0.7`; `front` accepts items whose smallest dimension is under 8 cm;
   everything else goes in `main`. Each compartment is packed independently. Set
   `placement.compartment`.
10. `unplaced` contains anything that could not be placed; never silently drop an item.
11. **Uncertainty gap.** `PackOptions.uncertaintyGapCm` (default 1.5) pads the width and
    depth of rigid items measured by `lidar`, `ar`, `reference` or `estimate`, scaled by
    `(1 - confidence) / 0.5` and clamped to 0–1. Height is never padded. Placements carry the
    padded slot. An item that fits nowhere padded is placed unpadded.
12. Suitcases and duffels are packed lying open on their back, so the opening for rule 8 is
    max y, as for backpacks.

`planWarnings(_:container:bagKg:)` reports `overWeight`, `nearWeightLimit` (≥ 90%) and
`unplaced`. The packer never refuses a plan over weight.

`stats`: `fillPct` over the compartments used, `kg` summed over placed items,
`comHeightPct` weighted by kg.

Use `Double` throughout with `let eps = 1e-6`; no `==` on floats.

### 3. Tests (`Packages/Packer/Tests/PackerTests/`)

Swift Testing (`import Testing`). The acceptance criteria from the outline, as tests that
fail loudly:

- `DeterminismTests`: `pack` on each fixture plan twice, results `==`. Also after shuffling
  the input array with a seeded generator.
- `GeometryTests`: 1,000 trials with a seeded PRNG (`SplitMix64`, in the test target only)
  generating random item sets (5-30 items, dims 2-50 cm) in each fixture container. For every
  trial `validatePlan` returns `[]`. Parameterised test over containers.
- `RuleTests`: hand-built cases for each of rules 3-9 with an obviously wrong placement that
  `validatePlan` rejects and a correct one it accepts.
- `BenchTests`: 30 items in the checked suitcase under 1,000 ms on the Mac in debug, under
  300 ms in release. Log the time. Section 2 reports the on-device number.
- `DescribeTests`: `describeStep` output is stable and names the right neighbours and region.

### 4. Pre-computed demo plans

For each demo trip in `schemas/fixtures/trips.json`, run `pack` and write
`schemas/fixtures/plans/<trip-id>-<bag>.json`. Provide `Packages/Packer/Sources/GenPlans/`
as an executable target: `swift run --package-path Packages/Packer GenPlans`. These are
what the viewer and voice coach use offline.

### 5. Optional, only if everything above is green

A local-search refinement pass (swap pairs, re-pack, keep if `comHeightPct` or `fillPct`
improves). Behind `PackOptions.refine: Bool = false`. Do not start before the last third; if
not done by judging, delete the branch. OR-tools is out: no Swift binding worth the time.

## Acceptance

- Deterministic output for fixed input.
- No overlaps or floating items in 1,000 random trials.
- 30 items in under 1 s (on device; Section 2 confirms).
- `Packages/PackFitSchemas` decodes every fixture; `pnpm schemas:check` passes.

## Conventions

- `Packages/Packer/Sources/Packer/`: `Pack.swift` (entry), `ExtremePoints.swift`,
  `Orientations.swift`, `Constraints.swift` (one function per rule returning
  `PlanViolation?`), `Compartments.swift`, `Stats.swift`, `Describe.swift`,
  `Validate.swift`. `Package.swift` with `swift-tools-version: 6.0`.
- Each constraint is a pure function `(candidate: Placement, placed: [Placement],
  items: [String: Item], container: Container) -> PlanViolation?`. This is what lets
  `validatePlan` and the solver share code.
- Everything not listed in the public API above is `internal`.
- The package compiles for iOS 18 and macOS 15. Run tests on the Mac.

## What to mock or skip

Nothing. You have no upstream dependencies.

## Report format

Append to `docs/status.md` after each milestone: what you built, what you cut, how to run
tests and `GenPlans`, bench numbers, any schema change you made and why.
