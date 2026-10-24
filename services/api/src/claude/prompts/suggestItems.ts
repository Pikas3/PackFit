import { z } from "zod";
import { zodToJsonSchema } from "zod-to-json-schema";
import { CategorySchema, Trip } from "../../schemas.js";
import type { PromptPayload } from "../client.js";

export const SuggestItemsToolSchema = z.object({
  suggestions: z.array(
    z.object({
      name: z.string(),
      category: CategorySchema,
      qty: z.number().int().min(1).max(10),
    }),
  ).min(1).max(20),
});
export type SuggestItemsTool = z.infer<typeof SuggestItemsToolSchema>;

export function buildSuggestItemsPrompt(input: {
  trip: Trip;
  weatherSummary: string;
}): PromptPayload {
  const toolName = "suggest_items";
  const json = zodToJsonSchema(SuggestItemsToolSchema, { $refStrategy: "none" }) as Record<string, unknown>;
  const { $schema: _s, ...schema } = json;

  return {
    system:
      "Suggest practical packing items for an international student's trip. Prefer common packable items. Output only via the tool.",
    messages: [
      {
        role: "user",
        content: [
          `Trip: ${input.trip.from} → ${input.trip.to} on ${input.trip.airline}, ${input.trip.nights} nights.`,
          `Activities: ${input.trip.activities.join(", ") || "unspecified"}.`,
          `Weather: ${input.weatherSummary}`,
          `Checked limit: ${input.trip.checked.weightLimitKg} kg.`,
          "Return a concise list of items with category and quantity.",
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
