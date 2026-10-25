# Country customs restrictions scraper

Apify actor scaffold for destination-country traveler rules (food, plants, medication,
drones, vapes, cash limits). Emits normalized records with `sourceUrl` and `scrapedAt`.

PackFit loads the last good results from `services/api/data/rules/country.json` when a
live run is missing or fails. Records older than 30 days are labeled stale in the UI.

## Input

```json
{
  "countries": ["IN", "KR", "IS", "GB", "CN"],
  "maxCountries": 20
}
```

See `INPUT_SCHEMA.json`.

## Run

```bash
apify login
cd services/apify/country-customs
apify run
```

Guidance only — not customs authority. Always keep source links on every record.
