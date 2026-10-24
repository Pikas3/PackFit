import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { ApifyClient } from "apify-client";
import { env } from "../env.js";
import { RuleRecordSchema } from "../schemas.js";
import { normalizeActorItems } from "./normalize.js";
import { reloadRules, setRulesLastSynced } from "./store.js";

const rulesDir = join(dirname(fileURLToPath(import.meta.url)), "../../data/rules");

const ACTORS: { id: string; scopeFile: string }[] = [
  { id: process.env.APIFY_ACTOR_TSA ?? "packfit/tsa-what-can-i-bring", scopeFile: "tsa.json" },
  { id: process.env.APIFY_ACTOR_AIRLINE ?? "packfit/airline-baggage", scopeFile: "airline.json" },
  { id: process.env.APIFY_ACTOR_COUNTRY ?? "packfit/country-customs", scopeFile: "country.json" },
];

/** Pull latest successful Apify runs into data/rules. Keeps last-good files on failure. */
export async function syncRulesFromApify(): Promise<{ ok: boolean; syncedAt: string | null; errors: string[] }> {
  const errors: string[] = [];
  if (!env.apifyToken) {
    return { ok: false, syncedAt: null, errors: ["APIFY_TOKEN missing; kept committed rules"] };
  }

  const client = new ApifyClient({ token: env.apifyToken, timeoutSecs: 5 });
  mkdirSync(rulesDir, { recursive: true });
  let newest: string | null = null;

  for (const actor of ACTORS) {
    const previousPath = join(rulesDir, actor.scopeFile);
    try {
      const runs = await client.actor(actor.id).runs().list({ status: "SUCCEEDED", limit: 1, desc: true });
      const run = runs.items[0];
      if (!run?.defaultDatasetId) {
        errors.push(`${actor.id}: no successful run`);
        continue;
      }
      const { items } = await client.dataset(run.defaultDatasetId).listItems({ limit: 5000 });
      const normalized = normalizeActorItems(items as Record<string, unknown>[]);
      const valid = normalized
        .map((r) => RuleRecordSchema.safeParse(r))
        .filter((r) => r.success)
        .map((r) => r.data);

      if (valid.length === 0) {
        errors.push(`${actor.id}: zero valid records after normalize`);
        continue;
      }

      writeFileSync(previousPath, JSON.stringify(valid, null, 2) + "\n");
      for (const r of valid) {
        if (!newest || r.lastVerified > newest) newest = r.lastVerified;
      }
    } catch (err) {
      errors.push(`${actor.id}: ${err instanceof Error ? err.message : String(err)}`);
      void existsSync(previousPath);
    }
  }

  reloadRules();
  const syncedAt = newest ? `${newest}T04:00:00Z` : null;
  if (syncedAt) setRulesLastSynced(syncedAt);
  return { ok: errors.length === 0, syncedAt, errors };
}

const isMain =
  process.argv[1] &&
  fileURLToPath(import.meta.url) === join(process.argv[1]);

if (isMain) {
  syncRulesFromApify().then((r) => {
    console.log(r);
    process.exit(r.ok ? 0 : 1);
  });
}
