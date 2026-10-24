import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

function loadDotEnv() {
  const path = resolve(process.cwd(), ".env");
  if (!existsSync(path)) return;
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq < 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (process.env[key] === undefined) process.env[key] = value;
  }
}

loadDotEnv();

function flag(name: string, fallback = false): boolean {
  const v = process.env[name]?.toLowerCase();
  if (v === undefined) return fallback;
  return v === "1" || v === "true" || v === "yes";
}

export const env = {
  port: Number(process.env.PORT ?? 8787),
  appToken: process.env.APP_TOKEN ?? "local-dev-token",
  anthropicApiKey: process.env.ANTHROPIC_API_KEY ?? "",
  anthropicModel: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-5-20250929",
  anthropicModelFast: process.env.ANTHROPIC_MODEL_FAST ?? "claude-haiku-4-5-20251001",
  apifyToken: process.env.APIFY_TOKEN ?? "",
  mockClaude: flag("MOCK_CLAUDE", !process.env.ANTHROPIC_API_KEY),
  version: "0.1.0",
};
