import { Hono } from "hono";
import {
  ScanInventoryRequestSchema,
  ScanInventoryResponseSchema,
  ScanItemRequestSchema,
  ScanItemResponseSchema,
} from "../schemas.js";
import { scanInventory, scanItem } from "../services/scan.js";
import { ApiError } from "../errors.js";

type Vars = { requestId: string; started: number };

export const scanRoutes = new Hono<{ Variables: Vars }>();

scanRoutes.post("/scan/item", async (c) => {
  const body = ScanItemRequestSchema.parse(await c.req.json());
  if (body.imageBase64.length > 4_000_000) {
    throw new ApiError("bad_request", "imageBase64 too large (max ~3MB)", 400);
  }
  const result = await scanItem(body);
  const payload = ScanItemResponseSchema.parse({
    ...result,
    meta: { requestId: c.get("requestId"), ms: Date.now() - c.get("started") },
  });
  return c.json(payload);
});

scanRoutes.post("/scan/inventory", async (c) => {
  const body = ScanInventoryRequestSchema.parse(await c.req.json());
  if (body.imageBase64.length > 4_000_000) {
    throw new ApiError("bad_request", "imageBase64 too large (max ~3MB)", 400);
  }
  const result = await scanInventory(body);
  const payload = ScanInventoryResponseSchema.parse({
    ...result,
    meta: { requestId: c.get("requestId"), ms: Date.now() - c.get("started") },
  });
  return c.json(payload);
});
