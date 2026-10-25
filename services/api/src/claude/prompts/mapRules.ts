import { z } from "zod";
import { zodToJsonSchema } from "zod-to-json-schema";
import { RuleSeveritySchema } from "../../schemas.js";
import type { PromptPayload } from "../client.js";
import type { RuleRecord } from "../../schemas.js";
import type { Item } from "../../schemas.js";

export const MapRulesToolSchema = z.object({
  flags: z.array(
    z.object({
      itemId: z.string(),
      ruleId: z.string(),
      severity: RuleSeveritySchema,
      text: z.string().min(1),
    }),
  ),
});
export type MapRulesTool = z.infer<typeof MapRulesToolSchema>;

export function buildMapRulesPrompt(input: {
  items: Item[];
  bag: "carryOn" | "checked";
  candidatesByItem: Record<string, RuleRecord[]>;
}): PromptPayload {
  const toolName = "map_rules";
  const json = zodToJsonSchema(MapRulesToolSchema, { $refStrategy: "none" }) as Record<string, unknown>;
  const { $schema: _s, ...schema } = json;

  const lines: string[] = [
    `Bag type: ${input.bag}`,
    "For each item, choose zero or more candidate rules the item actually breaks in this bag type. Do not invent ruleIds.",
    "If the item is allowed as packed, return no flag for it. Do not add general advice or reminders.",
    "Write 1-2 plain guidance sentences per flag. Zero flags is fine.",
    "",
  ];
  for (const item of input.items) {
    const cands = input.candidatesByItem[item.id] ?? [];
    lines.push(`Item ${item.id}: ${item.name} (${item.category})`);
    if (cands.length === 0) {
      lines.push("  candidates: none");
    } else {
      for (const c of cands) {
        lines.push(
          `  - ${c.ruleId} [${c.severity}] carryOn=${c.carryOn} checked=${c.checked} limits=${JSON.stringify(c.limits ?? {})} :: ${c.text}`,
        );
      }
    }
  }

  return {
    system:
      "You map travel items to candidate packing/security rules. Only use provided ruleIds. Guidance only, never invent URLs.",
    messages: [{ role: "user", content: lines.join("\n") }],
    tools: [
      {
        name: toolName,
        description: "Selected rule flags for the packing trip",
        input_schema: schema as { type: "object"; [k: string]: unknown },
      },
    ],
    toolName,
  };
}
