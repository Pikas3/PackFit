import { z } from "zod";

/** zod mirror of schemas/*.schema.json — keep in sync with Section 1. */

export const CategorySchema = z.enum([
  "clothing",
  "shoes",
  "toiletries",
  "liquids",
  "electronics",
  "documents",
  "medical",
  "food",
  "sharp",
  "other",
]);
export type Category = z.infer<typeof CategorySchema>;

export const MeasureMethodSchema = z.enum([
  "lidar",
  "reference",
  "manual",
  "catalog",
  "estimate",
]);

export const MeasurementSchema = z.object({
  method: MeasureMethodSchema,
  confidence: z.number().min(0).max(1),
  deviceHasLidar: z.boolean(),
});
export type Measurement = z.infer<typeof MeasurementSchema>;

export const ItemSourceSchema = z.enum(["scan", "manual", "suggested", "fixture"]);

export const ItemSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  w: z.number().positive(),
  h: z.number().positive(),
  d: z.number().positive(),
  kg: z.number().min(0),
  fragile: z.boolean(),
  hardness: z.number().min(0).max(1),
  soft: z.boolean(),
  upright: z.boolean(),
  category: CategorySchema,
  confidence: z.number().min(0).max(1),
  neededAtSecurity: z.boolean().optional(),
  source: ItemSourceSchema.optional(),
  measurement: MeasurementSchema.optional(),
});
export type Item = z.infer<typeof ItemSchema>;

const DimsSchema = z
  .array(z.number().positive())
  .length(3)
  .transform((d) => d as [number, number, number]);

export const CompartmentSchema = z.object({
  name: z.string().min(1),
  dims: DimsSchema,
  compressibility: z.number().min(0).max(1),
});

export const ContainerSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1),
  type: z.enum(["suitcase", "duffel", "backpack"]),
  outer: DimsSchema,
  compartments: z.array(CompartmentSchema).min(1),
  weightLimitKg: z.number().positive(),
  wheelsSide: z.enum(["back", "bottom"]).optional(),
  measurement: MeasurementSchema.optional(),
});
export type Container = z.infer<typeof ContainerSchema>;

export const RuleScopeSchema = z.enum(["tsa", "airline", "country"]);
export const RuleSeveritySchema = z.enum(["banned", "restricted", "check"]);

export const RuleFlagSchema = z.object({
  itemId: z.string().min(1),
  scope: RuleScopeSchema,
  severity: RuleSeveritySchema,
  text: z.string().min(1),
  sourceUrl: z.string().regex(/^https?:\/\//),
  lastVerified: z.string().regex(/^\d{4}-\d{2}-\d{2}/),
  ruleId: z.string().min(1).optional(),
});
export type RuleFlag = z.infer<typeof RuleFlagSchema>;

export const TripSchema = z.object({
  id: z.string().regex(/^[a-z0-9-]+$/).optional(),
  from: z.string().regex(/^[A-Z]{3}$/),
  to: z.string().regex(/^[A-Z]{3}$/),
  airline: z.string().regex(/^[A-Z0-9]{2}$/),
  nights: z.number().int().min(0),
  activities: z.array(z.string().min(1)),
  carryOn: ContainerSchema,
  checked: ContainerSchema,
  departDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});
export type Trip = z.infer<typeof TripSchema>;

export const PlacementSchema = z.object({
  itemId: z.string().min(1),
  x: z.number(),
  y: z.number(),
  z: z.number(),
  w: z.number().positive(),
  h: z.number().positive(),
  d: z.number().positive(),
  order: z.number().int().min(0),
  compartment: z.string().min(1).optional(),
});

export const PlanSchema = z.object({
  placed: z.array(PlacementSchema),
  unplaced: z.array(z.string()),
  stats: z.object({
    fillPct: z.number(),
    kg: z.number(),
    comHeightPct: z.number(),
  }),
});

export const MetaSchema = z.object({
  requestId: z.string(),
  ms: z.number(),
});

export const ScanItemRequestSchema = z.object({
  imageBase64: z.string().min(1),
  measured: z
    .object({
      w: z.number().positive(),
      h: z.number().positive(),
      d: z.number().positive(),
      method: z.enum(["lidar", "reference", "manual"]),
      confidence: z.number().min(0).max(1),
    })
    .nullable(),
  reference: z.enum(["credit_card", "a4_paper", "letter_paper"]).nullable().optional(),
  hint: z.string().optional(),
});

export const ScanItemResponseSchema = z.object({
  item: ItemSchema,
  alternatives: z.array(z.object({ name: z.string(), category: CategorySchema })),
  warnings: z.array(z.string()),
  meta: MetaSchema,
});

export const RulesCheckRequestSchema = z.object({
  items: z.array(ItemSchema),
  trip: z.object({
    from: z.string().regex(/^[A-Z]{3}$/),
    to: z.string().regex(/^[A-Z]{3}$/),
    airline: z.string().regex(/^[A-Z0-9]{2}$/),
  }),
  bag: z.enum(["carryOn", "checked"]),
});

export const RulesCheckResponseSchema = z.object({
  flags: z.array(RuleFlagSchema),
  summary: z.string(),
  stale: z.boolean(),
  rulesLastSynced: z.string().nullable(),
  meta: MetaSchema,
});

export const RulesAskRequestSchema = z.object({
  question: z.string().min(1),
  trip: z.object({
    from: z.string().regex(/^[A-Z]{3}$/),
    to: z.string().regex(/^[A-Z]{3}$/),
    airline: z.string().regex(/^[A-Z0-9]{2}$/),
  }),
  bag: z.enum(["carryOn", "checked"]),
});

export const RulesAskResponseSchema = z.object({
  answer: z.string(),
  flags: z.array(RuleFlagSchema),
  stale: z.boolean(),
  meta: MetaSchema,
});

export const TripLookupRequestSchema = z.object({
  airline: z.string().min(1),
  flightNumber: z.string().min(1),
  departDate: z.string().optional(),
});

export const TripLookupResponseSchema = z.object({
  airline: z.string(),
  flightNumber: z.string(),
  flightLabel: z.string(),
  from: z.string(),
  to: z.string(),
  fromName: z.string(),
  toName: z.string(),
  fromCountry: z.string().nullable(),
  toCountry: z.string().nullable(),
  departDate: z.string().nullable(),
  international: z.boolean(),
  source: z.enum(["live", "fixture"]),
  /** How sure the route is for the requested date, when it is not that day's own flight. */
  routeNote: z.string().nullable().optional(),
  routeNotices: z.array(
    z.object({
      text: z.string(),
      sourceUrl: z.string(),
      lastVerified: z.string(),
      scope: z.enum(["tsa", "country"]),
    }),
  ),
  meta: MetaSchema,
});

export const TripSuggestRequestSchema = z.object({
  trip: TripSchema,
});

/** Packing suggestion DTO (not Item). Additive API shape — see docs/requests.md. */
export const SuggestionSchema = z.object({
  id: z.string(),
  name: z.string(),
  reason: z.string(),
  category: CategorySchema,
  estDims: z.tuple([z.number(), z.number(), z.number()]),
  estKg: z.number(),
  fragile: z.boolean(),
  soft: z.boolean(),
  essential: z.boolean(),
});

export const BeforeYouGoTipSchema = z.object({
  text: z.string(),
  sourceUrl: z.string(),
  lastVerified: z.string(),
});

export const TripSuggestResponseSchema = z.object({
  suggestions: z.array(SuggestionSchema),
  weather: z.object({
    summary: z.string(),
    lowC: z.number(),
    highC: z.number(),
    precipChance: z.number(),
    sourceUrl: z.string(),
  }),
  warnings: z.array(
    z.union([
      z.object({
        kind: z.literal("overweight"),
        bag: z.enum(["carryOn", "checked"]),
        estimatedKg: z.number(),
        limitKg: z.number(),
      }),
      z.object({
        kind: z.literal("souvenir_space"),
        reservedLitres: z.number(),
      }),
      z.object({
        kind: z.literal("weather_unavailable"),
        message: z.string(),
      }),
      z.object({
        kind: z.literal("unknown_airline"),
        message: z.string(),
      }),
    ]),
  ),
  beforeYouGo: z
    .object({
      pack: z.array(BeforeYouGoTipSchema),
      leaveOrDeclare: z.array(BeforeYouGoTipSchema),
      medicationFood: z.array(BeforeYouGoTipSchema),
    })
    .optional(),
  destinationCountry: z.string().nullable().optional(),
  meta: MetaSchema,
});

export const RuleRecordSchema = z.object({
  ruleId: z.string(),
  scope: RuleScopeSchema,
  subject: z.string(),
  keywords: z.array(z.string()),
  categories: z.array(CategorySchema),
  severity: RuleSeveritySchema,
  carryOn: z.enum(["ok", "restricted", "banned"]),
  checked: z.enum(["ok", "restricted", "banned"]),
  text: z.string(),
  sourceUrl: z.string().regex(/^https?:\/\//),
  lastVerified: z.string(),
  limits: z
    .object({
      maxCm: z.tuple([z.number(), z.number(), z.number()]).optional(),
      maxKg: z.number().optional(),
      maxWh: z.number().optional(),
      maxMl: z.number().optional(),
    })
    .optional(),
});
export type RuleRecord = z.infer<typeof RuleRecordSchema>;
