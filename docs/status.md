# Status log

Append an entry after each milestone. Newest at the bottom. Section 4 reads this to write the
README and track docs, so include file paths and measured numbers.

Template:

```
## <date> <section> <milestone>
Built:
Cut:
Run:
Measured:
Blocked on:
Schema changes:
```

## 2026-10-24 section-2 ios scaffold + demo spine
Built:
- `apps/ios/PackFit.xcodeproj` (scheme PackFit) with Swift 6 / iOS 18 target
- Temp contracts + fixtures in `PackFit/Temp/` until `PackFitSchemas` / fixture JSON land
- Stores: `TripStore`, `ItemsStore`, `PlanStore`, `RulesStore`
- API: `APIClient` + `LiveAPIClient` + `MockAPIClient` (`MOCK_API=YES` via `Config/Example.xcconfig`)
- Theme/Copy/Onboarding (`PackFit/Theme`, `Copy.swift`, `Onboarding/`)
- Demo spine screens: TripPicker → BagSetup → ItemList → Scan → PlanViewer → Rules / ItemDetail
- LiDAR measurement math + session controller (`Scan/Measurement/`), simulator/manual fallback
- RealityKit plan viewer with `PlanViewerControlling` for Section 4, step/play/peel/orbit
- Unit tests: `PackFitTests/MeasurementMathTests.swift`
- Optional XcodeGen spec: `apps/ios/project.yml`
Cut:
- Live AROverlay stretch
- Suggestions screen
- Full LiDAR suitcase measure UI (seeded custom bag path only)
- Linking local `Packages/PackFitSchemas`, `Packer`, `Voice` (not on master yet)
Run:
- On Mac: open `apps/ios/PackFit.xcodeproj`, scheme `PackFit`, iPhone simulator or LiDAR Pro device
- xcconfig: project uses `Config/Example.xcconfig` (`API_BASE_URL`, `APP_TOKEN`, `MOCK_API=YES`). Copy to gitignored `Debug.xcconfig` / `Release.xcconfig` for live API
- Mock mode is default; set `MOCK_API=NO` and point `API_BASE_URL` at `services/api` for live scan/rules
- Or regenerate project: `cd apps/ios && xcodegen generate`
Measured:
- fps: not yet (needs device + Instruments)
- LiDAR MAE on 25 fixtures: not yet (needs Pro device + tape ground truth)
- Bag setup time: not yet
Blocked on:
- Section 1: `Packages/PackFitSchemas` + `schemas/fixtures/**` (delete `PackFit/Temp/` when available)
- Section 1: `Packages/Packer` (`PlanStore` uses deterministic local packer until then)
- Section 3: live `/scan/item` and `/rules/check`
- macOS/Xcode 26 to run `xcodebuild` (scaffolded on Windows)
Schema changes:
- none (local Temp types mirror `docs/contracts.md` only)
## 2026-10-24 Section 1 Core: schemas, PackFitSchemas, Packer, demo plans
Built:
- `schemas/{item,container,plan,ruleflag,trip}.schema.json` (JSON Schema 2020-12, `additionalProperties: false`, enums, 3-length dims).
  `schemas/fixtures.schema.json` gives the fixture-file shapes: items and containers carry a required `_source`.
- Fixtures: `schemas/fixtures/items.json` (25 items, all 10 categories, 3 fragile, 6 soft, 3 upright, 3 `neededAtSecurity`;
  rule-flag triggers: 400 ml shampoo, pocket knife, 454 g peanut butter, a power bank),
  `containers.json` (carry-on, checked 23 kg, backpack with main/front/laptop), `trips.json` (5 trips incl. SFO->DEL 23 kg,
  SFO->LAX domestic, SEA->KEF cold), `packlists.json` (items per trip and bag), `plans/<trip-id>-<bag>.json` (10 plans).
- `Packages/PackFitSchemas`: Codable mirror plus `Fixtures.items()/containers()/trips()/plan(named:)/data(named:)`.
  `Resources/fixtures` is a symlink to `schemas/fixtures`. It is declared as `.process("Resources")` because `.copy` copies the
  dangling link. `.process` flattens the files into the bundle root, so `plan(named: "sfo-del-checked")` loads `plans/sfo-del-checked.json`.
- `Packages/Packer`: `pack`, `validatePlan`, `describeStep`, as in `Packages/Packer/CLAUDE.md`. Rules 1-10 are enforced. Each rule is
  one function in `Constraints.swift`, and the solver and `validatePlan` share them.
  Candidate positions are extreme points dropped under gravity. Up to 16 deterministic strategies run (flat-first or lowest-top,
  fragile late, heavy first, security last), preferring the rule-following ones. The first plan that places everything wins.
  Otherwise the winner places the most items, then has the most packed volume, then the lowest centre of mass.
- `GenPlans` executable writes the demo plans.
- Root `package.json` with `pnpm schemas:check`. It runs ajv over the fixtures, checks the fixture schema hasn't drifted from the
  base schemas, and checks coverage counts and plan/packlist consistency. Then it runs the Swift decode test, then the zod half if
  `services/api` defines `schemas:check`.
Cut: optional refine pass (deliverable 5), not started. Weight limit is not enforced by `pack` (the UI compares `stats.kg` with `weightLimitKg`).
Run:
- `pnpm install && pnpm schemas:check`
- `swift test --package-path Packages/PackFitSchemas`
- `swift test --package-path Packages/Packer` (about 30 s debug, mostly the 3,000 geometry trials)
- `swift run --package-path Packages/Packer GenPlans` regenerates `schemas/fixtures/plans/` (DeterminismTests fails if they are stale)
Measured (M-series Mac, Swift 6.1.2 CLT): 30 items in checked-75, best of 5: 31 ms release, 520-650 ms debug.
GeometryTests: 1,000 random trials x 3 fixture containers with 0 violations.
Demo plans: every item is placed in all 10. sfo-del-checked has 16 items, 67% fill, 8.5 kg.
Decisions other sections should know:
- Bag orientation: suitcases lie open on their back. `outer` [w, h, d] = carry-on [55, 23, 40] and checked [75, 30, 50]: y is the
  shell depth (up), and z = 0 is the wheel end (`wheelsSide: back`). The backpack stands up: [30, 48, 20], opening at max y.
  The viewer and AR overlay should render this frame as is.
- Compartment placements are in that compartment's own frame (origin at its inner bottom-left-back). Steps are ordered by the
  container's compartment order (backpack: main, then front, then laptop).
- `describeStep` takes an optional `container:` for exact regions. Without it, the compartment size is inferred from the plan.
  `validatePlan` takes optional `options:` (support %, security rule).
- When "security items last" would leave something unplaced, a fallback ordering places them earlier. The rule-8 constraint still
  holds (nothing on top unless they touch the opening).
- The laptop and the hard-case headphones are not fragile in the fixtures. With them fragile, a carry-on with a laptop and a
  document folder has no valid packing under rule 4.
Blocked on:
- **Fixture dims are not tape-measured.** Nobody has weighed or measured the physical items yet. Each item's `_source` and
  `measurement.method` say `catalog` (maker spec) or `estimate`. Whoever has the 25 physical items: measure them, update
  `items.json` (set `measurement.method` to `manual`), then run GenPlans and `pnpm schemas:check`. The same applies to the bag dims in `containers.json`.
- The JS `pack()` prototype from the outline is not in the repo. The solver was written from the rules in `Packages/Packer/CLAUDE.md`.
Schema changes: `Trip.id` (optional) added; see `docs/requests.md`.

## 2026-10-24 section-2 integrate PackFitSchemas + Packer
Built:
- Linked local SPM packages in `apps/ios/PackFit.xcodeproj` and `project.yml`:
  `../../Packages/PackFitSchemas`, `../../Packages/Packer`
- Deleted `PackFit/Temp/` (Types + Fixtures). App uses `@_exported import PackFitSchemas`
  via `App/SchemaExports.swift`
- `Fixtures/AppFixtures.swift` wraps throwing `PackFitSchemas.Fixtures` for UI + mock rule flags
- `PlanStore.computePlan` runs `Packer.pack` on a background task
- API DTOs (`ScanItemResponse`, etc.) stay in `API/APIModels.swift`
Cut: none for this integration
Run:
- Open `apps/ios/PackFit.xcodeproj` (or `xcodegen generate` from `apps/ios`)
- Scheme PackFit; mock API still default via `Config/Example.xcconfig`
Measured: not re-run on device in this change (Windows host)
Blocked on: Section 3 live API; device fps / LiDAR MAE as before
Schema changes: none

## 2026-10-24 section-2 guided LiDAR flow (branch `arjun99ab/lidar-ar`)
Built:
- **Guided flow is the main path on LiDAR iPhones.** After picking a trip, the app goes to
  `Route.guidedScan` (`PackFit/Guided/`):
  1. Scan the open suitcase on the floor. The app measures the inner cavity and keeps it anchored.
  2. Pan over the items spread on the floor. Every separate object gets a numbered box.
  3. Identify all items in parallel through `/scan/item`, with cropped photos and LiDAR dims.
  4. Review the list, then pack. The plan is drawn inside the real bag, with step and play controls.
  Non-LiDAR devices and the simulator keep the old path: presets, manual entry, item list, 3D viewer.
- **Depth pipeline** (`Scan/Measurement/`, pure and unit-tested):
  - `DepthSnapshot`: a Sendable copy of the frame's depth, with intrinsics scaled to the depth resolution.
  - `HeightMap`: a persistent 1 cm world grid, taking the median of the last 8 per-snapshot top heights.
  - `BoxFitter`: components, convex hull and minimum-area rectangle.
  - `CavityFitter`: a basin flood-fill from the reticle point, measuring rim minus cavity floor.
  - `FitStabilizer`: EMA smoothing; a fit is stable after 6 fits within tolerance.
  - `ScanWorker`: an actor that runs all of this off the main thread at 5 Hz.
- **Shared plan stepping:** `PlanStepper` drives both the 3D viewer and the AR overlay. It conforms to
  `PlanViewerControlling`, so the voice coach can drive either one. `PlanStepControls` is the shared UI.
- **Container from a scan:** `ContainerFactory.fromCavity` gives inner `[long, 2 × shell depth, short]`,
  outer = inner + 6, method `.lidar`, `wheelsSide .back`.
- **Fallbacks:**
  - If the cavity isn't stable after 8 s, the user taps the two inside back corners. The other
    sizes come from the trip's preset bag.
  - "Add one manually" opens the manual scan form; "Use bag presets instead" goes to bag setup.
  - Tapping a box drops a false positive.
- **Fixes:**
  - `Category` is now unambiguous.
  - Bundle ID per team: put `DEVELOPMENT_TEAM` in the gitignored `Config/Local.xcconfig`.
  - Test target: `TEST_HOST` and target dependency fixed.
  - The 3D viewer's bag volume was opaque and hid the items. It is translucent now.
  - The viewer uses the inner dims and the first compartment only.
  - Materials are cached per (category, opacity).
Retired: `LidarSessionController` and `ARScanRepresentable` (tap-corner item scan). `ScanView` is
the manual and non-LiDAR form only.
Cut: occlusion toggle; per-item 3D labels in the overlay (the name shows in the step panel).
Run:
- Open `apps/ios/PackFit.xcodeproj` and add `Config/Local.xcconfig` with `DEVELOPMENT_TEAM = <team>`.
- Run on an iPhone Pro.
- Unit tests:
  `xcodebuild -scheme PackFit -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`
Measured:
- 21/21 unit tests pass on the simulator. They cover synthetic boxes within ±1 cm and ±3°, cavity
  inner dims within ±1.5 cm, and the frame orthonormal with its origin at the back-left corner.
- Device build compiles.
- Simulator smoke test: trip → presets → manual item → pack → viewer works.
- **Not yet run on a LiDAR device.** Bag accuracy against a tape, item MAE, overlay alignment and
  end-to-end time are still to measure.
Known limits:
- Items must be spread about a hand apart; touching or stacked items merge into one box.
- The bag must not move between the scan and the overlay.
- The cavity assumes a 50/50 clamshell.
Blocked on: device time with an iPhone Pro and a real suitcase.

## 2026-10-24 section-2 AR tap-measure for phones without LiDAR (branch `arjun99ab/lidar-ar`)
Built:
- **The guided flow now runs on any ARKit iPhone** (`DeviceCapabilities.supportsAR`), not only on LiDAR models.
  - It uses ARKit world tracking (camera plus motion sensors, in metric units) and plane detection. There is no depth map.
  - Apple's coaching overlay guides the user until the floor is found.
- **Bag:** tap three inside corners of the open shell: back-left, back-right, then a front one.
  - Length and width are measured from the taps. Depth comes from the trip's preset bag.
  - The container is recorded as method `.manual` with confidence 0.7.
  - This 3-tap flow is also the LiDAR fallback now, replacing the 2-tap one.
- **Items:** tap two bottom corners along one side, a bottom corner on the opposite side, then the top edge facing you.
  - Height comes from a surface hit over the item when ARKit has one. Otherwise it's where the tap ray meets the item's front face.
  - Length, width and height steppers allow correction before "Add item".
  - LiDAR phones can switch to this with "Measure by tapping".
- **Labelling:** tap-measured items are sent and stored as `.manual`, with confidence 0.65–0.75, so the badge reads "Check the size".
  - The app keeps their IDs in `ItemsStore.tapMeasuredIDs` and shows "Measured with AR taps".
- **Overlay:** the plan inside the bag works the same on these phones, anchored to the tapped corners.
- **Code:** the geometry is pure and unit-tested in `Scan/Measurement/TapMeasure.swift`.
Run:
- Same as before; any ARKit iPhone opens "Scan & pack" after a trip is picked.
- The simulator still uses presets and manual entry.
Measured:
- 28/28 unit tests pass, 7 of them new for taps.
- Device build compiles.
- Simulator routing checked.
- **Not yet run on a device.** Tap accuracy (expected 1–3 cm on footprints; height is worse) still to measure.
Known limits:
- Bag depth is not measured without LiDAR.
- Plain, shiny or dark surfaces make ARKit's floor and the surface hits less reliable.
