# AGENTS.md

CRM inmobiliario de RK Santos (Solfico). El contrato está en [PRD.md](PRD.md).

Lee [PLANNING.md](PLANNING.md) al empezar, revisa [TASKS.md](TASKS.md) y marca lo completado.

## Qué se construye ahora

La fase en curso es la 1: acceso por invitación, tres roles y valorador (formulario, comparables, revisión humana, ficha y PDF). Las fases 2 y 3 están nombradas en el PRD y no tienen criterios. No abras pantallas de contactos, círculo, checklists, ofertas, cierre ni notaría.

La IA normaliza, propone ajustes y redacta el borrador. El precio lo fija una persona. El sistema no habla con el cliente.

## Reglas de la fase 1

- Alta solo por invitación. No hay registro público.
- El rol que autoriza sale de `app_metadata` o de `profiles`. `user_metadata` no autoriza. Un perfil con `is_active = false` no lee ni escribe.
- Roles: `agent` ve y edita solo lo suyo. `coordinator` ve las valoraciones de la agencia en solo lectura. `supervisor` ve toda la agencia, es el único que crea o activa parámetros y el único que valida la excepción.
- Estados de la ficha: `draft`, `pending_supervisor`, `internal_validated`.
- El agente pasa a `internal_validated` solo si hay `point_estimate`, la confianza no es `insufficient` y todos los deltas están dentro de banda. Si falta una de esas tres condiciones, la ficha queda en `pending_supervisor`.
- Un delta fuera de banda solo lo guarda el supervisor. Un ajuste `other` sin motivo no se guarda.
- Menos de tres comparables seleccionados, o solo precios de oferta con `descuento_oferta_a_cierre` nulo: `point_estimate` nulo y confianza `insufficient`. El rango de ofertas se etiqueta como tal.
- Una extracción de IA nace en `pending_review` y no pisa el campo consolidado hasta que el agente la confirma.
- El PDF responde 403 si el estado no es `internal_validated`. El payload pasa por `ExternalValuationPdfSchema` y omite notas internas, honorarios y datos de otros contactos.
- La URL firmada de Storage caduca como máximo a los 300 segundos.
- No llames a Idealista, Fotocasa, Habitaclia, Pisos.com ni a una pasarela MLS. La publicación sigue en Inmovilla.

Los pesos y el cálculo están en [Reglas del valorador](docs/40-ia/valorador/criterios-valoracion.md). No los reescribas en el prompt ni en este archivo.

## Cómo trabajar

- Server Components por defecto. `'use client'` solo con interactividad.
- Toda mutación pasa por una Server Action o un Route Handler validado con Zod en `src/lib/validations/`.
- Datos ficticios en semillas, fixtures y ejemplos. Ningún nombre, teléfono, DNI o dirección de un cliente real entra en el repo ni en `docs/`.
- Al cerrar una tarea, márcala en `TASKS.md` y actualiza el relato en `docs/00-inicio/contexto-activo.md`. No copies la lista. No crees `index.md` ni `log.md`.
- `CLAUDE.md` solo contiene `@AGENTS.md`.

## Dónde mirar

- Arquitectura y flujo: [PLANNING.md](PLANNING.md).
- Bóveda: `docs/10-negocio/`, `docs/20-producto/`, `docs/30-arquitectura/`, `docs/40-ia/valorador/`, `docs/60-cliente/reuniones/`.
- Enlaces de la bóveda: rutas relativas Markdown. Sin wikilinks.
- `docs/20-producto/prd.md` es un puntero. El original es `PRD.md`.
