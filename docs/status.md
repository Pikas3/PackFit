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

## 2026-10-24 — Section 2 + 3: photo inventory (Claude object detection)
Built:
- `POST /scan/inventory` (services/api): one photo in, every distinct packable object out, each as an
  `Item` (`source: scan`, `measurement.method: estimate`, confidence capped 0.5) plus a rough
  normalized box. Prompt `src/claude/prompts/scanInventory.ts`, forced tool `report_inventory`,
  max 25 objects, 8192 max tokens. Catalog fallbacks for kg/dims as in `/scan/item`. Mock returns 4 items.
- iOS "Photo inventory" screen (`PackFit/Scan/Inventory/`): plain back camera (any iPhone, no LiDAR),
  take photo → frozen photo with numbered boxes → list with thumbnails cropped from the boxes,
  confidence badges, tick/untick, tap to edit (ItemDetailView), delete. "Scan more" takes another
  photo; names already seen in an earlier photo start unticked ("Seen in an earlier photo").
  "Add N items" appends to `ItemsStore` and returns to the item list.
- Entry: Items toolbar "Scan item" is now a menu (single-item scan / "Snap the pile"), plus a
  "Snap the pile" button on the empty item list. `Route.inventoryScan`.
- Badge for `estimate` now reads "Estimated from photo" (was "Scaled from credit card").
Cut:
- LiDAR refinement of inventory items (dims stay estimates; re-measure with the single-item scan).
- Live-key accuracy run: not measured. Claude's boxes are approximate; they are only used for UI.
Run:
- Backend: `pnpm --filter api test` (15 passing, mock Claude). iOS: `PackFitTests` 45 passing incl.
  `InventoryMergeTests`; device build clean. Simulator smoke test with MockAPIClient: trip → bag →
  Snap the pile → Take photo → 4 items → Add → item list.
Where Claude can be wrong: misses small or overlapping objects, counts a folded stack as one item,
names one object twice across photos (dedupe is by name only), and estimated sizes have no scale
reference, so packing from them is rough until the user edits or re-measures.
Blocked on: on-device test with a live key.

## 2026-10-24 — Section 2: photo inventory measured against a credit card
Built:
- The inventory photo must include a credit card (ISO/IEC 7810 ID-1, 85.60 × 53.98 mm). On device:
  1. `VNDetectRectanglesRequest` finds rectangle candidates. `PlanePose.fromCard`
     (`Scan/Measurement/CardScale.swift`) fits each one to an ID-1 card through the camera
     (homography + intrinsics from the lens field of view), recovering the floor's pose. Quads
     that do not fit a real card (error > 0.2) are rejected; Claude's card box breaks ties.
  2. `VNGenerateForegroundInstanceMaskRequest` outlines objects; each Claude box picks the
     instance under it, cut to the box so touching objects split, card pixels removed.
  3. `SilhouetteFit` finds the floor-standing box (centre, yaw, w, d, h) whose projection best
     overlaps the outline (Nelder-Mead on soft IoU, smallest box among equal fits).
- Items get `measurement.method = reference` and confidence 0.35-0.85 (lower for poor overlap,
  small card, straight-down or near-level views, cut-off objects, no segmentation outline).
  Straight-down photos keep Claude's heights and say so.
- Camera: live card outline (green) and "Card found" before the shot; the card is drawn on the
  frozen photo. No card → "No credit card found" with Try again or Use rough estimates.
- Server: `/scan/inventory` takes `reference: "credit_card"`, keeps the card out of the list and
  returns its box.
Measured: synthetic tests only (`CardScaleTests`): floor distances exact; 30×20×12 box within
10%; 7×7×24 bottle → 8.6×7.9×23.4. Not yet measured on real photos.
Limits: objects must rest on the same flat surface as the card; one view cannot see the back of
an object (smallest consistent box is used); soft or irregular things are boxed.
Run: iOS `PackFitTests` 53 passing; backend 16 passing; device build clean.

## 2026-10-24 — Section 2 + 3: card measurement follows Vision's outlines, cylinders for cans and bottles
Why: on a real photo, Claude's boxes were offset or clipped (can box beside the can, bottle box
over half the bottle). Masks were cut to those boxes, so the can measured 40.6×103.5×6.9 cm and
the bottle was not measured at all.
Built:
- Vision's segmented outlines are now the objects; Claude only names them. Each detection takes
  the outline its box overlaps best (or a nearby one if it misses), greedy and deterministic
  (`CardMeasurer.match`). Outlines are cut by Claude's boxes only when two detections share one
  (touching objects), and that lowers confidence. No outline means no measurement: the item
  keeps Claude's estimate rather than fitting a rectangle.
- `SilhouetteFit` fits a box, a standing cylinder or a lying cylinder. `/scan/inventory`
  detections carry `shape` (Claude picks: cans, bottles, jars are cylinders); null fits a box.
- The photo shows each measured solid's outline, traced over the object; boxes and thumbnails
  use the segmented outline's bounds, not Claude's box.
Measured (synthetic, `CardScaleTests`): can 6.6×12.2 → 6.6×6.6×12.2; bottle 7×24 → 7.0×7.0×23.9;
lying bottle 24×7 → 23.9×7.0×7.0. The same outlines fitted as boxes were off by up to 70%
(can 11.2 cm wide).
Limits: if Vision's foreground segmentation misses an object (e.g. low contrast against the
floor) it is not measured; touching objects that segment as one still depend on Claude's boxes.
Run: iOS `PackFitTests` all passing; backend 16 passing; device build clean.

## 2026-10-24 — Section 2 + 3: sharper card corners, re-segmenting missed objects, scan replay
Why: on device (13:25 and 13:28 photos) the fitted cylinders sat beside the objects and came out
too big (sparkling-water can 8.2 × 11.8 cm), Claude's boxes were consistently left of the
objects, and the sunglasses were found alone but not alongside the bottle and can.
Built:
- `CardEdges` (`Scan/Measurement/CardEdges.swift`): refines the card's corners from its four
  straight edges on the full-resolution photo (wide search, then a tight one; steps against the
  edge's brightness direction are dropped). Synthetic: Vision's corners were 10-15 px off; 3 px
  of corner error tilts the floor about 13 degrees; refined corners are within 0.3 px, tilt
  about 1 degree. A badly placed card used to give wrong shapes and sizes everywhere.
- Objects the whole-photo segmentation leaves out are re-segmented in a crop around Claude's
  box, skipping outlines already taken.
- `/scan/inventory` tells Claude the photo's pixel size and asks for pixel corners
  (x0, y0, x1, y1); the server normalizes. The response shape is unchanged.
- Debug builds save every inventory photo (original JPEG with EXIF) plus `scan.json` (Claude's
  answer, intrinsics, EXIF 35 mm focal length, card corners, measurements) to Documents/Scans,
  visible in Files › On My iPhone › PackFit. A Mac replay tool reruns `CardMeasurer` on a saved
  scan and draws the result.
Measured: synthetic end-to-end scene (Vision on the Mac, Claude boxes shifted 6% left and
clipped): can 5.8 × 15.7 → 5.8 × 15.7, bottle 7.5 × 25 → 7.6 × 25.0, sunglasses 14 × 5 × 4 →
14.1 × 5.1 × 3.9. Real photos not yet re-measured.
Run: iOS `PackFitTests`; backend 17 passing; device build clean.
## 2026-10-24 trip/rules/suggestions wiring (branch objectdetection)
Built:
- **F1 Trip setup:** `TripPickerView` activities multi-select, airport autocomplete (`AirportCatalog`),
  bag choice, validation; weather + warnings via `TripStore.loadSuggestions` ? `POST /trip/suggest`
- **F2 Apify:** airline-baggage public README + INPUT_SCHEMA; fixtures in `data/rules/*` remain the
  offline cache; stale labeling unchanged
- **F3 Flags:** item list badges + pack advice (`PackAdvice`); low-confidence confirm sheet;
  flags refresh when the list changes; banned items skipped at pack time; Rules sheet + disclaimer
- **F4 Suggestions:** `SuggestionsView` grouped by category, essentials, one-tap accept ? `Item`
  with `measurement.method = estimate`; subtracts already-scanned names
- **F5 Before you go:** `BeforeYouGoView` from `beforeYouGo` panel + country flags + overweight warning
- **F6:** Routes wired; README sponsor sections; API tests for Suggestion JSON (`suggestions.test.ts`)
- Backend: `/trip/suggest` now returns `Suggestion[]` + `beforeYouGo` + `destinationCountry`
  (additive; see `docs/requests.md`)
Cut:
- Live Apify publish (`apify push` still needs token)
- Separate `/trip/forecast` route (weather stays inside suggest)
- Changing `Trip.airline` to optional in JSON Schema
Run:
- `pnpm --filter api test` (15 passing)
- iOS: open `apps/ios/PackFit.xcodeproj`, mock API default
Measured: API unit tests green on Windows host
Blocked on: device build; live Anthropic/Apify keys for non-mock demo
Schema changes: none to `schemas/*.schema.json`; additive API DTOs only

## 2026-10-24 trip lookup by flight number
Built:
- Replaced sample-trip list with airline + flight number lookup (POST /trip/lookup)
- Weather / suggestions / before-you-go load only after the user confirms the found flight
- Route notices: TSA when US involved; destination-country customs when international
- Demo fixtures offline; optional `AVIATIONSTACK_API_KEY` for live lookup
Run: enter UA / 88 ? Use this flight ? weather for DEL + rules appear
Cut: browsing a dropdown of all sample trips as the primary path

## 2026-10-24 — Section 3: live flight lookup through Apify; weather for any trip date
Flight lookup (`/trip/lookup`):
- Tested four Apify flight-status actors on UA 901, BA 178, EK 202, AI 173 and 6E 1.
  `apt_marble/flight-status-tracker` won: right routes for every flight that operates now
  (as did travelcode and parseforge), 4-7 s per run, $0.003 per flight, airport names and
  countries included, 97 runs in 30 days with none failed. `moving_beacon-owner1/flightaware-flight-scraper`
  found nothing. None of them know flights months ahead, so the route comes from the flight
  operating now or next and the user's date is kept.
- Order: demo fixtures, then the in-memory route cache (7 days; misses 1 hour), then Apify,
  then AviationStack if configured. Not found is a 404 with a reason; a failing service a 502.
  Measured on the dev server: first UA 901 lookup 4.6 s, cached 2 ms.
- The app shows the server's message and no longer substitutes SFO→DEL for unknown flights.
Weather (`/trip/suggest`): Open-Meteo's forecast reaches 16 days; trips used to ask for the
whole stay and always fell back to a default. Now the forecast is cut where it ends, and
later trips get last year's weather on the same dates from the archive.
Run: backend 25 tests passing (no test calls Apify; live keys are cleared per test).
- Follow-up: the lookup now follows the trip date. The actor's history (about ten days back,
  two days ahead) gives that day's own flight when covered; later dates take the route flown
  on the same weekday most recently and return `routeNote` (shown in the app) saying it is
  inferred. One history run per flight number serves every date for 12 hours.

## 2026-10-24 — Section 2 (with Packer changes): why items don't fit, better packing, 3D shapes
Packer (`Packages/Packer`, see the request to Section 1):
- An upright item too tall to stand in the bag now lies down (step note: "too tall to
  stand, close it tightly and lay it flat") instead of going unplaced. A 27 cm-tall checked
  bag rejected any upright bottle scanned over 27 cm.
- Light soft items (≤ 1 kg) may go above fragile ones; rigid or heavier items still may not.
- Two more item orderings (largest volume, longest side) are tried after the 16 existing
  strategies when something is still left out.
- `explainUnplaced` gives each left-out item a reason: too large for the bag, only room is
  above a fragile item, no room left, or invalid size.
- Tests: 33 passing (3 new). Bench (30 items, checked, debug): 825 ms best of 5, was 717 ms;
  budget 1,000 ms. Demo plans unchanged.
Viewer:
- The suitcase lid plane lay vertically through the bag (a flat plane rotated again); now it
  caps the top.
- "Didn't fit" lists each item with its size and reason; tap opens it for editing. The
  current step shows the packer's notes (keep upright, fragile, lay flat, press down).
- Items are drawn as built-in models in one flat style (`Viewer/ItemModels.swift`), picked by
  name then category: bottle, can/jar/mug, tube, laptop, phone/tablet, book/documents,
  folded clothing, shoes, zip pouch, first-aid kit, headphones, camera, glasses, plain box.
  The photo scan's cylinder shape forces a round model. Models turn with the item when the
  packer lays it on its side. No photo textures. Past items are solid in the viewer (85%
  opacity let model parts show through each other); the AR overlay keeps 60%.
- The current item has a name tag above the bag that faces the camera.
- Fragile outlines were offset by half the item (drawn from a corner, not the centre) and
  their lines stretched with the item; now centred with a constant 4 mm line.
- The lid plane sat exactly on the bag volume's top face and flickered while orbiting; it is
  now 2 mm above it, drawn after it in one sort group, and lighter (15% instead of 35%).
- Debug builds launched with `-previewPlan` open the 3D plan with the fixture items in the
  checked bag.
Not measured yet: viewer fps with the multi-part models on device.

## Section 2: UI redesign to the PackFit-Cute Figma (uncommitted)

Figma: https://www.figma.com/design/90r9EPWzi2CDYln8Nwy4m5/PackFit-Cute

- **Built:**
  - **Tokens:** `Theme/Tokens.swift` holds the Figma palette (pink, green, alert colors) with dark variants. Its text styles map onto Dynamic Type using SF Rounded. Fredoka and Nunito are not bundled.
  - **Components:** `Components/PackFitKit.swift` has the shared building blocks:
    - Primary button, chips, section header and stat tile
    - Itinerary field, tip row, nav title and icon bubble
    - Flag card, checklist row, flow layout and blob background
  - **Tab bar:** a system `TabView` with Home, Results and Plan, each with its own NavigationStack. `AppNavigator` switches tabs after packing.
  - **Home** (`Trip/DashboardView.swift`) replaces the trip picker:
    - Next-trip card, then item and bag tiles.
    - Itinerary card, which opens the restyled flight lookup sheet (`TripPickerView`).
    - Season chips, the forecast and Optimize. `PackRun` checks the rules, drops banned items and packs the rest.
  - **Results** (`Viewer/PlanViewerView.swift`):
    - 3D card with 3D, Top and Side camera presets and a layer filter (the peel).
    - Step controls, stats, flag cards (rule flags plus route notices, filterable, with source links and stale labels) and the didn't-fit chips.
  - **Plan** (`Viewer/PackingPlanView.swift`): `describeStep` output as a checklist by layer, with progress and share. The ticks live in `PlanStore.packedSteps`.
  - **Restyled:** Rules (flag cards), bag setup, item list, onboarding and the empty state. Other screens get the canvas background.
- **Cut:** the Figma Profile tab, since there is no profile feature.
- **How to run:** debug builds take `-previewPlan` plus `-previewTab home|plan` to open a tab with the fixture trip.
- **Verified:** simulator tests pass, the device build is clean, and light and dark screenshots were checked. Not yet checked on device.

## 2026-10-25 section-2 tap-to-focus credit card (inventory)
Built:
- Tap on the inventory camera preview autofocuses/exposes at that point and searches for an
  ID-1 card in a box around the tap (`InventoryCamera.focusOnCard`).
- Live detection uses a Vision ROI + looser thresholds while searching, and
  `PlanePose.bestCard(..., requireHint: true)` so only a card in that region locks.
- Dashed search box + reticle; copy prompts to tap if the card is hard to lock.
- Still measurement falls back to the live/tap hint when Claude did not mark the card.
Cut: none.
Run: photo inventory on device — tap the card when the green outline will not lock.
Measured: not yet (needs Pro / packing-floor try).
Blocked on: device check of 90° POI mapping and ROI lock rate.
Schema changes: none.
