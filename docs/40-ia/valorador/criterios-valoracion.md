---
title: Reglas y especificación del Valorador IA
date: 2026-11-19
version: 2.0
status: especificacion-tecnica-v1-pendiente-validacion-negocio
---

# Reglas y especificación del Valorador IA

Documento maestro del motor de valoración comercial y su integración en el CRM. Sustituye a las hipótesis de pesos manuales del 17 de noviembre por una arquitectura AVM en dos niveles (modelo base hedónico y Gradient Boosting con explicabilidad SHAP e intervalos conformales) alineada con las métricas de la European AVM Alliance (EAA).

El flujo de pantalla está en [SPEC-001](../../20-producto/specs/SPEC-001-valorador-ia.md), las reglas de validación en [ADR-010](../../30-arquitectura/adr/registro.md) y el alcance de producto en [PRD](../../../PRD.md).

---

## 1. Alcance, usos admitidos y exclusiones

El sistema valora **vivienda residencial en el municipio de Barcelona** (v1) y devuelve un valor estimado en euros, un rango conformal calibrado, una nota de confianza de `0` a `7`, su desviación estándar prevista (FSD) y el desglose explicativo en euros por bloque de variables.

- **Usos admitidos:** valoración interna, orientación comercial de precio de salida, captación, priorización y seguimiento de carteras.
- **Exclusión regulatoria estricta:** no es una tasación homologada ni sustituye el valor fiscal. Queda prohibido su uso para finalidades hipotecarias reguladas o bajo el Anejo 9 de la Circular 4/2017 del Banco de España (que exige sociedades o servicios de tasación homologados).
- **Fuera de alcance en v1:** inmuebles no residenciales (locales, oficinas, naves, suelo) y municipios distintos de Barcelona.
- **Exclusiones del entrenamiento base (módulo aparte):** viviendas con situación posesoria no libre (`alquilado` con contrato vigente, `okupado`, `nuda propiedad`) o bajo régimen de protección oficial (`VPO`). No entran en el entrenamiento del modelo base; se etiquetan con bandera, generan aviso en API y pasan a un módulo de descuento financiero o tope legal aparte.

---

## 2. Fuentes de datos, verdad de precio y cumplimiento

> **Regla de oro:** los datos de oferta (anuncios) y los de cierre se mantienen siempre separados; el código rechaza cualquier fila de oferta como variable objetivo de nivel de precio.

| Fuente | Uso en el sistema | Condiciones y licencias |
| :--- | :--- | :--- |
| **Catastro INSPIRE** (parcelas, edificios, unidades) | Ficha física base (superficie, año, uso, plantas, calidad constructiva) y enlace parcela–edificio. | Uso interno transformado sin redistribuir datos originales. Referencia catastral seudonimizada con hash y sal secreta (RGPD). |
| **Notariado, Registradores y MIVAU** | Verdad de precio: agregados de cierre (€/m²) por zona y trimestre. | Base exclusiva para el ancla de nivel de precio y la validación fuera de muestra. |
| **INE – IPV** | Actualización temporal de cierres a fecha actual y baseline de comparación. | Serie trimestral oficial. |
| **INE – Atlas de Renta** | Renta media por sección censal. | Variable automática de entorno. |
| **OpenStreetMap (OSM)** | Tiempos a pie y en coche a transporte y servicios (comprimidos por PCA). | Licencia ODbL con atribución. |
| **Mapas de ruido (Ayuntamiento)** | Nivel de ruido en dB por vivienda. | Externalidad negativa automática. |
| **`idealista18`** | Exclusivamente prototipado y desarrollo inicial. | Licencia ODbL (uso científico/educativo); son precios de oferta de 2018, nunca producción ni verdad de cierre. |

- **Prohibiciones explícitas:** nada de scraping sin licencia; no entrenar con salidas de AVM de terceros (PriceHubble, Casafari, Tinsa Digital); cualquier benchmark comercial requiere autorización escrita previa y prohíbe sondeos en cuadrícula.
- **Privacidad (RGPD):** las direcciones exactas no entran en logs ni artefactos de modelo; las referencias catastrales se almacenan seudonimizadas en la tabla de modelado; base jurídica y plazos pendientes de validación con el DPD.

---

## 3. Procedencia de entradas y formulario núcleo

Cada dato de entrada conserva su nivel de procedencia heredado del flujo CRM:

- **`verificado`:** precargado automáticamente desde Catastro INSPIRE, INE, Notariado, OSM o mapas oficiales (o documento oficial validado).
- **`declarado`:** confirmado o introducido por el agente tras la visita.
- **`inferido`:** extraído por IA a partir de audio, texto libre o fotografías (`valuation_extractions` en estado `pending_review`). **Regla:** un campo `inferido` sin confirmar no consolida la ficha ni bloquea la intervención humana; debe ser aprobado o descartado por el agente.

### Reglas de obligatoriedad e imputación

| Condición | Comportamiento del sistema |
| :--- | :--- |
| Falta municipio/ubicación geocodificable o superficie construida | No se emite valoración automática fiable (`confianza = 0` / bloqueada para cliente). |
| Faltan variables secundarias | Imputación jerárquica por mediana del edificio → mediana del barrio → mediana global (ajustada solo en *train* por fold), generando bandera `variable_faltante = 1` y sumando al contador de imputaciones. |
| Exceso de variables imputadas o pocos cierres en la zona | Se aplican topes automáticos a la nota de confianza `0–7` (configurables en `config.yaml`). |

### Diccionario de variables (4 bloques)

Cada variable tiene dos etiquetas operativas: **Capa** (`automática` vs. `formulario`) y **Nivel de modelo** (`base + GBM` vs. `solo GBM`). El formulario obligatorio del agente se limita a **9 variables de alto impacto** no disponibles en fuentes abiertas (más confirmación de tipología y certificado energético).

#### Bloque 1 — Intrínsecas y catastrales

| Variable | Transformación clave | Capa | Nivel |
| :--- | :--- | :--- | :--- |
| Superficie construida (vivienda, sin comunes) | `log(m²)` | Automática | Base + GBM |
| Superficie útil | `log(m²)` + bandera faltante | Formulario (opcional) | Solo GBM |
| Tipología exacta (piso, ático, dúplex, bajo, estudio, unifamiliar) | Dummies / categórica nativa | Automática + confirmación | Base + GBM |
| Estado de conservación / reforma (5 niveles: obra nueva a reforma integral) | Dummies / ordinal `0–4` (separado del año de construcción) | **Formulario (núcleo)** | Base + GBM |
| Año de construcción | Tramos `<1936`, `1936–1979`, `1980–2006`, `>2006` (base); edad continua (GBM) | Automática | Base + GBM |
| Año de reforma | Años desde reforma + bandera faltante | Formulario (opcional) | Solo GBM |
| Planta y Ascensor (`planta × ascensor`) | `planta`<sub>`con_ascensor`</sub> `= planta · ascensor`<br>`planta`<sub>`sin_ascensor`</sub> `= planta · (1 − ascensor)` | **Formulario (núcleo)** | Base + GBM |
| Altura relativa | `planta / plantas`<sub>`totales`</sub> + banderas `es_bajo` y `es_ultima_planta` | Automática (derivada) | Solo GBM |
| Exterior / interior (calle, patio de manzana, patio de luces) | Dummies / categórica nativa | **Formulario (núcleo)** | Base + GBM |
| Espacio exterior privativo (balcón `<6 m²`, terraza `>10 m²`, solárium, jardín) | Terraza sí/no (base); ratio `m²`<sub>`exterior`</sub> `/ m²`<sub>`vivienda`</sub> (GBM) | **Formulario (núcleo)** | Base + GBM |
| Distribución (habitaciones y baños) | `m² / habitación` y `baños / habitación` | Formulario (opcional) | Solo GBM |
| Calidad constructiva catastral | Ordinal | Automática | Base + GBM |

#### Bloque 2 — Edificio, extras y eficiencia

| Variable | Transformación clave | Capa | Nivel |
| :--- | :--- | :--- | :--- |
| Plaza de garaje | Binaria `0/1` con interacción por submercado | **Formulario (núcleo)** | Solo GBM |
| Certificado energético (CEE) | Ordinal `A = 6` … `G = 0` | Automática + confirmación | Solo GBM |
| Orientación (sur / doble orientación) | Binarias `0/1` | Formulario (opcional) | Solo GBM |
| ITE del edificio (favorable, desfavorable, pendiente) | Dummies | Formulario (opcional) | Solo GBM |
| Accesibilidad a cota cero y Trastero | Binarias `0/1` | Formulario (opcional) | Solo GBM |
| Zonas comunes (piscina, portería, zona verde) | Índice compuesto entero | Formulario (opcional) | Solo GBM |
| Gastos de comunidad e IBI | `€/m²·mes` y `€/m²·año` + bandera faltante | Formulario (opcional) | Solo GBM |

#### Bloque 3 — Espaciales y entorno

| Variable | Transformación clave | Capa | Nivel |
| :--- | :--- | :--- | :--- |
| Barrio (73 barrios de Barcelona) | Efectos fijos (base); categórica (GBM) | Automática | Base + GBM |
| Submercado automático | Agrupación por comportamiento de precio (ajustada por fold) | Automática | Solo GBM |
| Nivel de precio local (*lag* espacial) | Media ponderada por distancia de `k` vecinos (ajustada por fold) | Automática | Solo GBM |
| Renta media de sección censal | `log(renta)` | Automática | Solo GBM |
| Accesibilidad a pie y en coche (OSM) | Componentes principales (PCA ajustado por fold) | Automática | Solo GBM |
| Ruido ambiental | Nivel continuo en dB | Automática | Solo GBM |
| Vistas / proximidad a mar o parque | Binarias `0/1` | **Formulario (núcleo)** | Solo GBM |

#### Bloque 4 — Temporales, mercado y legal

| Variable | Transformación clave | Capa | Nivel |
| :--- | :--- | :--- | :--- |
| Ajuste temporal IPV | Actualización de precios de cierre a trimestre actual | Automática | Ajuste objetivo |
| Liquidez de zona | `log(1 + n`<sub>`operaciones`</sub>`)` | Automática | Solo GBM |
| Situación posesoria (libre, alquilado, okupado, nuda propiedad) | Bandera de exclusión + módulo descuento aparte | **Formulario (núcleo)** | Excluida base |
| Protección oficial (VPO) | Bandera de exclusión + módulo precio tasado | **Formulario (núcleo)** | Excluida base |

---

## 4. Arquitectura matemática y mecánica de pesos

El sistema abandona los deltas fijos a mano y calcula los pesos de forma estadística en **dos niveles**, con variable objetivo `log(€/m²)`.

### Estrategia frente a la ausencia de cierres individuales (descomposición en dos capas)

Mientras no se disponga de transacciones individuales escrituradas, entrenar variables intrínsecas directamente contra la media de cierre del barrio produce varianza cero intrabarrio (las variables físicas no son identificables). Por ello, el modelo se formula en logaritmos separando nivel y diferencial:

> `log(€/m²`<sub>`i,b,t`</sub>`) = log(Base`<sub>`b,t`</sub>`) + Δ`<sub>`intrínseco`</sub>`(X`<sub>`i`</sub>`)`
> - `log(Base`<sub>`b,t`</sub>`)`: ancla de cierre real + IPV
> - `Δ`<sub>`intrínseco`</sub>`(X`<sub>`i`</sub>`)`: desviación relativa frente a mediana del barrio

- **Ancla de nivel (`Base`<sub>`b,t`</sub>):** procede exclusivamente de agregados de cierre oficiales actualizados con el IPV, evitando arrastrar el sesgo de sobreprecio de los portales.
- **Diferencial intrínseco (`Δ`<sub>`intrínseco`</sub>):** hasta firmar acceso a cierres individuales (Notariado/Registradores) o acumular cierres propios suficientes, se estima sobre microdatos con licencia centrados por barrio y trimestre (`y*`<sub>`i`</sub> `= log(p`<sub>`i`</sub>`) − mediana`<sub>`b,t`</sub>`(log p)`), capturando primas y descuentos relativos de reforma, planta/ascensor, exterior o terraza.
- **Contraste con comparables del CRM (capa comercial):** el agente puede seguir adjuntando testigos seleccionados en la ficha para el dossier del cliente (identificando si son `closing` o `asking`), que sirven como evidencia visual y control de coherencia junto al AVM, pero no sobrescriben los parámetros internos del modelo.

### Nivel 1 y Nivel 2 de modelado

1. **Modelo base hedónico (referencia interpretable):** regresión OLS en `statsmodels` con errores robustos y efectos fijos de barrio sobre el núcleo parsimonioso de variables. Cada coeficiente `β` se lee directamente como variación porcentual aproximada `100 · (e`<sup>`β`</sup> `− 1)%`. MGWR queda como extensión opcional cuando exista granularidad suficiente.
2. **Modelo principal (Gradient Boosting):** LightGBM (por defecto) o CatBoost con función de pérdida **Huber** sobre `log(€/m²)`, optimizando hiperparámetros para maximizar el porcentaje de valoraciones dentro de `±10%` (desempate por `±20%`) en validación espacial.

### Explicabilidad comercial (SHAP en euros)

TreeSHAP descompone la predicción logarítmica de cada inmueble en un valor base y aportaciones `φ`<sub>`i`</sub> que suman la desviación total `S = ∑ φ`<sub>`i`</sub>`. Con `V`<sub>`0`</sub> `= m² · exp(base)` y `V = m² · exp(base + S)`:

- Si `|S| ≥ 10`<sup>`−6`</sup>: `aportación`<sub>`i`</sub> `= (φ`<sub>`i`</sub> `/ S) · (V − V`<sub>`0`</sub>`)`.
- Si `|S| < 10`<sup>`−6`</sup> (guarda numérica cuando el inmueble está prácticamente en la media): `aportación`<sub>`i`</sub> `= m² · exp(base) · φ`<sub>`i`</sub>.

Las aportaciones se presentan agrupadas en categorías legibles para negocio (ubicación, superficie, planta y ascensor, estado de conservación, espacio exterior, antigüedad, accesibilidad y garaje).

---

## 5. Rango conformal, FSD y escala de confianza

En lugar de percentiles P25–P75 sobre testigos manuales, la incertidumbre se estima mediante **Regresión Cuantílica Conformalizada (CQR)** con ponderación espacial:

- Se entrenan dos regresores cuantílicos para los percentiles **P5** y **P95** de `log(€/m²)` con cobertura objetivo del **90 %**.
- Sobre el conjunto de calibración se calcula la puntuación `s = max(q`<sub>`P5`</sub> `− y, y − q`<sub>`P95`</sub>`)` y se aplica un ajuste ponderado espacialmente con núcleo gaussiano (pesan más los residuos de barrios cercanos).
- Se verifica consistencia de límites (`rango_inferior <= valor <= rango_superior`).
- **FSD (desviación típica del error relativo esperado):** `FSD ≈ [log(superior) − log(inferior)] / (2 · z`<sub>`90%`</sub>`)`.

### Mapeo provisional FSD → Confianza `0–7` y reglas de negocio CRM

Los umbrales se configuran en `config.yaml` (pendientes de calibración final con datos reales) y se mapean al flujo de validación del CRM:

| Nota AVM (`0–7`) | FSD provisional | Equivalencia operativa en CRM |
| :---: | :---: | :--- |
| **7** | `≤ 5%` | Alta confianza — validable por agente (`internal_validated`) |
| **6** | `≤ 8%` | Alta confianza — validable por agente |
| **5** | `≤ 11%` | Confianza media-alta — validable por agente |
| **4** | `≤ 14%` | Confianza media — revisar imputaciones y comparables |
| **3** | `≤ 17%` | Confianza media-baja — revisar con cautela comercial |
| **2** | `≤ 20%` | Baja confianza — requiere revisión (`pending_supervisor`) |
| **1** | `≤ 25%` | Muy baja confianza — requiere revisión (`pending_supervisor`) |
| **0** | `> 25%` | No apto comercialmente — bloqueado (`pending_supervisor`, sin PDF estándar) |

- **Topes automáticos:** si el barrio tiene menos cierres que el mínimo configurado o la vivienda supera el máximo de variables imputadas, la nota se recorta automáticamente al techo definido en `config.yaml`.

---

## 6. Semáforo comercial (precio del propietario)

Se calcula en la capa CRM únicamente cuando existe valoración válida (`confianza_0_7 >= 2` y sin bloqueo posesorio sin resolver) y el propietario declara `owner_asking_price_cents`:

| Color | Desviación de `owner_asking_price` frente a `valor` | Lectura comercial |
| :--- | :--- | :--- |
| `green` | Dentro de `±5%` | Precio alineado con mercado. |
| `amber` | Entre `+5%` y `+15%` por encima | Precio tensionado; margen de negociación ajustado. |
| `red` | Más de `+15%` por encima | En PDF: a este precio de salida no se esperan visitas. |

Un precio pedido por debajo del valor estimado nunca se marca en rojo; se documenta en `limitations` como palanca de velocidad de venta.

---

## 7. Validación, paso a producción y MLOps

El servicio Python (`POST /valorar`) solo promociona una versión de modelo a producción si supera los siguientes criterios sobre **precios de cierre** (nunca oferta) con validación cruzada espacial (**GroupKFold** por barrio/CP) y temporal (entrenar pasado, evaluar trimestres recientes), ajustando toda transformación con estado estrictamente dentro del *train* de cada fold:

1. **Superar Baseline 1:** batir al modelo base hedónico en validación espacial y temporal.
2. **Superar Baseline 2:** batir a una revalorización simple del barrio mediante el IPV del INE.
3. **Precisión objetivo:** superar el umbral mínimo dentro de `±20%`, con meta en que la mayoría de valoraciones caigan dentro de `±10%`.
4. **Calibración de incertidumbre:** cobertura empírica del rango cercana al 90 % y mejora monotónica de la precisión al filtrar por notas de confianza más altas (requisito EAA).
5. **Mantenimiento (MLOps):** informes trimestrales fuera de muestra, monitorización de deriva, carga de datos al menos trimestral y capacidad de valoración retroactiva de 5 años.

---

## 8. Contrato API, revisión humana y PDF de cliente

### Respuesta de `POST /valorar` (FastAPI / Pydantic → Zod CRM)

```json
{
  "valor": 385000,
  "rango_inferior": 355000,
  "rango_superior": 415000,
  "confianza_0_7": 5,
  "fsd": 0.095,
  "explicacion_shap": {
    "valor_referencia": 400000,
    "aportaciones": [
      { "variable": "planta_y_ascensor", "euros": 30000 },
      { "variable": "estado_conservacion", "euros": -40000 },
      { "variable": "certificado_energetico", "euros": -5000 }
    ]
  },
  "avisos": [],
  "version_modelo": "avm-bcn-v1.0.0",
  "aviso_legal": "Valoración automatizada para uso interno, comercial y de carteras. No es una tasación homologada ni apta para Anejo 9 del Banco de España."
}
```

*(Valores numéricos meramente ilustrativos de esquema).*

### Flujo de revisión humana y reglas del PDF

1. El motor genera el borrador y los campos extraídos de audio/notas/fotos entran en `valuation_extractions` con `pending_review`.
2. El agente revisa y consolida los campos `inferido` → `declarado` y comprueba la coherencia comercial de los bloques SHAP y del rango.
3. **Estados de ficha:** `draft` → `internal_validated` (caso normal con `confianza_0_7 >= 3` y situación libre). Si `confianza_0_7 <= 2`, existe aviso de exclusión (`alquilado`, `okupado`, `VPO`), o el agente aplica un ajuste comercial manual sobre la estimación del AVM, la ficha pasa obligatoriamente a `pending_supervisor` con `rationale` obligatorio.
4. **Generación de PDF:** bloqueada con HTTP `403` salvo que `status === internal_validated`. El payload se valida estrictamente contra `ExternalValuationPdfSchema`.
   - **Incluye:** ficha del inmueble con procedencia, valor estimado, rango inferior/superior, nota de confianza y lectura comercial, explicación simplificada por factores (SHAP agrupado), testigos de apoyo por zona (sin dirección exacta ni URL ajena), semáforo, argumentos, limitaciones, bloque de servicios de la agencia y aviso legal obligatorio.
   - **Excluye siempre:** `narrative_draft`, `internal_risk_notes`, `negotiation_margin_notes`, `source_quote`, extracciones sin confirmar, datos crudos de Catastro, honorarios y datos de terceros.

---

## 9. Historial de cambios

| Fecha | Versión | Cambio |
| :--- | :---: | :--- |
| 2026-11-17 | 0.1 | Hipótesis inicial tras entrevista del 4 de noviembre (mediana de 3 comparables, deltas manuales `±25%`, `descuento_oferta_a_cierre` nulo). |
| 2026-11-17 | 0.2 | Se introducen estados `draft` \| `internal_validated`, bloqueo 403 en PDF y `ExternalValuationPdfSchema`. |
| 2026-11-19 | 2.0 | Sustitución del motor heurístico por arquitectura AVM v1 Barcelona (Catastro INSPIRE + cierres agregados + IPV + Hedónico OLS + LightGBM/CatBoost Huber + SHAP en euros + CQR P5–P95 + FSD/Confianza `0–7`), incorporación de la descomposición en dos capas ante falta de cierres individuales y mapeo de confianza `0–7` a `pending_supervisor`. |
