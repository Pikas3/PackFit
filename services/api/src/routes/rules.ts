import { Hono } from "hono";
import {
  RulesAskRequestSchema,
  RulesAskResponseSchema,
  RulesCheckRequestSchema,
  RulesCheckResponseSchema,
} from "../schemas.js";
import { askRule, checkRules } from "../services/rules.js";

type Vars = { requestId: string; started: number };

export const rulesRoutes = new Hono<{ Variables: Vars }>();

rulesRoutes.post("/rules/check", async (c) => {
  const body = RulesCheckRequestSchema.parse(await c.req.json());
  const result = await checkRules(body);
  return c.json(
    RulesCheckResponseSchema.parse({
      ...result,
      meta: { requestId: c.get("requestId"), ms: Date.now() - c.get("started") },
    }),
  );
});

rulesRoutes.post("/rules/ask", async (c) => {
  const body = RulesAskRequestSchema.parse(await c.req.json());
  const result = await askRule(body);
  return c.json(
    RulesAskResponseSchema.parse({
      ...result,
      meta: { requestId: c.get("requestId"), ms: Date.now() - c.get("started") },
    }),
  );
});
