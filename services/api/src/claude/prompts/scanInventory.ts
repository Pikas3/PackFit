import { z } from "zod";
import { zodToJsonSchema } from "zod-to-json-schema";
import { CategorySchema } from "../../schemas.js";
import type { PromptPayload } from "../client.js";

export const MAX_INVENTORY_OBJECTS = 25;

/** The solid the phone fits to the object's outline when it measures against the card. */
export const ObjectShapeSchema = z.enum(["box", "cylinder_upright", "cylinder_lying"]);

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
  shape: ObjectShapeSchema.optional(),
  box: z
    .object({
      x0: z.number(),
      y0: z.number(),
      x1: z.number(),
      y1: z.number(),
    })
    .optional(),
  alternatives: z.array(z.object({ name: z.string(), category: CategorySchema })).max(3),
});

/** Pixel corners in the photo as sent: left, top, right, bottom. */
const BoxShape = z.object({ x0: z.number(), y0: z.number(), x1: z.number(), y1: z.number() });
export type PixelBox = z.infer<typeof BoxShape>;

/** When the photo's size is unknown, boxes are asked for on a 1000 × 1000 grid. */
export const UNKNOWN_SIZE_GRID = 1000;

export const ScanInventoryToolSchema = z.object({
  objects: z.array(DetectedObjectSchema).max(MAX_INVENTORY_OBJECTS),
  /** Box of the credit card used as a scale reference, when one is in the photo. */
  referenceBox: BoxShape.nullable().optional(),
});

export type ScanInventoryTool = z.infer<typeof ScanInventoryToolSchema>;

/**
 * Build the Claude vision prompt for `/scan/inventory`: every distinct packable object in one
 * photo. Boxes are rough (for highlighting and cropping on the phone), never for measuring.
 */
export function buildScanInventoryPrompt(input: {
  hint?: string;
  reference?: "credit_card" | null;
  imageSize?: { width: number; height: number } | null;
}): PromptPayload {
  const size = input.imageSize;
  const frame = size
    ? `The photo is ${size.width} × ${size.height} pixels. Give boxes in those pixels, origin at the top-left`
    : `Give boxes on a ${UNKNOWN_SIZE_GRID} × ${UNKNOWN_SIZE_GRID} grid laid over the photo, origin at the top-left`;
  const toolName = "report_inventory";
  const system = `You are an object-detection model for travel packing.
The photo shows things a traveler has laid out to pack. List every distinct physical object
that would go into a suitcase, one entry per object instance (two identical shirts are two
entries). Ignore the floor, furniture, walls, the suitcase or bag itself, hands and people.
Skip anything you cannot see well enough to name.

For each object give:
- name: short and specific ("Grey hoodie", "iPhone charger", "Shampoo 250 ml").
- category and packing attributes: weight kg, fragile, soft, hardness 0-1, upright.
  Drinks and anything pourable (energy drinks, soda, juice, coffee, sauces) are "liquids",
  not "food": airport security screens them as liquids. Put the size in the name when
  printed on it ("Energy drink 473 ml").
- w, h, d: your best estimate in cm of its packed size. These are rough; the app may
  replace them with measured values.
- shape: "cylinder_upright" for cans, bottles, jars, tubes and anything round standing on
  its end; "cylinder_lying" for those lying on their side; "box" for everything else.
- box: where it is in the photo: x0, y0 = its leftmost and topmost pixel, x1, y1 = its
  rightmost and bottommost pixel. ${frame}. The box must hug the whole object: look
  at where its edges really are, top to bottom and side to side. The app uses it to find the
  object's outline in the photo.
- confidence 0-1 that the name is right, and up to 3 alternatives (name + category).

If a credit card (or any bank or ID card) lies in the photo, it is a scale reference, not
something to pack: do not list it in objects; report its box as referenceBox instead.

List at most ${MAX_INVENTORY_OBJECTS} objects, the most clearly visible first. If nothing packable
is visible, return an empty list. Report only through the ${toolName} tool.`;

  const parts: string[] = [];
  if (input.hint) parts.push(`User hint (optional, may be wrong): ${input.hint}`);
  if (input.reference === "credit_card") {
    parts.push(
      "The user placed a credit card in the photo as a scale reference. Return its box as referenceBox, or null if you cannot see one.",
    );
  }
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
