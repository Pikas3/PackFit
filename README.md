# Snugly (Cal Hacks 13.0)

Snap one photo of your pile, get a 3D packing plan, and check travel rules with source links.
Target user: international students flying home under a 23 kg checked-bag limit.

**Guidance only — not legal or airline authority.** Every rule flag and before-you-go tip
includes a `sourceUrl` and `lastVerified`. Data older than 30 days is labeled stale in the UI.

## Demo spine

Flight lookup → weather, suggestions and before-you-go tips → pick a bag → photo of the pile
→ review items → rule flags → packer → 3D viewer and step-by-step packing checklist.

## How it works

- **Trip.** Enter an airline code and flight number. The server looks the flight up (Apify
  flight-status actor, then AviationStack, then bundled demo flights) and fills origin,
  destination, weather and route notices.
- **Bag.** Pick a preset suitcase or backpack, or type in your own bag's size. Suitcases can be
  single-shell or two-sided; backpacks use a simple compartment model.
- **Items.** Lay a credit card flat next to your things and take a photo at about 45°. Claude
  names every object in the photo. The app finds the card on-device and uses it as the scale
  reference to measure each object's width and depth (and height when the angle allows).
  Without a card, sizes are Claude's estimates and are marked with `~`. You can edit every
  field on every item.
- **Plan.** `Packages/Packer` runs on the phone and is deterministic: the same items and bag
  always give the same plan. The Results tab shows the plan in 3D (RealityKit), and the Plan
  tab lists the steps layer by layer.
- **Rules.** `POST /rules/check` flags only items that break a TSA, airline or customs rule.
  Each flag links to its source and is labeled stale after 30 days.

## Run

### What you need

- A Mac with **Xcode 26** (free on the Mac App Store).
- An **iPhone on iOS 18 or later**. Any model works: scanning uses the regular camera and a
  credit card for scale. The simulator has no camera, so it uses sample items instead.
- An **Apple ID**. A free one works. You don't need a paid developer account.
- For the backend only: **Node 24** and **pnpm**. Run `corepack enable` once and the repo's
  pinned pnpm version is used.

### 1. Get the code

```bash
git clone https://github.com/Pikas3/CalHacks13.git
cd CalHacks13
```

### 2. Run Snugly on your iPhone

1. **Add your Apple ID to Xcode:** Xcode → Settings → Accounts → **+** → Apple ID.
2. **Find your Team ID.** In the same Accounts pane, select your team. The ID is the
   10-character code, for example `ABCDE12345`. A free Apple ID shows up as
   "Your Name (Personal Team)".
3. **Create `apps/ios/Config/Local.xcconfig`.** It's gitignored, so your settings stay on your
   machine:

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   MOCK_API = YES
   ```

   `MOCK_API = YES` runs the whole app on bundled fixture data with no server, which is the
   quickest way to try it. To use a real backend, see [step 3](#3-optional-connect-a-backend).
   Your team ID also becomes the end of the bundle ID (`com.packfit.app.<TEAMID>`), so there is
   no ID clash with anyone else's build.
4. **Prepare the phone.** Plug it into the Mac, unlock it and tap **Trust**. Then turn on
   Settings → Privacy & Security → **Developer Mode** and let the phone restart.
5. **Build and run.** Open `apps/ios/PackFit.xcodeproj`, pick the **PackFit** scheme and your
   iPhone as the destination, then press **Run** (⌘R).
6. **First launch only:** iOS blocks apps from a new developer until you trust them. Open
   Settings → General → **VPN & Device Management**, tap your Apple ID and choose **Trust**.
   Then open Snugly from the home screen.

Builds signed with a free Apple ID expire after 7 days. When that happens, press Run in Xcode
again.

### 3. (Optional) Connect a backend

Live scanning, flight lookup, rules and suggestions go through `services/api`. The app never holds API keys.

**Run the server on your Mac:**

```bash
pnpm install
cp services/api/.env.example services/api/.env   # optional: ANTHROPIC_API_KEY, APIFY_TOKEN, AVIATIONSTACK_API_KEY
pnpm --filter api dev                            # http://localhost:8787
pnpm --filter api test
```

With no Anthropic key (or `MOCK_CLAUDE=1`, the default in `.env.example`), the server returns
deterministic stubs, so it still works offline. Set `MOCK_CLAUDE=0` and add a key for real
photo scans. Without an Apify token, flight lookup only knows the demo flights (UA 88, BA 178,
AS 204, DL 188, AA 100).

Your phone can't reach `localhost` on the Mac. Point the app at the Mac's Wi-Fi address and
keep both devices on the same network:

```bash
ipconfig getifaddr en0    # e.g. 10.0.0.42
```

Then set `apps/ios/Config/Local.xcconfig` to:

```
DEVELOPMENT_TEAM = ABCDE12345
MOCK_API = NO
API_BASE_URL = http:/$()/10.0.0.42:8787
APP_TOKEN = local-dev-token
```

`APP_TOKEN` must match `APP_TOKEN` in `services/api/.env`. The `/$()/` is not a typo:
xcconfig files treat `//` as the start of a comment. Run the app again, and tap **Allow** when
iOS asks for Local Network access.

**Use a hosted server:** set `API_BASE_URL` to its `https:/$()/…` address and set `APP_TOKEN`
to the token its operator gives you. Never commit that token.

### Simulator

Choose any iPhone simulator as the destination. It needs no team ID. It has no camera, so
**Take photo** loads sample items, and `MOCK_API = YES` is the simplest setup.

### Troubleshooting

| Problem | Fix |
|---|---|
| "Signing for PackFit requires a development team" | `DEVELOPMENT_TEAM` is missing from `Config/Local.xcconfig`, or the file isn't saved in `apps/ios/Config/` |
| "Untrusted Developer" when opening the app | Settings → General → VPN & Device Management → Trust |
| Xcode can't find the phone, or shows it as unavailable | Unlock it, reconnect the cable, and check that Developer Mode is on |
| The app can't reach the server | Make sure the phone and Mac are on the same Wi-Fi, `API_BASE_URL` uses the Mac's current IP, and Local Network access is allowed (Settings → Privacy & Security → Local Network) |
| Every request returns 401 | `APP_TOKEN` in `Local.xcconfig` doesn't match the server's |

## Sponsor tools

### Anthropic (Claude)

Used only on the server (`services/api`), never in the iOS binary.

| Where | What |
|---|---|
| `src/claude/prompts/scanInventory.ts` + `services/scan.ts` | Names every object in a pile photo, with a box per object and the credit card's location (`POST /scan/inventory`) |
| `src/claude/prompts/scanItem.ts` + `services/scan.ts` | Single-item ID from a photo (`POST /scan/item`) |
| `src/claude/prompts/mapRules.ts` + `services/rules.ts` | Choose among retrieved TSA/airline/country candidates; write one-sentence flag text |
| `src/claude/prompts/askRule.ts` | Free-text “is this allowed?” answers grounded in candidate rules |
| `src/claude/prompts/suggestItems.ts` + `services/trip.ts` | Destination packing suggestions as strict JSON (`Suggestion`) |

Keys: `ANTHROPIC_API_KEY`, optional `ANTHROPIC_MODEL` / `ANTHROPIC_MODEL_FAST` in `services/api/.env`.

### Apify

`POST /trip/lookup` calls a flight-status actor (`APIFY_FLIGHT_ACTOR`, default
`apt_marble~flight-status-tracker`) and caches results per flight number.

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
