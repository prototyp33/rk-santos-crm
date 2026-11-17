---
title: Registro de decisiones
date: 2026-11-17
status: vigente
---

# Registro de decisiones

Una ADR aceptada se mantiene. Para cambiarla se añade otra que la sustituya. El código nuevo se alinea con las aceptadas.

## ADR-001. Producto por fases, Inmovilla se queda en la publicación

- Estado: aceptada · 2026-11-17
- Contexto: la guía del 5 de noviembre pedía configurar el CRM existente antes de construir. La entrevista del 4 de noviembre acotó el uso real: Inmovilla publica en web, MLS y portales; Horus tiene el método de expediente y no se opera; el valorador diario es un chat suelto.
- Decisión: Fase 1 es el valorador (formulario, revisión humana, ficha, PDF) y la ficha de inmueble que ese valorador necesita. Fase 2 son contactos, círculo de influencia, expedientes y webhooks n8n. La publicación en portales no se construye.
- Consecuencias: no hay dos carteras. El precio publicado sigue mandándolo Inmovilla. Horus sigue como referencia de checklist y como obligación de red.

## ADR-002. Next.js, Supabase y Vercel AI SDK

- Estado: aceptada · 2026-11-17
- Decisión: App Router en `src/app`, UI con shadcn en `src/components/ui`, datos en Supabase (Auth, Postgres, Storage), clientes SSR en `src/lib/supabase`, y `generateObject` en `src/app/api/ai`. Los tipos de base salen de la CLI a `src/types/database.types.ts`.
- Consecuencias: no se edita ese archivo a mano. Cada migración nace con `supabase migration new`. El esquema expuesto lleva RLS desde la primera tabla.

## ADR-003. Tres roles y RLS por responsabilidad

- Estado: aceptada · 2026-11-17
- Decisión: `agent`, `coordinator`, `supervisor`, guardados en `app_metadata`. El agente trabaja sus valoraciones y sus contactos. La coordinadora ve pendientes de documentación de la oficina. El supervisor aprueba la valoración y las excepciones de peso.
- Consecuencias: `user_metadata` no autoriza. Una política abierta no se considera cerrada la tarea.

## ADR-004. La valoración es un cálculo con revisión humana

- Estado: aceptada · 2026-11-17
- Decisión: la fórmula, los códigos de ajuste y el semáforo viven en `reglas-valorador-ia.md`. El modelo rellena un borrador Zod. Sin comparables suficientes, `point_estimate` es nulo. El estado `approved` de esta ADR queda sustituido por `internal_validated` (ADR-009).
- Consecuencias: un peso nuevo no se escribe solo en el prompt. El descuento de oferta a cierre no tiene valor hasta que Raúl lo fije (ADR-005).

## ADR-005. El descuento oferta→cierre queda sin número

- Estado: aceptada · 2026-11-17
- Contexto: en la entrevista, los portales enseñan precios de oferta y las ventas reales hay que añadirlas como testigo. No se acordó un porcentaje de rebaja.
- Decisión: `descuento_oferta_a_cierre` nace nulo. Una valoración hecha solo con anuncios no produce cifra única.
- Consecuencias: el primer caso real que Raúl cierre con testigos propios sirve para proponer el número en una ADR nueva. Hasta entonces el producto prefiere callar la cifra.

## ADR-006. El PDF no ve las notas internas

- Estado: aceptada · 2026-11-17
- Decisión: las plantillas de `src/lib/pdf` leen la fila aprobada y los campos de visibilidad `client`. `narrative_draft`, honorarios y notas de visita quedan en almacenamiento y columnas internas.
- Consecuencias: el bucket separa el prefijo de cliente del prefijo interno. Los dos son privados.

## ADR-007. Bóveda `docs/` como memoria del proyecto

- Estado: aceptada · 2026-11-17
- Decisión: `docs/` se enlaza desde Obsidian. La estrategia, las actas, el contrato de datos y el estado del sprint viven ahí. Al cambiar rutas, campos o pesos se actualiza el archivo correspondiente en el mismo cambio (regla `99-doc-sync`).
- Consecuencias: no se versiona un segundo resumen paralelo del sprint.

## ADR-008. Datos reales fuera del repositorio

- Estado: aceptada · 2026-11-17
- Decisión: semillas, fixtures y prompts de ejemplo son ficticios. Las claves van en `.env.local`. `.env.local` y `.grok-*.xml` no se commitean. El tratamiento por cuenta de RK Santos exige encargo de tratamiento antes de conectar producción.
- Consecuencias: un volcado de Inmovilla o de Horus no se pega en `seed.sql` ni en un issue. Se anonimiza fuera del repo y se revisa antes de entrar.

## ADR-009. Pipeline, esquema del día 1 y ficha en dos estados

- Estado: aceptada · 2026-11-17
- Sustituye: el estado `approved` de ADR-004 y el aplazamiento de las tablas de expediente.
- Decisión: el pipeline comercial tiene ocho fases fijas (`circulo_influencia` → `notaria`). El esquema completo del diccionario se migra el día 1; la fase 1 de pantallas sigue siendo Auth/Roles + Valorador IA. La ficha de valoración está en `draft` o `internal_validated`. Las extracciones de IA nacen en `pending_review` y no pisan el campo consolidado. El PDF del propietario exige `internal_validated`, responde 403 en caso contrario y sale de `ExternalValuationPdfSchema`. Las URLs de Storage caducan como máximo a los 300 segundos. Idealista, Fotocasa, Habitaclia, Pisos.com y la pasarela MLS quedan fuera.
- Consecuencias: los parámetros maestros del valorador solo los cambia `supervisor`. `coordinator` no los toca. El agente solo ve lo suyo.

## ADR-010. Quién cierra una valoración en la fase 1

- Estado: aceptada · 2026-11-17
- Sustituye: la frase de ADR-003 que reserva al supervisor toda aprobación de la valoración, y la frase de ADR-009 que deja la ficha solo en `draft` o `internal_validated`. Se mantiene que el supervisor aprueba las excepciones de peso, que el rol se lee de `app_metadata` y que el PDF exige `internal_validated`.
- Contexto: un agente nuevo tiene que obtener una valoración con los mismos criterios. El criterio de Raúl entra cuando la cifra no sale o un ajuste se sale de banda. La coordinadora necesita ver la oficina en la fase 1; su revisión documental es la fase 2.
- Decisión: el agente pasa la ficha a `internal_validated` cuando hay `point_estimate`, la confianza no es `insufficient` y todos los deltas están dentro de su banda. Si falta alguna de esas tres condiciones, la ficha queda en `pending_supervisor` y solo el supervisor la valida. Un delta fuera de banda solo lo guarda el supervisor. En la fase 1 la coordinadora ve las valoraciones de toda la agencia en solo lectura. No hay pantalla de checklists ni de documentos. El alta es por invitación.
- Consecuencias: el contrato comprobable está en [PRD](../../20-producto/prd.md). Al implementar la fase 1, el estado que habilita el PDF es `internal_validated`. El valor `approved` del enum actual no cumple ese criterio. Las políticas de checklist ya existentes no se exponen en pantalla hasta la fase 2.
