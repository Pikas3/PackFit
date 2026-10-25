# Snugly: Project Outline for Delegation

> Original brief, kept verbatim for reference. Section 3 (Architecture) is superseded by the
> root `CLAUDE.md`: the client is native Swift/SwiftUI with RealityKit and LiDAR, not Expo,
> and the solver is a Swift package. Contracts, workstreams and acceptance criteria still
> apply.

Cal Hacks 13.0 travel app. Core idea: scan your items, then see exactly how to pack your bag
in 3D, with voice guidance and live travel rules.

## 1. Goal and target tracks

**Product:** a mobile app that turns a pile of items plus a bag into a step-by-step,
physically sensible packing plan, and flags items that break TSA, airline or destination rules.

**Named community (for Anthropic track):** international students flying home with a 23 kg
checked-bag limit.

**Tracks:**
- Apify: scrapers feed the rules engine, publish one reusable actor.
- Cartesia: hands-busy voice packing coach.
- Anthropic: vision, attribute estimation, rule summaries with sources.
- Optional: Notability (planning notes), Figma (UI design).

**Demo spine (2 min):** messy pile, scan 3 items, voice coach walks through the 3D plan, one
rule flag with a source link.

## 2. Status

| Area | Status |
|---|---|
| 3D packing solver and viewer (single-file web prototype) | Done (base version) |
| Everything else below | Not started |

## 3. Architecture

- App: Expo (React Native, TypeScript). 3D via react-three-fiber or expo-three. The
  prototype's `pack()` function ports directly to a shared TypeScript package.
- Packages: `packages/packer` (solver, pure TS, unit tested), `packages/schemas` (shared JSON
  schemas), `apps/mobile`, `services/api` (thin backend for Claude, Apify and Cartesia calls
  so no keys ship in the app).
- Rule: no API keys or secrets in the repo (Cartesia requires this).

## 4. Shared data contracts

| Type | Shape |
|---|---|
| Item | `{ id, name, w, h, d (cm), kg, fragile: bool, hardness: 0-1, soft: bool, upright: bool, category, confidence }` |
| Container | `{ id, name, type: suitcase\|duffel\|backpack, outer: [w,h,d], compartments: [{name, dims, compressibility}], weightLimitKg }` |
| Plan | `{ placed: [{itemId, x, y, z, w, h, d, order}], unplaced: [itemId], stats: {fillPct, kg, comHeightPct} }` |
| RuleFlag | `{ itemId, scope: tsa\|airline\|country, severity: banned\|restricted\|check, text, sourceUrl, lastVerified }` |
| Trip | `{ from, to, airline, nights, activities[], carryOn: Container, checked: Container }` |

See `docs/contracts.md` for the TypeScript definitions.

## 5. Workstreams

### WS1. Packing engine (`packages/packer`)
Exists: extreme-point heuristic with support check (60%), fragile-never-under rule, no
heavy-on-light, flat-first orientation, soft items compress 20%.
Next: unit tests; compartment-aware backpack model; heavy near wheels/back; "needed at
security" items on top; 6-orientation toggle with upright locks; optional OR-tools/CP-SAT
refinement pass; benchmark on 30 items under 1 s on a phone.
Accepts: deterministic output for a fixed input; no overlaps or floating items in 1,000
random trials.

### WS2. 3D viewer and plan UX (`apps/mobile`)
Port the web viewer: orbit, pinch zoom, step slider, play, highlight current item, fragile
outline. Layer view (peel back layers), item labels, tap an item to see its rules and notes.
Accepts: 60 fps on a mid-range phone with 30 items.

### WS3. Item scan (vision)
Camera capture, then Claude vision returns an Item JSON (name, category, dims, kg, fragile,
soft, confidence). Scale: reference object (credit card or paper) first, ARKit LiDAR where
available. Manual override for every field; confidence shown to the user.
Accepts: 20 common items identified, dims within ~15%, malformed model output handled.

### WS4. Container scan
Presets (carry-on, checked, backpack), manual measure, optional AR measure. Backpack:
tap-to-define compartments, one or two measurements each.
Accepts: user can define a new bag in under 30 seconds.

### WS5. Rules engine and Apify scrapers
Apify actors on a schedule: TSA "what can I bring", airline baggage policies (cabin and
checked dims and weight), country customs restrictions. Normalize to RuleFlag records stored
with sourceUrl and lastVerified. Publish one actor publicly (Best Actor award). Claude maps
scanned items to rules and summarizes, always linking the source. Wording is guidance, never
final authority.
Accepts: every flag has a source and date; stale data (older than 30 days) is labeled.

### WS6. Trip and suggestions
Origin, destination, airline, dates. Weather forecast leads to suggested items; overweight
warning against airline limit; return-trip souvenir space budget.
Accepts: a suggested list for 3 sample trips, each editable.

### WS7. Voice coach (Cartesia)
Voice is core: step-by-step packing instructions, interruptible ("I don't have that, swap
it"), add items by voice, ask "is this allowed?" at the airport. Short README section:
Cartesia features used, limits, privacy (no audio stored).
Accepts: one full packing flow completed hands-free; interruption handled.

### WS8. UI and design system
Figma file, tokens (color, type, spacing), light and dark, onboarding, empty and error states
in plain language.
Accepts: all screens responsive, readable contrast, reduced motion respected.

### WS9. Submission and demo
README per track (where and how each sponsor tool is used), 2-minute demo script and video
(open with the strongest moment), source access for judges, safe-by-default notes on where
Claude can be wrong.

### WS10. QA and fixtures
Fixture set: 3 bags, 25 items with ground-truth dims, 5 trip scenarios. Smoke-test the full
flow before judging.

## 6. Dependencies and order

1. WS1 and WS2 first (core demo).
2. WS3 and WS4 produce real inputs.
3. WS5 and WS6 add intelligence (can run in parallel from the start since they only depend
   on Item).
4. WS7 after WS1 has stable step output.
5. WS8 runs throughout.
6. WS9 and WS10 in the last third.

## 7. Scope guardrails

- Suitcase first; backpack in simplified compartment form.
- Weight and fragility come from a lookup table plus Claude estimates, with manual override.
- Cut anything that is not on the demo spine.

## 8. Risks

- Photo-based depth and dimension error: use reference objects, show confidence, allow edits.
- Wrong prohibited-item calls: cite sources, show last verified date, label as guidance.
- Scraper breakage: cache last good data, keep fixtures for the demo.
- Live demo failures: record a backup video, keep an offline sample trip.

## 9. Delegation prompt template

> You own WSn of Snugly. Read this outline (sections 3 and 4 for contracts). Deliver:
> [outputs]. Acceptance: [criteria]. Do not change shared schemas without flagging it. No
> secrets in the repo. Report what you built, what you cut, and how to run it.
