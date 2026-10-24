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
