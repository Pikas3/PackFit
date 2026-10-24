# Packages/PackFitSchemas

Owned by Section 1 (see `../Packer/CLAUDE.md`). Swift Codable mirror of
`schemas/*.schema.json`, plus `Fixtures` loaders for `schemas/fixtures/`.

If you are not Section 1: `import PackFitSchemas`, do not edit this package. To request a
field, add a row to `docs/requests.md` and work around it locally until it lands. See the
change protocol in `docs/contracts.md`.

The JSON Schema in `schemas/` is the source of truth. If this package and the schema
disagree, the schema wins; fix the Swift in the same PR and tell Section 3 so the zod mirror
follows.
