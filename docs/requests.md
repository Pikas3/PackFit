# Cross-section requests

Append a row when you need something from another section (a schema field, an endpoint, an
interface change). Keep working against a local mock until the owner marks it done.

| Date | From | To | Request | Status |
|---|---|---|---|---|
| 2026-10-24 | 1 Core | 3 Backend | `Trip.id?: string` (pattern `^[a-z0-9-]+$`) added to `trip.schema.json` and the Swift mirror. Additive optional; names fixture plans (`plans/<trip-id>-<bag>.json`) and is required in `fixtures/trips.json`. Please add it to the zod mirror. | done (schema, Swift); zod open |
| 2026-10-24 | 1 Core | 3 Backend | Root `package.json` + `pnpm-workspace.yaml` (`services/*`) created for `pnpm schemas:check`. It runs `pnpm --filter api --if-present run schemas:check` last, so add a `schemas:check` script to `services/api` for the zod half. Merge into these files rather than replacing them. | open |
| 2026-10-24 | 2 iOS | 4 Voice | The AR overlay is driven by `GuidedSession.stepper` (`PlanStepper`, conforms to `PlanViewerControlling`). `PlanViewerController` still conforms too. Hook the coach to whichever screen is showing. | open |
| 2026-10-24 | 2 iOS | 3 Backend | The guided flow sends up to 4 `/scan/item` calls in parallel, each with a cropped JPEG and `measured` dims (`method: lidar`). The app overwrites w/h/d with the measured values. | open |
| 2026-10-24 | 2 iOS | 1 Core | In the lying-open suitcase frame, the opening (lid) is max y, but `touchesOpening` uses max z. Scanned bags set `wheelsSide: .back`, meaning low z (hinge side); real wheels are on a short end (x). Please confirm the intended frame. | open |
