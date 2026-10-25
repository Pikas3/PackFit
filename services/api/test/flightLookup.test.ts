import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { env } from "../src/env.js";
import { clearFlightCache, lookupFlight, normalizeFlightQuery } from "../src/services/flightLookup.js";
import { weatherWindow } from "../src/services/trip.js";

describe("flight lookup", () => {
  const keys = { aviationStack: env.aviationStackKey, apify: env.apifyToken };
  // The real .env may hold live keys: no test may start a paid run.
  beforeEach(() => {
    env.aviationStackKey = "";
    env.apifyToken = "";
    clearFlightCache();
  });
  afterEach(() => {
    env.aviationStackKey = keys.aviationStack;
    env.apifyToken = keys.apify;
    vi.unstubAllGlobals();
  });

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

  it("an unknown flight with no key is a 404 that says live lookup is off", async () => {
    await expect(lookupFlight({ airline: "UA", flightNumber: "901" })).rejects.toMatchObject({
      status: 404,
      message: expect.stringContaining("isn’t set up"),
    });
  });

  // UA 901 alternates: SFO→LHR on even days, SFO→FRA on odd days, 13-26 Oct 2026.
  const legs = Array.from({ length: 14 }, (_, i) => {
    const day = 13 + i;
    return { date: `2026-10-${day}`, originIata: "SFO", destinationIata: day % 2 ? "FRA" : "LHR" };
  }).reverse();
  const apifyRow = {
    resultUnknown: false,
    scheduledDepartureLocal: "2026-10-24T13:50:00-07:00",
    originIata: "SFO",
    destinationIata: "LHR",
    originAirport: "San Francisco Int'l",
    destinationAirport: "Heathrow",
    originCountryCode: "US",
    destinationCountryCode: "GB",
    recentFlights: legs,
  };

  it("uses the flight on the trip's date, and caches the history across dates", async () => {
    env.apifyToken = "test-token";
    const fetchMock = vi.fn(async () => Response.json([apifyRow], { status: 201 }));
    vi.stubGlobal("fetch", fetchMock);
    const next = await lookupFlight({ airline: "UA", flightNumber: "901" });
    expect(next).toMatchObject({ to: "LHR", departDate: "2026-10-24", routeNote: null, source: "live" });
    const odd = await lookupFlight({ airline: "UA", flightNumber: "901", departDate: "2026-10-25" });
    expect(odd).toMatchObject({ to: "FRA", departDate: "2026-10-25", routeNote: null });
    expect(odd.international).toBe(true);
    const [url, init] = fetchMock.mock.calls[0] as unknown as [URL, RequestInit];
    expect(String(url)).toContain("apt_marble~flight-status-tracker/run-sync-get-dataset-items");
    expect(String(url)).not.toContain("test-token");
    expect(JSON.parse(String(init.body))).toMatchObject({ flights: ["UA901"], includeHistory: true });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("past the published schedule, takes the same weekday's route and says so", async () => {
    env.apifyToken = "test-token";
    vi.stubGlobal("fetch", async () => Response.json([apifyRow], { status: 201 }));
    // 3 Nov 2026 is a Tuesday; the latest Tuesday in the history is 20 Oct (even: LHR).
    const result = await lookupFlight({ airline: "UA", flightNumber: "901", departDate: "2026-11-03" });
    expect(result).toMatchObject({ to: "LHR", departDate: "2026-11-03" });
    expect(result.routeNote).toContain("Tuesdays");
    // 4 Nov is a Wednesday; latest Wednesday 21 Oct (odd: FRA).
    const wed = await lookupFlight({ airline: "UA", flightNumber: "901", departDate: "2026-11-04" });
    expect(wed.to).toBe("FRA");
  });

  it("a covered date the flight does not fly on is a 404", async () => {
    env.apifyToken = "test-token";
    const gap = { ...apifyRow, recentFlights: legs.filter((l) => l.date !== "2026-10-22") };
    vi.stubGlobal("fetch", async () => Response.json([gap], { status: 201 }));
    await expect(lookupFlight({ airline: "UA", flightNumber: "901", departDate: "2026-10-22" })).rejects.toMatchObject({
      status: 404,
      message: expect.stringContaining("doesn’t fly on 2026-10-22"),
    });
  });

  it("a flight the actor does not know is a 404, remembered for a while", async () => {
    env.apifyToken = "test-token";
    const fetchMock = vi.fn(async () => Response.json([], { status: 201 }));
    vi.stubGlobal("fetch", fetchMock);
    await expect(lookupFlight({ airline: "ZZ", flightNumber: "9876" })).rejects.toMatchObject({ status: 404 });
    await expect(lookupFlight({ airline: "ZZ", flightNumber: "9876" })).rejects.toMatchObject({ status: 404 });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("an Apify failure is a 502 and is not cached", async () => {
    env.apifyToken = "test-token";
    const fetchMock = vi.fn(async () => Response.json({ error: { type: "actor-is-not-rented" } }, { status: 403 }));
    vi.stubGlobal("fetch", fetchMock);
    await expect(lookupFlight({ airline: "UA", flightNumber: "901" })).rejects.toMatchObject({ status: 502 });
    await expect(lookupFlight({ airline: "UA", flightNumber: "901" })).rejects.toMatchObject({ status: 502 });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("uses AviationStack's route and keeps the user's date", async () => {
    env.aviationStackKey = "test-key";
    const fetchMock = vi.fn(async () =>
      Response.json({
        data: [
          {
            flight_date: "2026-10-20",
            flight: { iata: "UA901" },
            departure: { iata: "sfo", airport: "San Francisco International" },
            arrival: { iata: "fra", airport: "Frankfurt International" },
          },
        ],
      }),
    );
    vi.stubGlobal("fetch", fetchMock);
    const result = await lookupFlight({ airline: "UA", flightNumber: "901", departDate: "2026-12-01" });
    expect(result).toMatchObject({ from: "SFO", to: "FRA", departDate: "2026-12-01", source: "live" });
    const url = new URL(String((fetchMock.mock.calls[0] as unknown[])[0]));
    expect(url.searchParams.get("flight_date")).toBeNull(); // paid-only filter
  });

  it("explains AviationStack's free-plan https refusal", async () => {
    env.aviationStackKey = "test-key";
    vi.stubGlobal("fetch", async () =>
      Response.json({ error: { code: "https_access_restricted", message: "Access Restricted" } }, { status: 403 }),
    );
    await expect(lookupFlight({ airline: "UA", flightNumber: "901" })).rejects.toMatchObject({
      status: 502,
      message: expect.stringContaining("AVIATIONSTACK_BASE_URL"),
    });
  });
});

describe("weather window", () => {
  const today = new Date("2026-10-24T12:00:00Z");

  it("cuts a long trip off where the forecast ends", () => {
    expect(weatherWindow("2026-11-01", 21, today)).toEqual({
      source: "forecast",
      start: "2026-11-01",
      end: "2026-11-08",
      clamped: true,
    });
    expect(weatherWindow("2026-10-26", 5, today)).toMatchObject({ source: "forecast", end: "2026-10-31", clamped: false });
  });

  it("uses last year's dates beyond the forecast", () => {
    expect(weatherWindow("2026-12-10", 7, today)).toEqual({
      source: "last_year",
      start: "2025-12-10",
      end: "2025-12-17",
      clamped: false,
    });
  });
});
