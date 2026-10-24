import { z } from "zod";
import { zodToJsonSchema } from "zod-to-json-schema";
import { CategorySchema } from "../../schemas.js";
import type { PromptPayload } from "../client.js";

const MeasuredModelSchema = z.object({
  name: z.string(),
  category: CategorySchema,
  kg: z.number(),
  fragile: z.boolean(),
  soft: z.boolean(),
  hardness: z.number().min(0).max(1),
  upright: z.boolean(),
  confidence: z.number().min(0).max(1),
  neededAtSecurity: z.boolean().optional(),
  dimsPlausible: z.boolean(),
  /** Only when asked: the model's own size estimate, a cross-check for camera-measured dims. */
  estimatedDims: z
    .object({ w: z.number().positive(), h: z.number().positive(), d: z.number().positive() })
    .optional(),
  alternatives: z.array(z.object({ name: z.string(), category: CategorySchema })).min(1).max(3),
});

const EstimateModelSchema = MeasuredModelSchema.extend({
  w: z.number().positive(),
  h: z.number().positive(),
  d: z.number().positive(),
}).omit({ dimsPlausible: true, estimatedDims: true });

/** Below this measured confidence the model also estimates the size, as a cross-check. */
export const CROSS_CHECK_BELOW = 0.7;

export const ScanMeasuredToolSchema = MeasuredModelSchema;
export const ScanEstimateToolSchema = EstimateModelSchema;

export type ScanMeasuredTool = z.infer<typeof ScanMeasuredToolSchema>;
export type ScanEstimateTool = z.infer<typeof ScanEstimateToolSchema>;

function toolFromZod(name: string, description: string, schema: z.ZodTypeAny) {
  const json = zodToJsonSchema(schema, { $refStrategy: "none" }) as Record<string, unknown>;
  const { $schema: _s, ...rest } = json;
  return {
    name,
    description,
    input_schema: rest as { type: "object"; [k: string]: unknown },
  };
}

export function buildScanItemPrompt(input: {
  measured: { w: number; h: number; d: number; method: string; confidence: number } | null;
  reference?: string | null;
  hint?: string;
}): PromptPayload {
  const hasMeasured = !!input.measured;
  const schema = hasMeasured ? ScanMeasuredToolSchema : ScanEstimateToolSchema;
  const toolName = "report_item";

  const system = hasMeasured
    ? `You identify a single travel item in a photo and estimate weight and packing attributes.
The item's dimensions were already measured by the device and are given — do NOT re-estimate w/h/d.
Set dimsPlausible to false if the measured size is implausible for the item you identify.
If asked for estimatedDims, give your own estimate of the item's size in cm from the photo; it is only a cross-check.
The photo is a crop around one item; ignore the floor and anything cut off at the edges.
Output only via the report_item tool. Provide 2-3 alternatives (name + category).`
    : `You identify a single travel item in a photo and estimate its dimensions (cm), weight, and packing attributes.
Use the reference object for scale when provided. Output only via the report_item tool.
Provide 2-3 alternatives (name + category).`;

  const parts: string[] = [];
  if (input.hint) parts.push(`User hint: ${input.hint}`);
  if (input.measured) {
    parts.push(
      `Measured dimensions (cm): w=${input.measured.w}, h=${input.measured.h}, d=${input.measured.d} (method=${input.measured.method}, confidence=${input.measured.confidence}).`,
    );
    if (input.measured.method === "ar") {
      parts.push("These were measured from the camera without a depth sensor, so they may be off by a few cm.");
    }
    if (input.measured.confidence < CROSS_CHECK_BELOW) {
      parts.push("Also give estimatedDims: your own size estimate in cm.");
    }
  } else if (input.reference) {
    parts.push(`Scale reference in the photo: ${input.reference.replace("_", " ")}.`);
  } else {
    parts.push("No scale reference was provided.");
  }
  parts.push("The image is attached. Identify the single primary item to pack.");

  return {
    system,
    messages: [
      {
        role: "user",
        content: [
          { type: "text", text: parts.join("\n") },
          // Image is injected by the scan service so prompts stay unit-testable without bytes.
        ],
      },
    ],
    tools: [
      toolFromZod(
        toolName,
        "Structured packing attributes for the identified item",
        schema,
      ),
    ],
    toolName,
  };
}

export function attachImage(prompt: PromptPayload, imageBase64: string): PromptPayload {
  const mediaType = imageBase64.startsWith("/9j/") ? "image/jpeg" : "image/jpeg";
  const content = [
    ...(Array.isArray(prompt.messages[0]?.content)
      ? (prompt.messages[0].content as AnthropicContent[])
      : [{ type: "text" as const, text: String(prompt.messages[0]?.content ?? "") }]),
    {
      type: "image" as const,
      source: { type: "base64" as const, media_type: mediaType as "image/jpeg", data: imageBase64 },
    },
  ];
  return {
    ...prompt,
    messages: [{ role: "user", content }],
  };
}

type AnthropicContent =
  | { type: "text"; text: string }
  | { type: "image"; source: { type: "base64"; media_type: "image/jpeg" | "image/png" | "image/gif" | "image/webp"; data: string } };

/** Exported for unit tests: schema must be present on the tool. */
export function scanToolHasSchema(prompt: PromptPayload): boolean {
  const tool = prompt.tools[0];
  return !!tool && typeof tool.input_schema === "object" && tool.input_schema !== null;
}
