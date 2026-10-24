# services/api HTTP contract

Thin backend that holds every third-party key. The iOS app (Section 2) and voice layer
(Section 4) call these endpoints; Section 3 implements all of them except `/voice/*`, which
Section 4 implements in `services/api/src/routes/voice.ts`.

Base URL: `http://localhost:8787` in dev (`API_BASE_URL` in the app's `Config.xcconfig`;
on a physical device this is your Mac's LAN IP). All bodies are JSON unless noted. All
response payloads validate against the zod schemas in `services/api/src/schemas.ts`, which
mirror `schemas/*.schema.json`.

## Conventions

- Header `x-packfit-token: <APP_TOKEN>` on every request. A shared static token from `.env`;
  it stops drive-by use of the deployed API, nothing more.
- Errors: `{ "error": { "code": string, "message": string } }` with 4xx/5xx. Codes:
  `bad_request`, `unauthorized`, `model_output_invalid`, `upstream_unavailable`,
  `rate_limited`, `internal`.
- Every response includes `meta: { requestId: string, ms: number }`.
- Timeouts: Claude calls 20 s, Apify dataset reads 5 s with cache fallback.
- No audio and no images are persisted. Request bodies are logged only as sizes.

## GET /health

`200 { ok: true, version: string, rulesLastSynced: string | null }`

## POST /scan/item  (WS3 server, Section 3)

Claude vision acts as an object-detection model on the photo and returns an `Item`.
On LiDAR devices the app measures `w/h/d` itself for packing; those dims are attached
server-side and are not sent into the identification prompt. The model names the item
from the image alone and estimates what cannot be measured (category, kg, fragile, soft,
hardness, upright).

Request:
```json
{
  "imageBase64": "<jpeg, max 3 MB, long edge resized to 1024 px by the client>",
  "measured": {
    "w": 30.2, "h": 1.8, "d": 21.4,
    "method": "lidar" | "reference" | "manual",
    "confidence": 0.93
  } | null,
  "reference": "credit_card" | "a4_paper" | "letter_paper" | null,
  "hint": "optional user text, e.g. 'my laptop charger'"
}
```

Response:
```json
{
  "item": Item,
  "alternatives": [{ "name": string, "category": Category }],
  "warnings": string[],
  "meta": { ... }
}
```

Behaviour:
- `item.id` is a fresh uuid, `item.source = 'scan'`, `item.confidence` in 0-1.
- With `measured` present, copy `w/h/d` verbatim into the item and set
  `item.measurement = { method, confidence, deviceHasLidar: method == 'lidar' }`. The model
  does not see those dimensions — identification is image-only object detection; dims are
  for the packer only.
- With no `measured` and a `reference`, the model estimates dims from the reference object;
  `measurement.method = 'estimate'`, confidence capped at 0.7.
- With neither, add a warning `"no_scale_reference"`, `measurement.method = 'estimate'`,
  confidence capped at 0.5.
- Weight, hardness, fragile, soft fall back to the lookup table in
  `services/api/src/data/catalog.json` by category when the model's values are missing or
  outside 0.01-30 kg. Estimated dims outside 0.5-200 cm are also replaced from the catalog
  with warning `"dims_from_catalog"`. Measured dims are never replaced.
- Model output is parsed with the zod schema. One repair retry on failure; then
  `422 model_output_invalid`.

## POST /scan/inventory  (WS3 server, Section 3)

One photo of everything the user has laid out. Claude vision lists every distinct packable
object in frame, one entry per instance, and the app shows them as an inventory to tick.
Works on any iPhone; nothing is measured, so every dimension is an estimate.

Request:
```json
{ "imageBase64": "<jpeg, max 3 MB, long edge 1024 px>", "hint": "optional user text" }
```

Response:
```json
{
  "detections": [
    {
      "item": Item,
      "box": { "x": 0.1, "y": 0.2, "w": 0.3, "h": 0.25 } | null,
      "alternatives": [{ "name": string, "category": Category }]
    }
  ],
  "warnings": string[],
  "meta": { ... }
}
```

Behaviour:
- At most 25 detections. The suitcase, furniture, floor, hands and people are ignored.
- `box` is normalized to the upright photo, origin top-left. It is approximate and only
  used to highlight and crop thumbnails on the phone, never for measuring. Out-of-range
  boxes are clamped; degenerate ones become `null`.
- Each `item` gets a fresh uuid, `source = 'scan'`, `measurement.method = 'estimate'`,
  `measurement.confidence` capped at 0.5 (no scale reference). `item.confidence` is the
  identification confidence.
- kg and dims are clamped and replaced from the catalog exactly as in `/scan/item`.
- Warnings: always `"no_scale_reference"`; `"nothing_detected"` for an empty list;
  `"dims_from_catalog"` / `"kg_from_catalog"` when any item needed a fallback;
  `"sample_data"` when the server answered with stub items (no API key or `MOCK_CLAUDE=1`).

## POST /rules/check  (WS5, Section 3)

Map items to rule flags for a trip.

Request:
```json
{
  "items": Item[],
  "trip": { "from": "SFO", "to": "DEL", "airline": "UA" },
  "bag": "carryOn" | "checked"
}
```

Response:
```json
{
  "flags": RuleFlag[],
  "summary": "one-paragraph plain-language summary with no new claims beyond the flags",
  "stale": boolean,
  "rulesLastSynced": "2026-10-20T04:00:00Z",
  "meta": { ... }
}
```

Behaviour:
- Candidate rules come from the normalized rule store (`services/api/data/rules/*.json`,
  produced by the Apify actors). Claude only chooses among candidates and writes `text`;
  it never invents a `sourceUrl`. The server overwrites `sourceUrl` and `lastVerified` from
  the rule record regardless of what the model returns.
- Zero flags is a valid, common answer. Do not pad.
- `stale` is true if any returned flag's `lastVerified` is older than 30 days.

## POST /rules/ask  (WS5 + WS7, Section 3)

Free-text question for the "is this allowed?" voice path.

Request: `{ "question": "can I bring a power bank", "trip": {...}, "bag": "carryOn" }`
Response: `{ "answer": string, "flags": RuleFlag[], "stale": boolean, "meta": {...} }`

Same source rules as `/rules/check`. The answer must cite at least one flag or say that no
matching rule was found.

## POST /trip/suggest  (WS6, Section 3)

Request: `{ "trip": Trip }`
Response:
```json
{
  "suggestions": Item[],
  "weather": { "summary": string, "lowC": number, "highC": number, "precipChance": number, "sourceUrl": string },
  "warnings": [
    { "kind": "overweight", "bag": "checked", "estimatedKg": 24.3, "limitKg": 23 },
    { "kind": "souvenir_space", "reservedLitres": 8 }
  ],
  "meta": { ... }
}
```

Suggestions have `source = 'suggested'`, `confidence = 1`, dims and weight from the catalog.
Weather from Open-Meteo (no key) keyed by destination airport coordinates.

## POST /voice/tts  (WS7, Section 4)

Request: `{ "text": string, "voiceId"?: string }`
Response: `audio/wav` stream, or `application/json` error. Cartesia Sonic; the server does
not store text or audio.

## POST /voice/stt  (WS7, Section 4)

Request: `multipart/form-data` with `audio` (wav or webm, max 15 s).
Response: `{ "transcript": string, "confidence": number, "meta": {...} }`.

If Section 4 chooses on-device speech recognition (`SFSpeechRecognizer` / `SpeechAnalyzer`)
instead, this endpoint is removed and the decision is noted in `docs/status.md`.

## Mocking for the iOS app

Section 2 ships `apps/ios/PackFit/API/MockAPIClient.swift` conforming to the same
`APIClient` protocol as `LiveAPIClient`, with canned responses built from
`schemas/fixtures/` via `PackFitSchemas.Fixtures`. A `MOCK_API` flag in `Config.xcconfig`
(and a debug-menu toggle) selects it. The demo must still run end-to-end in mock mode
(offline sample trip).
