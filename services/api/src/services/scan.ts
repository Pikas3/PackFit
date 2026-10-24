import { randomUUID } from "node:crypto";
import { z } from "zod";
import { callClaudeTool } from "../claude/client.js";
import {
  ScanEstimateToolSchema,
  ScanMeasuredToolSchema,
  attachImage,
  buildScanItemPrompt,
} from "../claude/prompts/scanItem.js";
import type { Item, Category } from "../schemas.js";
import { catalogFor } from "./catalog.js";

export type ScanInput = {
  imageBase64: string;
  measured: {
    w: number;
    h: number;
    d: number;
    method: "lidar" | "reference" | "manual";
    confidence: number;
  } | null;
  reference?: "credit_card" | "a4_paper" | "letter_paper" | null;
  hint?: string;
};

export type ScanResult = {
  item: Item;
  alternatives: { name: string; category: Category }[];
  warnings: string[];
};

function clampKg(kg: number, category: Category, warnings: string[]): number {
  if (!Number.isFinite(kg) || kg < 0.01 || kg > 30) {
    warnings.push("kg_from_catalog");
    return catalogFor(category).kg;
  }
  return kg;
}

function clampEstimatedDims(
  w: number,
  h: number,
  d: number,
  category: Category,
  warnings: string[],
): { w: number; h: number; d: number } {
  const ok = (n: number) => Number.isFinite(n) && n >= 0.5 && n <= 200;
  if (!ok(w) || !ok(h) || !ok(d)) {
    warnings.push("dims_from_catalog");
    const c = catalogFor(category);
    return { w: c.w, h: c.h, d: c.d };
  }
  return { w, h, d };
}

function mockScan(input: ScanInput) {
  const category: Category = input.hint?.toLowerCase().includes("knife")
    ? "sharp"
    : input.hint?.toLowerCase().includes("shampoo")
      ? "liquids"
      : "electronics";
  const c = catalogFor(category);
  if (input.measured) {
    return {
      name: input.hint?.trim() || "Scanned item",
      category,
      kg: c.kg,
      fragile: c.fragile,
      soft: c.soft,
      hardness: c.hardness,
      upright: c.upright,
      // Identification confidence is visual, not measurement confidence.
      confidence: 0.85,
      neededAtSecurity: category === "electronics",
      alternatives: [
        { name: "Similar item", category },
        { name: "Travel accessory", category: "other" as const },
      ],
    };
  }
  return {
    name: input.hint?.trim() || "Estimated item",
    category,
    w: c.w,
    h: c.h,
    d: c.d,
    kg: c.kg,
    fragile: c.fragile,
    soft: c.soft,
    hardness: c.hardness,
    upright: c.upright,
    confidence: 0.65,
    alternatives: [
      { name: "Similar item", category },
      { name: "Travel accessory", category: "other" as const },
    ],
  };
}

export async function scanItem(input: ScanInput): Promise<ScanResult> {
  const warnings: string[] = [];
  const basePrompt = buildScanItemPrompt({
    measured: input.measured,
    reference: input.reference,
    hint: input.hint,
  });
  // Strip data-url prefix if present.
  const imageBase64 = input.imageBase64.replace(/^data:image\/\w+;base64,/, "");
  const prompt = attachImage(basePrompt, imageBase64);

  if (input.measured) {
    // Object detection from the image only; measured w/h/d are for packing, not the prompt.
    const { data } = await callClaudeTool({
      prompt,
      schema: ScanMeasuredToolSchema,
      mock: () => mockScan(input) as z.infer<typeof ScanMeasuredToolSchema>,
    });
    const category = data.category;
    const cat = catalogFor(category);
    const item: Item = {
      id: randomUUID(),
      name: data.name,
      w: input.measured.w,
      h: input.measured.h,
      d: input.measured.d,
      kg: clampKg(data.kg, category, warnings),
      fragile: data.fragile ?? cat.fragile,
      hardness: Number.isFinite(data.hardness) ? data.hardness : cat.hardness,
      soft: data.soft ?? cat.soft,
      upright: data.upright ?? cat.upright,
      category,
      confidence: Math.min(1, Math.max(0, data.confidence)),
      neededAtSecurity: data.neededAtSecurity,
      source: "scan",
      measurement: {
        method: input.measured.method,
        confidence: input.measured.confidence,
        deviceHasLidar: input.measured.method === "lidar",
      },
    };
    return { item, alternatives: data.alternatives, warnings };
  }

  const { data } = await callClaudeTool({
    prompt,
    schema: ScanEstimateToolSchema,
    mock: () => mockScan(input) as z.infer<typeof ScanEstimateToolSchema>,
  });

  if (!input.reference) warnings.push("no_scale_reference");
  const category = data.category;
  const cat = catalogFor(category);
  const dims = clampEstimatedDims(data.w, data.h, data.d, category, warnings);
  const confidenceCap = input.reference ? 0.7 : 0.5;
  const item: Item = {
    id: randomUUID(),
    name: data.name,
    w: dims.w,
    h: dims.h,
    d: dims.d,
    kg: clampKg(data.kg, category, warnings),
    fragile: data.fragile ?? cat.fragile,
    hardness: Number.isFinite(data.hardness) ? data.hardness : cat.hardness,
    soft: data.soft ?? cat.soft,
    upright: data.upright ?? cat.upright,
    category,
    confidence: Math.min(confidenceCap, Math.max(0, data.confidence)),
    neededAtSecurity: data.neededAtSecurity,
    source: "scan",
    measurement: {
      method: "estimate",
      confidence: Math.min(confidenceCap, Math.max(0, data.confidence)),
      deviceHasLidar: false,
    },
  };
  return { item, alternatives: data.alternatives, warnings };
}
