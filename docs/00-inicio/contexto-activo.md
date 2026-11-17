---
title: Contexto activo
date: 2026-11-17
status: vigente
tags:
  - estado
---

# Contexto activo

Único estado vivo del proyecto. Última actualización: 17 de noviembre de 2026.

## Ahora

La bóveda usa esta estructura. El contrato de producto está en [PRD](../20-producto/prd.md): producto completo y criterios comprobables solo de la fase 1. El esquema y la semilla ya están en el proyecto de Supabase **Solfico x RK** (`qijftdiwmjrytpvisvyw`, región eu-west-1): 36 tablas con RLS, 5 buckets privados, 49 zonas de ejemplo, parámetros del valorador v1 y el checklist de ejemplo inactivo. La prueba de humo RLS no se ha ejecutado: el archivo es solo para una base desechable y usa meta-comandos de psql. No hay aplicación Next.js todavía.

## Hecho

- Repositorio privado en GitHub: [prototyp33/rk-santos-crm](https://github.com/prototyp33/rk-santos-crm).
- Contrato de datos en [modelo de datos](../30-arquitectura/modelo-datos.md) y tipos Zod en `src/lib/validations/schema.types.ts`.
- Pruebas de RLS en `supabase/tests/rls_smoke_test.sql`.
- Negocio, auditoría y entrevista reubicados en `10-negocio/` y `60-cliente/reuniones/`.
- [PRD](../20-producto/prd.md) y [ADR-010](../30-arquitectura/adr/registro.md): el agente valida el caso normal, el supervisor la excepción, y la coordinadora ve la oficina en solo lectura.

## Siguiente paso

Cuando se pida arrancar el código: `create-next-app` en `src/` y `shadcn init`. Para enlazar el CLI hace falta la contraseña de la base (`supabase link --project-ref qijftdiwmjrytpvisvyw`). El mapa de pantallas está en [roadmap](../20-producto/roadmap.md).

## Pendiente del cliente

- Fijar el descuento de precio de oferta a precio de cierre, o confirmar que la cifra sale solo con ventas propias. Ver [registro de ADR](../30-arquitectura/adr/registro.md).
- Validar las bandas del valorador con un caso anonimizado.
- Entregar acceso de lectura a Horus y una ficha completa, ofrecidos en la [entrevista](../60-cliente/reuniones/2026-11-17-entrevista-raul.md).
