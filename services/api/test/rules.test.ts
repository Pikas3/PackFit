import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { checkRules } from "../src/services/rules.js";
import { findCandidatesForItem, upperBoundMl } from "../src/rules/store.js";
import type { Item } from "../src/schemas.js";

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "../../../schemas/fixtures");
const items = (JSON.parse(readFileSync(join(fixtures, "items.json"), "utf8")) as (Item & { _source?: string })[]).map(
  ({ _source, ...rest }) => rest as Item,
);
const byName = (pattern: RegExp) => {
  const hit = items.find((i) => pattern.test(i.name));
  if (!hit) throw new Error(`no fixture matching ${pattern}`);
  return hit;
};
const ua = { from: "SFO", to: "DEL", airline: "UA" };

function item(overrides: Partial<Item>): Item {
  return { ...byName(/T-shirts/), id: "test-item", ...overrides };
}

describe("rules: flag only real violations", () => {
  beforeAll(() => {
    process.env.MOCK_CLAUDE = "1";
  });

  it("does not flag clothing, shoes or a laptop on a checked bag", async () => {
    const quiet = [byName(/T-shirts/), byName(/Running shoes/), byName(/Laptop/), byName(/Hoodie/)];
    const res = await checkRules({ items: quiet, trip: ua, bag: "checked" });
    expect(res.flags).toEqual([]);
  });

  it("does not give a toothbrush kit the liquids rule", () => {
    const kit = byName(/Toothbrush/);
    expect(findCandidatesForItem(kit, ua, "carryOn").map((r) => r.ruleId)).not.toContain("tsa:liquids-100ml");
  });

  it("flags full-size liquids in carry-on only", async () => {
    const big = item({ name: "Shampoo 500 ml", category: "liquids" });
    const small = item({ id: "small", name: "Shampoo 50 ml", category: "liquids" });
    const carry = await checkRules({ items: [big, small], trip: ua, bag: "carryOn" });
    expect(carry.flags.map((f) => [f.itemId, f.ruleId])).toEqual([["test-item", "tsa:liquids-100ml"]]);
    const checked = await checkRules({ items: [big], trip: ua, bag: "checked" });
    expect(checked.flags).toEqual([]);
  });

  it("treats drinks as liquids even when filed under food", async () => {
    const drink = item({ id: "drink", name: "Large energy drink", category: "food", w: 7, h: 17, d: 7 });
    const juice = item({ id: "juice", name: "Orange juice", category: "food", w: 6, h: 15, d: 6 });
    const carry = await checkRules({ items: [drink, juice], trip: ua, bag: "carryOn" });
    expect(carry.flags.filter((f) => f.ruleId === "tsa:liquids-100ml").map((f) => f.itemId).sort()).toEqual(["drink", "juice"]);
  });

  it("does not treat drink-free names as liquids", () => {
    const jacket = item({ name: "Waterproof jacket", category: "clothing" });
    const bottle = item({ name: "Drinking straw set", category: "other", w: 2, h: 20, d: 2 });
    for (const thing of [jacket, bottle]) {
      expect(findCandidatesForItem(thing, ua, "carryOn").map((r) => r.ruleId)).not.toContain("tsa:liquids-100ml");
    }
  });

  it("knife flags in carry-on, power bank flags in checked", async () => {
    const knife = byName(/Pocket knife/);
    const bank = byName(/Power bank/);
    const carry = await checkRules({ items: [knife, bank], trip: ua, bag: "carryOn" });
    expect(carry.flags.map((f) => [f.itemId, f.severity])).toEqual([[knife.id, "banned"]]);
    const checked = await checkRules({ items: [knife, bank], trip: ua, bag: "checked" });
    expect(checked.flags.map((f) => [f.itemId, f.severity])).toEqual([[bank.id, "banned"]]);
  });

  it("checks weight once for the whole bag, only when over the limit", async () => {
    const under = await checkRules({ items: [byName(/Jeans/), byName(/Hoodie/)], trip: ua, bag: "checked" });
    expect(under.flags.filter((f) => f.itemId === "bag")).toEqual([]);

    const heavy = [item({ id: "a", kg: 12 }), item({ id: "b", kg: 12 })];
    const over = await checkRules({ items: heavy, trip: ua, bag: "checked" });
    const bagFlags = over.flags.filter((f) => f.itemId === "bag");
    expect(bagFlags).toHaveLength(1);
    expect(bagFlags[0]?.ruleId).toBe("airline:ua-checked-23kg");
    expect(bagFlags[0]?.sourceUrl).toMatch(/^https:\/\//);
    expect(over.flags.every((f) => f.itemId === "bag")).toBe(true);

    const carry = await checkRules({ items: heavy, trip: ua, bag: "carryOn" });
    expect(carry.flags).toEqual([]);
  });

  it("reads the stated volume from the name", () => {
    expect(upperBoundMl(item({ name: "Perfume 100 ml, boxed" }))).toBe(100);
    expect(upperBoundMl(item({ name: "Lotion 3.4 oz" }))).toBe(100);
    expect(upperBoundMl(item({ name: "Lotion", w: 2, h: 5, d: 5 }))).toBe(50);
  });
});
