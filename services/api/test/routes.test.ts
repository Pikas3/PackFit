import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it } from "vitest";
import { app } from "../src/index.js";

const token = "local-dev-token";
process.env.APP_TOKEN = token;
process.env.MOCK_CLAUDE = "1";

const fixtures = join(dirname(fileURLToPath(import.meta.url)), "../../../schemas/fixtures");

function authHeaders(): Record<string, string> {
  return { "content-type": "application/json", "x-snugly-token": token };
}

describe("api routes (mock Claude)", () => {
  beforeAll(() => {
    process.env.MOCK_CLAUDE = "1";
    process.env.APP_TOKEN = token;
  });

  it("GET /health", async () => {
    const res = await app.request("/health");
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.version).toBeTruthy();
  });

  it("rejects missing token", async () => {
    const res = await app.request("/rules/check", { method: "POST", body: "{}" });
    expect(res.status).toBe(401);
  });

  it("POST /scan/item measured", async () => {
    const res = await app.request("/scan/item", {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify({
        imageBase64: "/9j/4AAQ",
        measured: { w: 30, h: 2, d: 21, method: "lidar", confidence: 0.93 },
        reference: null,
        hint: "laptop",
      }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.item.w).toBe(30);
    expect(body.item.source).toBe("scan");
    expect(body.item.measurement.method).toBe("lidar");
    expect(body.meta.requestId).toBeTruthy();
  });

  it("POST /scan/inventory returns several estimated items with boxes", async () => {
    const res = await app.request("/scan/inventory", {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify({ imageBase64: "/9j/4AAQ" }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.detections.length).toBeGreaterThan(1);
    expect(body.warnings).toContain("sample_data");
    for (const d of body.detections) {
      expect(d.item.source).toBe("scan");
      expect(d.item.measurement.method).toBe("estimate");
      expect(d.item.measurement.confidence).toBeLessThanOrEqual(0.5);
      expect(d.box.x + d.box.w).toBeLessThanOrEqual(1);
      expect(["box", "cylinder_upright", "cylinder_lying", null]).toContain(d.shape);
    }
    expect(body.detections.some((d: { shape: string | null }) => d.shape === "cylinder_upright")).toBe(true);
    expect(new Set(body.detections.map((d: { item: { id: string } }) => d.item.id)).size).toBe(
      body.detections.length,
    );
    expect(body.reference).toBeNull();
  });

  it("POST /scan/inventory with a credit card returns the card box", async () => {
    const res = await app.request("/scan/inventory", {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify({ imageBase64: "/9j/4AAQ", reference: "credit_card" }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.reference.box.w).toBeGreaterThan(0);
  });

  it("POST /rules/check flags shampoo / knife fixtures", async () => {
    const items = JSON.parse(readFileSync(join(fixtures, "items.json"), "utf8")) as {
      id: string;
      name: string;
      category: string;
      [k: string]: unknown;
    }[];
    const interesting = items.filter(
      (i) =>
        /shampoo|knife|power bank|peanut/i.test(i.name) ||
        i.category === "liquids" ||
        i.category === "sharp",
    );
    const cleaned = interesting.map(({ _source, ...rest }) => rest);
    const res = await app.request("/rules/check", {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify({
        items: cleaned,
        trip: { from: "SFO", to: "DEL", airline: "UA" },
        bag: "carryOn",
      }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(Array.isArray(body.flags)).toBe(true);
    for (const f of body.flags) {
      expect(f.sourceUrl).toMatch(/^https?:\/\//);
      expect(f.lastVerified).toBeTruthy();
    }
  });

  it("POST /rules/ask", async () => {
    const res = await app.request("/rules/ask", {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify({
        question: "can I bring a power bank",
        trip: { from: "SFO", to: "DEL", airline: "UA" },
        bag: "checked",
      }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(typeof body.answer).toBe("string");
    expect(body.answer.split(/\s+/).length).toBeLessThanOrEqual(45);
  });

  it("POST /trip/suggest for sample trips", async () => {
    const trips = JSON.parse(readFileSync(join(fixtures, "trips.json"), "utf8")) as unknown[];
    const sample = trips.slice(0, 3);
    for (const trip of sample) {
      const res = await app.request("/trip/suggest", {
        method: "POST",
        headers: authHeaders(),
        body: JSON.stringify({ trip }),
      });
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.suggestions.length).toBeGreaterThan(0);
      for (const s of body.suggestions) {
        expect(s.name).toBeTruthy();
        expect(s.reason).toBeTruthy();
        expect(Array.isArray(s.estDims)).toBe(true);
        expect(s.estDims).toHaveLength(3);
        expect(typeof s.essential).toBe("boolean");
      }
      expect(body.beforeYouGo).toBeTruthy();
      expect(body.destinationCountry).toBeTruthy();
      // write snapshot-ish artifact for status
      const id = (trip as { id?: string }).id ?? "trip";
      await import("node:fs").then((fs) =>
        fs.writeFileSync(
          join(dirname(fileURLToPath(import.meta.url)), "snapshots", `${id}.json`),
          JSON.stringify(
            {
              suggestions: body.suggestions.map(
                (s: { name: string; category: string; reason: string; essential: boolean }) => ({
                  name: s.name,
                  category: s.category,
                  reason: s.reason,
                  essential: s.essential,
                }),
              ),
              warnings: body.warnings,
              weather: body.weather,
              beforeYouGo: body.beforeYouGo,
              destinationCountry: body.destinationCountry,
            },
            null,
            2,
          ),
        ),
      );
    }
  });
});
