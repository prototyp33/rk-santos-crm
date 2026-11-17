/**
 * 03_zod_types.ts · CRM Inmobiliario RK Santos · Solfico
 * Versión 1.1 (final) · 17/11/2026
 * -----------------------------------------------------------------------------
 * Esquemas Zod (v4) para las entidades clave y para la SALIDA ESTRUCTURADA del
 * Valorador IA. Fuente única de verdad para:
 *   - validación de formularios / Server Actions (Next.js App Router),
 *   - `Output.object({ schema })` de Vercel AI SDK 6 (`generateText`),
 *   - validación antes de persistir JSON en `valuation_ai_runs.output`,
 *     `transcriptions.extracted_facts` y `valuation_parameters.params`.
 *
 * Los tipos de fila de la BD se generan con `supabase gen types typescript`
 * (database.types.ts). Estos esquemas describen la ENTRADA/SALIDA de dominio.
 * TypeScript estricto: sin `any`, todo inferido con z.infer.
 */
import { z } from "zod";

// -----------------------------------------------------------------------------
// Enums (espejo 1:1 de los tipos enumerados de Postgres)
// -----------------------------------------------------------------------------
export const AppRole = z.enum(["agent", "coordinator", "supervisor"]);

/** Orden canónico del pipeline: el índice del array ES el orden de fase. */
export const PIPELINE_PHASES = [
  "circulo_influencia",
  "prospecto",
  "captacion",
  "documentacion",
  "publicacion",
  "visitas",
  "cierre",
  "notaria",
] as const;
export const PipelinePhase = z.enum(PIPELINE_PHASES);

export const PIPELINE_PHASE_LABELS: Readonly<Record<z.infer<typeof PipelinePhase>, string>> = {
  circulo_influencia: "Círculo de influencia",
  prospecto: "Prospecto",
  captacion: "Captación",
  documentacion: "Documentación",
  publicacion: "Publicación",
  visitas: "Visitas",
  cierre: "Cierre",
  notaria: "Notaría",
};

/** Siguiente fase válida (null en Notaría). La BD lo vuelve a validar en trigger. */
export function nextPhase(p: z.infer<typeof PipelinePhase>): z.infer<typeof PipelinePhase> | null {
  const i = PIPELINE_PHASES.indexOf(p);
  return PIPELINE_PHASES[i + 1] ?? null;
}

export const DealStatus = z.enum(["open", "paused", "won", "lost"]);
export const OperationType = z.enum(["sale", "rent", "transfer"]);
export const PropertyType = z.enum([
  "flat", "penthouse", "duplex", "studio", "house", "semi_detached", "townhouse", "rustic",
  "land", "commercial", "office", "warehouse", "garage", "storage_room", "building", "other",
]);
export const PropertyStatus = z.enum(["draft", "in_acquisition", "available", "reserved", "sold", "rented", "withdrawn"]);
export const PropertyCondition = z.enum(["new", "like_new", "good", "needs_update", "to_reform", "reformed"]);
export const EnergyRating = z.enum(["A", "B", "C", "D", "E", "F", "G", "in_process", "exempt"]);
export const HeatingType = z.enum(["none", "individual_gas", "individual_electric", "central", "heat_pump", "other"]);
export const Orientation = z.enum(["N", "NE", "E", "SE", "S", "SW", "W", "NW"]);
export const PublicationStatus = z.enum(["not_published", "pending_inmovilla", "published_via_inmovilla", "withdrawn"]);
export const ContactKind = z.enum(["person", "company"]);
export const LeadSource = z.enum([
  "influence_circle", "referral", "portal_via_inmovilla", "website", "walk_in", "signage", "phone", "social", "mls", "other",
]);
export const DealContactRole = z.enum([
  "seller", "buyer", "landlord", "tenant", "co_owner", "legal_representative", "heir", "referrer", "other",
]);
export const InteractionType = z.enum(["call", "whatsapp", "email", "meeting", "visit", "note", "valuation_delivery"]);
export const DocumentType = z.enum([
  "dni", "nie", "passport", "cif", "nota_simple", "escritura", "cee", "ibi", "cedula_habitabilidad", "hoja_encargo",
  "contrato_arras", "contrato_alquiler", "hoja_visita", "plano", "certificado_comunidad", "consentimiento_rgpd",
  "informe_valoracion", "foto", "otro",
]);
export const DataSensitivity = z.enum(["publishable", "internal", "sensitive"]);
export const ConsentPurpose = z.enum([
  "service_provision", "commercial_communications", "property_matching", "audio_recording",
  "share_with_mls", "share_with_franchise", "identity_verification",
]);
export const LegalBasis = z.enum(["consent", "contract", "legal_obligation", "legitimate_interest"]);
export const ValuationPurpose = z.enum(["acquisition", "revaluation", "quick_estimate", "rental"]);
export const ComparableSource = z.enum([
  "internal_closed_deal", "inmovilla_export", "manual_market_observation", "notary_registry_stats", "other",
]);
export const ChecklistItemStatus = z.enum(["pending", "submitted", "approved", "rejected", "not_applicable"]);
export const FinancingType = z.enum(["cash", "mortgage_preapproved", "mortgage_pending", "unknown"]);

// -----------------------------------------------------------------------------
// Primitivas reutilizables
// -----------------------------------------------------------------------------
const Uuid = z.uuid();
const Euros = z.number().nonnegative().max(100_000_000);
const M2 = z.number().positive().max(1_000_000);
const PhoneEs = z.string().trim().regex(/^\+?\d[\d\s]{7,16}$/, "Teléfono no válido");
/** DNI/NIE con letra de control. */
export const NationalIdEs = z
  .string()
  .trim()
  .toUpperCase()
  .regex(/^([0-9]{8}|[XYZ][0-9]{7})[A-Z]$/, "DNI/NIE no válido")
  .refine((v) => {
    const map: Record<string, string> = { X: "0", Y: "1", Z: "2" };
    const num = Number(v.slice(0, -1).replace(/^[XYZ]/, (c) => map[c] ?? c));
    return "TRWAGMYFPDXBNJZSQVHLCKE"[num % 23] === v.slice(-1);
  }, "Letra de control incorrecta");
const FeatureSlug = z.string().regex(/^[a-z0-9_]+$/, "Usa slugs en minúsculas (p.ej. 'aire_acondicionado')");

// -----------------------------------------------------------------------------
// CORE · Contactos (público interno) vs. datos sensibles (tabla aparte)
// -----------------------------------------------------------------------------
export const ContactInputSchema = z
  .object({
    kind: ContactKind.default("person"),
    firstName: z.string().trim().min(1).max(80).optional(),
    lastName: z.string().trim().max(120).optional(),
    companyName: z.string().trim().max(160).optional(),
    email: z.email().optional(),
    phone: PhoneEs.optional(),
    source: LeadSource.default("other"),
    inInfluenceCircle: z.boolean().default(false),
    relationshipNote: z.string().max(500).optional(),
    referredByContactId: Uuid.optional(),
    tags: z.array(z.string().max(40)).max(30).default([]),
  })
  .strict()
  .refine((c) => (c.kind === "person" ? Boolean(c.firstName ?? c.lastName) : Boolean(c.companyName)), {
    message: "Nombre (persona) o razón social (empresa) obligatorio",
  });
export type ContactInput = z.infer<typeof ContactInputSchema>;

export const ContactSensitiveInputSchema = z
  .object({
    contactId: Uuid,
    nationalIdType: z.enum(["dni", "nie", "passport", "cif"]),
    nationalIdNumber: z.string().trim().min(5).max(20),
    birthDate: z.iso.date().optional(),
    nationality: z.string().max(60).optional(),
    postalAddress: z.string().max(300).optional(),
    iban: z.string().regex(/^ES\d{22}$/, "IBAN español no válido").optional(),
  })
  .strict()
  .superRefine((v, ctx) => {
    if ((v.nationalIdType === "dni" || v.nationalIdType === "nie") && !NationalIdEs.safeParse(v.nationalIdNumber).success) {
      ctx.addIssue({ code: "custom", path: ["nationalIdNumber"], message: "DNI/NIE no válido" });
    }
  });
export type ContactSensitiveInput = z.infer<typeof ContactSensitiveInputSchema>;

export const ConsentRecordInputSchema = z
  .object({
    contactId: Uuid,
    purpose: ConsentPurpose,
    legalBasis: LegalBasis,
    granted: z.boolean(),
    policyVersion: z.string().min(1).max(20),
    channel: z.enum(["firma_papel", "web", "audio", "email", "firma_digital"]),
    evidenceDocumentId: Uuid.optional(),
    expiresAt: z.iso.date().optional(),
  })
  .strict();
export type ConsentRecordInput = z.infer<typeof ConsentRecordInputSchema>;

// -----------------------------------------------------------------------------
// INMUEBLES · Ficha técnica (interna) / perfil publicable / datos del encargo
// -----------------------------------------------------------------------------
/** Objeto base (sin refinamientos) para poder derivar subconjuntos con .pick/.partial. */
export const PropertyTechnicalSheetBase = z
  .object({
    reference: z.string().regex(/^RK-\d{4}-\d{4,}$/),
    status: PropertyStatus.default("draft"),
    operationType: OperationType,
    propertyType: PropertyType,
    street: z.string().max(200).optional(),
    streetNumber: z.string().max(20).optional(),
    floorLabel: z.string().max(20).optional(),
    door: z.string().max(20).optional(),
    postalCode: z.string().regex(/^\d{5}$/).optional(),
    city: z.string().min(1).max(100),
    province: z.string().max(100).default("Barcelona"),
    zoneId: Uuid.optional(),
    cadastralReference: z.string().regex(/^[0-9A-Z]{20}$/, "Referencia catastral de 20 caracteres").optional(),
    builtAreaM2: M2.optional(),
    usefulAreaM2: M2.optional(),
    plotAreaM2: M2.optional(),
    bedrooms: z.int().min(0).max(50).optional(),
    bathrooms: z.int().min(0).max(50).optional(),
    floorNumber: z.int().min(-5).max(100).optional(),
    yearBuilt: z.int().min(1700).max(2100).optional(),
    condition: PropertyCondition.optional(),
    energyRating: EnergyRating.optional(),
    orientation: Orientation.optional(),
    heating: HeatingType.optional(),
    isExterior: z.boolean().optional(),
    hasElevator: z.boolean().optional(),
    hasTerrace: z.boolean().optional(),
    hasGarage: z.boolean().optional(),
    hasStorageRoom: z.boolean().optional(),
    hasPool: z.boolean().optional(),
    hasGarden: z.boolean().optional(),
    hasAirConditioning: z.boolean().optional(),
    isFurnished: z.boolean().optional(),
    features: z.array(FeatureSlug).max(50).default([]),
    communityFeeMonth: Euros.optional(),
    ibiYear: Euros.optional(),
    askingPrice: Euros.optional(),
    inmovillaRef: z.string().max(40).optional(),
    publicationStatus: PublicationStatus.default("not_published"),
  })
  .strict();

export const PropertyTechnicalSheetSchema = PropertyTechnicalSheetBase
  .refine((p) => p.publicationStatus !== "published_via_inmovilla" || Boolean(p.inmovillaRef), {
    path: ["inmovillaRef"],
    message: "Para marcar como publicado en Inmovilla hace falta su referencia",
  })
  .refine((p) => p.usefulAreaM2 === undefined || p.builtAreaM2 === undefined || p.usefulAreaM2 <= p.builtAreaM2, {
    path: ["usefulAreaM2"],
    message: "La superficie útil no puede superar la construida",
  });
export type PropertyTechnicalSheet = z.infer<typeof PropertyTechnicalSheetSchema>;

export const PropertyInternalSchema = z
  .object({
    propertyId: Uuid,
    ownerMinPrice: Euros.optional(),
    commissionPct: z.number().min(0).max(100).optional(),
    commissionFixed: Euros.optional(),
    exclusivity: z.boolean().default(false),
    mandateStart: z.iso.date().optional(),
    mandateEnd: z.iso.date().optional(),
    keysLocation: z.string().max(200).optional(),
    internalNotes: z.string().max(5000).optional(),
  })
  .strict();
export type PropertyInternal = z.infer<typeof PropertyInternalSchema>;

/** Lo ÚNICO que puede salir hacia cliente / Inmovilla. Sin dirección exacta ni propietarios. */
export const PropertyPublicProfileSchema = z
  .object({
    propertyId: Uuid,
    publicTitle: z.string().min(10).max(120),
    publicDescription: z.string().max(4000).optional(),
    publicZoneLabel: z.string().max(80).optional(),
    showPrice: z.boolean().default(true),
    publicPrice: Euros.optional(),
    highlights: z.array(z.string().max(60)).max(10).default([]),
    virtualTourUrl: z.url().optional(),
  })
  .strict();
export type PropertyPublicProfile = z.infer<typeof PropertyPublicProfileSchema>;

// -----------------------------------------------------------------------------
// EXPEDIENTES · Pipeline
// -----------------------------------------------------------------------------
export const DealInputSchema = z
  .object({
    primaryContactId: Uuid,
    propertyId: Uuid.optional(),
    operationType: OperationType.default("sale"),
    phase: z.enum(["circulo_influencia", "prospecto"]).default("circulo_influencia"),
    expectedPrice: Euros.optional(),
    expectedFee: Euros.optional(),
    expectedCloseDate: z.iso.date().optional(),
  })
  .strict();
export type DealInput = z.infer<typeof DealInputSchema>;

export const ChangeDealPhaseSchema = z
  .object({
    dealId: Uuid,
    toPhase: PipelinePhase,
    reason: z.string().trim().min(3).max(500).optional(),
  })
  .strict();
export type ChangeDealPhase = z.infer<typeof ChangeDealPhaseSchema>;

// -----------------------------------------------------------------------------
// DEMANDAS  [F2]
// -----------------------------------------------------------------------------
export const DemandInputSchema = z
  .object({
    contactId: Uuid,
    operationType: OperationType.default("sale"),
    propertyTypes: z.array(PropertyType).default([]),
    zoneIds: z.array(Uuid).default([]),
    priceMin: Euros.optional(),
    priceMax: Euros.optional(),
    bedroomsMin: z.int().min(0).max(20).optional(),
    bathroomsMin: z.int().min(0).max(20).optional(),
    areaMinM2: M2.optional(),
    areaMaxM2: M2.optional(),
    needsElevator: z.boolean().default(false),
    needsGarage: z.boolean().default(false),
    needsTerrace: z.boolean().default(false),
    needsExterior: z.boolean().default(false),
    desiredFeatures: z.array(FeatureSlug).max(30).default([]),
    financing: FinancingType.default("unknown"),
    urgency: z.int().min(1).max(5).optional(),
  })
  .strict()
  .refine((d) => d.priceMin === undefined || d.priceMax === undefined || d.priceMin <= d.priceMax, {
    path: ["priceMax"],
    message: "El precio máximo debe ser ≥ mínimo",
  });
export type DemandInput = z.infer<typeof DemandInputSchema>;

export const MatchBreakdownSchema = z.object({
  price: z.number().min(0).max(35),
  zone: z.number().min(0).max(30),
  rooms: z.number().min(0).max(15),
  area: z.number().min(0).max(10),
  features: z.number().min(0).max(10),
  weights: z.object({ price: z.literal(35), zone: z.literal(30), rooms: z.literal(15), area: z.literal(10), features: z.literal(10) }),
});
export type MatchBreakdown = z.infer<typeof MatchBreakdownSchema>;

// -----------------------------------------------------------------------------
// CHECKLISTS  [F2]
// -----------------------------------------------------------------------------
export const ChecklistItemUpdateSchema = z
  .object({
    itemId: Uuid,
    status: ChecklistItemStatus,
    documentId: Uuid.optional(),
    reviewComment: z.string().max(1000).optional(),
  })
  .strict()
  .refine((v) => v.status !== "rejected" || Boolean(v.reviewComment), {
    path: ["reviewComment"],
    message: "Un rechazo exige comentario para el agente",
  });
export type ChecklistItemUpdate = z.infer<typeof ChecklistItemUpdateSchema>;

// -----------------------------------------------------------------------------
// VALORADOR IA  [F1]
// -----------------------------------------------------------------------------

/** Contenido de valuation_parameters.params (editable sólo por el supervisor). */
export const ValuationParamsSchema = z
  .object({
    max_agent_adjustment_pct: z.number().min(0).max(100).default(10),
    weights: z
      .object({
        comparables: z.number().min(0).max(1),
        zone_benchmark: z.number().min(0).max(1),
      })
      .refine((w) => Math.abs(w.comparables + w.zone_benchmark - 1) < 1e-6, "Los pesos deben sumar 1"),
    condition_coefficients: z.partialRecord(PropertyCondition, z.number().min(0.5).max(1.5)),
    floor_adjustments: z
      .object({
        ground_floor_pct: z.number().min(-30).max(10).default(-8),
        no_elevator_per_floor_pct: z.number().min(-10).max(0).default(-3),
        penthouse_pct: z.number().min(0).max(30).default(10),
      })
      .partial()
      .optional(),
    feature_premiums_pct: z.record(FeatureSlug, z.number().min(-20).max(20)).optional(),
    comparables: z
      .object({
        max_age_months: z.int().min(1).max(60).default(12),
        max_distance_m: z.int().min(100).max(20_000).default(1500),
        min_count: z.int().min(1).max(20).default(3),
        closing_price_weight: z.number().min(1).max(3).default(1.5),
      })
      .partial()
      .optional(),
    negotiation_margin_pct: z.number().min(0).max(30).default(5),
    min_confidence_to_deliver: z.number().min(0).max(1).default(0.6),
  })
  .strict();
export type ValuationParams = z.infer<typeof ValuationParamsSchema>;

export const ComparableInputSchema = z
  .object({
    source: ComparableSource,
    sourceReference: z.string().max(200).optional(),
    zoneId: Uuid.optional(),
    approxAddress: z.string().max(200).optional(),
    propertyType: PropertyType,
    operationType: OperationType.default("sale"),
    builtAreaM2: M2,
    bedrooms: z.int().min(0).max(50).optional(),
    bathrooms: z.int().min(0).max(50).optional(),
    condition: PropertyCondition.optional(),
    price: z.number().positive(),
    isClosingPrice: z.boolean().default(false),
    observedAt: z.iso.date(),
    distanceM: z.int().min(0).optional(),
  })
  .strict();
export type ComparableInput = z.infer<typeof ComparableInputSchema>;

/**
 * SALIDA ESTRUCTURADA DEL MODELO (Output.object). Se guarda tal cual en
 * valuation_ai_runs.output (+ columnas desnormalizadas estimated_*, confidence).
 * Reglas: importes en euros enteros, min ≤ valor ≤ max, confianza 0..1,
 * cada ajuste justificado, NUNCA datos personales.
 */
export const VALUATION_OUTPUT_SCHEMA_VERSION = "1.0.0" as const;

export const ValuationAIOutputSchema = z
  .object({
    schemaVersion: z.literal(VALUATION_OUTPUT_SCHEMA_VERSION),
    currency: z.literal("EUR"),
    estimatedValue: z.int().positive().describe("Valor de mercado más probable, en euros"),
    estimatedMin: z.int().positive().describe("Límite inferior del rango, en euros"),
    estimatedMax: z.int().positive().describe("Límite superior del rango, en euros"),
    estimatedPricePerM2: z.number().positive().describe("€/m² construido resultante"),
    recommendedListingPrice: z.int().positive().describe("Precio de salida recomendado (incluye margen de negociación)"),
    confidence: z.number().min(0).max(1).describe("Confianza 0-1 según cantidad/calidad de comparables"),
    confidenceDrivers: z.array(z.string().max(200)).min(1).max(6),
    methodology: z.enum(["comparables", "zone_benchmark", "hybrid"]),
    comparablesUsed: z
      .array(
        z.object({
          comparableId: z.uuid(),
          weight: z.number().min(0).max(1),
          adjustmentPct: z.number().min(-50).max(50),
          rationale: z.string().max(300),
        }),
      )
      .max(20),
    adjustments: z
      .array(
        z.object({
          factor: z.enum(["condition", "floor", "elevator", "orientation", "terrace", "garage", "energy", "views", "layout", "other"]),
          impactPct: z.number().min(-40).max(40),
          rationale: z.string().max(300),
        }),
      )
      .max(15),
    marketContext: z.string().max(800).describe("Contexto de mercado de la zona (sin datos personales)"),
    risks: z.array(z.string().max(200)).max(8),
    missingData: z.array(z.string().max(120)).max(15).describe("Datos de la ficha que mejorarían la estimación"),
    clientSummary: z.string().min(50).max(1200).describe("Texto publicable para el propietario, tono profesional"),
  })
  .strict()
  .refine((o) => o.estimatedMin <= o.estimatedValue && o.estimatedValue <= o.estimatedMax, {
    message: "Rango incoherente: debe cumplirse min ≤ valor ≤ max",
    path: ["estimatedValue"],
  })
  .refine((o) => o.estimatedMax / o.estimatedMin <= 1.5, {
    message: "Rango demasiado amplio (>50%): baja la confianza o pide más comparables",
    path: ["estimatedMax"],
  });
export type ValuationAIOutput = z.infer<typeof ValuationAIOutputSchema>;

/** Ajuste humano (valuation_reviews). La BD calcula ai_value y requires_supervisor. */
export const ValuationReviewInputSchema = z
  .object({
    valuationId: Uuid,
    aiRunId: Uuid,
    adjustedValue: z.int().positive(),
    adjustedMin: z.int().positive().optional(),
    adjustedMax: z.int().positive().optional(),
    adjustmentReason: z.string().trim().min(10).max(1000).optional(),
    isFinal: z.boolean().default(false),
  })
  .strict();
export type ValuationReviewInput = z.infer<typeof ValuationReviewInputSchema>;

/** Hechos extraídos de una transcripción de captación (transcriptions.extracted_facts). */
export const TranscriptFactsSchema = z
  .object({
    propertyFacts: PropertyTechnicalSheetBase
      .pick({
        propertyType: true, builtAreaM2: true, bedrooms: true, bathrooms: true, floorNumber: true,
        condition: true, hasElevator: true, hasTerrace: true, hasGarage: true, isExterior: true, features: true,
      })
      .partial(),
    ownerExpectations: z
      .object({
        expectedPrice: Euros.optional(),
        urgency: z.int().min(1).max(5).optional(),
        motivation: z.string().max(300).optional(),
      })
      .partial(),
    followUpActions: z.array(z.object({ title: z.string().max(140), dueInDays: z.int().min(0).max(90).optional() })).max(10),
    sensitiveDataDetected: z.boolean().describe("true si el audio contiene datos especialmente protegidos (salud, etc.)"),
  })
  .strict();
export type TranscriptFacts = z.infer<typeof TranscriptFactsSchema>;


// -----------------------------------------------------------------------------
// AUDIOS  [F1] · espejo de audio_owner_chk + audio_consent_chk
// -----------------------------------------------------------------------------
export const AudioContext = z.enum(["captacion", "visita", "valoracion", "reunion", "nota_voz"]);

/** Entidad dueña del audio = prefijo de ruta en el bucket audio-recordings. */
export const AudioOwner = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("deal"), id: Uuid }),
  z.object({ kind: z.literal("property"), id: Uuid }),
  z.object({ kind: z.literal("valuation"), id: Uuid }),
]);
export type AudioOwner = z.infer<typeof AudioOwner>;

/**
 * Ruta canónica: {deal|property|valuation}/{uuid}/{audioId}.{ext}. La BD verifica que el prefijo
 * corresponda a uno de los vínculos del audio (triggers guard_audio_recording / guard_document_links).
 *
 * DECISIÓN v1.1: la ruta es INMUTABLE. Si tras una valoración rápida se abre un expediente,
 * el archivo NO se mueve: se queda en valuation/… o property/… y sólo se rellena deal_id
 * (RPC public.link_audio_to_deal). No construyas rutas nuevas para archivos existentes:
 * usa siempre documents.object_path para pedir la signed URL.
 */
export function audioStoragePath(owner: AudioOwner, audioId: string, ext: "webm" | "m4a" | "mp3" | "ogg" | "wav"): string {
  return `${owner.kind}/${owner.id}/${audioId}.${ext}`;
}

export const AudioRecordingInputSchema = z
  .object({
    documentId: Uuid,
    dealId: Uuid.optional(),
    propertyId: Uuid.optional(),
    valuationRequestId: Uuid.optional(),
    contactId: Uuid.optional(),
    consentRecordId: Uuid.optional(),
    context: AudioContext.default("captacion"),
    durationSeconds: z.int().min(0).max(4 * 3600).optional(),
  })
  .strict()
  .refine((a) => [a.dealId, a.propertyId, a.valuationRequestId].some((v) => v !== undefined), {
    path: ["dealId"],
    message: "El audio debe vincularse al menos a un expediente, un inmueble o una valoración",
  })
  .refine((a) => a.context === "nota_voz" || a.consentRecordId !== undefined, {
    path: ["consentRecordId"],
    message: "Grabar a un tercero exige un consentimiento registrado (salvo notas de voz internas)",
  });
export type AudioRecordingInput = z.infer<typeof AudioRecordingInputSchema>;

// -----------------------------------------------------------------------------
// INFORME AL CLIENTE  [F1]
// La BD BLOQUEA el insert/update (trigger guard_valuation_client_report) salvo que la
// revisión pertenezca a la misma valoración, sea is_final y, si el ajuste supera el
// umbral, tenga approved_by. Este esquema sólo valida la forma del payload.
// -----------------------------------------------------------------------------
export const ValuationClientReportInputSchema = z
  .object({
    valuationId: Uuid,
    reviewId: Uuid,
    displayValue: z.int().positive(),
    displayMin: z.int().positive().optional(),
    displayMax: z.int().positive().optional(),
    clientSummary: z.string().trim().min(50).max(4000),
    publicComparables: z
      .array(z.object({ zoneLabel: z.string().max(80), builtAreaM2: M2, pricePerM2: z.number().positive(), observedAt: z.iso.date() }))
      .max(20)
      .default([]),
  })
  .strict()
  .refine((r) => r.displayMin === undefined || r.displayMax === undefined || (r.displayMin <= r.displayValue && r.displayValue <= r.displayMax), {
    path: ["displayValue"],
    message: "Rango incoherente",
  });
export type ValuationClientReportInput = z.infer<typeof ValuationClientReportInputSchema>;

/** Lee la entidad dueña ORIGINAL a partir de la ruta física (null si no es una ruta de audio válida). */
export function audioOwnerFromPath(path: string): AudioOwner | null {
  const [kind, id] = path.split("/");
  const parsed = AudioOwner.safeParse({ kind, id });
  return parsed.success ? parsed.data : null;
}

/**
 * Payload de public.link_audio_to_deal(p_audio_id, p_deal_id).
 * Permisos (impuestos en BD): gestionar el expediente destino Y la entidad original
 * (valoración/inmueble), o ser supervisor. El archivo no se mueve.
 */
export const LinkAudioToDealSchema = z
  .object({
    audioId: Uuid,
    dealId: Uuid,
  })
  .strict();
export type LinkAudioToDeal = z.infer<typeof LinkAudioToDealSchema>;

// -----------------------------------------------------------------------------
// BENCHMARKS DE ZONA (valuation_zone_benchmarks)
// isPlaceholder = true → valor de EJEMPLO cargado por seed.sql: el valorador debe
// excluirlo (o avisar) hasta que Raúl cargue cifras validadas.
// -----------------------------------------------------------------------------
export const ZoneBenchmarkSchema = z
  .object({
    parametersId: Uuid,
    zoneId: Uuid,
    propertyType: PropertyType.optional(),
    operationType: OperationType.default("sale"),
    basePriceM2: z.number().positive().max(100_000),
    sourceNote: z.string().max(500).optional(),
    isPlaceholder: z.boolean().default(false),
  })
  .strict();
export type ZoneBenchmark = z.infer<typeof ZoneBenchmarkSchema>;

/** Filtra benchmarks utilizables por el valorador (nunca los de EJEMPLO). */
export function usableBenchmarks<T extends { isPlaceholder: boolean }>(rows: readonly T[]): T[] {
  return rows.filter((r) => !r.isPlaceholder);
}
