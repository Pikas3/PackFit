# TSA What Can I Bring scraper

Public Apify actor that crawls [TSA What Can I Bring](https://www.tsa.gov/travel/security-screening/whatcanibring) item pages and emits one record per item with carry-on / checked verdicts and the source URL.

Snugly and other apps can normalize this dataset into their own rule formats. The dataset itself stays generic.

## Input

```json
{
  "startUrls": [
    { "url": "https://www.tsa.gov/travel/security-screening/whatcanibring/all" }
  ],
  "maxItems": 200
}
```

See `INPUT_SCHEMA.json`.

## Output example

```json
{
  "name": "Power Banks",
  "carryOn": "yes_with_limits",
  "checked": "no",
  "description": "Power banks must be in carry-on bags…",
  "url": "https://www.tsa.gov/travel/security-screening/whatcanibring/items/power-banks",
  "scrapedAt": "2026-10-24"
}
```

## Run

```bash
apify login
cd services/apify/tsa-what-can-i-bring
apify run
```

Schedule daily in the Apify Console. Downstream sync (`pnpm --filter api sync:rules`) pulls the latest successful dataset run.
