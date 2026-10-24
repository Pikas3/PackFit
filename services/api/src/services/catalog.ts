import catalog from "../../data/catalog.json" with { type: "json" };
import type { Category } from "../schemas.js";

export type CatalogEntry = {
  w: number;
  h: number;
  d: number;
  kg: number;
  hardness: number;
  soft: boolean;
  fragile: boolean;
  upright: boolean;
};

const table = catalog as Record<Category, CatalogEntry>;

export function catalogFor(category: Category): CatalogEntry {
  return table[category] ?? table.other;
}
