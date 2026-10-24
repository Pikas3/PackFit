import { Hono } from "hono";
import { env } from "../env.js";
import { getRulesLastSynced } from "../rules/store.js";

export const healthRoutes = new Hono();

healthRoutes.get("/health", (c) => {
  return c.json({
    ok: true,
    version: env.version,
    rulesLastSynced: getRulesLastSynced(),
  });
});
