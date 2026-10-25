# Section 3: Backend (Claude vision, rules engine, Apify scrapers, trip suggestions)

You own `services/api` (except `src/routes/voice.ts`, Section 4) and `services/apify`.
Workstreams WS3 (server side), WS5, WS6. Read the root `CLAUDE.md`, `docs/contracts.md`,
`docs/api.md`. The endpoint shapes in `docs/api.md` are the contract with Section 2; do not
change them without an entry in `docs/requests.md`.

You cover two sponsor tracks on your own: Anthropic (vision, attribute estimation, rule
summaries with sources) and Apify (scrapers feed the rules engine, publish one actor).
Section 4 writes the track READMEs from your `docs/status.md` notes, so write them well.

## Stack

- Node 24, TypeScript strict, Hono. `pnpm --filter api dev` runs on port 8787 with
  `tsx watch`.
- `@anthropic-ai/sdk`. Default model: the current Claude Sonnet for vision and mapping;
  swap to Haiku for `/rules/ask` if latency matters. Model id in `.env`, never hardcoded.
- `apify-client` for reading datasets; the `apify` SDK plus `crawlee` inside the actors.
- zod in `src/schemas.ts`, mirroring `schemas/*.schema.json` exactly (see
  `docs/contracts.md`). You own keeping this mirror current. `test/schemas.test.ts` validates
  every file in `schemas/fixtures/` with both the zod schemas and the JSON Schema (via
  `ajv`); this is the TypeScript half of `pnpm schemas:check`. When Section 1 changes a
  schema, update the mirror the same day.
- Weather: Open-Meteo, no key. Airport coordinates from a static `data/airports.json`
  (IATA code to lat/lon, top 300 airports).
- `.env.example`: `ANTHROPIC_API_KEY=`, `ANTHROPIC_MODEL=`, `APIFY_TOKEN=`, `APP_TOKEN=`,
  `PORT=8787`. Never commit `.env`.

## Layout

```
services/api/
  src/
    index.ts            Hono app, auth middleware, error handler, request id, timing
    schemas.ts          zod mirror of schemas/*.schema.json
    routes/
      health.ts
      scan.ts           POST /scan/item
      rules.ts          POST /rules/check, POST /rules/ask
      trip.ts           POST /trip/suggest
      voice.ts          (Section 4)
    claude/
      client.ts         wrapper: timeout, one repair retry, zod parse, token logging
      prompts/
        scanItem.ts
        mapRules.ts
        askRule.ts
        suggestItems.ts
    rules/
      store.ts          loads data/rules/*.json, indexes by scope and keyword
      sync.ts           pulls latest Apify dataset runs into data/rules, keeps last-good
      stale.ts          30-day check
    data/
      catalog.json      category -> typical dims, kg, hardness, soft, fragile defaults
      airports.json
      rules/            normalized RuleFlag source records (committed; demo fallback)
  test/
services/apify/
  tsa-what-can-i-bring/    actor 1, the one we publish
  airline-baggage/         actor 2
  country-customs/         actor 3
  shared/normalize.ts      raw -> RuleRecord
```

## WS3 server: `POST /scan/item`

The iOS app no longer calls this route; it uses `POST /scan/inventory` (one photo of the
pile, credit card for scale) and measures `w/h/d` on-device. When a caller attaches
`measured` dims, they are for packing only.
The model's job is object detection from the photo: name, category, kg, fragile, soft,
hardness, upright. Two prompt variants in `scanItem.ts`, chosen by whether `measured`
is present:

- **Measured (object-detection) variant.** System: act as an object-detection model; identify
  the single travel item from visual appearance alone. Do not use size or scale for naming.
  Measured `w/h/d` are withheld from the prompt and copied onto the Item by the server for
  the packer. Tool schema omits `w/h/d`. Output only via the tool schema.
- **Estimate variant.** Same visual identification, but dims are also requested and the
  reference object (if any) is described for scale. Server sets `measurement.method =
  'estimate'` and caps confidence per `docs/api.md`.
- Both: include the JSON schema from zod (`zodToJsonSchema`) and use tool-use so the model
  returns structured output. Pass `hint` when present. Ask for 2-3 `alternatives`.
- Post-process: kg clamped to 0.01-30, replaced from `catalog.json` by category when
  missing or out of range. Estimated dims outside 0.5-200 cm are replaced from the catalog
  with warning `"dims_from_catalog"`. Measured dims are never touched. Set `id`,
  `source: 'scan'`.
- Malformed output: one retry with the validation error appended ("Your previous output
  failed: ..."). Then `422 model_output_invalid`. Log both attempts' token counts.
- Test with photos of the 25 fixture items (Section 1 measured them; you photograph them,
  `test/photos/`, under 300 KB each) in both variants. Record identification hit rate for
  both, and dimension error for the estimate variant, in `docs/status.md`. Target: 20 of 25
  identified; estimate-variant dims within ~15% with a reference card.

## WS5: rules engine and Apify actors

### Rule records

Normalized record stored in `data/rules/<scope>.json`:

```ts
interface RuleRecord {
  ruleId: string;          // stable slug, e.g. 'tsa:lithium-battery-spare'
  scope: 'tsa' | 'airline' | 'country';
  subject: string;         // 'UA' for airline, 'IN' for country, 'all' for tsa
  keywords: string[];      // lowercase match terms
  categories: Category[];  // from src/schemas.ts
  severity: 'banned' | 'restricted' | 'check';
  carryOn: 'ok' | 'restricted' | 'banned';
  checked: 'ok' | 'restricted' | 'banned';
  text: string;            // original rule wording, trimmed
  sourceUrl: string;
  lastVerified: string;    // ISO date of the scrape
  limits?: { maxCm?: [number, number, number]; maxKg?: number; maxWh?: number; maxMl?: number };
}
```

### Actors (`services/apify/`)

1. `tsa-what-can-i-bring`: crawls tsa.gov "What Can I Bring?" item pages. Output one
   record per item with carry-on and checked verdicts and the item page URL. This is the
   actor we publish publicly for the Best Actor award, so it needs a clean `README.md`,
   `INPUT_SCHEMA.json`, actor description, and an example output. Keep it generic: no
   Snugly-specific fields in the published dataset, we normalize on our side.
2. `airline-baggage`: input `{ airlines: ['UA', 'AI', 'EK', ...] }`, scrapes each carrier's
   baggage policy page for cabin and checked dims and weight. Start with 5 airlines that
   matter for the target user (UA, AA, AI, EK, QR). Hardcode the policy URL per airline in
   the input defaults; a general crawler is out of scope.
3. `country-customs`: input `{ countries: ['IN', 'CN', 'KR', ...] }`, scrapes the official
   customs "prohibited and restricted items" page for 5 destination countries. Same
   approach: URL per country, no discovery.

Each actor has a `.actor/actor.json`, runs on a daily schedule, and writes to a named
dataset. `sync.ts` pulls the latest successful run per actor, normalizes with
`shared/normalize.ts`, and writes `data/rules/*.json`. If a pull fails, the previous file is
kept and `/health` reports the old `rulesLastSynced`. Commit a good snapshot of
`data/rules/` so the demo works without Apify.

### `POST /rules/check`

1. For each item, candidate records: keyword match on `name` plus `categories` match plus
   scope filter (`tsa` always; `airline` where `subject === trip.airline`; `country` where
   `subject === destination country` from `airports.json`). Cap at 8 candidates per item.
2. Items with zero candidates get no flag. Do not call Claude for them.
3. One Claude call per request with all items and their candidates. Tool-use schema:
   `{ flags: [{ itemId, ruleId, severity, text }] }`. The model picks which candidates apply
   given the bag (carry-on vs checked) and `limits`, and writes one or two plain sentences.
4. Server fills `scope`, `sourceUrl`, `lastVerified` from the record by `ruleId`. If the
   model returns a `ruleId` not in the candidates, drop that flag and log it.
5. `summary`: a second short call, or template it from the flags. No new claims.
6. `stale`: any flag older than 30 days.

### `POST /rules/ask`

Same candidate search on the question text, then one call producing `{ answer, ruleIds }`.
The answer must reference a returned rule or state no matching rule was found. This feeds
the voice coach; keep answers under 40 words.

## WS6: `POST /trip/suggest`

1. Weather: Open-Meteo daily forecast for the destination for `departDate` through
   `departDate + nights` (if `departDate` is missing, use climate normals for the month or
   skip weather and say so in `warnings`).
2. Claude call with trip, weather, and activities; tool-use schema returns a list of
   `{ name, category, qty }`. Expand with `catalog.json` to full `Item`s with
   `source: 'suggested'`, `confidence: 1`.
3. Overweight warning: sum suggested `kg` and compare with `trip.checked.weightLimitKg`.
4. Souvenir space: reserve `max(5, nights) ` litres when the trip is international; return as
   a warning the packer UI can show.
5. Test against the three sample trips from `fixtures/trips.json` and snapshot the results
   under `test/snapshots/`.

## Acceptance

- Every `RuleFlag` has a real `sourceUrl` and a `lastVerified` date; stale is computed.
- 20 of 25 fixture items identified, dims within ~15%; malformed output returns 422 rather
  than crashing.
- Suggestions for 3 sample trips, each a valid `Item[]`.
- One actor published publicly on Apify with README and example output.
- `pnpm --filter api test` green; `.env.example` complete; no key in git history.

## Conventions

- Every route: parse input with zod, call a service function, validate output with zod,
  return. Routes contain no business logic.
- Every Claude call goes through `claude/client.ts`. It logs model, tokens in and out,
  latency, and whether the repair retry fired. No prompt text or image data in logs.
- Prompts are TypeScript functions returning `{ system, messages, tools }`, with a unit test
  asserting the schema is included.
- Never let the model supply a URL. URLs come from records only.

## Mocking while you wait

- Before `schemas/*.schema.json` lands: write `src/schemas.ts` from `docs/contracts.md`
  directly; reconcile against the JSON Schema when it merges.
- Before fixture photos exist: use 5 photos of your own items to develop the prompt.
- Before Apify actors run: hand-write 15 `RuleRecord`s in `data/rules/` from the TSA site
  (power bank, full-size liquids, pocket knife, lighter, aerosols, and the two items in the
  fixture set that should flag). The demo depends on these existing regardless.

## Report format

Append to `docs/status.md`: endpoints live, scan hit rate and dimension error, actors
published (with URLs), how to run (`pnpm --filter api dev`, env vars needed), latencies per
endpoint, and a paragraph each on where Claude can be wrong for scan and for rules. Section 4
turns those into the safe-by-default notes.
