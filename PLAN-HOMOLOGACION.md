# Plan de Homologación Vehicular: Estrategia n8n + Supabase

## Objetivo

Unificar los catálogos vehiculares de todas las aseguradoras en una tabla maestra homologada, usando un flujo eficiente y escalable basado en n8n para la normalización y Supabase para la persistencia y comparación inteligente.

---

## Contexto General

Este documento describe una estrategia de homologación vehicular pensada para proyectos de integración de datos, ETL, y sistemas de catalogación en el sector asegurador. Puede ser adaptado para otros dominios donde se requiera deduplicación, normalización y persistencia inteligente de registros heterogéneos.

**Recomendado para:**

- Equipos de ingeniería de datos, analistas, desarrolladores de ETL, arquitectos de soluciones, y AI Agents que requieran instrucciones claras y transferibles.
- Proyectos que usen n8n, Supabase, PostgreSQL, o sistemas similares.

**Puntos clave:**

- El plan es modular y puede ser adaptado a otros flujos de datos.
- Los umbrales y funciones de similitud pueden ajustarse según el dominio.
- La lógica de limpieza y matching puede ser extendida para otros tipos de entidades (productos, clientes, etc.).

---

---

## 1. Extracción y Normalización en n8n

### a) Extracción

- Ejecutar los queries de extracción para cada aseguradora.
- Obtener los CSVs completos de cada origen.

**Notas para otros proyectos:**

- Los queries pueden ser adaptados para cualquier fuente de datos (APIs, bases SQL, archivos planos).
- El proceso de extracción debe garantizar la obtención de todos los campos relevantes para el matching posterior.

### b) Limpieza y Normalización

- Limpiar y estandarizar los campos principales: `marca`, `modelo`, `anio`, `transmision`.
- Limpiar el campo `version` eliminando specs irrelevantes (A/A, E/E, PIEL, B/A, etc.) y normalizando el string.
- Calcular el `hash_comercial` usando los 4 parámetros principales: `marca`, `modelo`, `anio`, `transmision`.
- Validar que cada registro tenga los 4 main specs y una versión limpia.
- Preparar el objeto para enviar a Supabase: `{ hash_comercial, version, aseguradora }`.

**Recomendaciones para AI Agents y desarrolladores:**

- Documentar la función de limpieza de versión y mantener una lista de specs irrelevantes actualizable.
- El hash comercial debe ser reproducible y estable; usar funciones hash estándar (ej. SHA-256) y normalizar los campos antes de concatenar.
- Validar y loggear registros incompletos para análisis posterior.

---

## 2. Subflujo y Envío a Supabase

- Enviar los datos normalizados al subflujo que llama la función RPC de Supabase.
- Mandar solo los campos necesarios: `hash_comercial`, `version`, y datos de aseguradora.

**Notas para integración:**

- El subflujo puede ser implementado en cualquier orquestador (n8n, Airflow, etc.).
- El payload debe ser compacto y contener solo los datos necesarios para la homologación.

---

## 3. Lógica de Homologación en Supabase (Función RPC)

### a) Búsqueda de Coincidencias

- Buscar en la tabla maestra por `hash_comercial`.
- Si hay más de un match, usar fuzzy matching (`pg_trgm` o `fuzzystrmatch`) sobre el campo `version`.
- Definir umbral de similitud (ejemplo: `similarity >= 0.85` para match seguro).

**Detalles técnicos y transferibles:**

- Activar extensiones necesarias en PostgreSQL: `CREATE EXTENSION IF NOT EXISTS pg_trgm;` y/o `fuzzystrmatch`.
- Crear índices sobre los campos usados en búsquedas (`hash_comercial`, `version`).
- El umbral de similitud puede ser ajustado según la calidad de los datos; documentar los valores usados y su justificación.

### b) Decisión de Acción

- Si el match es seguro, actualizar la columna `disponibilidad` agregando la nueva aseguradora.
- Si no hay match seguro, crear una nueva entrada en la tabla maestra.
- Actualizar `confianza_score` y `fecha_actualizacion` según corresponda.

**Recomendaciones para lógica de actualización:**

- La columna `disponibilidad` debe ser un JSONB que permita agregar aseguradoras sin sobrescribir las existentes.
- El score de confianza puede ser el valor de similitud del mejor match.
- Loggear todas las acciones (inserciones, actualizaciones, matches dudosos) en una tabla de auditoría.

---

## 4. Recomendaciones y Detalles Técnicos

- Realizar la limpieza de la versión en n8n para asegurar datos comparables.
- Ajustar el umbral de similitud tras pruebas reales.
- Documentar y loggear los matches dudosos para revisión manual.
- Mantener índices sobre `hash_comercial` y considerar índices trigram para performance.

**Transferencia a otros proyectos:**

- Mantener la lógica de limpieza y matching desacoplada del resto del sistema para facilitar su reutilización.
- Documentar el proceso de homologación y los criterios de decisión para facilitar la colaboración entre equipos y agentes.

---

## 5. Ejemplo de Flujo

1. n8n extrae y normaliza los datos, calcula el hash y limpia la versión.
2. n8n envía el registro a Supabase.
3. Supabase busca por hash comercial y compara versiones con fuzzy matching.
4. Si hay match, actualiza disponibilidad; si no, inserta nuevo registro.
5. Se loggean las acciones y se actualizan métricas.

**Ejemplo transferible:**
Este flujo puede ser adaptado para homologar productos, clientes, proveedores, etc. Solo se requiere definir los campos principales y la lógica de similitud.

---

## 6. Próximos Pasos

- Implementar nodo de código de cada aseguradora en n8n para el cálculo del hash_comercial y la extracción de la versión limpia, más la deduplicación por versión más adelante.
- Implementar la función de limpieza de versión en n8n.
- Definir y probar el umbral de similitud en Supabase.
- Desarrollar la función RPC con lógica de búsqueda, fuzzy matching y actualización/inserción.
- Realizar pruebas con los catálogos de HDI y Qualitas como base.
- Documentar el proceso y ajustar según resultados.

**Siguientes pasos para otros equipos/proyectos:**

- Adaptar la función de limpieza y el cálculo de hash a los campos relevantes de su dominio.
- Probar el flujo con datos reales y ajustar los umbrales de similitud.
- Documentar todo el proceso y compartirlo con otros equipos para retroalimentación y mejora continua.

---

**Este plan busca maximizar la eficiencia y la calidad de la homologación vehicular, aprovechando la potencia de n8n para la normalización y la flexibilidad de Supabase para la persistencia y comparación inteligente.**

---

## Referencias y Recursos

- [n8n Documentation](https://docs.n8n.io/)
- [Supabase Documentation](https://supabase.com/docs)
- [PostgreSQL pg_trgm](https://www.postgresql.org/docs/current/pgtrgm.html)
- [PostgreSQL fuzzystrmatch](https://www.postgresql.org/docs/current/fuzzystrmatch.html)
- [SHA-256 Hashing in JS](https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/digest)

---

**Este documento puede ser usado como plantilla y referencia para homologación de datos en cualquier proyecto que requiera deduplicación, normalización y persistencia inteligente.**
