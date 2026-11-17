# AGENTS.md

CRM inmobiliario de RK Santos (Solfico). Cursor abre la raíz. Obsidian abre solo `docs/`.

## Dónde mirar

- Estado vivo: `docs/00-inicio/contexto-activo.md`. No crees `index.md` ni `log.md`.
- Negocio: `docs/10-negocio/`. Producto: `docs/20-producto/`. Contrato: `docs/20-producto/prd.md`.
- Datos y ADR: `docs/30-arquitectura/`.
- Valorador: `docs/40-ia/valorador/`. Reuniones: `docs/60-cliente/reuniones/`.
- Enlaces entre notas: rutas relativas Markdown. Sin wikilinks.

## Código

- `src/`: Next.js App Router y TypeScript estricto, sin `any`.
- `supabase/migrations/`: esquema. `supabase/seed/`: datos ficticios. `supabase/tests/`: pruebas de RLS, fuera de las migraciones.
- Contratos de entrada y salida: `src/lib/validations/schema.types.ts`.
- Fase 1 de pantallas: auth, roles y valorador. La publicación en portales sigue en Inmovilla.

## Datos

Prohibido guardar nombres, teléfonos, DNI o direcciones de clientes reales en el repo o en `docs/`.
