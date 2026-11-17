---
title: Diccionario de datos
date: 2026-11-17
status: sustituido-por-arquitectura-maestra
turn: turno-1
---

# Diccionario de datos

Sustituido. El contrato vigente es `docs/30-arquitectura/modelo-datos.md` y los términos están en `docs/00-inicio/glosario.md`, junto con `supabase/migrations/20261117000000_init_schema.sql` y `src/lib/validations/schema.types.ts`. Este archivo conserva el borrador del turno 1, no se enlaza desde las notas activas y no se usa para crear tablas.

Entidades y campos extraídos de la guía del 5 de noviembre, la entrevista del 4 de noviembre y el reparto de fases.

Procedencia, en cualquier campo de negocio: `verificado` (catastro, documento, comparable cerrado), `declarado` (lo dice el propietario o el agente sin soporte) o `inferido` (lo propone el modelo o una foto). Se guarda en `field_provenance`, no en el nombre de la columna.

Identificadores `uuid`. Importes en céntimos de euro (`integer`) para evitar flotantes. Superficies en m² con un decimal (`numeric`). Deltas de ajuste en tanto por uno (`numeric(5,4)`, por ejemplo `0.0600` = +6 %).

## Fase 1

### `profiles`

Una fila por usuario de Auth. El rol no se lee de `user_metadata`.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | uuid | `auth.users.id` |
| `full_name` | text | |
| `role` | enum | `agent` \| `coordinator` \| `supervisor` |
| `active` | boolean | |

### `properties`

Ficha del inmueble. La fase comercial vive en `expedientes.phase`, no aquí.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | uuid | |
| `internal_ref` | text | Referencia de oficina, no la de Inmovilla |
| `cadastral_ref` | text | La «matrícula» que desbloquea metros y año |
| `address_line` | text | |
| `municipality` | text | Ej. Vilanova i la Geltrú, Olèrdola, Sitges |
| `zone` | text | Barrio o polígono, declarado |
| `typology` | enum | `flat` \| `house` \| `other` |
| `useful_m2` | numeric | Distinta de la construida |
| `built_m2` | numeric | |
| `rooms` | integer | |
| `baths` | integer | |
| `floor` | integer | Planta. Nulo si no aplica |
| `has_elevator` | boolean | |
| `year_built` | integer | Catastro cuando exista |
| `condition` | enum | `to_reform` \| `partial` \| `reformed` |
| `terrace` | boolean | |
| `parking_spaces` | integer | |
| `orientation` | text | |
| `views_notes` | text | Lo que el agente confirma de las vistas. La foto no escribe este campo sola |
| `owner_asking_price_cents` | integer | Lo que el propietario quiere pedir. Distinto del precio recomendado |
| `agent_id` | uuid | El agente solo opera las filas suyas |
| `field_provenance` | jsonb | Mapa campo → `verificado` \| `declarado` \| `inferido` |
| `created_by` | uuid | `profiles.id` |
| `created_at` / `updated_at` | timestamptz | |

### `property_owners`

Une la ficha con quien encarga la valoración. El contacto completo es de Fase 2; aquí basta la persona necesaria para el informe.

| Campo | Tipo | Notas |
|---|---|---|
| `property_id` | uuid | |
| `contact_id` | uuid | |
| `role` | enum | `owner` \| `co_owner` |

### `contacts`

En Fase 1 solo el propietario ligado a una valoración. El círculo de influencia reutiliza esta tabla en Fase 2.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | uuid | |
| `display_name` | text | |
| `email` | text | Opcional |
| `phone` | text | Opcional |
| `origin` | text | Web, portal, referido, visita |
| `owner_id` | uuid | Agente responsable |
| `created_at` | timestamptz | |

### `valuations`

Una pasada de valoración. Varias por inmueble. La que puede convertirse en PDF es la última con `status = internal_validated`.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | uuid | |
| `property_id` | uuid | |
| `author_id` | uuid | Agente que la pide |
| `status` | enum | `draft` \| `internal_validated` |
| `subject_snapshot` | jsonb | Copia de los campos del inmueble usados en el cálculo |
| `asking_discount` | numeric | `descuento_oferta_a_cierre` aplicado. Nulo si no hay parámetro y solo hay ofertas |
| `base_eur_m2_cents` | integer | Mediana de los comparables seleccionados, ya pasados a €/m² útil |
| `adjustment_factor` | numeric | Suma de deltas, ya recortada |
| `point_estimate_cents` | integer | Nulo si `confidence = insufficient` |
| `range_low_cents` / `range_high_cents` | integer | |
| `confidence` | enum | `high` \| `medium` \| `low` \| `insufficient` |
| `traffic_light` | enum | `green` \| `amber` \| `red`. Contra `owner_asking_price_cents` |
| `missing_data` | text[] | |
| `limitations` | text | Sale en el PDF |
| `narrative_draft` | text | Borrador del modelo. No entra en el PDF |
| `price_min_cents` | integer | Mínimo del rango. Nulo mientras `status = draft` y la confianza sea insuficiente |
| `price_market_cents` | integer | Precio de mercado |
| `price_exit_cents` | integer | Precio de salida recomendado |
| `commercial_arguments` | text | Entra en el PDF |
| `internal_risk_notes` | text | Alertas internas. Fuera del PDF |
| `negotiation_margin_notes` | text | Margen oculto. Fuera del PDF |
| `narrative_approved` | text | Texto que sí entra |
| `schema_version` | text | Versión del Zod |
| `model_id` | text | |
| `validated_by` | uuid | Nulo hasta `internal_validated` |
| `validated_at` | timestamptz | |
| `created_at` | timestamptz | |

### `valuation_extractions`

Lo que la IA saca de un audio, una nota o un texto de comparable. Confirmar en la UI copia el valor al campo consolidado. Hasta entonces el campo consolidado no cambia.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | uuid | |
| `valuation_id` | uuid | |
| `field_code` | text | Campo de destino |
| `value` | jsonb | Tipo de ese campo. En Zod, el esquema concreto, nunca `any` |
| `confidence` | numeric | 0 a 1 |
| `source_quote` | text | Cita de origen. Fuera del PDF |
| `status` | enum | `pending_review` \| `accepted` \| `discarded` |

### `valuation_comparables`

| Campo | Tipo | Notas |
|---|---|---|
| `id` | uuid | |
| `valuation_id` | uuid | |
| `source` | enum | `portal_asking` \| `own_closing` \| `registry` \| `manual` |
| `source_label` | text | Portal, «venta propia», registro. Sin URL de un anuncio ajeno en el PDF |
| `zone_label` | text | Zona, no la dirección completa del comparable ajeno |
| `price_cents` | integer | |
| `price_kind` | enum | `asking` \| `closing` |
| `surface_m2` | numeric | |
| `surface_kind` | enum | `useful` \| `built` |
| `rooms` / `baths` / `floor` | integer | |
| `has_elevator` | boolean | |
| `condition` | enum | El mismo de `properties` |
| `observed_on` | date | Fecha del anuncio o de la escritura |
| `selected` | boolean | Solo los seleccionados entran en la mediana |
| `exclusion_reason` | text | Si `selected = false` |
| `provenance` | enum | `verificado` \| `declarado` \| `inferido` |

### `valuation_adjustments`

Una fila por criterio aplicado. El catálogo de códigos quedó en `docs/40-ia/valorador/criterios-valoracion.md`. Esta línea no enlaza: el borrador no debe volver al grafo activo.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | uuid | |
| `valuation_id` | uuid | |
| `code` | text | `reform`, `elevator_floor`, `terrace`, `parking`, `views`, `orientation`, `year`, `other` |
| `delta` | numeric(5,4) | Tanto por uno, con signo |
| `rationale` | text | Frase que puede pasar al PDF |
| `provenance` | enum | `verificado` \| `declarado` \| `inferido` |

### `documents`

En Fase 1, el PDF aprobado. El checklist legal es Fase 2, sobre la misma tabla.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | uuid | |
| `valuation_id` | uuid | Nulo cuando el documento sea de expediente |
| `kind` | enum | Fase 1: `valuation_pdf` |
| `storage_path` | text | Bucket privado. Lectura con `createSignedUrl`, caducidad máxima 300 s |
| `visibility` | enum | `client` \| `internal` |
| `version` | integer | |
| `created_by` | uuid | |
| `created_at` | timestamptz | |

## Resto del esquema (se migra el día 1; la UI llega después)

### `contacts` (columnas nuevas)

`roles` (`owner`, `buyer`, `referrer`, `ally`), `influence_circle`, `consent_purpose`, `consent_evidence`, `consent_at`, `last_touch_at`.

### `activities`

Fecha, autor, tipo (`call`, `visit`, `note`, `task`), resumen, resultado y siguiente acción con vencimiento. Sirve al círculo y al expediente.

### `demands`

Contacto comprador, zona, presupuesto declarado, habitaciones, requisitos obligatorios, requisitos deseables, plazo y fecha de última confirmación.

### `expedientes`

`property_id` nulo hasta `captacion`, `phase` con estos ocho valores y en este orden: `circulo_influencia`, `prospecto`, `captacion`, `documentacion`, `publicacion`, `visitas`, `cierre`, `notaria`. Responsable y bloqueo activo. `agent_id` para la política del agente.

### `checklist_items`

`expediente_id`, `code` (`nota_simple`, `catastro`, `mandato`, `visita_auth`, `ficha_tecnica`, `dni`, `escritura`, `comunidad`), `required`, `status` (`missing`, `requested`, `received`), `document_id`.

### `documents.kind` (valores nuevos)

`nota_simple`, `catastro`, `mandato`, `escritura`, `dni`, `comunidad_receipt`, `visita_auth`, `other`.

## Qué no es una entidad

- El precio publicado en Idealista no es un campo de `properties` mientras Inmovilla publique. Si algún día se importa, será un espejo con fecha, no la fuente que manda.
- Los puntos del variable del comercial y la previsión de honorarios no tienen tabla en Fase 1.
- Una tasación oficial no se guarda como `valuations`. Si llega un PDF de tasación, será un `documents.kind` futuro, separado de la estimación comercial.
