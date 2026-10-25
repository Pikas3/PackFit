# Snugly

Cal Hacks 13.0 travel app (formerly PackFit). Snap one photo of your items, then see exactly how to pack your
bag in 3D, with voice guidance and live travel rules. Target user: international students flying
home with a 23 kg checked-bag limit.

**Demo spine (2 min):** messy pile -> one photo with a credit card for scale -> voice coach walks the 3D plan ->
one rule flag with a source link. If a feature is not on this spine, cut it.

Full brief: `docs/outline.md`. Data contracts: `docs/contracts.md`. HTTP API: `docs/api.md`.

## Platform

Native iOS. SwiftUI, Swift 6 toolchain (Xcode 26), iOS 18 minimum. 3D with RealityKit
(`RealityView`). Measurement from a single camera photo: Vision finds a credit card for
scale and outlines each object. No LiDAR or ARKit; the app runs on any iPhone on iOS 18.
No Android, no web. The outline's Expo plan is superseded.

The backend stays Node + TypeScript because the Claude, Apify and Cartesia SDKs are there
and keys must not ship in the app.

## Layout and ownership

Four agents work in parallel. Each owns the paths below and does not edit other sections'
paths. If you need a change elsewhere, write the request in `docs/requests.md` and continue
with a local mock.

| Section | Owns | Workstreams | Doc |
|---|---|---|---|
| 1 Core | `schemas/`, `Packages/PackFitSchemas`, `Packages/Packer` | WS1, WS10 | `Packages/Packer/CLAUDE.md` |
| 2 iOS app | `apps/ios` (except `PackFit/Voice/`) | WS2, WS3 (client + measurement), WS4, WS8 | `apps/ios/CLAUDE.md` |
| 3 Backend | `services/api` (except `src/routes/voice.ts`), `services/apify` | WS3 (server), WS5, WS6 | `services/api/CLAUDE.md` |
| 4 Voice + Submission | `Packages/Voice`, `apps/ios/PackFit/Voice/`, `services/api/src/routes/voice.ts`, `README.md`, `docs/tracks/`, `docs/demo/` | WS7, WS9 | `Packages/Voice/CLAUDE.md` |

## Hard rules

1. **No secrets in the repo.** Keys live in `.env` (gitignored) on the server. Every service
   ships a `.env.example`. The iOS app never holds an API key; it talks to `services/api`.
   Cartesia requires this.
2. **`schemas/*.schema.json` is the source of truth** for `Item`, `Container`, `Plan`,
   `RuleFlag`, `Trip`. `Packages/PackFitSchemas` (Swift Codable) and
   `services/api/src/schemas.ts` (zod) mirror it, and both validate the shared fixtures in
   CI. Do not change a shared type without an entry in `docs/requests.md`. Additive optional
   fields are fine with a note; renames and removals need agreement.
3. **Coordinate convention** (packer, viewer and AR overlay must agree): origin at the
   container's inner bottom-left-back corner. `x` runs along width (left to right), `y` is
   height (up), `z` is depth (back to front, toward the viewer). A placement's `(x, y, z)` is
   its minimum corner and `(w, h, d)` are the dimensions after orientation. Units: cm, kg.
   This matches RealityKit's right-handed y-up frame scaled by 0.01.
4. **Rules are guidance, never authority.** Every `RuleFlag` has a `sourceUrl` and
   `lastVerified`. Data older than 30 days is labeled stale in the UI.
5. **Deterministic solver.** Same input, same `Plan`. No randomness in the packer and no
   reliance on unstable sort order.
6. **Measure, don't guess.** Dimensions come from the photo, scaled by the credit card; the
   model names the objects and estimates only what cannot be measured (category, weight,
   fragility, and sizes when no card is found). Show the
   measurement method and confidence to the user and allow manual override of every field.
7. Suitcase first. Backpack is a simplified compartment model. Nothing beyond that.

## Toolchain

- iOS: Xcode 26, Swift Package Manager for `Packages/*`, Swift Testing for unit tests.
  Open `apps/ios/PackFit.xcodeproj`; the local packages are referenced by path.
- Backend: pnpm, Node 24, TypeScript strict, Hono, vitest.
- Commands: `swift test --package-path Packages/Packer`, `swift test --package-path
  Packages/Voice`, `xcodebuild -scheme PackFit -destination 'generic/platform=iOS' build`,
  `pnpm --filter api dev`, `pnpm --filter api test`.
- Schema check: `pnpm schemas:check` validates `schemas/fixtures/**` against
  `schemas/*.schema.json` and runs the Swift decode test.

## Workflow

- Branch per section: `ws/core`, `ws/ios`, `ws/backend`, `ws/voice`. Small PRs to `master`,
  rebase often. Section 1 merges `schemas/` and `Packages/PackFitSchemas` first; everyone
  else rebases onto it.
- Until a dependency lands, code against `docs/contracts.md` and use fixtures from
  `schemas/fixtures/`.
- When you finish a task, append to `docs/status.md`: what you built, what you cut, how to
  run it, measured numbers, and anything blocking you.
