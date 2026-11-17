---
title: PRD
date: 2026-11-17
status: vigente
tags:
  - producto
---

# PRD

Qué se construye, para quién, y qué tiene que cumplirse para dar por cerrada la fase 1. El detalle largo vive en las notas enlazadas. Este archivo no lo copia.

## Problema

Cada valoración de RK Santos sale hoy de un chat suelto. Un agente nuevo no reproduce el criterio de Raúl, la presentación parece hecha por un chat genérico, y lo que falta se persigue por WhatsApp. El círculo de influencia vive en la cabeza y en Drive.

## Para quién

El CRM es para tres personas de la agencia.

| Rol | Quién | En la fase 1 |
|---|---|---|
| `supervisor` | Raúl Santos | Ve toda la oficina. Único que cambia los parámetros del valorador y único que valida la excepción |
| `agent` | Comercial | Trabaja sus valoraciones. Valida el caso normal |
| `coordinator` | Coordinación | Ve las valoraciones de toda la agencia en solo lectura |

La revisión de checklists y expedientes de la coordinadora llega en la fase 2.

## Alcance

CRM operativo de la agencia. La fase 1 de pantallas es el acceso por invitación, los tres roles y el valorador: formulario, comparables, revisión humana, ficha y PDF. El esquema de base ya lleva el pipeline completo (`circulo_influencia` → `prospecto` → `captacion` → `documentacion` → `publicacion` → `visitas` → `cierre` → `notaria`).

La fase 2 nombra contactos, círculo de influencia, demandas y checklists. La fase 3 nombra ofertas, cierre y notaría. Esas dos fases no tienen criterios de aceptación.

## No-objetivos

Quedan fuera de todas las fases los scrapers y las API de Idealista, Fotocasa, Habitaclia y Pisos.com, la pasarela MLS y la publicación en portales, que siguen en Inmovilla, la administración de alquileres, la firma, la facturación y WhatsApp. Horus se conserva como referencia de método. La IA normaliza, propone ajustes y redacta el borrador. El precio lo fija una persona, y el sistema no habla con el cliente.

## Reglas de la fase 1

El cálculo, los comparables, el semáforo y el contenido del PDF siguen en [Reglas del valorador](../40-ia/valorador/criterios-valoracion.md).

Los estados de la ficha en esta fase son `draft`, `pending_supervisor` e `internal_validated`.

**Quién cierra una valoración.** El agente la pasa a `internal_validated` cuando hay `point_estimate`, la confianza no es `insufficient` y todos los deltas están dentro de su banda. Si falta alguna de esas tres condiciones, la ficha queda en `pending_supervisor` y solo el supervisor la valida. Solo el supervisor crea o activa una versión de parámetros. Un delta fuera de banda solo lo deja él. Ver [ADR-010](../30-arquitectura/adr/registro.md).

**Coordinadora.** Inicia sesión y ve las valoraciones de toda la agencia en solo lectura. No cambia el estado, no edita la ficha y no toca parámetros. La revisión de checklists y documentos no tiene pantalla en esta fase. Las políticas de checklist que ya están en la base esperan a la fase 2.

**Acceso.** No hay registro público. El alta es por invitación. El rol que autoriza es el de `app_metadata`.

## Casos límite

Con menos de tres comparables seleccionados no hay cifra. Con solo precios de oferta y `descuento_oferta_a_cierre` nulo, no hay cifra y el rango se etiqueta como precios de oferta. Una extracción de la IA nace en `pending_review` y no pisa el campo consolidado hasta que el agente la confirma. Un ajuste `other` sin motivo no se guarda. El PDF responde 403 si la ficha no está en `internal_validated`, y omite notas internas, honorarios y datos de otros contactos. La URL de un archivo caduca como máximo a los 300 segundos.

Los pesos del valorador siguen siendo hipótesis hasta que Raúl valide un caso anonimizado. La fase 1 se puede comprobar con datos ficticios.

## Criterios de aceptación de la fase 1

1. Una persona sin invitación no crea cuenta.
2. Cambiar `user_metadata` no cambia lo que esa persona puede ver o hacer.
3. Un usuario desactivado no lee ni escribe datos.
4. Un agente ve y edita solo sus valoraciones. La de otro agente no le aparece.
5. Un agente no crea ni activa parámetros del valorador.
6. La coordinadora ve las valoraciones de toda la agencia en solo lectura.
7. La fase 1 no ofrece pantalla de revisión de checklists ni de documentos.
8. El supervisor ve toda la agencia y es el único que crea o activa parámetros.
9. Con menos de tres comparables seleccionados, `point_estimate` queda nulo y la confianza queda `insufficient`.
10. Con solo anuncios y el descuento nulo, `point_estimate` queda nulo y el rango se muestra como precios de oferta.
11. Confirmar una extracción escribe el campo consolidado. Descartarla lo deja como estaba.
12. El agente pasa la ficha a `internal_validated` cuando hay `point_estimate`, la confianza no es `insufficient` y todos los deltas están dentro de banda. Si falta alguna de esas tres condiciones, el intento deja la ficha en `pending_supervisor` y solo el supervisor la pasa a `internal_validated`.
13. Un delta fuera de su banda, guardado por alguien que no es supervisor, es rechazado.
14. Pedir el PDF en un estado distinto de `internal_validated` responde 403.
15. El PDF generado no contiene notas internas, honorarios ni datos de otros contactos.
16. Una URL firmada de Storage caduca en 300 segundos o menos.
17. Ninguna pantalla ni ruta llama a Idealista, Fotocasa, Habitaclia, Pisos.com ni a una pasarela MLS.

## Lecturas

- [Alcance y visión](../10-negocio/vision-y-alcance.md)
- [Roadmap](roadmap.md)
- [Registro de ADR](../30-arquitectura/adr/registro.md)
- [Reglas del valorador](../40-ia/valorador/criterios-valoracion.md)
