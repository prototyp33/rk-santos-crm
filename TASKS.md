# TASKS

Lista única. Al cerrar una tarea, márcala aquí. El relato va en [contexto activo](docs/00-inicio/contexto-activo.md) y no copia esta lista.

Cada tarea abierta cabe en una revisión. La verificación es la prueba que tiene que cumplirse antes de marcarla. Los criterios numerados son los de [PRD.md](PRD.md).

## Hecho

- [x] Esquema y semilla en Supabase **Solfico x RK**: 36 tablas con RLS, 5 buckets privados, 49 zonas, parámetros v1 y checklist de ejemplo inactivo.
  Verificación: el proyecto `qijftdiwmjrytpvisvyw` tiene esas tablas y la semilla aplicada.
- [x] Contratos Zod en `src/lib/validations/schema.types.ts` y modelo en `docs/30-arquitectura/modelo-datos.md`.
  Verificación: el archivo exporta `AppRole`, `ValuationParamsSchema` y `ValuationAIOutputSchema`.
- [x] Prueba de humo escrita en `supabase/tests/rls_smoke_test.sql`.
  Verificación: el archivo existe y no forma parte de `supabase/migrations/`.
- [x] `PRD.md`, `AGENTS.md`, `PLANNING.md` y ADR-010.
  Verificación: el PRD tiene 17 criterios y la fase en curso es la 1.
- [x] **SPEC-001.** `docs/20-producto/specs/SPEC-001-valorador-ia.md`.
  Verificación: el flujo es formulario cerrado, extracción con confirmación, ficha interna y PDF limitado. Enlaza criterios, modelo de datos, `schema.types.ts` y deja constancia de que `reglas-valorador-ia.md` no está en la bóveda.

## Fase 0. Base alineada con el PRD

- [ ] **F0-1. Estado `internal_validated` en el enum**
  Añade `internal_validated` a `valuation_status` en una migración nueva. El PDF no trata `approved` como ficha cerrada.
  Verificación: la migración aplica en una base desechable y `select enum_range(null::public.valuation_status)` incluye `internal_validated`. `docs/30-arquitectura/modelo-datos.md` menciona ese valor.

- [ ] **F0-2. Humo RLS ejecutado**
  Corre `supabase/tests/rls_smoke_test.sql` en una base desechable, con el stub de auth que el propio archivo espera.
  Verificación: la salida termina con las comprobaciones en OK y el proceso sale con código 0. Si falta el stub local, la tarea sigue abierta.

## Fase 1. Acceso y roles

- [ ] **F1-1. App Next.js sin borrar los contratos**
  Crea la app en App Router con TypeScript estricto, Tailwind y la carpeta `src/`. Conserva `src/lib/validations/schema.types.ts`.
  Verificación: `npm run build` sale con código 0 y el contrato Zod sigue en su ruta.

- [ ] **F1-2. shadcn**
  Inicializa shadcn y deja el botón de la librería en `src/components/ui/`.
  Verificación: existe `components.json` y `npm run build` sigue en código 0.

- [ ] **F1-3. Clientes Supabase de servidor**
  Añade los clientes SSR en `src/lib/supabase/` leyendo la URL y la clave publicable de entorno. No imprimas secretos.
  Verificación: `npx tsc --noEmit` sale con código 0 y un grep de `src/` no encuentra la service role en un componente de cliente.

- [ ] **F1-4. Alta solo por invitación**
  Criterio 1. No hay página de registro. El alta pública de Auth queda desactivada.
  Verificación: `signUp` con la clave anónima y un email ficticio no crea fila en `auth.users`.

- [ ] **F1-5. Login**
  Pantalla `src/app/(auth)/login`. Una sesión válida entra al listado de valoraciones.
  Verificación: sin sesión, `/login` responde 200. Con una sesión de semilla, el listado responde 200 y `/login` redirige a ese listado.

- [ ] **F1-6. El rol no sale de `user_metadata`**
  Criterio 2. La sesión usa `app_metadata.role`. Un rol escrito solo en `user_metadata` no concede acceso de otro rol.
  Verificación: un usuario de prueba con `user_metadata.role = supervisor` y sin ese rol en `app_metadata` no puede activar parámetros.

- [ ] **F1-7. Perfil inactivo**
  Criterio 3. `profiles.is_active = false` no lee ni escribe.
  Verificación: con un usuario de semilla desactivado, un `select` de sus valoraciones devuelve cero filas y un `insert` falla.

- [ ] **F1-8. Aislamiento del agente**
  Criterio 4. El agente ve y edita solo sus valoraciones.
  Verificación: dos agentes de semilla. El agente A pide la valoración del agente B y la respuesta no incluye esa fila. Un update directo de esa fila no cambia nada.

- [ ] **F1-9. El agente no toca parámetros**
  Criterio 5.
  Verificación: como agente, `insert` en `valuation_parameters` falla. Como supervisor, crear una versión inactiva y activarla deja una sola fila con `is_active`.

- [ ] **F1-10. Coordinadora en solo lectura**
  Criterio 6. Ve el listado de toda la agencia. La ficha no muestra acciones de guardar, validar ni editar deltas.
  Verificación: con la sesión de coordinadora, el listado muestra valoraciones de dos agentes. La Server Action de guardar responde error y la fila no cambia.

- [ ] **F1-11. Sin pantallas de checklist ni de documentos**
  Criterio 7.
  Verificación: no existe ruta `src/app/**/expedientes` ni `src/app/**/checklists`. Un recorrido de la navegación de la fase 1 no enlaza esas pantallas.

- [ ] **F1-12. Parámetros solo del supervisor**
  Criterio 8. Pantalla de parámetros visible para el supervisor y ausente para agente y coordinadora.
  Verificación: el supervisor activa una versión y la valoración nueva guarda ese `parameters_id`. Agente y coordinadora reciben 403 al abrir la ruta.

## Fase 1. Valorador

- [ ] **F1-13. Alta en borrador**
  `src/app/(dashboard)/valuations/new` crea una fila `draft` con el `parameters_id` activo.
  Verificación: el alta con datos ficticios deja `status = draft` y el parámetro activo del momento.

- [ ] **F1-14. Menos de tres comparables**
  Criterio 9. Función pura en `src/lib/valuation/`.
  Verificación: un test con dos comparables seleccionados devuelve `point_estimate` nulo y confianza `insufficient`.

- [ ] **F1-15. Solo ofertas y descuento nulo**
  Criterio 10.
  Verificación: un test con tres comparables de oferta y `descuento_oferta_a_cierre` nulo devuelve `point_estimate` nulo, confianza `insufficient` y el rango etiquetado como precios de oferta.

- [ ] **F1-16. Caso con cifra**
  Tres comparables de cierre, en la misma zona, producen mediana, rango y `point_estimate`.
  Verificación: un test con tres cierres ficticios devuelve una cifra distinta de nulo y confianza distinta de `insufficient`.

- [ ] **F1-17. Extracciones**
  Criterio 11. La ruta `src/app/api/ai/valuations` guarda cada extracción en `pending_review`. Confirmar escribe el campo. Descartar lo deja igual.
  Verificación: un test de la acción de confirmar cambia el campo consolidado al valor extraído. La acción de descartar, sobre una copia de la misma fila, lo deja como estaba.

- [ ] **F1-18. Cierre del caso normal y de la excepción**
  Criterio 12. Pantalla `valuations/[id]/review`.
  Verificación: con cifra, confianza distinta de `insufficient` y deltas dentro de banda, el agente deja la ficha en `internal_validated`. Con una de esas tres condiciones ausente, el mismo intento deja `pending_supervisor` y un segundo intento del agente no la saca de ahí. El supervisor sí la pasa a `internal_validated`.

- [ ] **F1-19. Delta fuera de banda**
  Criterio 13.
  Verificación: un agente envía un delta por encima del techo de [criterios](docs/40-ia/valorador/criterios-valoracion.md) y el guardado es rechazado. El mismo delta, guardado por el supervisor, persiste con su motivo.

- [ ] **F1-20. Ajuste `other` sin motivo**
  Verificación: un test del esquema rechaza `other` con motivo vacío y acepta `other` con una frase.

- [ ] **F1-21. PDF cerrado**
  Criterios 14 y 15. `src/lib/pdf/` responde 403 fuera de `internal_validated`. El payload pasa por `ExternalValuationPdfSchema`.
  Verificación: pedir el PDF en `draft` y en `pending_supervisor` responde 403. En `internal_validated`, el cuerpo no contiene `narrative_draft`, notas internas, honorarios ni datos de otro contacto.

- [ ] **F1-22. URL firmada**
  Criterio 16. Toda lectura de Storage usa `createSignedUrl` con caducidad de 300 segundos o menos.
  Verificación: un grep de `createSignedUrl` en `src/` muestra el límite en cada llamada, y un test pide una URL con 301 segundos y la función la rechaza.

- [ ] **F1-23. Sin portales**
  Criterio 17.
  Verificación: un grep de `src/` no encuentra Idealista, Fotocasa, Habitaclia, Pisos.com ni una llamada de publicación MLS.

## Fase 2. Nombrada, sin criterios

No se implementa. El PRD nombra contactos, círculo de influencia, demandas y checklists, y no da criterios de aceptación.

- [ ] **F2-0. Esperar criterios**
  Verificación: `PRD.md` sigue sin criterios de la fase 2. No existe código de pantallas en `src/app/(dashboard)/contacts` ni en `expedientes`.

## Fase 3. Nombrada, sin criterios

No se implementa. El PRD nombra ofertas, cierre y notaría.

- [ ] **F3-0. Esperar criterios**
  Verificación: `PRD.md` sigue sin criterios de la fase 3 y no hay rutas de ofertas, cierre ni notaría.

## Bloqueado por el cliente

Estas tres no se cierran con código.

- [ ] **C-1. Descuento oferta a cierre**
  Verificación: Raúl fija el número, o confirma por escrito que la cifra sale solo de ventas propias. Hasta entonces `descuento_oferta_a_cierre` sigue nulo.

- [ ] **C-2. Bandas del valorador**
  Verificación: un caso anonimizado, fuera del repo, valida o corrige las bandas de `docs/40-ia/valorador/criterios-valoracion.md`.

- [ ] **C-3. Horus y una ficha completa**
  Verificación: llegan el acceso de lectura y una ficha anonimizada antes de guardarla. El original con datos reales no entra en el repo.
