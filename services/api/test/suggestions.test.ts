import { describe, expect, it } from "vitest";
import { SuggestionSchema, TripSuggestResponseSchema } from "../src/schemas.js";
import { suggestTrip } from "../src/services/trip.js";
import type { Trip } from "../src/schemas.js";

const sampleTrip = {
  id: "sfo-del",
  from: "SFO",
  to: "DEL",
  airline: "UA",
  nights: 14,
  activities: ["home"],
  carryOn: {
    id: "c",
    name: "carry",
    type: "suitcase" as const,
    outer: [55, 23, 40] as [number, number, number],
    compartments: [{ name: "main", dims: [52, 20, 37] as [number, number, number], compressibility: 0.1 }],
    weightLimitKg: 7,
  },
  checked: {
    id: "k",
    name: "checked",
    type: "suitcase" as const,
    outer: [75, 30, 50] as [number, number, number],
    compartments: [{ name: "main", dims: [72, 27, 47] as [number, number, number], compressibility: 0.1 }],
    weightLimitKg: 23,
  },
  departDate: "2026-11-01",
} satisfies Trip;

describe("suggestion JSON validation", () => {
  it("SuggestionSchema clamps required fields", () => {
    const parsed = SuggestionSchema.parse({
      id: "1",
      name: "Adapter",
      reason: "Destination voltage",
      category: "electronics",
      estDims: [8, 4, 6],
      estKg: 0.2,
      fragile: false,
      soft: false,
      essential: true,
    });
    expect(parsed.essential).toBe(true);
  });

  it("suggestTrip returns valid TripSuggestResponse shape (mock Claude)", async () => {
    process.env.MOCK_CLAUDE = "1";
    const result = await suggestTrip(sampleTrip);
    const wrapped = TripSuggestResponseSchema.parse({
      ...result,
      meta: { requestId: "test", ms: 1 },
    });
    expect(wrapped.suggestions.length).toBeGreaterThan(0);
    expect(wrapped.beforeYouGo?.leaveOrDeclare.length).toBeGreaterThan(0);
    expect(wrapped.destinationCountry).toBe("IN");
  });
});
