import { describe, expect, it } from "vitest";
import { lookupFlight, normalizeFlightQuery } from "../src/services/flightLookup.js";

describe("flight lookup", () => {
  it("normalizes airline + number", () => {
    expect(normalizeFlightQuery("ua", "88")).toEqual({ airline: "UA", flightNumber: "88", key: "UA88" });
    expect(normalizeFlightQuery("UA88", "")).toEqual({ airline: "UA", flightNumber: "88", key: "UA88" });
  });

  it("resolves demo fixture UA 88 to SFO→DEL with route notices", async () => {
    const result = await lookupFlight({ airline: "UA", flightNumber: "88" });
    expect(result.from).toBe("SFO");
    expect(result.to).toBe("DEL");
    expect(result.international).toBe(true);
    expect(result.source).toBe("fixture");
    expect(result.routeNotices.length).toBeGreaterThan(0);
    expect(result.routeNotices.some((n) => n.scope === "tsa")).toBe(true);
    expect(result.routeNotices.some((n) => n.scope === "country")).toBe(true);
  });
});
