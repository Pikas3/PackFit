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
