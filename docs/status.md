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

## 2026-10-24 section-2 one-tap LiDAR measuring (branch `arjun99ab/lidar-ar`)
Built:
- **Bag in one tap:** tap the bottom of the open shell. `CavityFitter` raises a water level from the
  tap until it spills over the walls, takes the basin at half that level (so handle channels and seams
  on the floor stay inside), then pushes each side out to its wall across floor hidden behind the near rim.
- **Items in one tap each:** tap an item; its box goes yellow, refines over ~1 s, then turns green and numbered.
  - Vision's foreground instance mask (`Segmenter`) picks the object under the tap in the camera image.
  - Only LiDAR points inside that mask, shrunk 2 depth pixels from the outline, build the box (`ObjectCloud`).
  - The ground is the median of a ring of points just outside the mask, so boxes sit on the real
    surface (floor or table) instead of ARKit's floor plane.
  - No mask under the tap: `SeedFitter` grows the object from the tapped cell in the height map,
    with a cut halfway up the object, measured from the surrounding surface.
  - Tap a boxed item again to re-measure it; the × on its chip removes it.
- **Depth fixes behind the "box floats above the item" bug:**
  - Raw `sceneDepth` instead of temporally smoothed depth.
  - Pixels on depth discontinuities are dropped. They used to smear each item back and up, away from the camera.
- The automatic sweep is no longer used in the flow (`BoxFitter` stays, with its tests).
  Corner taps stay available ("Measure by corners instead") and remain the only path without LiDAR.
Run: same as before. Tests: `xcodebuild -scheme PackFit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Measured:
- 41/41 unit tests pass (13 new).
- Synthetic results:
  - A 30×20×10 box on a table: within ±1 cm footprint and ±6 mm height, with mask spill onto the table.
  - A 6 mm passport: within ±1 cm footprint and ±4 mm height.
  - A 1.2 cm item with the floor plane 8 mm wrong: found, height within ±4 mm.
  - Cavity with 3 cm handle ridges, or with an 8 cm strip hidden behind the near wall: within ±1.5 cm.
- Device build compiles.
- **Not yet run on a device.** Item MAE against a tape is still to measure.
Known limits:
- Vision may group touching items into one instance. Leave a small gap between items.
- Segmentation runs only while an item is measuring, at about 50 ms per frame.

## 2026-10-24 section-3 backend API + Apify scaffold
Built:
- `services/api` Hono app on port 8787: `GET /health`, `POST /scan/item`, `POST /rules/check`,
  `POST /rules/ask`, `POST /trip/suggest`; voice routes stubbed 501 for Section 4
- `src/schemas.ts` zod mirror of `schemas/*.schema.json`; `test/schemas.test.ts` is the TS half of
  `pnpm schemas:check`
- Claude wrapper `src/claude/client.ts` (20s timeout, one repair retry, token/latency logs, no
  prompt/image logging). `MOCK_CLAUDE=1` (default when no `ANTHROPIC_API_KEY`) uses deterministic stubs
- Hand-written demo rules in `data/rules/{tsa,airline,country}.json` (18 records) with real sourceUrls
- Catalog + airports (`data/catalog.json`, `data/airports.json`); Open-Meteo weather for suggestions
- Apify actors under `services/apify/`: `tsa-what-can-i-bring` (publishable README + INPUT_SCHEMA),
  `airline-baggage`, `country-customs`, plus `shared/normalize.ts` / api `sync:rules`
Cut:
- Live 25-photo scan accuracy run (no fixture photos in repo yet)
- Public Apify publish URL (actor code ready; needs `apify push` with token)
- Full 300-airport list (≈80 major + demo destinations)
Run:
- `pnpm install`
- Copy `services/api/.env.example` → `services/api/.env` (set `APP_TOKEN`, optional keys)
- `pnpm --filter api dev` → http://localhost:8787
- `pnpm --filter api test` (12 passing with mock Claude)
- Header on every non-health route: `x-packfit-token: <APP_TOKEN>`
Measured:
- Mock-mode route tests green; trip/suggest ~0.6s/trip including Open-Meteo when reachable
- Scan identification hit rate / dim MAE: not measured (needs photos + live key)
Where Claude can be wrong:
- Scan: mis-IDs similar gadgets, may mark measured dims implausible incorrectly, weight estimates drift;
  catalog fallbacks hide bad kg/dims but can disagree with the photo.
- Rules: may drop a real candidate or over-flag when keywords are broad; server always overwrites
  sourceUrl/lastVerified from records so invented URLs cannot ship.
Blocked on: fixture photos for scan eval; Apify tokens to publish/schedule actors
Schema changes: none

## 2026-10-24 sections 1-3: one-tap measuring without LiDAR, robust packing, offline identification (branch `ws/scan-robust`)
Built:
- **Measuring without depth** (`apps/ios/PackFit/Scan/Measurement/`). Pure geometry, unit-tested:
  - `SilhouetteHull.swift`:
    - `VoxelHull` carves a 1 cm × 5 mm grid on the floor with Vision's outline of the tapped object from each camera pose (ARKit world tracking is metric on every iPhone).
    - A voxel dies only when at least 2 views, and at least 25% of the views that saw it, put it outside, so a few bad masks don't cut the object.
    - The hull isolates the object from neighbours and gives the first box.
  - `BoxSilhouetteFit.swift` refines centre, yaw, long, short and height by coordinate descent so that the box's projected outline matches every view. Two things make this necessary:
    - Hull height is unreliable: the hull's roof rises toward the cameras when nobody looks from the far side or from low down.
    - The hull keeps a "shadow" behind the object that elevated views can't see past.

    The score is a trimmed mean IoU, with the worst fifth of views dropped.
  - `HullCoverage`: the views must include at least 90° of azimuth, one view from above (elevation 70° or more, bounds the far side) and one low view (40° or less, bounds the height). Until then the hint says "hold above", "lower the phone" or "walk around", and confidence is capped at 0.6.
  - `ShellSplitter`: an open clamshell becomes base plus lid. It splits at the hinge valley if one shows, otherwise at the middle of the long axis, and the two boxes are refined together.
  - `HullWorker` (actor) runs at 5 Hz:
    - segments each frame;
    - tracks the target by the instance under its current box;
    - keeps up to 20 views at least 6° apart;
    - locks when coverage is complete and 3 fits agree within 8 mm (15 mm for bags), or after 12 s.
- **Guided flow on phones without LiDAR** (`Guided/`):
  - One tap per item, then move around it. Corner taps remain a fallback.
  - Bag: pick Hard shell, Soft / zip lid, or Backpack (goes to the presets), then tap inside the bottom half of the open suitcase.
  - `ContainerFactory.fromShells` turns the measured outer shells into inner dims. It subtracts per-kind allowances (hard shell: 6 / 2 / 1 cm for wheels and handle, sides, shell wall; soft: 6 / 3 / 1.5) plus a 1 cm camera margin per axis.
  - The scanned bag takes the trip's weight limit for that bag.
  - After packing, non-LiDAR phones open the 3D viewer, not the AR overlay.
- **New measurement method `ar`** (camera plus ARKit pose, no depth) in `item.schema.json`, PackFitSchemas, zod and `/scan/item`. Badge: "Measured with the camera".
- **Packer** (`Packages/Packer`, rules 4, 8, 11 and 12 in its CLAUDE.md):
  - Uncertainty gap: rigid items measured by `lidar`, `ar`, `reference` or `estimate` get up to 1.5 cm more width and depth, scaled by confidence. Height is never padded. An item that fits nowhere padded is placed unpadded.
  - `planWarnings`: over weight, within 10% of the limit, didn't fit. Shown in the viewer, with the names of items that didn't fit. The packer never refuses a plan over weight.
  - Rule 8 opening is max y for suitcases too: they're packed lying open on their back, so the lid closes over the top.
  - Rule 4 only protects crushable items: not soft, hardness under 0.5. The old rule made a laptop on a jumper or a folder invalid, which left the laptop unplaced in a mostly empty carry-on.
  - Faster candidate generation: no tuple keys and no per-item arrays.
  - `BenchTests` times thread CPU, not wall clock.
  - Demo plans regenerated.
- **Identification:**
  - Claude through the backend first. `FallbackAPIClient` falls back to `OnDeviceAPIClient` on any error, after a 15 s request timeout.
  - `OnDeviceAPIClient`: Vision `VNClassifyImageRequest` labels are matched on whole words against `Resources/travel_catalog.json` (58 typical travel items). The measured size breaks ties between look-alikes.
  - `MOCK_API=YES` on a phone now means on-device identification. The simulator keeps the fixtures.
  - `/scan/item`: when a camera size has confidence under 0.7, Claude also estimates the size. More than 30% apart on any sorted side gives `dims_disagree`, and the app lowers the size confidence to 0.6 ("Check the size") but keeps the measured size (rule 6).
- **Rules before packing:**
  - The guided review has a Carry-on / Checked picker and checks the whole list once.
  - Flags appear under each item with scope, text, source link and "verified N days ago".
  - A banned item needs Remove or Keep anyway before Pack is enabled.
  - Offline, `LocalRules` uses a bundled copy of the backend's rule records and requires a keyword match. A category alone would flag every electronics item as a spare battery. Refresh the copy with `apps/ios/scripts/sync-rules.sh`.
- **Review:** the guided review uses `ReviewCardView`, so every field is editable:
  - Picking an alternative or typing a name refills weight and handling from the catalog.
  - A corrected size is recorded as `manual`, at confidence 1, and gets no gap.
Cut:
- The AR overlay on non-LiDAR phones: the 3D viewer instead.
- A background-removed second image for Claude.
- Automatic detection of which end the wheels are on.
Run:
- `xcodebuild -scheme PackFit -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
- `swift test --package-path Packages/Packer`
- `swift run --package-path Packages/Packer GenPlans`
- `pnpm --filter api test`
- `pnpm schemas:check`
- On a phone, `MOCK_API=YES` identifies items on the device. Set `MOCK_API=NO` and `API_BASE_URL` to use Claude.
Measured (Mac, simulator, synthetic outlines rendered from known poses; not yet on a phone):
- Hull plus box fit, 12 views over 150°, mixed elevations:
  - 30×20×10 box: within ±1.5 cm on the footprint and ±2 cm in height.
  - 25 cm bottle: height within ±2 cm.
  - Passport: footprint within ±1.5 cm, height 2 cm or less.
  - Two of 12 masks blank: still within tolerance.
  - Open clamshell 70×45 with a 14 cm base and a 9 cm lid: base within ±3 cm, depths within ±2.5 cm.
- Views from above only: confidence 0.6 or less.
- iOS: 59 test cases pass (18 new).
- Packer: 37 tests pass (7 new), including 600 random padded trials.
- Bench, 30 items: release 25.9 ms (was 31.6). Debug 763 ms alone, about 830–930 ms with the other suites running in parallel.
- All 10 demo plans place every item.
- API: 14 of 14 tests pass. `tsc` shows the same 17 errors as before, none in changed files.
Known limits:
- Concave items come out as their bounding box.
- Touching items can merge in Vision's mask, so leave a hand's gap between them.
- Glossy, black or very thin items segment worse.
- Accuracy depends on ARKit's floor plane, so use a matte, textured floor.
Blocked on:
- Time on an iPhone 17 (no LiDAR) to measure item and bag error against a tape, scan time per item, and frame rate while segmenting.
- **Open:** which end of the bag the wheels are on. Rule 7 biases heavy items toward low z, but in the lying-open frame the wheel end is a short end (an x end).
Schema changes: `measurement.method` adds `ar` (additive). See `docs/requests.md`.
