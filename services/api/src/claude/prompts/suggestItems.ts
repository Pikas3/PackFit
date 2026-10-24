import { z } from "zod";
import { zodToJsonSchema } from "zod-to-json-schema";
import { CategorySchema, Trip } from "../../schemas.js";
import type { PromptPayload } from "../client.js";

export const SuggestItemsToolSchema = z.object({
  suggestions: z
    .array(
      z.object({
        name: z.string(),
        reason: z.string(),
        category: CategorySchema,
        qty: z.number().int().min(1).max(10),
        essential: z.boolean(),
      }),
    )
    .min(1)
    .max(20),
});
export type SuggestItemsTool = z.infer<typeof SuggestItemsToolSchema>;

export function buildSuggestItemsPrompt(input: {
  trip: Trip;
  weatherSummary: string;
  alreadyPackedNames?: string[];
}): PromptPayload {
  const toolName = "suggest_items";
  const json = zodToJsonSchema(SuggestItemsToolSchema, { $refStrategy: "none" }) as Record<string, unknown>;
  const { $schema: _s, ...schema } = json;
  const packed = input.alreadyPackedNames?.length
    ? `Already packing: ${input.alreadyPackedNames.join(", ")}. Do not suggest duplicates.`
    : "No items scanned yet.";

  return {
    system:
      "Suggest practical packing items for an international student's trip. Prefer common packable items. Mark essentials. Output only via the tool.",
    messages: [
      {
        role: "user",
        content: [
          `Trip: ${input.trip.from} → ${input.trip.to} on ${input.trip.airline}, ${input.trip.nights} nights.`,
          `Activities: ${input.trip.activities.join(", ") || "unspecified"}.`,
          `Weather: ${input.weatherSummary}`,
          `Checked limit: ${input.trip.checked.weightLimitKg} kg.`,
          packed,
          "Return items with category, short reason, quantity, and essential flag.",
        ].join("\n"),
      },
    ],
    tools: [
      {
        name: toolName,
        description: "Suggested packing list",
        input_schema: schema as { type: "object"; [k: string]: unknown },
      },
    ],
    toolName,
  };
}
