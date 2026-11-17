---
title: Seguridad y RGPD
date: 2026-11-17
status: vigente
tags:
  - seguridad
  - rgpd
---

# Seguridad y RGPD

- Ningún nombre, teléfono, DNI o dirección de un cliente real entra en el repo ni en `docs/`. La semilla de `supabase/seed/` es ficticia.
- El rol vive en `profiles` y en `app_metadata`. `user_metadata` no autoriza.
- RLS en cada tabla de `public`, con políticas distintas para `agent`, `coordinator` y `supervisor`.
- DNI, nota simple, escrituras, mandatos, audios y PDF de valoración van a buckets privados. La lectura usa una URL firmada de 300 segundos como máximo.
- El PDF para el propietario sale solo de una valoración validada por una persona y sin notas internas, alertas de riesgo ni citas del modelo.
- Un consentimiento para avisos de inmuebles no autoriza otra campaña.

El detalle de tablas y políticas está en [modelo de datos](modelo-datos.md).
