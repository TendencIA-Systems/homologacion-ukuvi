# Extraction Phase

<cite>
**Referenced Files in This Document**   
- [ana-query-de-extraccion.sql](file://src/insurers/ana/ana-query-de-extraccion.sql)
- [atlas-query-de-extraccion.sql](file://src/insurers/atlas/atlas-query-de-extraccion.sql)
- [axa-query-de-extraccion.sql](file://src/insurers/axa/axa-query-de-extraccion.sql)
- [bx-query-de-extraccion.sql](file://src/insurers/bx/bx-query-de-extraccion.sql)
- [chubb-query-de-extraccion.sql](file://src/insurers/chubb/chubb-query-de-extraccion.sql)
- [elpotosi-query-de-extraccion.sql](file://src/insurers/elpotosi/elpotosi-query-de-extraccion.sql)
- [gnp-query-de-extraccion.sql](file://src/insurers/gnp/gnp-query-de-extraccion.sql)
- [hdi-query-de-extraccion.sql](file://src/insurers/hdi/hdi-query-de-extraccion.sql)
- [mapfre-query-de-extraccion.sql](file://src/insurers/mapfre/mapfre-query-de-extraccion.sql)
- [qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql)
- [zurich-query-de-extraccion.sql](file://src/insurers/zurich/zurich-query-de-extraccion.sql)
- [instrucciones.md](file://instrucciones.md)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Extraction Query Structure and Purpose](#extraction-query-structure-and-purpose)
3. [Common Patterns Across Insurers](#common-patterns-across-insurers)
4. [Handling Source Schema Variations](#handling-source-schema-variations)
5. [JOIN Strategies and Filtering Logic](#join-strategies-and-filtering-logic)
6. [Data Type Casting and Normalization](#data-type-casting-and-normalization)
7. [Alignment with Completeness and Traceability Requirements](#alignment-with-completeness-and-traceability-requirements)
8. [Error Handling, Timeouts, and Performance Optimization](#error-handling-timeouts-and-performance-optimization)
9. [Guidelines for Adding New Extraction Queries](#guidelines-for-adding-new-extraction-queries)
10. [Conclusion](#conclusion)

## Introduction
The data extraction phase is a foundational step in the homologacion-ukuvi system, responsible for retrieving raw vehicle catalog data from multiple insurer databases. This document details how insurer-specific SQL queries are structured to extract relevant data, ensuring alignment with the canonical model defined in `instrucciones.md`. The extraction process emphasizes completeness, traceability, and performance, while accommodating variations in source schemas. Each query is tailored to its respective insurer's database structure, yet follows common patterns to maintain consistency across the system.

**Section sources**
- [instrucciones.md](file://instrucciones.md#L1-L279)

## Extraction Query Structure and Purpose
Each insurer's extraction query is designed to retrieve a standardized set of fields that map directly to the canonical model in `catalogo_homologado`. The primary fields extracted include `origen_aseguradora`, `id_original`, `marca`, `modelo`, `anio`, `version_original`, `transmision`, and `activo`. These fields are selected to ensure that all necessary information for homogenization is captured during extraction. The purpose of each query is to transform insurer-specific data into a uniform format that can be processed by the n8n orchestration layer and ultimately stored in the canonical table.

**Section sources**
- [ana-query-de-extraccion.sql](file://src/insurers/ana/ana-query-de-extraccion.sql#L1-L27)
- [atlas-query-de-extraccion.sql](file://src/insurers/atlas/atlas-query-de-extraccion.sql#L1-L33)
- [axa-query-de-extraccion.sql](file://src/insurers/axa/axa-query-de-extraccion.sql#L1-L26)

## Common Patterns Across Insurers
Despite differences in source schemas, several common patterns emerge across the extraction queries. First, all queries include a constant `origen_aseguradora` field to identify the source insurer. Second, they apply filtering logic to include only records with `anio` between 2000 and 2030, ensuring data relevance. Third, most queries use `INNER JOIN` operations to link related tables, such as marcas, modelos, and versiones, based on shared keys. Finally, all queries include a `transmision` field derived from source-specific codes, which are mapped to standardized values (`AUTO`, `MANUAL`, or `NULL`).

**Section sources**
- [ana-query-de-extraccion.sql](file://src/insurers/ana/ana-query-de-extraccion.sql#L1-L27)
- [bx-query-de-extraccion.sql](file://src/insurers/bx/bx-query-de-extraccion.sql#L1-L26)
- [chubb-query-de-extraccion.sql](file://src/insurers/chubb/chubb-query-de-extraccion.sql#L1-L25)

## Handling Source Schema Variations
Source schema variations are addressed through tailored JOIN conditions and field mappings. For example, Atlas and El Potosí require multi-column JOINs that include `Anio`, `Categoria`, and `Liga` to ensure accurate record linkage. AXA uses dual-year fields (`AnoInicial` and `AnoFinal`), with the extraction query selecting `AnoInicial` as the `anio` value. Chubb's schema is atypical, with the `NTipo` table containing the actual model information, necessitating a distinct JOIN strategy. These variations are handled within each query to ensure consistent output despite differing source structures.

**Section sources**
- [atlas-query-de-extraccion.sql](file://src/insurers/atlas/atlas-query-de-extraccion.sql#L1-L33)
- [axa-query-de-extraccion.sql](file://src/insurers/axa/axa-query-de-extraccion.sql#L1-L26)
- [chubb-query-de-extraccion.sql](file://src/insurers/chubb/chubb-query-de-extraccion.sql#L1-L25)

## JOIN Strategies and Filtering Logic
JOIN strategies are critical for accurately linking related data across tables. Most queries use `INNER JOIN` to connect marca, modelo, and version tables based on primary and foreign keys. For insurers like Atlas and El Potosí, additional filtering criteria are included in the JOIN conditions to account for composite keys involving `Anio`, `Categoria`, and `Liga`. Filtering logic is applied in the `WHERE` clause to exclude inactive records (where applicable) and limit results to valid years. This ensures that only relevant, active data is extracted, improving efficiency and data quality.

**Section sources**
- [atlas-query-de-extraccion.sql](file://src/insurers/atlas/atlas-query-de-extraccion.sql#L1-L33)
- [elpotosi-query-de-extraccion.sql](file://src/insurers/elpotosi/elpotosi-query-de-extraccion.sql#L1-L29)
- [hdi-query-de-extraccion.sql](file://src/insurers/hdi/hdi-query-de-extraccion.sql#L1-L25)

## Data Type Casting and Normalization
Data type casting is used to ensure consistency in the extracted data. For example, `id_original` values are cast to `VARCHAR(50)` to standardize their format across insurers. String fields like `marca` and `modelo` are normalized using `UPPER`, `LTRIM`, and `RTRIM` functions to remove leading/trailing spaces and ensure uniform case. The `transmision` field is derived using `CASE` statements that map source-specific codes (e.g., 1=MANUAL, 2=AUTO) to standardized values. These transformations are applied during extraction to minimize processing overhead in subsequent stages.

**Section sources**
- [atlas-query-de-extraccion.sql](file://src/insurers/atlas/atlas-query-de-extraccion.sql#L1-L33)
- [bx-query-de-extraccion.sql](file://src/insurers/bx/bx-query-de-extraccion.sql#L1-L26)
- [elpotosi-query-de-extraccion.sql](file://src/insurers/elpotosi/elpotosi-query-de-extraccion.sql#L1-L29)

## Alignment with Completeness and Traceability Requirements
The extraction queries are designed to meet the completeness and traceability requirements outlined in `instrucciones.md`. Each query ensures that 100% of active records from the source databases are represented in the canonical model, with `id_original` and `version_original` preserving traceability to the source. The inclusion of `origen_aseguradora` allows for insurer-level tracking, while the `activo` field supports the system's active/inactive logic. By extracting all necessary fields during this phase, the system ensures that no data is lost during homogenization.

**Section sources**
- [instrucciones.md](file://instrucciones.md#L1-L279)
- [ana-query-de-extraccion.sql](file://src/insurers/ana/ana-query-de-extraccion.sql#L1-L27)
- [chubb-query-de-extraccion.sql](file://src/insurers/chubb/chubb-query-de-extraccion.sql#L1-L25)

## Error Handling, Timeouts, and Performance Optimization
Error handling during extraction is primarily managed through robust SQL practices, such as using `COALESCE` to handle potential NULL values in `version_original` (e.g., El Potosí). Timeouts are mitigated by limiting the data range to years between 2000 and 2030, reducing query execution time. Performance is further optimized by leveraging indexing on source systems, particularly on fields used in JOIN and WHERE conditions (e.g., `Anio`, `Activo`, `IdMarca`). These optimizations ensure that extraction queries execute efficiently, even with large datasets.

**Section sources**
- [elpotosi-query-de-extraccion.sql](file://src/insurers/elpotosi/elpotosi-query-de-extraccion.sql#L1-L29)
- [gnp-query-de-extraccion.sql](file://src/insurers/gnp/gnp-query-de-extraccion.sql#L1-L25)
- [instrucciones.md](file://instrucciones.md#L1-L279)

## Guidelines for Adding New Extraction Queries
When onboarding a new insurer, the extraction query should follow the established patterns while accommodating the insurer's unique schema. Key steps include:
1. Identify the source tables and fields that map to the canonical model.
2. Define JOIN conditions based on primary and foreign keys, including any composite keys.
3. Apply filtering logic to include only active records and valid years.
4. Use data type casting and string normalization to ensure consistency.
5. Map source-specific codes (e.g., transmision) to standardized values using `CASE` statements.
6. Include `origen_aseguradora` as a constant field to identify the source.
7. Test the query with a subset of data to verify accuracy and performance.

**Section sources**
- [instrucciones.md](file://instrucciones.md#L1-L279)
- [qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql#L1-L25)
- [zurich-query-de-extraccion.sql](file://src/insurers/zurich/zurich-query-de-extraccion.sql#L1-L25)

## Conclusion
The data extraction phase is a critical component of the homologacion-ukuvi system, enabling the consolidation of vehicle catalog data from diverse insurer databases into a unified canonical model. By adhering to common patterns while addressing source schema variations, the extraction queries ensure completeness, traceability, and performance. The use of standardized JOIN strategies, filtering logic, and data type casting facilitates seamless integration with subsequent processing stages. As new insurers are onboarded, these guidelines provide a clear framework for developing robust and efficient extraction queries.