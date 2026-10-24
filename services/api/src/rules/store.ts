import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  Category,
  Item,
  RuleRecord,
  RuleRecordSchema,
} from "../schemas.js";
import airports from "../../data/airports.json" with { type: "json" };

const root = join(dirname(fileURLToPath(import.meta.url)), "../../data/rules");

type Airport = { lat: number; lon: number; country: string; name: string };
const airportMap = airports as Record<string, Airport>;

let cache: RuleRecord[] | null = null;
let rulesLastSynced: string | null = null;

function loadAll(): RuleRecord[] {
  if (cache) return cache;
  const records: RuleRecord[] = [];
  if (!existsSync(root)) {
    cache = records;
    return records;
  }
  let newest: string | null = null;
  for (const file of readdirSync(root).filter((f) => f.endsWith(".json"))) {
    const raw = JSON.parse(readFileSync(join(root, file), "utf8")) as unknown;
    if (!Array.isArray(raw)) continue;
    for (const row of raw) {
      const parsed = RuleRecordSchema.safeParse(row);
      if (parsed.success) {
        records.push(parsed.data);
        if (!newest || parsed.data.lastVerified > newest) newest = parsed.data.lastVerified;
      } else {
        console.warn("skip invalid rule", file, parsed.error.message);
      }
    }
  }
  cache = records;
  rulesLastSynced = newest ? `${newest}T04:00:00Z` : null;
  return records;
}

export function getRulesLastSynced(): string | null {
  loadAll();
  return rulesLastSynced;
}

export function setRulesLastSynced(iso: string | null) {
  rulesLastSynced = iso;
}

export function reloadRules() {
  cache = null;
  loadAll();
}

export function countryForAirport(iata: string): string | undefined {
  return airportMap[iata]?.country;
}

export function airportCoords(iata: string): { lat: number; lon: number } | undefined {
  const a = airportMap[iata];
  return a ? { lat: a.lat, lon: a.lon } : undefined;
}

export function findCandidatesForItem(
  item: Item,
  trip: { from: string; to: string; airline: string },
  bag: "carryOn" | "checked",
  limit = 8,
): RuleRecord[] {
  const destCountry = countryForAirport(trip.to) ?? "";
  const name = item.name.toLowerCase();
  const scored: { record: RuleRecord; score: number }[] = [];

  for (const record of loadAll()) {
    if (record.scope === "airline" && record.subject !== trip.airline) continue;
    if (record.scope === "country" && record.subject !== destCountry) continue;

    const bagVerdict = bag === "carryOn" ? record.carryOn : record.checked;
    if (bagVerdict === "ok" && record.severity === "check" && record.scope !== "tsa") {
      // still allow "check" guidance
    }

    let score = 0;
    if (record.categories.includes(item.category as Category)) score += 2;
    for (const kw of record.keywords) {
      if (name.includes(kw)) score += 3;
    }
    if (score === 0) continue;

    // Prefer rules that actually restrict this bag.
    if (bagVerdict !== "ok") score += 1;
    scored.push({ record, score });
  }

  scored.sort((a, b) => b.score - a.score || a.record.ruleId.localeCompare(b.record.ruleId));
  return scored.slice(0, limit).map((s) => s.record);
}

export function findCandidatesForQuestion(
  question: string,
  trip: { from: string; to: string; airline: string },
  bag: "carryOn" | "checked",
  limit = 8,
): RuleRecord[] {
  const destCountry = countryForAirport(trip.to) ?? "";
  const q = question.toLowerCase();
  const scored: { record: RuleRecord; score: number }[] = [];

  for (const record of loadAll()) {
    if (record.scope === "airline" && record.subject !== trip.airline) continue;
    if (record.scope === "country" && record.subject !== destCountry) continue;

    let score = 0;
    for (const kw of record.keywords) {
      if (q.includes(kw)) score += 3;
    }
    for (const cat of record.categories) {
      if (q.includes(cat)) score += 1;
    }
    if (score === 0) continue;
    const bagVerdict = bag === "carryOn" ? record.carryOn : record.checked;
    if (bagVerdict !== "ok") score += 1;
    scored.push({ record, score });
  }

  scored.sort((a, b) => b.score - a.score || a.record.ruleId.localeCompare(b.record.ruleId));
  return scored.slice(0, limit).map((s) => s.record);
}

export function recordById(ruleId: string): RuleRecord | undefined {
  return loadAll().find((r) => r.ruleId === ruleId);
}
