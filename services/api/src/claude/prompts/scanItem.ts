import { z } from "zod";
import { zodToJsonSchema } from "zod-to-json-schema";
import { CategorySchema } from "../../schemas.js";
import type { PromptPayload } from "../client.js";

/** Vision / object-detection attributes only — no w/h/d (device dims are attached server-side). */
const DetectModelSchema = z.object({
  name: z.string(),
  category: CategorySchema,
  kg: z.number(),
  fragile: z.boolean(),
  soft: z.boolean(),
  hardness: z.number().min(0).max(1),
  upright: z.boolean(),
  confidence: z.number().min(0).max(1),
  neededAtSecurity: z.boolean().optional(),
  alternatives: z.array(z.object({ name: z.string(), category: CategorySchema })).min(1).max(3),
});

/** When the device did not measure size, the model also estimates dims from the photo. */
const EstimateModelSchema = DetectModelSchema.extend({
  w: z.number().positive(),
  h: z.number().positive(),
  d: z.number().positive(),
});

export const ScanMeasuredToolSchema = DetectModelSchema;
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

/**
 * Build the Claude vision prompt for `/scan/item`.
 *
 * When `measured` is present, identification is pure object detection from the image.
 * Measured dimensions are intentionally omitted from the prompt — the server copies them
 * onto the Item for packing only.
 */
export function buildScanItemPrompt(input: {
  measured: { w: number; h: number; d: number; method: string; confidence: number } | null;
  reference?: string | null;
  hint?: string;
}): PromptPayload {
  const hasMeasured = !!input.measured;
  const schema = hasMeasured ? ScanMeasuredToolSchema : ScanEstimateToolSchema;
  const toolName = "report_item";

  const system = hasMeasured
    ? `You are an object-detection model for travel packing.
Look only at the attached photo. Detect and name the single primary item a traveler would pack.
Do NOT use size, scale, dimensions, or any numeric measurements to decide what the item is —
identify from visual appearance alone (shape, materials, labels, typical form).
Also estimate packing attributes that cannot be seen as size: weight (kg), fragile, soft,
hardness (0-1), whether it should stay upright, and confidence (0-1).
Output only via the report_item tool. Provide 2-3 alternatives (name + category).
Never invent or return w/h/d — dimensions are measured on-device and attached separately for packing.`
    : `You are an object-detection model for travel packing.
Look at the attached photo. Detect and name the single primary item a traveler would pack from
visual appearance alone. Also estimate its dimensions in cm (using the scale reference when
provided), weight, and packing attributes.
Output only via the report_item tool. Provide 2-3 alternatives (name + category).`;

  const parts: string[] = [];
  if (input.hint) parts.push(`User hint (optional, may be wrong): ${input.hint}`);
  if (hasMeasured) {
    parts.push(
      "Device-measured dimensions exist but are withheld on purpose. Identify the item from the image only; size is used later for packing, not for naming.",
    );
  } else if (input.reference) {
    parts.push(`Scale reference in the photo: ${input.reference.replace("_", " ")}.`);
  } else {
    parts.push("No scale reference was provided.");
  }
  parts.push("The image is attached. Detect the single primary item to pack.");

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
        "Object-detection result: identity and packing attributes for the detected item",
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

/** User text for a measured (device-dims) prompt — must not leak numeric dimensions. */
export function measuredPromptUserText(prompt: PromptPayload): string {
  const content = prompt.messages[0]?.content;
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((c): c is { type: "text"; text: string } => c.type === "text")
    .map((c) => c.text)
    .join("\n");
}
