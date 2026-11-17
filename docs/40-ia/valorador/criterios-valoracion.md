---
title: Reglas del valorador IA
date: 2026-11-17
status: hipotesis-pendiente-de-raul
---

# Reglas del valorador IA

Cálculo reproducible de una estimación comercial de precio de salida. Los deltas son hipótesis de trabajo del 17 de noviembre: Raúl no dio pesos en la entrevista. Cada vez que corrija una valoración, el delta tocado se actualiza aquí y en el esquema Zod, con la fecha en el historial del final.

La tasación oficial, el valor fiscal y el precio de un anuncio ajeno presentado como propio quedan fuera de este cálculo.

## Entradas obligatorias

| Entrada | Si falta |
|---|---|
| Municipio y zona | `confidence = insufficient` |
| Superficie útil, o construida con `surface_kind` explícito | `confidence = insufficient`. No se mezclan en la misma mediana |
| Tipología, habitaciones, baños, planta, ascensor, estado de reforma | Se listan en `missing_data` y bajan la confianza |
| Al menos 3 comparables seleccionados, de los últimos 6 meses, en la misma zona | Con menos de 3, no hay `point_estimate` |
| Precio pedido por el propietario | El semáforo no se calcula; el rango sí puede salir |

La referencia catastral es la vía prevista para verificar metros, año, habitaciones y baños. Lo que salga del catastro entra como `verificado`. Lo que el agente añada en la visita (reforma, terraza, plazas, vistas, orientación) entra como `declarado` hasta que haya foto o documento, y la foto sola no pasa de `inferido`.

## Comparables

Cada comparable declara `price_kind`:

- `closing`: venta propia del agente o precio de registro. Cuenta tal cual.
- `asking`: anuncio de portal. Solo entra en la mediana si existe `descuento_oferta_a_cierre`.

`descuento_oferta_a_cierre` no tiene valor por defecto. Mientras sea nulo, una valoración hecha solo con anuncios devuelve el rango de precios de oferta marcado como tal, `point_estimate = null` y `confidence = insufficient`. No se inventa un 10 % o un 15 % de rebaja.

Unidad de la mediana: euros por m² útil. Si el comparable solo trae superficie construida, se excluye de la mediana útil y se explica en `exclusion_reason`. Se puede calcular una mediana paralela en m² construidos, etiquetada, cuando el sujeto tampoco tenga útil.

Precio normalizado del comparable:

```text
eur_m2 = price_cents / surface_m2
eur_m2_cierre = eur_m2                         si price_kind = closing
eur_m2_cierre = eur_m2 * (1 - asking_discount) si price_kind = asking y asking_discount no es nulo
```

`base_eur_m2` = mediana de `eur_m2_cierre` de los comparables con `selected = true`.

El agente elige y descarta. El modelo puede proponer una selección; la selección guardada es la del agente.

## Ajustes

Se aplican al sujeto respecto de la mediana de los comparables ya elegidos (no respecto de un piso ideal). Cada fila es un delta en tanto por uno.

```text
adjustment_factor = clamp(suma(delta), -0.25, +0.25)
point_estimate = base_eur_m2 * (1 + adjustment_factor) * useful_m2
```

El tope ±25 % evita que un cúmulo de hipótesis se coma el mercado. Si la suma cae fuera, se recorta y `limitations` lo dice.

Deltas iniciales, todavía sin validar. El valor usado se guarda en la fila; el de la tabla es el techo sugerido, no un automático.

| Código | Cuándo | Delta sugerido | Procedencia mínima para aplicarlo |
|---|---|---|---|
| `reform` | Reforma integral reciente frente a la media de los testigos | `+0.06` a `+0.10` | `declarado` por el agente tras la visita |
| `reform` | Para reformar | `-0.04` a `-0.08` | `declarado` |
| `elevator_floor` | Planta 2 o superior sin ascensor | `-0.05` a `-0.10` | `verificado` o `declarado` de planta y ascensor |
| `elevator_floor` | Misma finca, con ascensor, sin otra diferencia | `0` | No se suma por defecto |
| `views` | Vistas u orientación distinta dentro del mismo edificio (el segundo A frente al segundo B) | `-0.08` a `+0.08` | `declarado`. Una foto puede proponerlo como `inferido` y no se aplica hasta que el agente lo confirme |
| `terrace` | Terraza que los comparables no tienen | `+0.03` a `+0.07` | `declarado` |
| `parking` | Cada plaza no incluida en los comparables | `+0.03` a `+0.06`, o un importe cerrado en euros si el agente lo tiene de una venta propia | `declarado` |
| `year` | Año de construcción claramente distinto al de la mediana | `-0.03` a `+0.03` | `verificado` (catastro) |
| `other` | Cualquier otro criterio de Raúl | Lo que él fije en la revisión, dentro del tope global | Siempre `declarado` y con `rationale` |

`other` sin frase de motivo no se guarda. Un delta fuera de su banda sugerida solo lo puede dejar un `supervisor`, y queda en la fila.

Planta baja con terraza y dos plazas, el ejemplo que Raúl puso cerca de 460.000 €, no es un peso propio: son `terrace` + `parking` + la mediana de esa zona. El caso no se codifica como regla.

## Rango y confianza

- `range_low` y `range_high`: percentil 25 y 75 de (`eur_m2_cierre` × superficie del sujeto), y después se les aplica el mismo `adjustment_factor`.
- `high`: 4 o más comparables, al menos uno `closing`, superficie útil verificada, todos los ajustes `declarado` o `verificado`.
- `medium`: 3 comparables de oferta ya descontados, o algún ajuste `inferido` pendiente de confirmar. Con un `inferido` sin confirmar, ese delta no entra en la suma.
- `low`: superficie solo construida, o comparables de más de 6 meses que el agente ha forzado a incluir.
- `insufficient`: falta una entrada obligatoria, hay menos de 3 comparables seleccionados, o solo hay ofertas y el descuento es nulo. `point_estimate` queda nulo.

## Semáforo

Solo si hay `point_estimate` y `owner_asking_price_cents`.

| Color | Precio que el propietario quiere, frente al punto |
|---|---|
| `green` | Dentro de ±5 % |
| `amber` | Por encima, hasta +15 % |
| `red` | Más de +15 %. En el PDF: a este precio de salida no se esperan visitas |

Por debajo del punto no se pinta de rojo. Se explica como margen para vender antes, en `limitations`.

## Revisión humana

1. El modelo devuelve borrador, ajustes propuestos, huecos y limitaciones. Cada extracción de audio, nota o texto queda en `valuation_extractions` con `pending_review`.
2. El agente confirma o descarta cada extracción. Confirmar escribe el campo consolidado.
3. El agente pasa la ficha a `internal_validated` en el caso normal. Si no hay cifra, la confianza es `insufficient` o un delta se sale de banda, la ficha queda en `pending_supervisor` y solo el supervisor la valida. El detalle está en [ADR-010](../../30-arquitectura/adr/registro.md) y en el [PRD](../../20-producto/prd.md).
4. El PDF se genera solo si `status === internal_validated`. En otro estado el servidor responde 403. El payload pasa por `ExternalValuationPdfSchema`.

El PDF de cliente incluye: datos del inmueble con su procedencia, comparables por zona y precio (sin dirección ajena ni URL), ajustes con su frase, mínimo, mercado y salida, semáforo, argumentos, limitaciones y la frase de que es una estimación comercial de precio de salida. Incluye también el bloque de servicios de la agencia.

El PDF excluye: `narrative_draft`, `internal_risk_notes`, `negotiation_margin_notes`, `source_quote`, notas de visita sin confirmar, honorarios y otros contactos.

## Historial de parámetros

| Fecha | Cambio |
|---|---|
| 2026-11-17 | Hipótesis inicial a partir de la entrevista del 4 de noviembre. `descuento_oferta_a_cierre` sin valor. Topes y bandas sin validar. |
| 2026-11-17 | La ficha pasa a `draft` \| `internal_validated`. El PDF exige `internal_validated` y `ExternalValuationPdfSchema`. |
