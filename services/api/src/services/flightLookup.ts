import { ApiError } from "../errors.js";
import { env } from "../env.js";
import { countryForAirport, loadCountryTips } from "../rules/store.js";

export type FlightLookupInput = {
  airline: string;
  flightNumber: string;
  departDate?: string;
};

export type FlightLookupResult = {
  airline: string;
  flightNumber: string;
  flightLabel: string;
  from: string;
  to: string;
  fromName: string;
  toName: string;
  fromCountry: string | null;
  toCountry: string | null;
  departDate: string | null;
  international: boolean;
  source: "live" | "fixture";
  routeNotices: Array<{ text: string; sourceUrl: string; lastVerified: string; scope: "tsa" | "country" }>;
};

/** Demo / offline flights so the hackathon flow works without AviationStack. */
const FIXTURE_FLIGHTS: Record<
  string,
  { from: string; to: string; fromName: string; toName: string; departDate?: string }
> = {
  UA88: { from: "SFO", to: "DEL", fromName: "San Francisco", toName: "Delhi", departDate: "2026-11-01" },
  AI173: { from: "SFO", to: "DEL", fromName: "San Francisco", toName: "Delhi", departDate: "2026-11-01" },
  AS204: { from: "SEA", to: "KEF", fromName: "Seattle", toName: "Reykjavik", departDate: "2026-12-10" },
  DL188: { from: "LAX", to: "ICN", fromName: "Los Angeles", toName: "Seoul Incheon", departDate: "2026-10-28" },
  BA178: { from: "JFK", to: "LHR", fromName: "New York JFK", toName: "London Heathrow", departDate: "2026-11-15" },
  AA100: { from: "SFO", to: "LAX", fromName: "San Francisco", toName: "Los Angeles", departDate: "2026-10-30" },
  UA900: { from: "SFO", to: "NRT", fromName: "San Francisco", toName: "Tokyo Narita", departDate: "2026-11-05" },
};

export function normalizeFlightQuery(airline: string, flightNumber: string): { airline: string; flightNumber: string; key: string } {
  let a = airline.trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
  let n = flightNumber.trim().toUpperCase().replace(/[^0-9]/g, "");

  // Allow "UA88" pasted into either field.
  const combined = `${airline}${flightNumber}`.toUpperCase().replace(/\s+/g, "");
  const m = combined.match(/^([A-Z]{2})(\d{1,4})$/);
  if (m && (!a || a.length > 2 || !n)) {
    a = m[1];
    n = m[2];
  }
  if (a.length === 2 && n.length >= 1) {
    return { airline: a, flightNumber: n.replace(/^0+/, "") || n, key: `${a}${n.replace(/^0+/, "") || n}` };
  }
  throw new ApiError("bad_request", "Enter a 2-letter airline code and a flight number (for example UA and 88).");
}

function buildRouteNotices(from: string, to: string): FlightLookupResult["routeNotices"] {
  const fromCountry = countryForAirport(from) ?? null;
  const toCountry = countryForAirport(to) ?? null;
  const notices: FlightLookupResult["routeNotices"] = [];

  // US TSA always relevant when origin or destination is the US.
  if (fromCountry === "US" || toCountry === "US") {
    notices.push({
      scope: "tsa",
      text: "TSA liquid and battery rules apply for US security screening. Keep liquids ≤100 ml in carry-on and spare lithium batteries in the cabin.",
      sourceUrl: "https://www.tsa.gov/travel/security-screening/whatcanibring",
      lastVerified: "2026-09-20",
    });
  }

  if (fromCountry && toCountry && fromCountry !== toCountry) {
    const tips = loadCountryTips(toCountry);
    if (tips.length) {
      for (const tip of tips.slice(0, 4)) {
        notices.push({ scope: "country", ...tip });
      }
    } else {
      notices.push({
        scope: "country",
        text: `International trip to ${toCountry}: check customs rules for food, plants, medication, drones, and cash before you fly.`,
        sourceUrl: "https://www.iatatravelcentre.com/",
        lastVerified: "2026-09-20",
      });
    }
  }

  return notices;
}

function fromFixture(airline: string, flightNumber: string, departDate?: string): FlightLookupResult | null {
  const key = `${airline}${flightNumber}`;
  const hit = FIXTURE_FLIGHTS[key] ?? FIXTURE_FLIGHTS[`${airline}${flightNumber.replace(/^0+/, "")}`];
  if (!hit) return null;
  const fromCountry = countryForAirport(hit.from) ?? null;
  const toCountry = countryForAirport(hit.to) ?? null;
  return {
    airline,
    flightNumber,
    flightLabel: `${airline}${flightNumber}`,
    from: hit.from,
    to: hit.to,
    fromName: hit.fromName,
    toName: hit.toName,
    fromCountry,
    toCountry,
    departDate: departDate ?? hit.departDate ?? null,
    international: fromCountry !== toCountry,
    source: "fixture",
    routeNotices: buildRouteNotices(hit.from, hit.to),
  };
}

async function fromAviationStack(
  airline: string,
  flightNumber: string,
  departDate?: string,
): Promise<FlightLookupResult | null> {
  if (!env.aviationStackKey) return null;
  const url = new URL("https://api.aviationstack.com/v1/flights");
  url.searchParams.set("access_key", env.aviationStackKey);
  url.searchParams.set("airline_iata", airline);
  url.searchParams.set("flight_number", flightNumber);
  url.searchParams.set("limit", "1");
  if (departDate) url.searchParams.set("flight_date", departDate);

  const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) return null;
  const body = (await res.json()) as {
    data?: Array<{
      airline?: { iata?: string };
      flight?: { number?: string; iata?: string };
      departure?: { iata?: string; airport?: string; scheduled?: string };
      arrival?: { iata?: string; airport?: string };
      flight_date?: string;
    }>;
  };
  const row = body.data?.[0];
  const from = row?.departure?.iata?.toUpperCase();
  const to = row?.arrival?.iata?.toUpperCase();
  if (!from || !to) return null;
  const fromCountry = countryForAirport(from) ?? null;
  const toCountry = countryForAirport(to) ?? null;
  const date = departDate ?? row.flight_date ?? row.departure?.scheduled?.slice(0, 10) ?? null;
  return {
    airline,
    flightNumber,
    flightLabel: row.flight?.iata ?? `${airline}${flightNumber}`,
    from,
    to,
    fromName: row.departure?.airport ?? from,
    toName: row.arrival?.airport ?? to,
    fromCountry,
    toCountry,
    departDate: date,
    international: fromCountry !== toCountry,
    source: "live",
    routeNotices: buildRouteNotices(from, to),
  };
}

export async function lookupFlight(input: FlightLookupInput): Promise<FlightLookupResult> {
  const { airline, flightNumber } = normalizeFlightQuery(input.airline, input.flightNumber);
  const live = await fromAviationStack(airline, flightNumber, input.departDate);
  if (live) return live;
  const fixture = fromFixture(airline, flightNumber, input.departDate);
  if (fixture) return fixture;
  throw new ApiError(
    "bad_request",
    `Couldn’t find ${airline}${flightNumber}. Try a demo flight like UA 88 (SFO→DEL), BA 178 (JFK→LHR), or AS 204 (SEA→KEF).`,
  );
}
