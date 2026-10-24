# Cross-section requests

Append a row when you need something from another section (a schema field, an endpoint, an
interface change). Keep working against a local mock until the owner marks it done.

| Date | From | To | Request | Status |
|---|---|---|---|---|
| 2026-10-24 | 1 Core | 3 Backend | `Trip.id?: string` (pattern `^[a-z0-9-]+$`) added to `trip.schema.json` and the Swift mirror. Additive optional; names fixture plans (`plans/<trip-id>-<bag>.json`) and is required in `fixtures/trips.json`. Please add it to the zod mirror. | done (schema, Swift); zod open |
| 2026-10-24 | 1 Core | 3 Backend | Root `package.json` + `pnpm-workspace.yaml` (`services/*`) created for `pnpm schemas:check`. It runs `pnpm --filter api --if-present run schemas:check` last, so add a `schemas:check` script to `services/api` for the zod half. Merge into these files rather than replacing them. | open |
