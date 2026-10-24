import { describe, expect, it } from "vitest";
import { buildAskRulePrompt } from "../src/claude/prompts/askRule.js";
import { buildMapRulesPrompt } from "../src/claude/prompts/mapRules.js";
import {
  buildScanItemPrompt,
  measuredPromptUserText,
  scanToolHasSchema,
} from "../src/claude/prompts/scanItem.js";
import { buildSuggestItemsPrompt } from "../src/claude/prompts/suggestItems.js";
import type { Item, Trip } from "../src/schemas.js";

const sampleItem: Item = {
  id: "i1",
  name: "Shampoo 400 ml",
  w: 6,
  h: 18,
  d: 6,
  kg: 0.4,
  fragile: false,
  hardness: 0.5,
  soft: false,
  upright: true,
  category: "liquids",
  confidence: 1,
};

const sampleTrip = {
  from: "SFO",
  to: "DEL",
  airline: "UA",
  nights: 14,
  activities: ["home"],
  carryOn: {
    id: "c",
    name: "carry",
    type: "suitcase" as const,
    outer: [55, 23, 40] as [number, number, number],
    compartments: [{ name: "main", dims: [52, 20, 37] as [number, number, number], compressibility: 0.1 }],
    weightLimitKg: 7,
  },
  checked: {
    id: "k",
    name: "checked",
    type: "suitcase" as const,
    outer: [75, 30, 50] as [number, number, number],
    compartments: [{ name: "main", dims: [72, 27, 47] as [number, number, number], compressibility: 0.1 }],
    weightLimitKg: 23,
  },
} satisfies Trip;

describe("prompts include tool schemas", () => {
  it("scan measured + estimate", () => {
    const measured = buildScanItemPrompt({
      measured: { w: 10, h: 2, d: 8, method: "lidar", confidence: 0.9 },
    });
    expect(scanToolHasSchema(measured)).toBe(true);
    const estimate = buildScanItemPrompt({ measured: null, reference: "credit_card" });
    expect(scanToolHasSchema(estimate)).toBe(true);
  });

  it("measured path is object detection: no numeric dims in the prompt", () => {
    const measured = buildScanItemPrompt({
      measured: { w: 30.2, h: 1.8, d: 21.4, method: "lidar", confidence: 0.93 },
    });
    const text = `${measured.system}\n${measuredPromptUserText(measured)}`;
    expect(text.toLowerCase()).toMatch(/object-detection/);
    expect(text).not.toMatch(/30\.2|1\.8|21\.4/);
    expect(text).not.toMatch(/w=\d|h=\d|d=\d/);
    const schema = measured.tools[0]?.input_schema as { properties?: Record<string, unknown> };
    expect(schema.properties?.w).toBeUndefined();
    expect(schema.properties?.h).toBeUndefined();
    expect(schema.properties?.d).toBeUndefined();
    expect(schema.properties?.dimsPlausible).toBeUndefined();
  });

  it("map / ask / suggest", () => {
    const map = buildMapRulesPrompt({
      items: [sampleItem],
      bag: "carryOn",
      candidatesByItem: { i1: [] },
    });
    expect(map.tools[0]?.input_schema).toBeTruthy();

    const ask = buildAskRulePrompt({
      question: "can I bring a power bank",
      bag: "carryOn",
      candidates: [],
    });
    expect(ask.tools[0]?.input_schema).toBeTruthy();

    const suggest = buildSuggestItemsPrompt({
      trip: sampleTrip,
      weatherSummary: "mild",
    });
    expect(suggest.tools[0]?.input_schema).toBeTruthy();
  });
});
