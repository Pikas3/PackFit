# Airline baggage policy scraper

Reusable Apify actor that fetches cabin and checked baggage size/weight notes for a list of
airline IATA codes and emits one normalized record per airline with a `sourceUrl` and scrape
timestamp.

Snugly syncs successful runs into `services/api/data/rules/airline.json` via
`pnpm --filter api sync:rules`. Other apps can consume the dataset as-is.

## Input

```json
{
  "airlines": ["UA", "AA", "DL", "BA", "AI"],
  "maxAirlines": 20
}
```

See `INPUT_SCHEMA.json`.

## Output example

```json
{
  "airline": "UA",
  "carryOnMaxCm": [56, 35, 23],
  "checkedWeightKg": 23,
  "notes": "Economy checked bag typically 23 kg…",
  "url": "https://www.united.com/en/us/fly/baggage.html",
  "scrapedAt": "2026-10-24"
}
```

## Publish / run

```bash
apify login
cd services/apify/airline-baggage
apify push
apify run --input '{"airlines":["UA","BA"]}'
```

Schedule daily in the Apify Console. When the live scrape fails, Snugly keeps the last good
`data/rules/airline.json` and labels records older than 30 days as stale in the UI.

## Guidance

These outputs are travel guidance for packing apps, not legal advice. Always keep `sourceUrl`
and `lastVerified` (or `scrapedAt`) on every record.
