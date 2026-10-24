# PackFit (Cal Hacks 13.0)

Scan items with LiDAR, get a 3D packing plan, and check travel rules with source links.
Target user: international students flying home under a 23 kg checked-bag limit.

**Guidance only — not legal or airline authority.** Every rule flag and before-you-go tip
includes a `sourceUrl` and `lastVerified`. Data older than 30 days is labeled stale in the UI.

## Demo spine

Trip setup → suggestions / before-you-go → LiDAR scan → rule flags → packer → 3D viewer.

## Run

### Backend

```bash
pnpm install
cp services/api/.env.example services/api/.env   # set APP_TOKEN; optional ANTHROPIC_API_KEY, APIFY_TOKEN
pnpm --filter api dev                            # http://localhost:8787
pnpm --filter api test
```

`MOCK_CLAUDE=1` (default when no Anthropic key) keeps the demo offline with deterministic stubs.

### iOS

Open `apps/ios/PackFit.xcodeproj`, scheme **PackFit**, iPhone Pro with LiDAR (or simulator with mock API).
`Config/Example.xcconfig` sets `MOCK_API=YES` by default.

## Sponsor tools

### Anthropic (Claude)

Used only on the server (`services/api`), never in the iOS binary.

| Where | What |
|---|---|
| `src/claude/prompts/scanItem.ts` + `services/scan.ts` | Object-detection style item ID from a photo; device dims attached for packing only |
| `src/claude/prompts/mapRules.ts` + `services/rules.ts` | Choose among retrieved TSA/airline/country candidates; write one-sentence flag text |
| `src/claude/prompts/askRule.ts` | Free-text “is this allowed?” answers grounded in candidate rules |
| `src/claude/prompts/suggestItems.ts` + `services/trip.ts` | Destination packing suggestions as strict JSON (`Suggestion`) |

Keys: `ANTHROPIC_API_KEY`, optional `ANTHROPIC_MODEL` / `ANTHROPIC_MODEL_FAST` in `services/api/.env`.

### Apify

Actors under `services/apify/` scrape and normalize travel rules. Downstream sync fills
`services/api/data/rules/{tsa,airline,country}.json`. The app and API always fall back to the
last good fixtures if a scrape fails.

| Actor | Path | Notes |
|---|---|---|
| TSA What Can I Bring | `services/apify/tsa-what-can-i-bring/` | README + INPUT_SCHEMA; schedule daily |
| Airline baggage | `services/apify/airline-baggage/` | Public-reusable README + INPUT_SCHEMA; `apify push` |
| Country customs | `services/apify/country-customs/` | Food/plants/meds-style restrictions |

Key: `APIFY_TOKEN` in `services/api/.env`. Sync: `pnpm --filter api sync:rules` (when configured).

### Open-Meteo

Proxied inside `POST /trip/suggest` (`services/trip.ts` → Open-Meteo forecast). No API key.
Failures return a plain-language weather warning and mild defaults so the demo never stalls.

## Layout

| Area | Path |
|---|---|
| Shared schemas / fixtures | `schemas/`, `Packages/PackFitSchemas` |
| Packer | `Packages/Packer` |
| iOS app | `apps/ios` |
| API | `services/api` |
| Apify actors | `services/apify` |

Full briefs: root `CLAUDE.md`, `docs/api.md`, `docs/contracts.md`.
