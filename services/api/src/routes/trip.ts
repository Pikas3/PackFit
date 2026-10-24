import { Hono } from "hono";
import {
  TripLookupRequestSchema,
  TripLookupResponseSchema,
  TripSuggestRequestSchema,
  TripSuggestResponseSchema,
} from "../schemas.js";
import { lookupFlight } from "../services/flightLookup.js";
import { suggestTrip } from "../services/trip.js";

type Vars = { requestId: string; started: number };

export const tripRoutes = new Hono<{ Variables: Vars }>();

tripRoutes.post("/trip/lookup", async (c) => {
  const body = TripLookupRequestSchema.parse(await c.req.json());
  const result = await lookupFlight(body);
  return c.json(
    TripLookupResponseSchema.parse({
      ...result,
      meta: { requestId: c.get("requestId"), ms: Date.now() - c.get("started") },
    }),
  );
});

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
