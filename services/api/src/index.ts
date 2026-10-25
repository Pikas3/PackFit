import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { randomUUID } from "node:crypto";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { ZodError } from "zod";
import { env } from "./env.js";
import { ApiError, toErrorBody } from "./errors.js";
import { healthRoutes } from "./routes/health.js";
import { scanRoutes } from "./routes/scan.js";
import { rulesRoutes } from "./routes/rules.js";
import { tripRoutes } from "./routes/trip.js";
import { voiceRoutes } from "./routes/voice.js";
import { getRulesLastSynced } from "./rules/store.js";

type Vars = { requestId: string; started: number };

const app = new Hono<{ Variables: Vars }>();

app.use("*", async (c, next) => {
  const requestId = randomUUID();
  const started = Date.now();
  c.set("requestId", requestId);
  c.set("started", started);
  c.header("x-request-id", requestId);

  if (c.req.path !== "/health") {
    // x-packfit-token is the pre-rename header; older app builds still send it.
    const token = c.req.header("x-snugly-token") ?? c.req.header("x-packfit-token");
    if (!token || token !== env.appToken) {
      return c.json({ error: { code: "unauthorized", message: "Missing or invalid x-snugly-token" } }, 401);
    }
  }

  // Log body sizes only — never image/prompt contents.
  const len = c.req.header("content-length");
  console.log(
    JSON.stringify({
      kind: "request",
      method: c.req.method,
      path: c.req.path,
      requestId,
      contentLength: len ?? null,
    }),
  );

  await next();
});

app.onError((err, c) => {
  if (err instanceof ZodError) {
    return c.json({ error: { code: "bad_request", message: err.flatten() } }, 400);
  }
  if (err instanceof ApiError) {
    return c.json({ error: { code: err.code, message: err.message } }, err.status as 400);
  }
  const mapped = toErrorBody(err);
  return c.json(mapped.body, mapped.status as 500);
});

app.route("/", healthRoutes);
app.route("/", scanRoutes);
app.route("/", rulesRoutes);
app.route("/", tripRoutes);
app.route("/", voiceRoutes);

export { app };

const isMain = !!process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1]);
if (isMain) {
  console.log(
    JSON.stringify({
      kind: "boot",
      port: env.port,
      mockClaude: env.mockClaude,
      rulesLastSynced: getRulesLastSynced(),
    }),
  );
  serve({ fetch: app.fetch, port: env.port });
}
