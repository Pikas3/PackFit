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
  /** How sure the route is for the requested date, when it is not that day's own flight. */
  routeNote?: string | null;
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
    a = m[1] ?? a;
    n = m[2] ?? n;
  }
  if (a.length === 2 && n.length >= 1) {
    return { airline: a, flightNumber: n.replace(/^0+/, "") || n, key: `${a}${n.replace(/^0+/, "") || n}` };
  }
  throw new ApiError("bad_request", "Enter a 2-letter airline code and a flight number (for example UA and 88).", 400);
}

function buildRouteNotices(from: string, to: string): FlightLookupResult["routeNotices"] {
  const fromCountry = countryForAirport(from) ?? null;
  const toCountry = countryForAirport(to) ?? null;
  const notices: FlightLookupResult["routeNotices"] = [];

  // TSA rules show up as item flags only when an item breaks one, so no blanket notice here.
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

type Route = Pick<FlightLookupResult, "from" | "to" | "fromName" | "toName" | "fromCountry" | "toCountry">;

/** One operation of a flight number: its date (local departure day) and airports. */
type Leg = { date: string; from: string; to: string };

/** What the actor knows about a flight number: about ten days back and two days ahead. */
type FlightHistory = {
  /** The operation running now or next. */
  next: Leg;
  legs: Leg[];
  /** Airport names and countries the actor gave, by IATA code. */
  airports: Record<string, { name: string; country: string | null }>;
};

/**
 * Flight histories by flight number. Each Apify run costs money and takes seconds; a history
 * stays right for hours (schedules change slowly, but new days appear), misses (typos, flights
 * not operating) are remembered an hour. In memory: a restart starts empty.
 */
const HISTORY_TTL_MS = 12 * 3600 * 1000;
const MISS_TTL_MS = 3600 * 1000;
const historyCache = new Map<string, { history: FlightHistory | null; until: number }>();

export function clearFlightCache() {
  historyCache.clear();
}

type ApifyLeg = { date?: string; originIata?: string | null; destinationIata?: string | null; cancelled?: boolean };
type ApifyFlightRow = {
  resultUnknown?: boolean;
  scheduledDepartureLocal?: string | null;
  scheduledDeparture?: string | null;
  originIata?: string | null;
  destinationIata?: string | null;
  originAirport?: string | null;
  destinationAirport?: string | null;
  originCity?: string | null;
  destinationCity?: string | null;
  originCountryCode?: string | null;
  destinationCountryCode?: string | null;
  recentFlights?: ApifyLeg[];
};

/**
 * The flight number's recent and next operations from an Apify actor
 * (apt_marble/flight-status-tracker by default), one run of a few seconds. Null when there is
 * no token or no such flight; throws when Apify fails.
 */
async function historyFromApify(airline: string, flightNumber: string): Promise<FlightHistory | null> {
  if (!env.apifyToken) return null;
  const url = new URL(`https://api.apify.com/v2/acts/${env.flightActor}/run-sync-get-dataset-items`);
  url.searchParams.set("timeout", "20");
  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      // The token goes in a header, never the URL, so it stays out of logs.
      headers: { Authorization: `Bearer ${env.apifyToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        flights: [`${airline}${flightNumber}`],
        includeHistory: true,
        maxHistoryLegs: 14,
        maxRows: 1,
      }),
      signal: AbortSignal.timeout(22_000),
    });
  } catch (err) {
    console.warn(`[flight] Apify unreachable or slow: ${(err as Error).message}`);
    throw new ApiError("upstream_unavailable", "The flight lookup took too long. Try again in a moment.", 502);
  }
  const body = (await res.json().catch(() => null)) as ApifyFlightRow[] | { error?: { type?: string; message?: string } } | null;
  if (!res.ok || !Array.isArray(body)) {
    const error = body && !Array.isArray(body) ? body.error : undefined;
    console.warn(`[flight] Apify ${res.status} ${error?.type ?? ""}: ${error?.message ?? ""}`);
    throw new ApiError("upstream_unavailable", "The flight lookup service failed. Try again, or use a demo flight.", 502);
  }
  const row = body.find((r) => !r.resultUnknown && r.originIata && r.destinationIata);
  if (!row?.originIata || !row.destinationIata) return null;
  const up = (s: string) => s.toUpperCase();
  const next: Leg = {
    date: (row.scheduledDepartureLocal ?? row.scheduledDeparture ?? "").slice(0, 10),
    from: up(row.originIata),
    to: up(row.destinationIata),
  };
  const legs = (row.recentFlights ?? []).flatMap((l): Leg[] =>
    l.date && l.originIata && l.destinationIata && !l.cancelled
      ? [{ date: l.date.slice(0, 10), from: up(l.originIata), to: up(l.destinationIata) }]
      : [],
  );
  const airports: FlightHistory["airports"] = {
    [next.from]: { name: row.originAirport ?? row.originCity ?? next.from, country: row.originCountryCode ?? null },
    [next.to]: { name: row.destinationAirport ?? row.destinationCity ?? next.to, country: row.destinationCountryCode ?? null },
  };
  return { next, legs, airports };
}

const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const weekday = (iso: string) => new Date(iso + "T00:00:00Z").getUTCDay();

/**
 * The leg for the trip's date. That day's own flight when the history covers it; for later
 * dates, the most recent flight on the same weekday (airline schedules repeat weekly), with a
 * note saying so. Null when the history covers the date and the flight does not fly that day.
 */
export function legForDate(
  history: Pick<FlightHistory, "next" | "legs">,
  label: string,
  departDate?: string,
): { leg: Leg; note: string | null } | null {
  if (!departDate) return { leg: history.next, note: null };
  const exact = history.legs.find((l) => l.date === departDate) ?? (history.next.date === departDate ? history.next : undefined);
  if (exact) return { leg: exact, note: null };
  const dates = [...history.legs.map((l) => l.date), history.next.date].filter(Boolean).sort();
  const first = dates[0];
  const last = dates[dates.length - 1];
  if (first && last && departDate >= first && departDate <= last) return null;
  const day = weekday(departDate);
  const sameDay = history.legs
    .filter((l) => weekday(l.date) === day)
    .sort((a, b) => b.date.localeCompare(a.date))[0];
  const asOf = sameDay?.date ?? last ?? "";
  const route = (l: Leg) => `${l.from}→${l.to}`;
  if (sameDay) {
    return {
      leg: sameDay,
      note: `${label}'s schedule for ${departDate} isn’t published yet. On ${WEEKDAYS[day]}s it flies ${route(sameDay)} (as of ${asOf}); check again closer to the date.`,
    };
  }
  const latest = [...history.legs].sort((a, b) => b.date.localeCompare(a.date))[0] ?? history.next;
  return {
    leg: latest,
    note: `${label}'s schedule for ${departDate} isn’t published yet, and it hasn’t flown on a ${WEEKDAYS[day]} lately. Showing its latest route, ${route(latest)}; check again closer to the date.`,
  };
}

function routeFor(leg: Leg, airports: FlightHistory["airports"]): Route {
  return {
    from: leg.from,
    to: leg.to,
    fromName: airports[leg.from]?.name ?? leg.from,
    toName: airports[leg.to]?.name ?? leg.to,
    fromCountry: countryForAirport(leg.from) ?? airports[leg.from]?.country ?? null,
    toCountry: countryForAirport(leg.to) ?? airports[leg.to]?.country ?? null,
  };
}

function liveResult(
  airline: string,
  flightNumber: string,
  departDate: string | undefined,
  history: FlightHistory,
): FlightLookupResult {
  const label = `${airline}${flightNumber}`;
  const pick = legForDate(history, label, departDate);
  if (!pick) {
    throw new ApiError(
      "bad_request",
      `${label} doesn’t fly on ${departDate}. Check the date, or the flight number on your booking.`,
      404,
    );
  }
  const route = routeFor(pick.leg, history.airports);
  return {
    airline,
    flightNumber,
    // The code the user typed; the actor's own label can differ (IndiGo 6E1 comes back "N01").
    flightLabel: label,
    ...route,
    departDate: departDate ?? (pick.leg.date || null),
    international: route.fromCountry !== route.toCountry,
    source: "live",
    routeNote: pick.note,
    routeNotices: buildRouteNotices(route.from, route.to),
  };
}


/**
 * The flight's route from AviationStack's most recent flights under that number. Routes rarely
 * change by date, and filtering by date is a paid feature, so the date is not sent; the user's
 * date is kept. Null when there is no key or no such flight; throws when AviationStack refuses.
 */
async function fromAviationStack(
  airline: string,
  flightNumber: string,
  departDate?: string,
): Promise<FlightLookupResult | null> {
  if (!env.aviationStackKey) return null;
  const url = new URL(`${env.aviationStackBaseUrl.replace(/\/$/, "")}/flights`);
  url.searchParams.set("access_key", env.aviationStackKey);
  url.searchParams.set("airline_iata", airline);
  url.searchParams.set("flight_number", flightNumber);
  url.searchParams.set("limit", "1");

  let res: Response;
  try {
    res = await fetch(url, { signal: AbortSignal.timeout(8000) });
  } catch (err) {
    console.warn(`[flight] AviationStack unreachable: ${(err as Error).message}`);
    throw new ApiError("upstream_unavailable", "The flight lookup service is unreachable. Try again, or use a demo flight.", 502);
  }
  const body = (await res.json().catch(() => ({}))) as {
    error?: { code?: string; message?: string };
    data?: Array<{
      airline?: { iata?: string };
      flight?: { number?: string; iata?: string };
      departure?: { iata?: string; airport?: string; scheduled?: string };
      arrival?: { iata?: string; airport?: string };
      flight_date?: string;
    }>;
  };
  if (!res.ok || body.error) {
    // Never echo the URL: it carries the key.
    console.warn(`[flight] AviationStack ${res.status} ${body.error?.code ?? ""}: ${body.error?.message ?? ""}`);
    const hint =
      body.error?.code === "https_access_restricted"
        ? " (the free plan needs AVIATIONSTACK_BASE_URL=http://api.aviationstack.com/v1)"
        : body.error?.code === "usage_limit_reached"
          ? " (monthly request limit reached)"
          : "";
    throw new ApiError("upstream_unavailable", `The flight lookup service refused the request${hint}.`, 502);
  }
  const row = body.data?.[0];
  const from = row?.departure?.iata?.toUpperCase();
  const to = row?.arrival?.iata?.toUpperCase();
  if (!row || !from || !to) return null;
  const fromCountry = countryForAirport(from) ?? null;
  const toCountry = countryForAirport(to) ?? null;
  // Their flight_date is the last time it flew, not the user's trip.
  const date = departDate ?? null;
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
  // Demo flights answer instantly and keep the demo working offline or out of quota.
  const fixture = fromFixture(airline, flightNumber, input.departDate);
  if (fixture) return fixture;

  const key = `${airline}${flightNumber}`;
  const cached = historyCache.get(key);
  let apifyFailure: unknown;
  if (cached && cached.until > Date.now()) {
    if (cached.history) return liveResult(airline, flightNumber, input.departDate, cached.history);
  } else {
    let history: FlightHistory | null = null;
    try {
      history = await historyFromApify(airline, flightNumber);
      // Only answers are cached; a failed run is retried next time.
      if (env.apifyToken) {
        historyCache.set(key, { history, until: Date.now() + (history ? HISTORY_TTL_MS : MISS_TTL_MS) });
      }
    } catch (err) {
      apifyFailure = err;
    }
    if (history) return liveResult(airline, flightNumber, input.departDate, history);
  }

  const live = await fromAviationStack(airline, flightNumber, input.departDate);
  if (live) return live;
  if (apifyFailure) throw apifyFailure;
  const demos = "Try a demo flight like UA 88 (SFO→DEL), BA 178 (JFK→LHR), or AS 204 (SEA→KEF).";
  if (!env.apifyToken && !env.aviationStackKey) {
    throw new ApiError(
      "bad_request",
      `Couldn’t find ${airline}${flightNumber}: live flight lookup isn’t set up on the server, so only demo flights work. ${demos}`,
      404,
    );
  }
  throw new ApiError(
    "bad_request",
    `Couldn’t find ${airline}${flightNumber} flying today or soon. Check the airline code and number. ${demos}`,
    404,
  );
}
