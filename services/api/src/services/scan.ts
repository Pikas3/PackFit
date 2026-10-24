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
import {
  ScanInventoryToolSchema,
  UNKNOWN_SIZE_GRID,
  buildScanInventoryPrompt,
  type PixelBox,
  type ScanInventoryTool,
} from "../claude/prompts/scanInventory.js";
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

export type InventoryResult = {
  reference: { box: { x: number; y: number; w: number; h: number } } | null;
  detections: {
    item: Item;
    box: { x: number; y: number; w: number; h: number } | null;
    alternatives: { name: string; category: Category }[];
    shape: "box" | "cylinder_upright" | "cylinder_lying" | null;
  }[];
  warnings: string[];
};

/** Claude's pixel corners as a normalized box, clamped to the photo. */
function normalizeBox(box: PixelBox | null | undefined, size: { width: number; height: number }) {
  if (!box) return null;
  const c = (n: number) => (Number.isFinite(n) ? Math.min(1, Math.max(0, n)) : 0);
  const x0 = c(Math.min(box.x0, box.x1) / size.width);
  const x1 = c(Math.max(box.x0, box.x1) / size.width);
  const y0 = c(Math.min(box.y0, box.y1) / size.height);
  const y1 = c(Math.max(box.y0, box.y1) / size.height);
  const w = x1 - x0;
  const h = y1 - y0;
  return w > 0.005 && h > 0.005 ? { x: x0, y: y0, w, h } : null;
}

/** Width and height from a JPEG's frame header; null when it is not a JPEG we can read. */
export function jpegSize(bytes: Buffer): { width: number; height: number } | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let i = 2;
  while (i + 9 < bytes.length) {
    if (bytes[i] !== 0xff) return null;
    const marker = bytes[i + 1] ?? 0;
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      i += 2;
      continue;
    }
    const length = bytes.readUInt16BE(i + 2);
    // SOF0-SOF15 except DHT (C4), JPG (C8) and DAC (CC) carry the frame size.
    if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      const height = bytes.readUInt16BE(i + 5);
      const width = bytes.readUInt16BE(i + 7);
      return width > 0 && height > 0 ? { width, height } : null;
    }
    i += 2 + length;
  }
  return null;
}

function mockInventory(size: { width: number; height: number }): ScanInventoryTool {
  const pixels = (b: { x: number; y: number; w: number; h: number }) => ({
    x0: b.x * size.width,
    y0: b.y * size.height,
    x1: (b.x + b.w) * size.width,
    y1: (b.y + b.h) * size.height,
  });
  const entry = (
    name: string,
    category: Category,
    box: { x: number; y: number; w: number; h: number },
    shape: "box" | "cylinder_upright" | "cylinder_lying" = "box",
  ) => {
    const c = catalogFor(category);
    return {
      name,
      category,
      w: c.w,
      h: c.h,
      d: c.d,
      kg: c.kg,
      fragile: c.fragile,
      soft: c.soft,
      hardness: c.hardness,
      upright: c.upright,
      confidence: 0.8,
      neededAtSecurity: category === "electronics" || category === "liquids",
      shape,
      box: pixels(box),
      alternatives: [{ name: "Travel accessory", category: "other" as const }],
    };
  };
  return {
    objects: [
      entry("Folded T-shirt", "clothing", { x: 0.06, y: 0.12, w: 0.3, h: 0.25 }),
      entry("Sneakers", "shoes", { x: 0.55, y: 0.1, w: 0.38, h: 0.3 }),
      entry("Laptop", "electronics", { x: 0.1, y: 0.5, w: 0.42, h: 0.3 }),
      entry("Shampoo bottle", "liquids", { x: 0.66, y: 0.55, w: 0.12, h: 0.3 }, "cylinder_upright"),
    ],
  };
}

/** Every packable object in one photo. Dims are model estimates; the app overrides them when it can measure. */
export async function scanInventory(input: {
  imageBase64: string;
  hint?: string;
  reference?: "credit_card" | null;
}): Promise<InventoryResult> {
  const warnings: string[] = ["no_scale_reference"];
  const imageBase64 = input.imageBase64.replace(/^data:image\/\w+;base64,/, "");
  const imageSize = jpegSize(Buffer.from(imageBase64, "base64"));
  const frame = imageSize ?? { width: UNKNOWN_SIZE_GRID, height: UNKNOWN_SIZE_GRID };
  const prompt = attachImage(
    buildScanInventoryPrompt({ hint: input.hint, reference: input.reference, imageSize }),
    imageBase64,
  );
  const { data, model } = await callClaudeTool({
    prompt,
    schema: ScanInventoryToolSchema,
    maxTokens: 8192,
    mock: () => ({
      ...mockInventory(frame),
      referenceBox: input.reference
        ? { x0: 0.42 * frame.width, y0: 0.42 * frame.height, x1: 0.58 * frame.width, y1: 0.5 * frame.height }
        : null,
    }),
  });

  // Without a scale reference, estimated dims are capped like the /scan/item estimate path.
  const confidenceCap = 0.5;
  const detections = data.objects.map((o) => {
    const itemWarnings: string[] = [];
    const cat = catalogFor(o.category);
    const dims = clampEstimatedDims(o.w, o.h, o.d, o.category, itemWarnings);
    const item: Item = {
      id: randomUUID(),
      name: o.name,
      w: dims.w,
      h: dims.h,
      d: dims.d,
      kg: clampKg(o.kg, o.category, itemWarnings),
      fragile: o.fragile ?? cat.fragile,
      hardness: Number.isFinite(o.hardness) ? o.hardness : cat.hardness,
      soft: o.soft ?? cat.soft,
      upright: o.upright ?? cat.upright,
      category: o.category,
      confidence: Math.min(1, Math.max(0, o.confidence)),
      neededAtSecurity: o.neededAtSecurity,
      source: "scan",
      measurement: {
        method: "estimate",
        confidence: Math.min(confidenceCap, Math.max(0, o.confidence)),
        deviceHasLidar: false,
      },
    };
    for (const w of itemWarnings) if (!warnings.includes(w)) warnings.push(w);
    return { item, box: normalizeBox(o.box, frame), alternatives: o.alternatives, shape: o.shape ?? null };
  });
  if (detections.length === 0) warnings.push("nothing_detected");
  const referenceBox = input.reference ? normalizeBox(data.referenceBox, frame) : null;
  if (input.reference && !referenceBox) warnings.push("reference_not_seen");
  // No API key (or MOCK_CLAUDE=1): these are stub items, not what is in the photo.
  if (model === "mock") warnings.push("sample_data");
  return { detections, reference: referenceBox ? { box: referenceBox } : null, warnings };
}
