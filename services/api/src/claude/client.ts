import Anthropic from "@anthropic-ai/sdk";
import { z, ZodTypeAny } from "zod";
import { env } from "../env.js";
import { ApiError } from "../errors.js";

export type PromptPayload = {
  system: string;
  messages: Anthropic.MessageParam[];
  tools: Anthropic.Tool[];
  toolName: string;
};

export type ClaudeCallResult<T> = {
  data: T;
  model: string;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
  repaired: boolean;
};

function getClient(): Anthropic | null {
  if (env.mockClaude || !env.anthropicApiKey) return null;
  return new Anthropic({ apiKey: env.anthropicApiKey, timeout: 20_000 });
}

function extractToolJson(message: Anthropic.Message, toolName: string): unknown {
  for (const block of message.content) {
    if (block.type === "tool_use" && block.name === toolName) {
      return block.input;
    }
  }
  throw new Error(`No tool_use block named ${toolName}`);
}

/**
 * Run a Claude tool-use call with zod parse and one repair retry.
 * Logs model, tokens, latency, repair — never prompts or images.
 */
export async function callClaudeTool<T extends ZodTypeAny>(opts: {
  prompt: PromptPayload;
  schema: T;
  model?: string;
  mock: () => z.infer<T>;
}): Promise<ClaudeCallResult<z.infer<T>>> {
  const model = opts.model ?? env.anthropicModel;
  const client = getClient();
  const started = Date.now();

  if (!client) {
    const data = opts.schema.parse(opts.mock());
    return {
      data,
      model: "mock",
      inputTokens: 0,
      outputTokens: 0,
      latencyMs: Date.now() - started,
      repaired: false,
    };
  }

  let inputTokens = 0;
  let outputTokens = 0;
  let repaired = false;

  const runOnce = async (extraUser?: string) => {
    const messages = [...opts.prompt.messages];
    if (extraUser) {
      messages.push({ role: "user", content: extraUser });
    }
    const controller = AbortSignal.timeout(20_000);
    const message = await client.messages.create(
      {
        model,
        max_tokens: 2048,
        system: opts.prompt.system,
        messages,
        tools: opts.prompt.tools,
        tool_choice: { type: "tool", name: opts.prompt.toolName },
      },
      { signal: controller },
    );
    inputTokens += message.usage.input_tokens;
    outputTokens += message.usage.output_tokens;
    return extractToolJson(message, opts.prompt.toolName);
  };

  try {
    let raw = await runOnce();
    let parsed = opts.schema.safeParse(raw);
    if (!parsed.success) {
      repaired = true;
      raw = await runOnce(
        `Your previous output failed validation: ${parsed.error.message}. Return a corrected tool call only.`,
      );
      parsed = opts.schema.safeParse(raw);
      if (!parsed.success) {
        logCall({ model, inputTokens, outputTokens, latencyMs: Date.now() - started, repaired, ok: false });
        throw new ApiError("model_output_invalid", "Model output failed validation after retry", 422);
      }
    }
    const latencyMs = Date.now() - started;
    logCall({ model, inputTokens, outputTokens, latencyMs, repaired, ok: true });
    return { data: parsed.data, model, inputTokens, outputTokens, latencyMs, repaired };
  } catch (err) {
    if (err instanceof ApiError) throw err;
    logCall({
      model,
      inputTokens,
      outputTokens,
      latencyMs: Date.now() - started,
      repaired,
      ok: false,
    });
    const message = err instanceof Error ? err.message : "Claude unavailable";
    if (message.includes("rate")) {
      throw new ApiError("rate_limited", message, 429);
    }
    throw new ApiError("upstream_unavailable", message, 502);
  }
}

function logCall(info: {
  model: string;
  inputTokens: number;
  outputTokens: number;
  latencyMs: number;
  repaired: boolean;
  ok: boolean;
}) {
  console.log(
    JSON.stringify({
      kind: "claude_call",
      ...info,
    }),
  );
}
