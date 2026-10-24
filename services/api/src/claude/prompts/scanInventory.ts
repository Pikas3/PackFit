import { z } from "zod";
import { zodToJsonSchema } from "zod-to-json-schema";
import { CategorySchema } from "../../schemas.js";
import type { PromptPayload } from "../client.js";

export const MAX_INVENTORY_OBJECTS = 25;

const DetectedObjectSchema = z.object({
  name: z.string(),
  category: CategorySchema,
  w: z.number().positive(),
  h: z.number().positive(),
  d: z.number().positive(),
  kg: z.number(),
  fragile: z.boolean(),
  soft: z.boolean(),
  hardness: z.number().min(0).max(1),
  upright: z.boolean(),
  confidence: z.number().min(0).max(1),
  neededAtSecurity: z.boolean().optional(),
  box: z
    .object({
      x: z.number(),
      y: z.number(),
      w: z.number(),
      h: z.number(),
    })
    .optional(),
  alternatives: z.array(z.object({ name: z.string(), category: CategorySchema })).max(3),
});

export const ScanInventoryToolSchema = z.object({
  objects: z.array(DetectedObjectSchema).max(MAX_INVENTORY_OBJECTS),
});

export type ScanInventoryTool = z.infer<typeof ScanInventoryToolSchema>;

/**
 * Build the Claude vision prompt for `/scan/inventory`: every distinct packable object in one
 * photo. Boxes are rough (for highlighting and cropping on the phone), never for measuring.
 */
export function buildScanInventoryPrompt(input: { hint?: string }): PromptPayload {
  const toolName = "report_inventory";
  const system = `You are an object-detection model for travel packing.
The photo shows things a traveler has laid out to pack. List every distinct physical object
that would go into a suitcase, one entry per object instance (two identical shirts are two
entries). Ignore the floor, furniture, walls, the suitcase or bag itself, hands and people.
Skip anything you cannot see well enough to name.

For each object give:
- name: short and specific ("Grey hoodie", "iPhone charger", "Shampoo 250 ml").
- category and packing attributes: weight kg, fragile, soft, hardness 0-1, upright.
- w, h, d: your best estimate in cm of its packed size. These are rough; the app may
  replace them with measured values.
- box: where it is in the photo, normalized 0-1 with origin at the top-left
  (x, y = top-left corner; w, h = width and height as fractions of the image).
- confidence 0-1 that the name is right, and up to 3 alternatives (name + category).

List at most ${MAX_INVENTORY_OBJECTS} objects, the most clearly visible first. If nothing packable
is visible, return an empty list. Report only through the ${toolName} tool.`;

  const parts: string[] = [];
  if (input.hint) parts.push(`User hint (optional, may be wrong): ${input.hint}`);
  parts.push("The photo is attached. List every packable object in it.");

  const json = zodToJsonSchema(ScanInventoryToolSchema, { $refStrategy: "none" }) as Record<
    string,
    unknown
  >;
  const { $schema: _s, ...inputSchema } = json;

  return {
    system,
    messages: [{ role: "user", content: [{ type: "text", text: parts.join("\n") }] }],
    tools: [
      {
        name: toolName,
        description: "Object-detection result: every packable object in the photo",
        input_schema: inputSchema as { type: "object"; [k: string]: unknown },
      },
    ],
    toolName,
  };
}
