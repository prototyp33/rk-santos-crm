---
title: Reglas del valorador IA
date: 2026-11-17
status: vigente
tags:
  - valorador
  - sistema
---

# Reglas del valorador IA

Lógica de sistema. Los pesos, las bandas y el semáforo son hipótesis de negocio y viven en [criterios de valoración](criterios-valoracion.md). Esta nota no los copia: dice cómo el sistema los aplica.

Las dos entran en la [especificación de producto](../../20-producto/prd.md). Las tablas están en el [modelo de datos](../../30-arquitectura/modelo-datos.md). La salida estructurada es `ValuationAIOutputSchema` en `src/lib/validations/schema.types.ts`.

## Qué impone el sistema

- Lee los pesos de la versión activa de `valuation_parameters`. No los reescribe en el prompt.
- Con menos de tres comparables seleccionados, `point_estimate` queda nulo y la confianza queda `insufficient`.
- Con solo precios de oferta y `descuento_oferta_a_cierre` nulo, no hay cifra. El rango se etiqueta como precios de oferta.
- Una extracción de audio, nota o texto nace en `pending_review` y no pisa el campo consolidado hasta que el agente la confirma.
- El agente pasa la ficha a `internal_validated` cuando hay cifra, la confianza no es `insufficient` y todos los deltas están dentro de su banda. Si falta alguna de esas tres, la ficha queda en `pending_supervisor` y solo el supervisor la valida.
- Un delta fuera de banda, o un `other` sin motivo, no se guarda salvo el supervisor.
- El PDF solo sale con `internal_validated`. En otro estado el servidor responde 403 y el payload pasa por `ExternalValuationPdfSchema`.
- La plantilla de cliente no recibe notas internas, honorarios ni datos de otros contactos.
