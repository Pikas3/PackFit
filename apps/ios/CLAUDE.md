# Section 2: iOS app (RealityKit viewer, photo scanning, container setup, design system)

You own `apps/ios` except `PackFit/Voice/`, which belongs to Section 4. Workstreams WS2,
WS3 (client side, including card-scaled measurement), WS4, WS8. Read the root `CLAUDE.md`,
`docs/contracts.md`, `docs/api.md`.

You are on the critical path for the demo. The photo scan and the viewer are the two things
judges will remember; everything else is ordered by how much of the demo spine it unlocks.

## Stack

- Xcode 26, SwiftUI, Swift 6 toolchain, iOS 18 minimum. Swift 6 language mode on; if strict
  concurrency slows you down on AVFoundation delegate callbacks, use
  `@preconcurrency import AVFoundation` and `nonisolated(unsafe)` sparingly rather than
  downgrading the whole target.
- Project: `apps/ios/PackFit.xcodeproj`, one app target `PackFit`, local package
  dependencies by path on `../../Packages/PackFitSchemas`, `../../Packages/Packer`,
  `../../Packages/Voice`.
- Config: `Config/Debug.xcconfig` and `Config/Release.xcconfig` with `API_BASE_URL`,
  `APP_TOKEN` (the shared static token, not a vendor key), `MOCK_API`. Read via
  `Bundle.main.infoDictionary`. The committed `Config/Example.xcconfig` has placeholders;
  the real ones are gitignored.
- State: `@Observable` stores, one per domain: `TripStore`, `ItemsStore`, `PlanStore`,
  `RulesStore`. Injected with `.environment`.
- Navigation: `NavigationStack` with a typed `Route` enum.
- 3D: RealityKit `RealityView`, non-AR, for the plan viewer.
- Camera: AVFoundation back camera (`InventoryCamera`) for stills and a live credit-card
  check. Works on every iPhone; no LiDAR, no ARKit. Measurement uses Vision on the still.
  See the scan section.
- Upload: resize to 1024 px long edge, JPEG 0.8 (`ImageCapture`).
- Networking: `URLSession` async/await, `JSONDecoder` into `PackFitSchemas` types.
  `APIClient` protocol with `LiveAPIClient` and `MockAPIClient`.
- Solver: `import Packer`; `pack(_:into:options:)` runs on-device on a background task.

## Screens

| Route | Purpose | Spine? |
|---|---|---|
| `TripPicker` | Sample trips from fixtures, or new trip (from, to, airline, nights, date) | yes |
| `BagSetup` | Presets (carry-on, checked, backpack), manual measure, one- or two-sided shell; backpack compartment editor | yes |
| `ItemList` | Items with thumbnails, measurement method and confidence badges, swipe to delete, tap to edit | yes |
| `InventoryScan` | Photo of the pile with a credit card; Claude names the objects, the card scales them; review and tick which to add | yes |
| `PlanViewer` | RealityKit viewer with step controls; the hero screen | yes |
| `ItemDetail` | Sheet: item fields, rule flags with source links and "verified N days ago", notes | yes |
| `Rules` | All flags for the trip, grouped by severity, stale banner | yes |
| `Suggestions` | Suggested items from `/trip/suggest`, each toggleable into the list | no (cut first) |

## WS3 client: photo item scan (`PackFit/Scan/`)

This is the differentiator. Rule 6 in the root doc: dimensions come from the photo and the
card, Claude identifies and estimates the rest. There is no LiDAR or ARKit path.

### Measurement flow (`Scan/Inventory/`, `Scan/Measurement/`)

1. The user lays a credit card flat beside the pile and holds the phone at about 45°.
   `InventoryCamera` looks for the card in the live preview (tap to focus and search that
   region) and shows when it locks.
2. Capture a still and send it to `POST /scan/inventory` with `reference: "credit_card"`.
   Claude returns every object with a box, and where the card is.
3. `CardMeasurer`: Vision rectangles find the ID-1 card, which gives the floor's pose
   (`CardScale`, `CardEdges`). Vision foreground instance segmentation outlines each object.
   `SilhouetteFit` fits the floor-standing box or cylinder whose projection matches the
   outline. Width and depth come from that fit; height only when the photo is not close to
   straight down. `measurement.method = .reference`.
4. No card found: offer "Use rough estimates", which keeps Claude's sizes
   (`measurement.method = .estimate`, shown with `~`).
5. Review: tick which objects to add (repeats from earlier photos start unticked), then every
   `Item` field is editable in `ItemDetail`. Confidence labels: >= 0.8 "Looks right",
   0.5-0.8 "Check the size", < 0.5 "Please measure".
6. Saved items go to `ItemsStore` with `source: .scan`.

Measure the 25 fixture items with this flow and record mean absolute error per axis in
`docs/status.md`. Target: within ~15%.

## WS4: container setup (`PackFit/Bag/`)

- Presets from `Fixtures.containers()` plus "Custom".
- Manual: three fields, weight limit defaulting to 23. Inner `main` compartment is outer
  minus 3 cm per side (`ContainerFactory`). Then ask "wheels on the back or bottom?" and,
  for suitcases, one main cavity or two sides.
- Backpack: compartment list, add compartment, each with name and one or two measurements
  (third dim assumed from the outer size). Tap-to-define is "tap a preset region" (main /
  front / laptop), not AR.
- Acceptance: a new bag defined in under 45 seconds manually. Time it and record it.

## WS2: 3D viewer (`PackFit/Viewer/`)

Port the web prototype into a non-AR `RealityView`:

- Scene: a `PerspectiveCamera` entity orbited by `DragGesture` (azimuth and elevation,
  elevation clamped to 5-85 degrees so the user cannot go under the floor) and
  `MagnifyGesture` (distance). Scale cm to metres with 0.01.
- Container as a translucent inner-volume box (`UnlitMaterial`, alpha 0.08) plus edges
  drawn as thin box entities along the 12 edges; opening side marked (lid plane for
  suitcases, top for backpacks).
- Items as `ModelEntity(mesh: .generateBox(size:), materials:)` at `Placement` coordinates
  per the root convention. One `SimpleMaterial` per `Category` (10 total), cached. Fragile
  items get a red edge frame (same 12-edge technique, or a slightly larger box with
  `triangleFillMode = .lines`).
- Step slider (0...placed.count) and Play (600 ms per step, pause on touch). Current item
  brightened and gently scaled 1.03x; future items hidden (`isEnabled = false`); past items
  at 85% opacity.
- Layer view: a "peel" slider that disables items whose `y + h` is above a threshold.
- Tap an item: `RealityView` entity hit test via `SpatialTapGesture` + `targetedToAnyEntity`,
  open `ItemDetail`.
- Label for the current item only (a `ModelEntity` with `generateText` or a SwiftUI overlay
  using the projected position); labelling all 30 costs frames.
- Public interface for Section 4's coach, fixed early and not changed after:

  ```swift
  @MainActor protocol PlanViewerControlling: AnyObject {
      func goToStep(_ n: Int, animated: Bool)
      var currentStep: Int { get }
      var onStepChange: ((Int) -> Void)? { get set }
  }
  ```

Performance budget: 60 fps with 30 items on an iPhone 13 Pro or newer. Rules: one shared
`MeshResource` box, materials cached per category, update entity transforms and
`isEnabled` directly rather than rebuilding the scene on each step, no SwiftUI state
churn per frame. Measure with Instruments (RealityKit Trace or Core Animation FPS) and
record in `docs/status.md`.

## WS8: design system (`PackFit/Theme/`)

- `Tokens.swift`: colour (asset catalog with light and dark variants), type scale on
  Dynamic Type text styles, spacing (4 pt), radii, motion durations.
- `@Environment(\.accessibilityReduceMotion)`: when on, Play steps instantly and the
  current-item scale pulse is static.
- Contrast: all text at least 4.5:1 in both appearances; check the severity colours
  (banned/restricted/check) specifically against their backgrounds.
- Empty and error states in plain language, one sentence plus one action. All user-facing
  strings in `PackFit/Copy.swift` as a `enum Copy` so Section 4 reuses the same wording in
  voice.
- Onboarding: three screens max, skippable, shown once (`@AppStorage`).
- Figma file is optional. If you make one, link it in `docs/status.md`.

## Mocking while you wait

- Before `PackFitSchemas` lands (first hour): define the structs from `docs/contracts.md`
  in a temporary `PackFit/Temp/Types.swift`. Delete it the moment the package is on
  `master`.
- Before `Packer` lands: load `Fixtures.plan(named:)` directly for the viewer.
- Before `services/api` lands: `MockAPIClient` returns fixture items for `/scan/inventory`,
  two fixture flags for `/rules/check`, and the SFO->DEL suggestions.
- The demo must run fully in mock mode. This is also the offline fallback for judging.
- The simulator has no camera: "Take photo" loads sample items so the flow is testable.

## Acceptance

- Card-scaled measurement of 25 fixture items with recorded error, mean under 15%.
- 60 fps with 30 items in the viewer on an iPhone 13 Pro or newer, number recorded.
- Scan to editable card works against the live API and against mock, on device and in the
  simulator.
- New bag in under 45 seconds manually.
- Light and dark, contrast checked, reduced motion respected, Dynamic Type up to xxxLarge
  does not clip the plan controls.
- `xcodebuild build` clean with no warnings in your targets.

## Conventions

- `PackFit/` layout: `App/` (entry, routes, config), `Scan/`, `Bag/`, `Viewer/`, `Items/`,
  `Rules/`, `API/`, `Store/`, `Theme/`, `Components/`, `Copy.swift`, `Voice/` (not yours).
- Views are small; logic lives in the stores or in `Scan/Measurement/` (pure functions
  from the card pose and object outlines to `(w, h, d, confidence)`, unit tested in
  `PackFitTests`).
- Never `URLSession` in a view; all network goes through `APIClient`.
- Decode every API response into `PackFitSchemas` types; on failure show the manual
  fallback, never a raw error.
- `Info.plist`: `NSCameraUsageDescription` explains measuring items; no microphone key (that
  is Section 4's and lives in the same plist, coordinate the edit).

## Report format

Append to `docs/status.md`: what you built, what you cut, how to run (scheme, device,
xcconfig values, mock vs live), measured fps, measured scan error, measured bag-setup time.
