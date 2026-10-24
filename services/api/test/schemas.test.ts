import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";
import { describe, expect, it } from "vitest";
import {
  ContainerSchema,
  ItemSchema,
  PlanSchema,
  RuleFlagSchema,
  TripSchema,
} from "../src/schemas.js";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../../schemas");
const fixtures = join(root, "fixtures");
const read = (p: string) => JSON.parse(readFileSync(p, "utf8"));
const BASE = "https://packfit.local/schemas/";

describe("zod + ajv fixture validation", () => {
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  for (const f of readdirSync(root).filter((f) => f.endsWith(".schema.json"))) {
    ajv.addSchema(read(join(root, f)));
  }

  const stripSource = ({ _source, ...rest }: { _source?: string }) => rest;

  it("validates items with zod and ajv", () => {
    const items = read(join(fixtures, "items.json")) as Record<string, unknown>[];
    expect(items).toHaveLength(25);
    for (const raw of items) {
      const item = stripSource(raw as { _source?: string });
      expect(ItemSchema.safeParse(item).success).toBe(true);
      const v = ajv.getSchema(BASE + "item.schema.json");
      expect(v?.(item)).toBe(true);
    }
  });

  it("validates containers, trips, plans", () => {
    const containers = read(join(fixtures, "containers.json")) as Record<string, unknown>[];
    for (const raw of containers) {
      expect(ContainerSchema.safeParse(stripSource(raw as { _source?: string })).success).toBe(true);
    }
    const trips = read(join(fixtures, "trips.json")) as unknown[];
    for (const t of trips) {
      expect(TripSchema.safeParse(t).success).toBe(true);
    }
    for (const f of readdirSync(join(fixtures, "plans")).filter((n) => n.endsWith(".json"))) {
      const plan = read(join(fixtures, "plans", f));
      expect(PlanSchema.safeParse(plan).success).toBe(true);
    }
  });

  it("rule flag shape", () => {
    const flag = {
      itemId: "x",
      scope: "tsa",
      severity: "banned",
      text: "no",
      sourceUrl: "https://example.com/a",
      lastVerified: "2026-10-01",
    };
    expect(RuleFlagSchema.safeParse(flag).success).toBe(true);
  });
});
