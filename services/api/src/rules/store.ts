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

/** Country customs tips for the Before You Go panel (from cached rule fixtures). */
export function loadCountryTips(
  country: string | undefined,
): Array<{ text: string; sourceUrl: string; lastVerified: string }> {
  if (!country) return [];
  return loadAll()
    .filter((r) => r.scope === "country" && r.subject === country)
    .map((r) => ({ text: r.text, sourceUrl: r.sourceUrl, lastVerified: r.lastVerified }));
}

/** Categories that are themselves the hazard, so a category match is enough to flag. */
const HAZARD_CATEGORIES: ReadonlySet<Category> = new Set(["liquids", "sharp"]);

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Whole-word keyword hit, so "jam" does not match "pajamas". */
export function nameMatchesKeyword(name: string, keyword: string): boolean {
  return new RegExp(`\\b${escapeRegex(keyword.toLowerCase())}\\b`).test(name.toLowerCase());
}

export function bagVerdict(record: RuleRecord, bag: "carryOn" | "checked"): RuleRecord["carryOn"] {
  return bag === "carryOn" ? record.carryOn : record.checked;
}

/**
 * True only when this item, in this bag, breaks the rule. Advisory rules (verdict "ok"),
 * bag-level weight rules, loose category matches and items measurably under a limit never
 * flag.
 */
export function violates(item: Item, record: RuleRecord, bag: "carryOn" | "checked"): boolean {
  if (record.limits?.maxKg !== undefined) return false;
  if (bagVerdict(record, bag) === "ok") return false;
  const keywordHit = record.keywords.some((kw) => nameMatchesKeyword(item.name, kw));
  const hazardHit =
    HAZARD_CATEGORIES.has(item.category as Category) && record.categories.includes(item.category as Category);
  if (!keywordHit && !hazardHit) return false;
  const maxMl = record.limits?.maxMl;
  if (bagVerdict(record, bag) === "restricted" && maxMl !== undefined && upperBoundMl(item) <= maxMl) {
    return false;
  }
  return true;
}

/**
 * Most the item can hold: the volume written on it ("400 ml", "3.4 oz") when the name says,
 * else the bounding box, which always holds at least as much as the container inside it.
 */
export function upperBoundMl(item: Item): number {
  const name = item.name.toLowerCase();
  const ml = name.match(/(\d+(?:\.\d+)?)\s*ml\b/);
  if (ml) return Number(ml[1]);
  const oz = name.match(/(\d+(?:\.\d+)?)\s*(?:fl\.?\s*)?oz\b/);
  // TSA treats 3.4 oz as 100 ml, so round down.
  if (oz) return Math.floor(Number(oz[1]) * 29.5735);
  return item.w * item.h * item.d;
}

/** Rules this item breaks in this bag, best match first. */
export function findCandidatesForItem(
  item: Item,
  trip: { from: string; to: string; airline: string },
  bag: "carryOn" | "checked",
  limit = 8,
): RuleRecord[] {
  const destCountry = countryForAirport(trip.to) ?? "";
  const scored: { record: RuleRecord; score: number }[] = [];

  for (const record of loadAll()) {
    if (record.scope === "airline" && record.subject !== trip.airline) continue;
    if (record.scope === "country" && record.subject !== destCountry) continue;
    if (!violates(item, record, bag)) continue;

    let score = 0;
    if (record.categories.includes(item.category as Category)) score += 2;
    for (const kw of record.keywords) {
      if (nameMatchesKeyword(item.name, kw)) score += 3;
    }
    if (bagVerdict(record, bag) === "banned") score += 1;
    scored.push({ record, score });
  }

  scored.sort((a, b) => b.score - a.score || a.record.ruleId.localeCompare(b.record.ruleId));
  return scored.slice(0, limit).map((s) => s.record);
}

/** The airline's checked-bag weight rule, if we have one. */
export function weightRuleForAirline(airline: string): RuleRecord | undefined {
  return loadAll().find(
    (r) => r.scope === "airline" && r.subject === airline && r.limits?.maxKg !== undefined,
  );
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
