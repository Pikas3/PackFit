# schemas/

Owned by Section 1. JSON Schema 2020-12 for the five shared types and the fixture JSON that
every section loads.

- `*.schema.json`: source of truth. Mirrored by `Packages/PackFitSchemas` (Swift) and
  `services/api/src/schemas.ts` (zod).
- `fixtures/`: 3 containers, 25 items with tape-measured dims, 5 trips, pre-computed plans.
  Loaded by the Swift package as a resource bundle and by backend tests directly.

Changing anything here follows the protocol in `docs/contracts.md`. `pnpm schemas:check`
must pass before merge.
