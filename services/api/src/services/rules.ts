import { callClaudeTool } from "../claude/client.js";
import { buildAskRulePrompt, AskRuleToolSchema } from "../claude/prompts/askRule.js";
import { buildMapRulesPrompt, MapRulesToolSchema } from "../claude/prompts/mapRules.js";
import { env } from "../env.js";
import {
  bagVerdict,
  findCandidatesForItem,
  findCandidatesForQuestion,
  getRulesLastSynced,
  recordById,
  weightRuleForAirline,
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

  const weightFlag = bagWeightFlag(input.items, input.trip.airline, input.bag);

  if (itemsWithCandidates.length === 0) {
    const flags = weightFlag ? [weightFlag] : [];
    return {
      flags,
      summary: templateSummary(flags),
      stale: anyStale(flags.map((f) => f.lastVerified)),
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

  const flags: RuleFlag[] = [];
  for (const f of data.flags) {
    // Only rules this item breaks were offered, so anything else is dropped.
    if (!candidatesByItem[f.itemId]?.some((r) => r.ruleId === f.ruleId)) {
      console.warn(JSON.stringify({ kind: "drop_unknown_ruleId", ruleId: f.ruleId }));
      continue;
    }
    const record = recordById(f.ruleId);
    if (!record) continue;
    const verdict = bagVerdict(record, input.bag);
    flags.push({
      itemId: f.itemId,
      scope: record.scope,
      // Severity comes from the record's verdict for this bag, never from the model.
      severity: verdict === "banned" ? "banned" : "restricted",
      text: f.text,
      sourceUrl: record.sourceUrl,
      lastVerified: record.lastVerified,
      ruleId: record.ruleId,
    });
  }

  if (weightFlag) flags.push(weightFlag);

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

/**
 * One flag for the whole bag, only when the items together are over the airline's
 * checked-bag weight limit. Weight is a property of the bag, never of a single item.
 */
function bagWeightFlag(items: Item[], airline: string, bag: "carryOn" | "checked"): RuleFlag | null {
  if (bag !== "checked") return null;
  const record = weightRuleForAirline(airline);
  const maxKg = record?.limits?.maxKg;
  if (!record || maxKg === undefined) return null;
  const totalKg = items.reduce((sum, i) => sum + i.kg, 0);
  if (totalKg <= maxKg) return null;
  return {
    itemId: "bag",
    scope: record.scope,
    severity: "restricted",
    text: `Your items weigh about ${totalKg.toFixed(1)} kg, over the ${airline} ${maxKg} kg checked-bag limit. Excess weight fees may apply.`,
    sourceUrl: record.sourceUrl,
    lastVerified: record.lastVerified,
    ruleId: record.ruleId,
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
  // Candidates are already only the rules each item breaks in this bag.
  const flags = [];
  for (const item of items) {
    for (const c of candidatesByItem[item.id] ?? []) {
      flags.push({
        itemId: item.id,
        ruleId: c.ruleId,
        severity: bagVerdict(c, bag) === "banned" ? ("banned" as const) : ("restricted" as const),
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
