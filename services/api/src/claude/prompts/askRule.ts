import { z } from "zod";
import { zodToJsonSchema } from "zod-to-json-schema";
import type { PromptPayload } from "../client.js";
import type { RuleRecord } from "../../schemas.js";

export const AskRuleToolSchema = z.object({
  answer: z.string().min(1).max(280),
  ruleIds: z.array(z.string()),
});
export type AskRuleTool = z.infer<typeof AskRuleToolSchema>;

export function buildAskRulePrompt(input: {
  question: string;
  bag: "carryOn" | "checked";
  candidates: RuleRecord[];
}): PromptPayload {
  const toolName = "answer_rule";
  const json = zodToJsonSchema(AskRuleToolSchema, { $refStrategy: "none" }) as Record<string, unknown>;
  const { $schema: _s, ...schema } = json;

  const candLines = input.candidates.length
    ? input.candidates
        .map(
          (c) =>
            `- ${c.ruleId} [${c.severity}] carryOn=${c.carryOn} checked=${c.checked}: ${c.text}`,
        )
        .join("\n")
    : "(no candidates)";

  return {
    system:
      "Answer a traveler's packing/security question in under 40 words. Cite only provided ruleIds, or say no matching rule was found. Guidance only.",
    messages: [
      {
        role: "user",
        content: `Bag: ${input.bag}\nQuestion: ${input.question}\nCandidates:\n${candLines}`,
      },
    ],
    tools: [
      {
        name: toolName,
        description: "Short answer plus cited rule ids",
        input_schema: schema as { type: "object"; [k: string]: unknown },
      },
    ],
    toolName,
  };
}
