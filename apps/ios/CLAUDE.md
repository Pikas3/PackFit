# Section 2: iOS app (RealityKit viewer, LiDAR scanning, container setup, design system)

You own `apps/ios` except `PackFit/Voice/`, which belongs to Section 4. Workstreams WS2,
WS3 (client side, including all LiDAR measurement), WS4, WS8. Read the root `CLAUDE.md`,
`docs/contracts.md`, `docs/api.md`.

You are on the critical path for the demo. The LiDAR scan and the viewer are the two things
judges will remember; everything else is ordered by how much of the demo spine it unlocks.

## Stack

- Xcode 26, SwiftUI, Swift 6 toolchain, iOS 18 minimum. Swift 6 language mode on; if strict
  concurrency slows you down on ARKit delegate callbacks, use `@preconcurrency import ARKit`
  and `nonisolated(unsafe)` sparingly rather than downgrading the whole target.
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
- 3D: RealityKit `RealityView` (non-AR for the plan viewer, AR for the optional overlay).
- Measurement: ARKit `ARSession` with `ARWorldTrackingConfiguration`, `sceneDepth` frame
  semantics and `.mesh` scene reconstruction. See the LiDAR section.
- Camera stills: take the photo from the running `ARSession` (`ARFrame.capturedImage`) so
  the measurement and the photo are from the same moment and pose. Resize to 1024 px long
  edge, JPEG 0.8, via `CIContext`.
- Networking: `URLSession` async/await, `JSONDecoder` into `PackFitSchemas` types.
  `APIClient` protocol with `LiveAPIClient` and `MockAPIClient`.
- Solver: `import Packer`; `pack(_:into:options:)` runs on-device on a background task.

## Screens

| Route | Purpose | Spine? |
|---|---|---|
| `TripPicker` | Sample trips from fixtures, or new trip (from, to, airline, nights, date) | yes |
| `BagSetup` | Presets (carry-on, checked, backpack), LiDAR measure, manual measure; backpack compartment editor | yes |
| `ItemList` | Items with thumbnails, measurement method and confidence badges, swipe to delete, tap to edit | yes |
| `Scan` | AR camera, LiDAR measure, capture, review card with editable fields | yes |
| `PlanViewer` | RealityKit viewer with step controls; the hero screen | yes |
| `ItemDetail` | Sheet: item fields, rule flags with source links and "verified N days ago", notes | yes |
| `Rules` | All flags for the trip, grouped by severity, stale banner | yes |
| `AROverlay` | Plan projected onto the real suitcase through the camera | stretch, high value |
| `Suggestions` | Suggested items from `/trip/suggest`, each toggleable into the list | no (cut first) |

## WS3 client: LiDAR item scan (`PackFit/Scan/`)

This is the differentiator. Rule 6 in the root doc: dimensions come from the device,
Claude identifies and estimates the rest.

### Capability check

```swift
let hasLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
```

Decide once at launch, store in `DeviceCapabilities`, and show it on the scan screen
("LiDAR measuring" vs "Place a credit card next to the item"). Non-LiDAR devices get the
reference-card flow and the model estimates dims (`measurement.method = .estimate`). Never
crash on a non-LiDAR device or in the simulator; the simulator uses `MockAPIClient` and a
manual dims form.

### Measurement flow (LiDAR)

1. Start `ARSession` with `planeDetection = [.horizontal]`, `frameSemantics =
   [.sceneDepth, .smoothedSceneDepth]`, `sceneReconstruction = .mesh`. Ask the user to put
   the item on a table or floor and move until a plane is found.
2. **Footprint:** user taps two opposite corners of the item's base. Each tap is an
   `ARRaycastQuery(... allowing: .existingPlaneGeometry, alignment: .horizontal)`. The two
   hits give `w` and `d` in the plane's local frame (project onto the plane's x and z axes
   so a rotated item still measures its own edges, not world axes).
3. **Height:** automatic. Within the footprint rectangle, sample the scene mesh
   (`ARMeshAnchor` vertices that fall inside the footprint) or, if the mesh is sparse,
   sample `smoothedSceneDepth` along a grid of pixels covering the footprint, unproject with
   the camera intrinsics, and take the 98th percentile of height above the plane. Show a
   third tap as an override: tap the top of the item, raycast against `.estimatedPlane`
   with `.any` alignment, height = hit.y - plane.y.
4. **Confidence:** start at 0.95. Subtract 0.1 if the mean `confidenceMap` value over the
   footprint is below `.medium`, 0.1 if the footprint is under 4 cm on any side (depth noise
   dominates), 0.15 if the height came from fewer than 20 samples. Floor at 0.5. Put the
   result in `measurement.confidence`.
5. Draw the measured box in the AR view as a translucent RealityKit `ModelEntity` anchored
   to the plane, with the three numbers as labels, before the user confirms. If it looks
   wrong, they re-tap. This preview is also a demo moment.
6. Capture the current `ARFrame.capturedImage`, send `imageBase64 + measured` to
   `POST /scan/item`. Show a skeleton card while waiting (3-8 s; say so on screen).
7. Review card: every `Item` field editable. `w/h/d` are prefilled from LiDAR and shown with
   a "Measured with LiDAR" badge; confidence shown as a label: >= 0.8 "Looks right", 0.5-0.8
   "Check the size", < 0.5 "Please measure". `alternatives` from the API appear as chips to
   swap name and category. Any API error drops to a manual form with the measured dims kept.
8. Save appends to `ItemsStore` with `source: .scan`.

Measure the 25 fixture items with this flow and record mean absolute error per axis in
`docs/status.md`. Target: within ~15%; with LiDAR you should beat 10% on items over 5 cm.

### Reference-card fallback (non-LiDAR)

Overlay a card outline, user places a credit card beside the item, capture, send
`reference: "credit_card"` and no `measured`. The rest of the review card is identical.

## WS4: container setup (`PackFit/Bag/`)

- Presets from `Fixtures.containers()` plus "Custom".
- **LiDAR measure a suitcase:** same two-corner footprint plus auto height, on the closed
  suitcase lying flat. Outer dims go to `outer`; inner `main` compartment is outer minus
  3 cm per side (configurable constant), `compressibility 0.1`. `measurement.method =
  .lidar`. Then ask "wheels on the back or bottom?" with two pictures.
- Manual: three fields with a live RealityKit preview of the box, weight limit defaulting
  to 23.
- Backpack: compartment list, add compartment, each with name and one or two measurements
  (third dim assumed from the outer size). Tap-to-define is "tap a preset region" (main /
  front / laptop), not AR.
- Acceptance: a new bag defined in under 30 seconds with LiDAR, under 45 manually. Time it
  and record both.

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

### Stretch: `AROverlay`

After the viewer, scan, and bag flows are done. Anchor the plan to the real suitcase: the
user taps the suitcase's back-left corner on the detected plane, the full plan renders
inside the real bag through the camera, and the step controls drive it. This reuses the
viewer entities in an AR `RealityView` with the container anchor at the tapped point. If
you get here, tell Section 4; it becomes the opening shot of the demo.

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
- Before `services/api` lands: `MockAPIClient` returns fixture items for `/scan/item`
  (cycle through them), two fixture flags for `/rules/check`, and the SFO->DEL suggestions.
- The demo must run fully in mock mode. This is also the offline fallback for judging.
- The simulator has no LiDAR and no camera: `Scan` shows the manual dims form and still
  calls the (mock) API with a bundled photo so the flow is testable.

## Acceptance

- LiDAR measurement of 25 fixture items with recorded error, mean under 15%.
- 60 fps with 30 items in the viewer on an iPhone 13 Pro or newer, number recorded.
- Scan to editable card works against the live API and against mock, on device and in the
  simulator.
- New bag in under 30 seconds with LiDAR.
- Light and dark, contrast checked, reduced motion respected, Dynamic Type up to xxxLarge
  does not clip the plan controls.
- `xcodebuild build` clean with no warnings in your targets.

## Conventions

- `PackFit/` layout: `App/` (entry, routes, config), `Scan/`, `Bag/`, `Viewer/`, `Items/`,
  `Rules/`, `API/`, `Store/`, `Theme/`, `Components/`, `Copy.swift`, `Voice/` (not yours).
- Views are small; logic lives in the stores or in `Scan/Measurement/` (pure functions
  from raycast hits and depth samples to `(w, h, d, confidence)`, unit tested in
  `PackFitTests`).
- Never `URLSession` in a view; all network goes through `APIClient`.
- Decode every API response into `PackFitSchemas` types; on failure show the manual
  fallback, never a raw error.
- `Info.plist`: `NSCameraUsageDescription` explains measuring items; no microphone key (that
  is Section 4's and lives in the same plist, coordinate the edit).

## Report format

Append to `docs/status.md`: what you built, what you cut, how to run (scheme, device,
xcconfig values, mock vs live), measured fps, measured LiDAR error, measured bag-setup time.
