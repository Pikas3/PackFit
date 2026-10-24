import { callClaudeTool } from "../claude/client.js";
import { buildAskRulePrompt, AskRuleToolSchema } from "../claude/prompts/askRule.js";
import { buildMapRulesPrompt, MapRulesToolSchema } from "../claude/prompts/mapRules.js";
import { env } from "../env.js";
import {
  findCandidatesForItem,
  findCandidatesForQuestion,
  getRulesLastSynced,
  recordById,
} from "../rules/store.js";
import { anyStale } from "../rules/stale.js";
import type { Item, RuleFlag } from "../schemas.js";

export async function checkRules(input: {
  items: Item[];
  trip: { from: string; to: string; airline: string };
  bag: "carryOn" | "checked";
}): Promise<{ flags: RuleFlag[]; summary: string; stale: boolean; rulesLastSynced: string | null }> {
  const candidatesByItem: Record<string, ReturnType<typeof findCandidatesForItem>> = {};
  const itemsWithCandidates: Item[] = [];

  for (const item of input.items) {
    const cands = findCandidatesForItem(item, input.trip, input.bag);
    candidatesByItem[item.id] = cands;
    if (cands.length > 0) itemsWithCandidates.push(item);
  }

  if (itemsWithCandidates.length === 0) {
    return {
      flags: [],
      summary: "No matching travel-rule flags for these items.",
      stale: false,
      rulesLastSynced: getRulesLastSynced(),
    };
  }

  const prompt = buildMapRulesPrompt({
    items: itemsWithCandidates,
    bag: input.bag,
    candidatesByItem,
  });

  const { data } = await callClaudeTool({
    prompt,
    schema: MapRulesToolSchema,
    model: env.anthropicModel,
    mock: () => mockMap(itemsWithCandidates, candidatesByItem, input.bag),
  });

  const allowed = new Set(
    Object.values(candidatesByItem)
      .flat()
      .map((r) => r.ruleId),
  );

  const flags: RuleFlag[] = [];
  for (const f of data.flags) {
    if (!allowed.has(f.ruleId)) {
      console.warn(JSON.stringify({ kind: "drop_unknown_ruleId", ruleId: f.ruleId }));
      continue;
    }
    const record = recordById(f.ruleId);
    if (!record) continue;
    flags.push({
      itemId: f.itemId,
      scope: record.scope,
      severity: f.severity,
      text: f.text,
      sourceUrl: record.sourceUrl,
      lastVerified: record.lastVerified,
      ruleId: record.ruleId,
    });
  }

  const summary = templateSummary(flags);
  return {
    flags,
    summary,
    stale: anyStale(flags.map((f) => f.lastVerified)),
    rulesLastSynced: getRulesLastSynced(),
  };
}

export async function askRule(input: {
  question: string;
  trip: { from: string; to: string; airline: string };
  bag: "carryOn" | "checked";
}): Promise<{ answer: string; flags: RuleFlag[]; stale: boolean }> {
  const candidates = findCandidatesForQuestion(input.question, input.trip, input.bag);
  const prompt = buildAskRulePrompt({
    question: input.question,
    bag: input.bag,
    candidates,
  });

  const { data } = await callClaudeTool({
    prompt,
    schema: AskRuleToolSchema,
    model: env.anthropicModelFast,
    mock: () => mockAsk(input.question, candidates, input.bag),
  });

  const flags: RuleFlag[] = [];
  for (const ruleId of data.ruleIds) {
    const record = candidates.find((c) => c.ruleId === ruleId) ?? recordById(ruleId);
    if (!record || !candidates.some((c) => c.ruleId === ruleId)) continue;
    flags.push({
      itemId: "question",
      scope: record.scope,
      severity: record.severity,
      text: record.text,
      sourceUrl: record.sourceUrl,
      lastVerified: record.lastVerified,
      ruleId: record.ruleId,
    });
  }

  let answer = data.answer.trim();
  if (flags.length === 0 && !/no matching rule/i.test(answer)) {
    answer = "No matching rule was found for that question.";
  }

  return {
    answer,
    flags,
    stale: anyStale(flags.map((f) => f.lastVerified)),
  };
}

function templateSummary(flags: RuleFlag[]): string {
  if (flags.length === 0) return "No matching travel-rule flags for these items.";
  const banned = flags.filter((f) => f.severity === "banned").length;
  const restricted = flags.filter((f) => f.severity === "restricted").length;
  const parts = [
    `${flags.length} flag${flags.length === 1 ? "" : "s"}`,
    banned ? `${banned} banned` : null,
    restricted ? `${restricted} restricted` : null,
  ].filter(Boolean);
  return `${parts.join(", ")}. Open each flag for the source page — guidance only, not authority.`;
}

function mockMap(
  items: Item[],
  candidatesByItem: Record<string, ReturnType<typeof findCandidatesForItem>>,
  bag: "carryOn" | "checked",
) {
  const flags = [];
  for (const item of items) {
    for (const c of candidatesByItem[item.id] ?? []) {
      const verdict = bag === "carryOn" ? c.carryOn : c.checked;
      if (verdict === "ok" && c.severity === "check") continue;
      if (verdict === "ok") continue;
      flags.push({
        itemId: item.id,
        ruleId: c.ruleId,
        severity: c.severity,
        text: c.text,
      });
    }
  }
  return { flags };
}

function mockAsk(
  question: string,
  candidates: ReturnType<typeof findCandidatesForQuestion>,
  bag: "carryOn" | "checked",
) {
  const hit = candidates[0];
  if (!hit) {
    return { answer: "No matching rule was found for that question.", ruleIds: [] as string[] };
  }
  const verdict = bag === "carryOn" ? hit.carryOn : hit.checked;
  return {
    answer: `For ${bag}: ${hit.keywords[0] ?? "this"} is ${verdict}. ${hit.text}`.slice(0, 240),
    ruleIds: [hit.ruleId],
  };
}
