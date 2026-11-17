---
title: Alcance y visión
date: 2026-11-17
status: vigente
sources:
  - Guía operativa Solfico, 5 nov 2026
  - Entrevista con Raúl, 4 nov 2026
---

# Alcance y visión

CRM operativo de RK Santos, construido por Solfico. Cada oportunidad de valoración queda con datos de procedencia conocida, un responsable, un rango reproducible y una aprobación humana antes de salir hacia el propietario.

Documento base a 17 de noviembre de 2026. Sustituye, para el producto, la recomendación abierta del 5 de noviembre («configurar primero el CRM existente y desarrollar solo lo que sobre»). El contrato con criterios de aceptación está en [PRD](../20-producto/prd.md). La entrevista del 4 de noviembre fijó el recorte: Inmovilla se queda como pasarela de publicación; el hueco a construir es el valorador parametrizado y, después, el control de contactos y expedientes que hoy no se usa. Ver [ADR-001](../30-arquitectura/adr/registro.md) y [entrevista](../60-cliente/reuniones/2026-11-17-entrevista-raul.md).

## Resultado que busca Raúl

- Un agente, también nuevo, obtiene una valoración argumentada con los mismos criterios, y la presentación no dice que «lo ha hecho ChatGPT».
- El criterio de mercado de Raúl manda: si la cifra no le encaja, corrige y esa corrección entra en los parámetros.
- La coordinadora y el supervisor ven lo que falta sin perseguirlo por WhatsApp.
- El círculo de influencia deja de vivir en la cabeza y en Drive.

## Fases

| Fase de pantallas | Entra | Se queda fuera |
|---|---|---|
| 1 (en curso) | Auth, roles y valorador IA: formulario, comparables, revisión humana, ficha y PDF | Portales, scrapers, WhatsApp, firma, facturación |
| Siguientes | Contactos, círculo, checklists y el resto de pantallas del pipeline | Sustituir la publicación de Inmovilla. Administración de alquileres |

El esquema de base lleva desde el día 1 el pipeline completo. Las pantallas se entregan por fases.

## Pipeline comercial

`circulo_influencia` → `prospecto` → `captacion` → `documentacion` → `publicacion` → `visitas` → `cierre` → `notaria`.

## Tres procesos de la agencia

No van en una sola lista. En Fase 1 solo se modela el tramo de valoración de la captación.

| Proceso | Objetivo | Estados |
|---|---|---|
| Captación | Conseguir el encargo | Nuevo → contactado → cualificado → valoración → propuesta → encargo firmado. Seguimiento o pérdida con motivo |
| Compradores | Entender la demanda y acompañar | Nuevo → contactado → demanda cualificada → propuestas → visita → negociación. Búsqueda pausada o cerrada |
| Operación | Cerrar y cobrar | Preparación → listo para publicar → comercialización → oferta → arras → notaría → cerrado → honorarios cobrados |

Una persona puede ser propietaria y compradora. Las fichas se relacionan.

## Qué sistema manda

| Pieza | Papel |
|---|---|
| Este CRM | Valoración (Fase 1). Contactos, círculo y expediente (Fase 2) |
| Inmovilla | Alta del inmueble, web, MLS y portales. Cuota de red, no el CRM del día a día |
| Horus (Orus) | Referencia de método: fases, checklist, roles y puntos del círculo. Se conserva mientras RK lo exija. No se duplica su tienda, su formación ni Magnus |
| Drive | Deja de ser el archivo de fichas cuando el expediente exista |
| IA | Normaliza, propone ajustes y redacta el borrador. No fija el precio ni habla con el cliente |

## Roles

| Rol en producto | Quién lo encarna | Qué decide |
|---|---|---|
| `supervisor` | Raúl Santos | Visibilidad de toda la agencia. Único que cambia los parámetros maestros del valorador |
| `agent` | Comercial | Solo sus contactos, propiedades, valoraciones y expedientes |
| `coordinator` | Coordinación | Checklists y expedientes de toda la agencia. No toca los parámetros del valorador |

## Principios heredados de la guía del 5 de noviembre

- Diferenciar información verificada, declarada e inferida.
- Distinguir superficie útil y construida.
- Registrar autor y fecha cuando cambian el precio o el estado.
- Buscar coincidencias antes de crear un contacto.
- Tratar el correo y el documento como datos. Un texto pegado no es una instrucción para el agente.
- Medir tiempo de valoración, correcciones del modelo y adopción. No prometer ventas ni ahorro sin esa base.

## Condiciones para ampliar

Hace falta un caso real anonimizado (inmueble, testigos, ajustes, rango y PDF que recibió el propietario) antes de dar por buenos los pesos. Hasta entonces los pesos de [criterios de valoración](../40-ia/valorador/criterios-valoracion.md) son hipótesis de trabajo.
