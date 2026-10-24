import { randomUUID } from "node:crypto";
import { callClaudeTool } from "../claude/client.js";
import { buildSuggestItemsPrompt, SuggestItemsToolSchema } from "../claude/prompts/suggestItems.js";
import { airportCoords, countryForAirport } from "../rules/store.js";
import type { Item, Trip } from "../schemas.js";
import { catalogFor } from "./catalog.js";

export type TripSuggestResult = {
  suggestions: Item[];
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
  >;
};

async function fetchWeather(
  trip: Trip,
): Promise<{ weather: TripSuggestResult["weather"]; warning?: TripSuggestResult["warnings"][number] }> {
  const coords = airportCoords(trip.to);
  const sourceUrl = "https://open-meteo.com/";
  if (!coords) {
    return {
      weather: {
        summary: "Weather unavailable for this airport code.",
        lowC: 15,
        highC: 25,
        precipChance: 0.2,
        sourceUrl,
      },
      warning: { kind: "weather_unavailable", message: `No coordinates for ${trip.to}` },
    };
  }

  if (!trip.departDate) {
    return {
      weather: {
        summary: "No departDate provided; using mild temperate defaults.",
        lowC: 12,
        highC: 22,
        precipChance: 0.25,
        sourceUrl,
      },
      warning: { kind: "weather_unavailable", message: "departDate missing; skipped live forecast" },
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
        summary: "Live weather fetch failed; using mild defaults.",
        lowC: 12,
        highC: 22,
        precipChance: 0.25,
        sourceUrl,
      },
      warning: { kind: "weather_unavailable", message: "Open-Meteo unavailable" },
    };
  }
}

function mockSuggestions(trip: Trip) {
  const base = [
    { name: "T-shirt stack", category: "clothing" as const, qty: Math.min(5, Math.max(2, trip.nights)) },
    { name: "Jeans", category: "clothing" as const, qty: 1 },
    { name: "Toiletry pouch", category: "toiletries" as const, qty: 1 },
    { name: "Phone charger cable", category: "electronics" as const, qty: 1 },
  ];
  if (trip.activities.some((a) => /ski|cold|winter/i.test(a))) {
    base.push({ name: "Warm sweater", category: "clothing", qty: 2 });
  }
  if (countryForAirport(trip.to) !== countryForAirport(trip.from)) {
    base.push({ name: "Passport wallet", category: "documents", qty: 1 });
  }
  return { suggestions: base };
}

export async function suggestTrip(trip: Trip): Promise<TripSuggestResult> {
  const { weather, warning } = await fetchWeather(trip);
  const prompt = buildSuggestItemsPrompt({ trip, weatherSummary: weather.summary });
  const { data } = await callClaudeTool({
    prompt,
    schema: SuggestItemsToolSchema,
    mock: () => mockSuggestions(trip),
  });

  const suggestions: Item[] = [];
  for (const s of data.suggestions) {
    const cat = catalogFor(s.category);
    for (let i = 0; i < s.qty; i++) {
      suggestions.push({
        id: randomUUID(),
        name: s.qty > 1 ? `${s.name} (${i + 1})` : s.name,
        w: cat.w,
        h: cat.h,
        d: cat.d,
        kg: cat.kg,
        fragile: cat.fragile,
        hardness: cat.hardness,
        soft: cat.soft,
        upright: cat.upright,
        category: s.category,
        confidence: 1,
        source: "suggested",
        measurement: { method: "catalog", confidence: 1, deviceHasLidar: false },
      });
    }
  }

  const warnings: TripSuggestResult["warnings"] = [];
  if (warning) warnings.push(warning);

  const estimatedKg = suggestions.reduce((sum, i) => sum + i.kg, 0);
  if (estimatedKg > trip.checked.weightLimitKg) {
    warnings.push({
      kind: "overweight",
      bag: "checked",
      estimatedKg: Math.round(estimatedKg * 10) / 10,
      limitKg: trip.checked.weightLimitKg,
    });
  }

  const international = countryForAirport(trip.from) !== countryForAirport(trip.to);
  if (international) {
    warnings.push({ kind: "souvenir_space", reservedLitres: Math.max(5, trip.nights) });
  }

  return { suggestions, weather, warnings };
}
