---
title: Contexto activo
date: 2026-11-17
status: vigente
tags:
  - estado
---

# Contexto activo

Relato del momento. La lista de tareas está en [TASKS.md](../../TASKS.md) y no se copia aquí. Última actualización: 17 de noviembre de 2026.

## Ahora

El núcleo de agentes está en la raíz: [PRD](../../PRD.md), [PLANNING](../../PLANNING.md), [AGENTS](../../AGENTS.md) y [TASKS](../../TASKS.md). El contrato cubre el producto completo y los criterios comprobables solo de la fase 1. El esquema y la semilla ya están en el proyecto de Supabase **Solfico x RK** (`qijftdiwmjrytpvisvyw`, región eu-west-1): 36 tablas con RLS, 5 buckets privados, 49 zonas de ejemplo, parámetros del valorador v1 y el checklist de ejemplo inactivo. La prueba de humo RLS no se ha ejecutado: el archivo es solo para una base desechable y usa meta-comandos de psql. No hay aplicación Next.js todavía.

## Hecho

- Repositorio público en GitHub: [prototyp33/rk-santos-crm](https://github.com/prototyp33/rk-santos-crm). Un bot puede leerlo sin token. La política está en [.github/SECURITY.md](../../.github/SECURITY.md).
- Contrato de datos en [modelo de datos](../30-arquitectura/modelo-datos.md) y tipos Zod en `src/lib/validations/schema.types.ts`.
- Pruebas de RLS en `supabase/tests/rls_smoke_test.sql`.
- Negocio, auditoría y entrevista reubicados en `10-negocio/` y `60-cliente/reuniones/`.
- El grafo activo ya no sale de `90-archivo/`: el diccionario del turno 1 no enlaza, y Obsidian excluye `_sistema/` y `90-archivo/`.
- [PRD](../../PRD.md) y [ADR-010](../30-arquitectura/adr/registro.md): el agente valida el caso normal, el supervisor la excepción, y la coordinadora ve la oficina en solo lectura.
- Núcleo de agentes en la raíz, [ADR-011](../30-arquitectura/adr/registro.md).
- [SPEC-001](../20-producto/specs/SPEC-001-valorador-ia.md): flujo del valorador, del formulario cerrado al PDF limitado.

## Siguiente paso

La lista está en [TASKS.md](../../TASKS.md). La primera tarea abierta es F0-1: el enum `valuation_status` tiene que incluir `internal_validated`. Las fases 2 y 3 siguen sin criterios y no se abren.

## Pendiente del cliente

- Fijar el descuento de precio de oferta a precio de cierre, o confirmar que la cifra sale solo con ventas propias. Ver [registro de ADR](../30-arquitectura/adr/registro.md).
- Validar las bandas del valorador con un caso anonimizado.
- Entregar acceso de lectura a Horus y una ficha completa, ofrecidos en la [entrevista](../60-cliente/reuniones/2026-11-17-entrevista-raul.md).
