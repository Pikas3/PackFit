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
