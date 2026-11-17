# Política del repositorio

El repositorio es público para que un bot lea las tareas. Cualquiera con el enlace puede leer el mismo contenido. No hay licencia de uso ni de reutilización.

## Lectura del bot

El bot consulta, sin token de escritura:

- `TASKS.md` es la lista única de tareas.
- `docs/00-inicio/contexto-activo.md` es el relato del momento.
- `PRD.md`, `PLANNING.md` y `AGENTS.md` fijan el contrato.

No se añade al bot como colaborador. No se le da un token con permiso `repo` ni `contents: write`.

## Rama `main`

No se reescribe el historial y no se borra la rama. El titular empuja a `main`. El bot no empuja.

## Qué no se sube

Nada de clientes reales: nombres, teléfonos, DNI, direcciones o documentos. Tampoco claves, `.env` ni `supabase/.temp/`.

## Aviso de un problema

Si aparece una clave o un dato personal, avisa a Adrian por el canal de Solfico. No abras un issue público con ese dato.
