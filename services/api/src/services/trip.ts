import { randomUUID } from "node:crypto";
import { callClaudeTool } from "../claude/client.js";
import { buildSuggestItemsPrompt, SuggestItemsToolSchema } from "../claude/prompts/suggestItems.js";
import { airportCoords, countryForAirport, loadCountryTips } from "../rules/store.js";
import type { Category, Trip } from "../schemas.js";
import { catalogFor } from "./catalog.js";

export type Suggestion = {
  id: string;
  name: string;
  reason: string;
  category: Category;
  estDims: [number, number, number];
  estKg: number;
  fragile: boolean;
  soft: boolean;
  essential: boolean;
};

export type BeforeYouGoTip = {
  text: string;
  sourceUrl: string;
  lastVerified: string;
};

export type TripSuggestResult = {
  suggestions: Suggestion[];
  weather: {
    summary: string;
    lowC: number;
    highC: number;
    precipChance: number;
    sourceUrl: string;
  };
  warnings: Array<
    | { kind: "overweight"; bag: "checked"; estimatedKg: number; limitKg: number }
    | { kind: "souvenir_space"; reservedLitres: number }
    | { kind: "weather_unavailable"; message: string }
    | { kind: "unknown_airline"; message: string }
  >;
  beforeYouGo: {
    pack: BeforeYouGoTip[];
    leaveOrDeclare: BeforeYouGoTip[];
    medicationFood: BeforeYouGoTip[];
  };
  destinationCountry: string | null;
};

const KNOWN_AIRLINES = new Set([
  "UA", "AA", "DL", "WN", "B6", "AS", "NK", "F9", "BA", "LH", "AF", "KL", "EK", "QR", "SQ", "CX", "NH", "KE", "AI", "UK",
]);

async function fetchWeather(
  trip: Trip,
): Promise<{ weather: TripSuggestResult["weather"]; warning?: TripSuggestResult["warnings"][number] }> {
  const coords = airportCoords(trip.to);
  const sourceUrl = "https://open-meteo.com/";
  if (!coords) {
    return {
      weather: {
        summary: "No forecast for that airport code — pick a listed destination or check the weather yourself.",
        lowC: 15,
        highC: 25,
        precipChance: 0.2,
        sourceUrl,
      },
      warning: {
        kind: "weather_unavailable",
        message: `No coordinates for ${trip.to}. Using a mild default summary.`,
      },
    };
  }

  if (!trip.departDate) {
    return {
      weather: {
        summary: "No departure date yet — showing a mild temperate default forecast.",
        lowC: 12,
        highC: 22,
        precipChance: 0.25,
        sourceUrl,
      },
      warning: {
        kind: "weather_unavailable",
        message: "Add a depart date (YYYY-MM-DD) for a live forecast.",
      },
    };
  }

  const window = weatherWindow(trip.departDate, trip.nights);
  const forecast = window.source === "forecast";
  const url = new URL(forecast ? "https://api.open-meteo.com/v1/forecast" : "https://archive-api.open-meteo.com/v1/archive");
  url.searchParams.set("latitude", String(coords.lat));
  url.searchParams.set("longitude", String(coords.lon));
  url.searchParams.set(
    "daily",
    forecast
      ? "temperature_2m_max,temperature_2m_min,precipitation_probability_max"
      : "temperature_2m_max,temperature_2m_min,precipitation_sum",
  );
  url.searchParams.set("timezone", "auto");
  url.searchParams.set("start_date", window.start);
  url.searchParams.set("end_date", window.end);
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
    const body = (await res.json()) as {
      reason?: string;
      daily?: {
        temperature_2m_max?: (number | null)[];
        temperature_2m_min?: (number | null)[];
        precipitation_probability_max?: (number | null)[];
        precipitation_sum?: (number | null)[];
      };
    };
    if (!res.ok) throw new Error(`Open-Meteo HTTP ${res.status}: ${body.reason ?? "no reason"}`);
    const nums = (a?: (number | null)[]) => (a ?? []).filter((n): n is number => typeof n === "number");
    const highs = nums(body.daily?.temperature_2m_max);
    const lows = nums(body.daily?.temperature_2m_min);
    if (!highs.length || !lows.length) throw new Error("Open-Meteo returned no temperatures");
    const highC = Math.max(...highs);
    const lowC = Math.min(...lows);
    let precipChance = 0.2;
    if (forecast) {
      const p = nums(body.daily?.precipitation_probability_max);
      if (p.length) precipChance = p.reduce((a, b) => a + b, 0) / p.length / 100;
    } else {
      // Archive has rain amounts, not chances: the share of days with at least 1 mm.
      const p = nums(body.daily?.precipitation_sum);
      if (p.length) precipChance = p.filter((mm) => mm >= 1).length / p.length;
    }
    const temps = `highs around ${Math.round(highC)}°C and lows around ${Math.round(lowC)}°C`;
    const span = `${shortDate(window.start)}–${shortDate(window.end)}`;
    const summary = forecast
      ? `Forecast for ${span}: ${temps}.${window.clamped ? ` The forecast only reaches ${shortDate(window.end)}.` : ""}`
      : `Too far ahead for a forecast. Last year on these dates (${span} ${window.start.slice(0, 4)}): ${temps}.`;
    return {
      weather: { summary, lowC, highC, precipChance, sourceUrl: url.toString() },
    };
  } catch (err) {
    console.warn(`[weather] ${trip.to} ${window.start}..${window.end}: ${(err as Error).message}`);
    return {
      weather: {
        summary: "Live weather is unavailable — using a mild default. Pack layers to be safe.",
        lowC: 12,
        highC: 22,
        precipChance: 0.25,
        sourceUrl,
      },
      warning: { kind: "weather_unavailable", message: "Open-Meteo unavailable; offline defaults applied." },
    };
  }
}

/** Open-Meteo's forecast reaches this many days ahead, today included. */
export const FORECAST_DAYS = 16;

/**
 * Which dates to ask Open-Meteo for. Inside the forecast range: the trip's days, cut off where
 * the forecast ends. Starting later (or already past): the same days last year, from the archive.
 */
export function weatherWindow(
  departDate: string,
  nights: number,
  today: Date = new Date(),
): { source: "forecast" | "last_year"; start: string; end: string; clamped: boolean } {
  const day = (d: Date) => d.toISOString().slice(0, 10);
  const addDays = (iso: string, n: number) => {
    const d = new Date(iso + "T00:00:00Z");
    d.setUTCDate(d.getUTCDate() + n);
    return day(d);
  };
  const start = departDate;
  const end = addDays(start, Math.max(0, nights));
  const first = day(today);
  const last = addDays(first, FORECAST_DAYS - 1);
  if (start >= first && start <= last) {
    return { source: "forecast", start, end: end > last ? last : end, clamped: end > last };
  }
  const lastYear = (iso: string) => `${Number(iso.slice(0, 4)) - 1}${iso.slice(4)}`.replace(/-02-29$/, "-02-28");
  // Last year's archive ends a few days before today; never ask past that.
  const archiveEnd = addDays(first, -6);
  let ly = { start: lastYear(start), end: lastYear(end) };
  if (ly.end > archiveEnd) ly = { start: lastYear(ly.start), end: lastYear(ly.end) };
  return { source: "last_year", start: ly.start, end: ly.end, clamped: false };
}

function shortDate(iso: string): string {
  return new Date(iso + "T00:00:00Z").toLocaleDateString("en-GB", { day: "numeric", month: "short", timeZone: "UTC" });
}

function mockSuggestions(trip: Trip) {
  const base: { name: string; reason: string; category: Category; qty: number; essential: boolean }[] = [
    {
      name: "T-shirt stack",
      reason: `Everyday tops for ${trip.nights} nights`,
      category: "clothing" as const,
      qty: Math.min(5, Math.max(2, trip.nights)),
      essential: true,
    },
    {
      name: "Jeans",
      reason: "One durable pair for the trip",
      category: "clothing" as const,
      qty: 1,
      essential: false,
    },
    {
      name: "Toiletry pouch",
      reason: "Basics for the trip length",
      category: "toiletries" as const,
      qty: 1,
      essential: true,
    },
    {
      name: "Phone charger cable",
      reason: "Keep devices charged",
      category: "electronics" as const,
      qty: 1,
      essential: true,
    },
  ];
  if (trip.activities.some((a) => /ski|cold|winter/i.test(a))) {
    base.push({
      name: "Warm sweater",
      reason: "Cold activity on the itinerary",
      category: "clothing",
      qty: 2,
      essential: true,
    });
  }
  if (countryForAirport(trip.to) !== countryForAirport(trip.from)) {
    base.push({
      name: "Passport wallet",
      reason: "International documents",
      category: "documents",
      qty: 1,
      essential: true,
    });
  }
  return { suggestions: base };
}

function buildBeforeYouGo(country: string | undefined): TripSuggestResult["beforeYouGo"] {
  const tips = loadCountryTips(country);
  const pack: BeforeYouGoTip[] = [
    {
      text: `Pack a power adapter suitable for ${country ?? "your destination"} and check charger voltage.`,
      sourceUrl: "https://www.iatatravelcentre.com/",
      lastVerified: "2026-09-20",
    },
    {
      text: "Keep passport and visas in your cabin bag.",
      sourceUrl: "https://travel.state.gov/",
      lastVerified: "2026-09-20",
    },
  ];
  const medicationFood: BeforeYouGoTip[] = [
    {
      text: "Keep prescription medication in original packaging with a copy of the prescription.",
      sourceUrl: "https://www.tsa.gov/travel/security-screening/whatcanibring/items/medications",
      lastVerified: "2026-09-18",
    },
  ];
  return {
    pack,
    leaveOrDeclare: tips.length
      ? tips
      : [
          {
            text: "Check destination customs for food, plants, drones, vapes, and cash limits.",
            sourceUrl: "https://www.iatatravelcentre.com/",
            lastVerified: "2026-09-20",
          },
        ],
    medicationFood,
  };
}

export async function suggestTrip(trip: Trip): Promise<TripSuggestResult> {
  const { weather, warning } = await fetchWeather(trip);
  const prompt = buildSuggestItemsPrompt({ trip, weatherSummary: weather.summary });
  const { data } = await callClaudeTool({
    prompt,
    schema: SuggestItemsToolSchema,
    mock: () => mockSuggestions(trip),
  });

  const suggestions: Suggestion[] = [];
  for (const s of data.suggestions) {
    const cat = catalogFor(s.category);
    for (let i = 0; i < s.qty; i++) {
      suggestions.push({
        id: randomUUID(),
        name: s.qty > 1 ? `${s.name} (${i + 1})` : s.name,
        reason: s.reason,
        category: s.category,
        estDims: [cat.w, cat.h, cat.d],
        estKg: cat.kg,
        fragile: cat.fragile,
        soft: cat.soft,
        essential: s.essential,
      });
    }
  }

  const warnings: TripSuggestResult["warnings"] = [];
  if (warning) warnings.push(warning);
  if (!KNOWN_AIRLINES.has(trip.airline.toUpperCase())) {
    warnings.push({
      kind: "unknown_airline",
      message: `Airline ${trip.airline} isn’t in our short list — baggage limits may be wrong. Check the airline site.`,
    });
  }

  const estimatedKg = suggestions.reduce((sum, i) => sum + i.estKg, 0);
  if (estimatedKg > trip.checked.weightLimitKg) {
    warnings.push({
      kind: "overweight",
      bag: "checked",
      estimatedKg: Math.round(estimatedKg * 10) / 10,
      limitKg: trip.checked.weightLimitKg,
    });
  }

  const destinationCountry = countryForAirport(trip.to) ?? null;
  const international = countryForAirport(trip.from) !== destinationCountry;
  if (international) {
    warnings.push({ kind: "souvenir_space", reservedLitres: Math.max(5, trip.nights) });
  }

  return {
    suggestions,
    weather,
    warnings,
    beforeYouGo: buildBeforeYouGo(destinationCountry ?? undefined),
    destinationCountry,
  };
}
