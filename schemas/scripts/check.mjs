// Validates schemas/fixtures/** against schemas/*.schema.json.
// Run via `pnpm schemas:check` (which also runs the Swift decode test).
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const fixtures = join(root, "fixtures");
const read = (p) => JSON.parse(readFileSync(p, "utf8"));
const BASE = "https://snugly.local/schemas/";

const ajv = new Ajv2020({ allErrors: true, strict: true });
for (const f of readdirSync(root).filter((f) => f.endsWith(".schema.json"))) {
  ajv.addSchema(read(join(root, f)));
}

const errors = [];
const fail = (msg) => errors.push(msg);

function validate(ref, data, label) {
  const v = ajv.getSchema(BASE + ref);
  if (!v) throw new Error(`schema not found: ${ref}`);
  if (!v(data)) {
    for (const e of v.errors) fail(`${label}${e.instancePath} ${e.message} ${JSON.stringify(e.params)}`);
  }
}

const stripSource = ({ _source, ...rest }) => rest;

// 1. Fixture files against their fixture shapes.
const items = read(join(fixtures, "items.json"));
const containers = read(join(fixtures, "containers.json"));
const trips = read(join(fixtures, "trips.json"));
const packLists = read(join(fixtures, "packlists.json"));
validate("fixtures.schema.json#/$defs/itemsFile", items, "items.json");
validate("fixtures.schema.json#/$defs/containersFile", containers, "containers.json");
validate("fixtures.schema.json#/$defs/tripsFile", trips, "trips.json");
validate("fixtures.schema.json#/$defs/packListsFile", packLists, "packlists.json");

// 2. Fixture objects minus _source must be valid base objects.
items.forEach((it, i) => validate("item.schema.json", stripSource(it), `items.json/${i}`));
containers.forEach((c, i) => validate("container.schema.json", stripSource(c), `containers.json/${i}`));

// 3. Fixture shapes must list exactly the base properties plus _source.
const fx = read(join(root, "fixtures.schema.json")).$defs;
for (const [fixtureDef, baseFile] of [["fixtureItem", "item"], ["fixtureContainer", "container"]]) {
  const base = read(join(root, `${baseFile}.schema.json`));
  const want = [...Object.keys(base.properties), "_source"].sort().join(",");
  const got = Object.keys(fx[fixtureDef].properties).sort().join(",");
  if (want !== got) fail(`fixtures.schema.json ${fixtureDef} properties drifted from ${baseFile}.schema.json: ${got} != ${want}`);
  const wantReq = [...base.required, "_source"].sort().join(",");
  if (wantReq !== [...fx[fixtureDef].required].sort().join(",")) fail(`fixtures.schema.json ${fixtureDef} required drifted`);
}

// 4. Coverage required by docs/contracts.md.
if (items.length !== 25) fail(`items.json has ${items.length} items, want 25`);
const categories = read(join(root, "item.schema.json")).$defs.category.enum;
for (const c of categories) if (!items.some((i) => i.category === c)) fail(`items.json: no item with category ${c}`);
const count = (pred) => items.filter(pred).length;
if (count((i) => i.fragile) < 3) fail("items.json: fewer than 3 fragile items");
if (count((i) => i.soft) < 5) fail("items.json: fewer than 5 soft items");
if (count((i) => i.upright) < 2) fail("items.json: fewer than 2 upright items");
if (count((i) => i.neededAtSecurity) < 3) fail("items.json: fewer than 3 neededAtSecurity items");
if (new Set(items.map((i) => i.id)).size !== items.length) fail("items.json: duplicate ids");
if (containers.length !== 3) fail(`containers.json has ${containers.length} containers, want 3`);
if (trips.length !== 5) fail(`trips.json has ${trips.length} trips, want 5`);
if (!trips.some((t) => t.from === "SFO" && t.to === "DEL" && t.checked.weightLimitKg === 23)) fail("trips.json: missing SFO->DEL on 23 kg");

// 5. Referential integrity and pre-computed plans.
const itemIds = new Set(items.map((i) => i.id));
const tripIds = new Set(trips.map((t) => t.id));
if (tripIds.size !== trips.length) fail("trips.json: duplicate ids");
const planFiles = new Set(readdirSync(join(fixtures, "plans")).filter((f) => f.endsWith(".json")));
for (const pl of packLists) {
  const name = `${pl.tripId}-${pl.bag}`;
  if (!tripIds.has(pl.tripId)) fail(`packlists.json ${name}: unknown trip`);
  for (const id of pl.itemIds) if (!itemIds.has(id)) fail(`packlists.json ${name}: unknown item ${id}`);
  if (!planFiles.has(`${name}.json`)) {
    fail(`plans/${name}.json missing; run: swift run --package-path Packages/Packer GenPlans`);
    continue;
  }
  planFiles.delete(`${name}.json`);
  const plan = read(join(fixtures, "plans", `${name}.json`));
  validate("plan.schema.json", plan, `plans/${name}.json`);
  const covered = [...plan.placed.map((p) => p.itemId), ...plan.unplaced].sort();
  if (covered.join(",") !== [...pl.itemIds].sort().join(",")) fail(`plans/${name}.json: placed + unplaced != packlist items`);
}
for (const f of planFiles) fail(`plans/${f}: no matching packlist entry`);

if (errors.length) {
  console.error(`schemas:check FAILED (${errors.length})`);
  for (const e of errors) console.error("  " + e);
  process.exit(1);
}
console.log(`schemas:check ok: ${items.length} items, ${containers.length} containers, ${trips.length} trips, ${packLists.length} plans`);
