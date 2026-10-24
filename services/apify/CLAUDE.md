# services/apify

Owned by Section 3. Full instructions in `../api/CLAUDE.md` under "WS5: rules engine and
Apify actors". Three actors, one directory each, plus `shared/normalize.ts`.

`tsa-what-can-i-bring` is the actor we publish publicly. Keep it generic and documented:
`README.md`, `INPUT_SCHEMA.json`, `.actor/actor.json`, example output in the README. No
PackFit-specific fields in its dataset.

Run locally with `apify run` inside an actor directory. `APIFY_TOKEN` comes from `.env`,
never from the repo.
