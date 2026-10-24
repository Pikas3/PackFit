#!/bin/sh
# Copies the backend's rule records and airport countries into the app bundle, so the
# on-device rule check (offline fallback) uses the same data as /rules/check.
set -e
cd "$(dirname "$0")/../../.."
python3 - <<'PY'
import json
rules = []
for f in ["tsa", "airline", "country"]:
    rules += json.load(open(f"services/api/data/rules/{f}.json"))
json.dump({"_source": "Copied from services/api/data/rules/*.json; regenerate with apps/ios/scripts/sync-rules.sh", "rules": rules},
          open("apps/ios/PackFit/Resources/rules.json", "w"), indent=1)
airports = json.load(open("services/api/data/airports.json"))
json.dump({k: v["country"] for k, v in sorted(airports.items())}, open("apps/ios/PackFit/Resources/airport_countries.json", "w"))
print(f"{len(rules)} rules, {len(airports)} airports")
PY
