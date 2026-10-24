import { Hono } from "hono";
import { TripSuggestRequestSchema, TripSuggestResponseSchema } from "../schemas.js";
import { suggestTrip } from "../services/trip.js";

type Vars = { requestId: string; started: number };

export const tripRoutes = new Hono<{ Variables: Vars }>();

tripRoutes.post("/trip/suggest", async (c) => {
  const body = TripSuggestRequestSchema.parse(await c.req.json());
  const result = await suggestTrip(body.trip);
  return c.json(
    TripSuggestResponseSchema.parse({
      ...result,
      meta: { requestId: c.get("requestId"), ms: Date.now() - c.get("started") },
    }),
  );
});
