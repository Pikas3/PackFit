/**
 * Normalize raw Apify actor dataset items into PackFit RuleRecords.
 * Keep in sync with `services/api/src/rules/normalize.ts`.
 */

export type RawActorItem = Record<string, unknown>;

export interface NormalizedRule {
  ruleId: string;
  scope: "tsa" | "airline" | "country";
  subject: string;
  keywords: string[];
  categories: string[];
  severity: "banned" | "restricted" | "check";
  carryOn: "ok" | "restricted" | "banned";
  checked: "ok" | "restricted" | "banned";
  text: string;
  sourceUrl: string;
  lastVerified: string;
  limits?: { maxCm?: [number, number, number]; maxKg?: number; maxWh?: number; maxMl?: number };
}

function asString(v: unknown, fallback = ""): string {
  return typeof v === "string" ? v : fallback;
}

function asVerdict(v: unknown): "ok" | "restricted" | "banned" {
  const s = asString(v, "ok").toLowerCase();
  if (s.includes("ban") || s === "no") return "banned";
  if (s.includes("restrict") || s.includes("limit") || s === "yes_with_limits") return "restricted";
  return "ok";
}

function severityFrom(carryOn: string, checked: string): "banned" | "restricted" | "check" {
  if (carryOn === "banned" || checked === "banned") return "banned";
  if (carryOn === "restricted" || checked === "restricted") return "restricted";
  return "check";
}

function slug(parts: string[]): string {
  return parts
    .join(":")
    .toLowerCase()
    .replace(/[^a-z0-9:.-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

export function normalizeActorItems(items: RawActorItem[]): NormalizedRule[] {
  const out: NormalizedRule[] = [];
  const today = new Date().toISOString().slice(0, 10);

  for (const raw of items) {
    const scope = asString(raw.scope || raw.kind, "tsa") as NormalizedRule["scope"];
    if (!["tsa", "airline", "country"].includes(scope)) continue;

    const name = asString(raw.name || raw.itemName || raw.title, "item");
    const subject = asString(raw.subject || raw.airline || raw.country || "all", "all").toUpperCase();
    const sourceUrl = asString(raw.sourceUrl || raw.url || raw.pageUrl);
    if (!/^https?:\/\//.test(sourceUrl)) continue;

    const carryOn = asVerdict(raw.carryOn ?? raw.carry_on ?? raw.cabin);
    const checked = asVerdict(raw.checked ?? raw.checkedBag ?? raw.hold);
    const keywords = Array.isArray(raw.keywords)
      ? raw.keywords.map((k) => String(k).toLowerCase())
      : name
          .toLowerCase()
          .split(/[^a-z0-9]+/)
          .filter((w) => w.length > 2);

    const categories = Array.isArray(raw.categories) ? raw.categories.map(String) : ["other"];

    out.push({
      ruleId: asString(raw.ruleId) || slug([scope, subject === "ALL" ? "all" : subject, name]),
      scope,
      subject: subject === "ALL" ? "all" : subject,
      keywords,
      categories,
      severity: (asString(raw.severity) as NormalizedRule["severity"]) || severityFrom(carryOn, checked),
      carryOn,
      checked,
      text: asString(raw.text || raw.description || raw.summary, name).trim(),
      sourceUrl,
      lastVerified: asString(raw.lastVerified || raw.scrapedAt, today).slice(0, 10),
      limits: typeof raw.limits === "object" && raw.limits ? (raw.limits as NormalizedRule["limits"]) : undefined,
    });
  }

  return out;
}
