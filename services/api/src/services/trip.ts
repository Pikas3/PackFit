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

  try {
    const start = trip.departDate;
    const endDate = new Date(start + "T00:00:00Z");
    endDate.setUTCDate(endDate.getUTCDate() + Math.max(0, trip.nights));
    const end = endDate.toISOString().slice(0, 10);
    const url = new URL("https://api.open-meteo.com/v1/forecast");
    url.searchParams.set("latitude", String(coords.lat));
    url.searchParams.set("longitude", String(coords.lon));
    url.searchParams.set("daily", "temperature_2m_max,temperature_2m_min,precipitation_probability_max");
    url.searchParams.set("timezone", "auto");
    url.searchParams.set("start_date", start);
    url.searchParams.set("end_date", end);

    const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) throw new Error(`Open-Meteo HTTP ${res.status}`);
    const body = (await res.json()) as {
      daily?: {
        temperature_2m_max?: number[];
        temperature_2m_min?: number[];
        precipitation_probability_max?: number[];
      };
    };
    const highs = body.daily?.temperature_2m_max ?? [];
    const lows = body.daily?.temperature_2m_min ?? [];
    const precip = body.daily?.precipitation_probability_max ?? [];
    const highC = highs.length ? Math.max(...highs) : 22;
    const lowC = lows.length ? Math.min(...lows) : 12;
    const precipChance = precip.length
      ? precip.reduce((a, b) => a + b, 0) / precip.length / 100
      : 0.2;
    return {
      weather: {
        summary: `Forecast highs around ${Math.round(highC)}°C and lows around ${Math.round(lowC)}°C.`,
        lowC,
        highC,
        precipChance,
        sourceUrl: url.toString(),
      },
    };
  } catch {
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

function mockSuggestions(trip: Trip) {
  const base = [
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
