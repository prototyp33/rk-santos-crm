# PLANNING

Cómo se construye lo que pide [PRD.md](PRD.md), con las reglas de [AGENTS.md](AGENTS.md).

## Fase en curso

La fase 1 entrega acceso por invitación, los tres roles y el valorador. El esquema de las ocho fases del pipeline ya está en la base. Las pantallas de las fases 2 y 3 no se construyen hasta que el PRD tenga criterios.

Flujo de una valoración:

1. El agente crea una ficha en `draft`, ligada a la versión activa de parámetros.
2. El modelo devuelve un borrador. Cada extracción queda en `pending_review`.
3. El agente confirma o descarta. Solo la confirmación escribe el campo consolidado.
4. El cálculo deja `point_estimate` nulo cuando faltan tres comparables o cuando solo hay ofertas y el descuento es nulo.
5. El agente valida si hay cifra, la confianza no es `insufficient` y los deltas están dentro de banda. Si no, la ficha pasa a `pending_supervisor` y la cierra el supervisor.
6. El PDF se genera solo desde `internal_validated`.

## Stack

- Next.js (App Router) y TypeScript estricto, sin `any`. Tailwind y shadcn/ui.
- Supabase: PostgreSQL, Auth, RLS y Storage. Proyecto **Solfico x RK** (`qijftdiwmjrytpvisvyw`, región eu-west-1).
- Vercel AI SDK, `generateObject`, y Zod. Contratos en `src/lib/validations/schema.types.ts`.
- Los tipos generados de la base van a `src/types/database.types.ts` y no se editan a mano.

## Mapa

| Ruta | Responsabilidad |
|---|---|
| `PRD.md` | Contrato y criterios de la fase 1 |
| `AGENTS.md` | Reglas que el agente no rompe |
| `TASKS.md` | Lista única. Se marca al cerrar |
| `docs/` | Memoria larga. Obsidian abre solo esta carpeta |
| `src/app/(auth)/login` | Acceso. Sin página de registro |
| `src/app/(dashboard)/valuations` | Lista según el rol |
| `src/app/(dashboard)/valuations/new` | Alta en `draft` |
| `src/app/(dashboard)/valuations/[id]` | Ficha |
| `src/app/(dashboard)/valuations/[id]/review` | Confirmar extracciones y cerrar |
| `src/app/(dashboard)/properties` | Ficha del inmueble que la valoración necesita |
| `src/app/api/ai/valuations` | Borrador estructurado. No fija el precio publicado |
| `src/lib/valuation/` | Cálculo puro: comparables, banda, confianza, transición de estado |
| `src/lib/pdf/` | PDF de cliente. Exige `internal_validated` |
| `supabase/migrations/` | Esquema. Una migración nueva nace con `supabase migration new` |
| `supabase/seed/` | Datos ficticios |
| `supabase/tests/` | RLS, fuera de las migraciones |

Todavía no existe el árbol de Next.js. `src/` solo tiene los contratos Zod.

## Roles en la fase 1

| Rol | Pantalla | Mutación |
|---|---|---|
| `agent` | Sus valoraciones y la ficha del inmueble asociado | Crea el borrador, confirma extracciones y valida el caso normal |
| `coordinator` | Todas las valoraciones de la agencia | Ninguna. Sin pantalla de checklists ni de documentos |
| `supervisor` | Toda la agencia y los parámetros | Activa parámetros, guarda un delta fuera de banda y valida la excepción |

`profiles.is_active` nace en falso. El alta la completa el supervisor. Las políticas ya exigen `is_active`.

## Qué no entra en el código

Scrapers y API de Idealista, Fotocasa, Habitaclia y Pisos.com. Pasarela MLS. Firma, facturación, WhatsApp y administración de alquileres. Pantallas de la fase 2 y la fase 3. Un número inventado para `descuento_oferta_a_cierre`.

## Flujo de trabajo

1. Leer este archivo, revisar `TASKS.md` y coger la primera tarea abierta de la fase en curso.
2. Arrancar la app, cuando toque esa tarea, con `create-next-app` dejando los contratos que ya están en `src/lib/validations/`. Después, `shadcn init`.
3. Enlazar el CLI con `supabase link --project-ref qijftdiwmjrytpvisvyw` cuando haya contraseña de la base.
4. Cerrar la tarea en `TASKS.md` solo si la verificación de esa tarea se cumple. Actualizar el relato en `docs/00-inicio/contexto-activo.md`.
