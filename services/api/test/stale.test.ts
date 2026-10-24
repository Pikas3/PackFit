import { describe, expect, it } from "vitest";
import { isStale } from "../src/rules/stale.js";

describe("stale", () => {
  it("flags dates older than 30 days", () => {
    const now = new Date("2026-10-24T00:00:00Z");
    expect(isStale("2026-10-01", now)).toBe(false);
    expect(isStale("2026-08-01", now)).toBe(true);
  });
});
