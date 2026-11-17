---
title: Roadmap
date: 2026-11-17
status: vigente
tags:
  - producto
---

# Roadmap

El esquema de base existe desde el día 1. Las pantallas salen por fases. El contrato de producto y los criterios de la fase 1 están en [PRD](../../PRD.md). Las tablas vigentes están en [modelo de datos](../30-arquitectura/modelo-datos.md) y los términos, en el [glosario](../00-inicio/glosario.md).

| Fase de pantallas | Incluye |
|---|---|
| 1, en curso | Auth, roles y valorador (formulario, revisión humana, ficha, PDF) |
| 2 | Contactos, círculo de influencia, demandas y checklists |
| 3 | Ofertas, cierre y notaría |

Fuera de todas las fases: scrapers, API de Idealista, Fotocasa, Habitaclia o Pisos.com, y la pasarela MLS.

## Rutas previstas

Ninguna existe todavía.

| Ruta | Fase |
|---|---|
| `src/app/(auth)/login` | 1 |
| `src/app/(dashboard)/valuations` | 1 |
| `src/app/(dashboard)/valuations/new` | 1 |
| `src/app/(dashboard)/valuations/[id]` | 1 |
| `src/app/(dashboard)/valuations/[id]/review` | 1 |
| `src/app/(dashboard)/properties` | 1 |
| `src/app/(dashboard)/properties/[id]` | 1 |
| `src/app/api/ai/valuations` | 1 |
| `src/app/(dashboard)/contacts` | 2 |
| `src/app/(dashboard)/expedientes` | 2 |
| `src/app/(dashboard)/expedientes/[id]` | 2 |
| `src/app/api/webhooks/n8n` | 2 |

Las especificaciones de cada pantalla van en [specs](specs/). La primera es [SPEC-001 Valorador IA](specs/SPEC-001-valorador-ia.md).
