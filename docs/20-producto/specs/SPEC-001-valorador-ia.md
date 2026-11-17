---
title: SPEC-001 Valorador IA
date: 2026-11-17
status: borrador
tags:
  - spec
tipo: spec
---

# SPEC-001. Valorador IA

Puente entre la bóveda y el código de la fase 1. El flujo de pantalla es el de esta nota. Los pesos siguen en [criterios de valoración](../../40-ia/valorador/criterios-valoracion.md). Las tablas están en [modelo de datos](../../30-arquitectura/modelo-datos.md), sección 9. Los contratos que el código ya exporta están en `src/lib/validations/schema.types.ts`.

La lógica de sistema citada como [reglas del valorador](../../40-ia/valorador/reglas-valorador-ia.md) no está en la bóveda. Esta spec no la redacta ni copia sus pesos.

Cuando el [modelo de datos](../../30-arquitectura/modelo-datos.md) habla de `approved`, de `ai_completed` o de un umbral del 10 %, la pantalla de esta fase sigue [ADR-010](../../30-arquitectura/adr/registro.md): `draft`, `pending_supervisor` e `internal_validated`.

## Resultado

Un agente rellena un formulario cerrado, confirma lo que el modelo saca de un audio o de un comparable, y obtiene una ficha interna. El PDF del propietario solo sale de una ficha `internal_validated`, y solo con los campos publicables.

La coordinadora ve la ficha y no la edita. El supervisor valida la excepción y es el único que guarda un delta fuera de banda.

## Fuera de esta spec

Contactos, círculo, checklists, ofertas, cierre y notaría. Scrapers y API de Idealista, Fotocasa, Habitaclia, Pisos.com y la pasarela MLS. Tasación oficial y valor fiscal. Un número inventado para `descuento_oferta_a_cierre`. La pantalla de parámetros del supervisor, salvo la regla de que el agente no los activa.

## Flujo

### 1. Formulario cerrado

La entrada es la ficha técnica, validada con `PropertyTechnicalSheetSchema`. No hay un cuadro de chat que sustituya al formulario.

Campos que el agente completa: municipio (`city`), zona (`zoneId`), superficie útil (`usefulAreaM2`) o construida (`builtAreaM2`) sin mezclarlas en la misma mediana, tipología, habitaciones, baños, planta, ascensor, estado y precio pedido (`askingPrice`). La calle, el portal, la puerta, la referencia catastral y la referencia de Inmovilla no viajan al modelo: el trigger `prepare_valuation_request` los quita de `valuation_requests.input_snapshot`.

Guardar crea `valuation_requests` en `draft`, con `parameters_id` de la versión activa. Los benchmarks con `isPlaceholder = true` no entran en el cálculo (`usableBenchmarks`).

Si falta municipio, zona o una superficie con procedencia clara, la confianza queda `insufficient` y no hay `point_estimate`. Si falta el precio pedido, el rango puede salir y el semáforo no.

### 2. Extracción con confirmación humana

El audio se registra con `AudioRecordingInputSchema` y se guarda en `audio-recordings/{deal|property|valuation}/{id}/`. Una nota de voz interna no exige consentimiento. Cualquier otra grabación exige `consentRecordId`.

La transcripción produce hechos con `TranscriptFactsSchema`. Cada hecho, y cada comparable propuesto por el modelo, nace como extracción pendiente. El campo consolidado no cambia hasta que el agente confirma esa fila. Descartarla lo deja como estaba. Una foto puede proponer un ajuste como `inferido`; ese delta no entra en la suma hasta la confirmación.

El comparable guardado cumple `ComparableInputSchema`. La columna de cierre es `is_closing_price` (`true` = `closing` de los criterios, `false` = `asking`). La selección guardada es la del agente (`included`). El modelo puede proponer; no pisa esa selección.

Origen permitido: cierre propio, exportación manual de Inmovilla, estadística notarial o registral, u observación manual. Sin scraping.

Con menos de tres comparables `included`, `point_estimate` queda nulo y la confianza queda `insufficient`. Con solo ofertas y `descuento_oferta_a_cierre` nulo, el resultado es el mismo y el rango se etiqueta como precios de oferta.

### 3. Ficha interna

La ejecución del modelo se guarda en `valuation_ai_runs`, inmutable, validada con `ValuationAIOutputSchema`. Esa salida es borrador: ajustes propuestos, huecos y limitaciones. No es la ficha cerrada.

La ficha interna muestra mínimo, mercado, salida, semáforo, argumentos y las notas que no salen del despacho: `narrative_draft`, `internal_risk_notes`, `negotiation_margin_notes`, `source_quote` y honorarios.

El agente la pasa a `internal_validated` solo si hay `point_estimate`, la confianza no es `insufficient` y todos los deltas están dentro de la banda de los criterios. Si falta una de esas tres condiciones, el intento deja la ficha en `pending_supervisor` y solo el supervisor la cierra. Un ajuste `other` sin `rationale` no se guarda. Un delta fuera de banda solo lo guarda el supervisor.

La revisión humana se persiste en `valuation_reviews`. Hoy el esquema Zod de esa fila es `ValuationReviewInputSchema` (`adjustedValue`, `isFinal`). No expresa todavía `point_estimate` ni `internal_validated`. El código nuevo no trata `is_final` como sustituto de `internal_validated`.

### 4. PDF limitado

Pedir el PDF en un estado distinto de `internal_validated` responde 403.

El payload publicable se valida antes de renderizar. El esquema con ese papel, `ExternalValuationPdfSchema`, no está exportado en `schema.types.ts`. Lo más cercano es `ValuationClientReportInputSchema`, que cubre valor, rango, resumen y testigos con zona, metros, €/m² y fecha. No basta: el PDF de esta spec también lleva procedencia del dato, la frase de cada ajuste, el semáforo, los argumentos, las limitaciones y la frase de estimación comercial de precio de salida, más el bloque de servicios de la agencia.

El PDF no lleva dirección ajena, URL de anuncio, `narrative_draft`, `internal_risk_notes`, `negotiation_margin_notes`, `source_quote`, notas de visita sin confirmar, honorarios ni datos de otros contactos.

La fila publicable es `valuation_client_reports`. El PDF va al bucket privado `valuation-reports`. La URL firmada caduca como máximo a los 300 segundos.

## Qué no coincide todavía

| Esta spec y los criterios | El código de hoy |
|---|---|
| `point_estimate`, confianza `insufficient` | `ValuationAIOutputSchema.estimatedValue` y `confidence` de 0 a 1 |
| `selected` | columna `valuation_comparables.included` |
| `price_kind` `closing` / `asking` | `ComparableInputSchema.isClosingPrice` |
| `ExternalValuationPdfSchema` | no exportado. Existe `ValuationClientReportInputSchema` |
| Extracción `pending_review` | no hay esquema Zod ni tabla `valuation_extractions` |
| `internal_validated` | el enum `valuation_status` todavía no lo incluye. La tarea F0-1 lo añade |
| [reglas del valorador](../../40-ia/valorador/reglas-valorador-ia.md) | el archivo no está en la bóveda |

## Criterio de aceptación

- [ ] El alta exige `PropertyTechnicalSheetSchema` y deja `valuation_requests.status = draft` con el parámetro activo.
- [ ] El snapshot enviado al modelo no contiene calle, portal, puerta, referencia catastral, coordenadas ni referencia de Inmovilla.
- [ ] Confirmar una extracción escribe el campo consolidado. Descartarla no lo cambia.
- [ ] Dos comparables incluidos dejan `point_estimate` nulo y confianza `insufficient`.
- [ ] Tres ofertas con descuento nulo dejan `point_estimate` nulo y el rango etiquetado como precios de oferta.
- [ ] El agente no pasa a `internal_validated` si falta cifra, la confianza es `insufficient` o un delta se sale de banda. Ese intento queda en `pending_supervisor`.
- [ ] Un `other` sin motivo es rechazado. Un delta fuera de banda guardado por quien no es supervisor es rechazado.
- [ ] El PDF responde 403 fuera de `internal_validated`.
- [ ] El cuerpo del PDF no contiene notas internas, honorarios ni datos de otros contactos.
- [ ] La URL firmada del PDF caduca en 300 segundos o menos.
