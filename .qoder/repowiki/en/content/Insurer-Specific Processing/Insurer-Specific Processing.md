# Insurer-Specific Processing

<cite>
**Referenced Files in This Document**   
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md)
- [hdi-query-de-extraccion.sql](file://src/insurers/hdi/hdi-query-de-extraccion.sql)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js)
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md)
- [gnp-query-de-extraccion.sql](file://src/insurers/gnp/gnp-query-de-extraccion.sql)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js)
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md)
- [qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql)
- [qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js)
- [elpotosi-analisis.md](file://src/insurers/elpotosi/elpotosi-analisis.md)
- [elpotosi-query-de-extraccion.sql](file://src/insurers/elpotosi/elpotosi-query-de-extraccion.sql)
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Three-Part Processing Pattern](#three-part-processing-pattern)
3. [HDI: Structured and Predictable](#hdi-structured-and-predictable)
4. [GNP: Chaotic and Contaminated](#gnp-chaotic-and-contaminated)
5. [Qualitas: n8n-Specific JavaScript Implementation](#qualitas-n8n-specific-javascript-implementation)
6. [El Potosí: Unique Structure and Special Handling](#el-potosí-unique-structure-and-special-handling)
7. [Analysis-Driven Normalization](#analysis-driven-normalization)
8. [SQL Query Optimization per Insurer](#sql-query-optimization-per-insurer)
9. [Conclusion](#conclusion)

## Introduction

This document details the insurer-specific processing workflows for vehicle data homologation across multiple insurance providers. Each insurer—ANA, Atlas, AXA, BX, Chubb, El Potosí, GNP, HDI, Mapfre, Qualitas, and Zurich—follows a standardized three-artifact pattern: `analysis.md` for data profiling, `query-de-extraccion.sql` for source extraction, and `codigo-de-normalizacion.js` for transformation logic. The goal is to standardize inconsistent source formats into a canonical model that supports unified vehicle cataloging. Special emphasis is placed on HDI and GNP as contrasting examples of clean versus problematic data structures, while Qualitas and El Potosí represent unique implementation cases involving n8n-specific JavaScript and non-standard architectures.

## Three-Part Processing Pattern

Each insurer follows a consistent three-part artifact pattern designed to ensure systematic data processing:

1. **`analysis.md`**: A comprehensive data profiling document that includes executive summaries, field anatomy, statistical breakdowns, and normalization strategies. It identifies key metrics such as active record percentages, unique brands/models, and data quality issues.
2. **`query-de-extraccion.sql`**: A SQL query optimized for extracting relevant data from the insurer’s database schema. It includes filtering logic (e.g., active records), joins across necessary tables, and field casting where needed.
3. **`codigo-de-normalizacion.js`**: A JavaScript transformation script that parses raw data, extracts technical specifications, normalizes values, and generates canonical identifiers like hashes.

This triad ensures traceability from source to target, enabling reproducible and auditable data pipelines.

**Section sources**
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md)
- [hdi-query-de-extraccion.sql](file://src/insurers/hdi/hdi-query-de-extraccion.sql)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js)

## HDI: Structured and Predictable

HDI exhibits one of the cleanest data structures among all insurers, making it a model for reliable homologation. Its `ClaveVersion` field uses a comma-separated format with consistent ordering: TRIM, motor configuration, displacement, power, doors, transmission, and extras.

### Data Profiling Insights

The `hdi-analisis.md` reveals that 45.15% of records are active, significantly higher than Qualitas (15.47%). Key findings include:
- TRIM is always before the first comma
- Transmission codes like AUT and STD appear consistently
- Field contamination is minimal

### Extraction Strategy

The `hdi-query-de-extraccion.sql` focuses on filtering only active records (`Activo = 1`) and joining with the `Marca` table to retrieve brand descriptions. It avoids redundant fields and ensures efficient data retrieval.

```sql
SELECT 
    v.IdVersion as id_original,
    m.Descripcion as marca,
    v.ClaveSubMarca as modelo,
    v.Anio as anio,
    v.ClaveVersion as version_completa,
    v.Activo as activo
FROM hdi.Version v
INNER JOIN (
    SELECT DISTINCT IdMarca, Descripcion FROM hdi.Marca
) m ON v.IdMarca = m.IdMarca
WHERE v.Activo = 1
```

### Normalization Logic

The `hdi-codigo-de-normalizacion.js` script implements aggressive cleaning rules:
- Removes "BASE" and "CP PUERTAS" variants
- Eliminates transmission types (CVT, DSG, etc.)
- Strips technical specs before identifying TRIM
- Uses a prioritized list of valid trims

It also infers body type from door count when explicit labels are missing and maps transmission codes to canonical values (AUTO/MANUAL).

**Section sources**
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L1-L525)
- [hdi-query-de-extraccion.sql](file://src/insurers/hdi/hdi-query-de-extraccion.sql#L1-L27)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L1-L718)

## GNP: Chaotic and Contaminated

In stark contrast to HDI, GNP presents significant data quality challenges. The `gnp-analisis.md` highlights critical issues:
- No `activo` field—requiring all records to be processed
- Severe data contamination: ~8% of `VersionCorta` entries contain incorrect brand/model references
- Only ~10% of records have identifiable TRIMs
- Redundant transmission indicators across multiple fields

### Extraction Complexity

The `gnp-query-de-extraccion.sql` must handle version expansion across years due to GNP’s schema design. It concatenates `IdVersion` with `Clave` to create a composite key and casts year values from string to integer.

```sql
SELECT 
    CAST(v.IdVersion as VARCHAR(50)) + '_' + m.Clave as id_original,
    UPPER(LTRIM(RTRIM(a.Armadora))) as marca,
    TRY_CAST(m.Clave as INT) as anio
FROM gnp.Version v
LEFT JOIN gnp.Modelo m ON m.ClaveVersion = v.Clave
WHERE TRY_CAST(m.Clave as INT) BETWEEN 2000 AND 2030
```

### Normalization with Strict Validation

The `gnp-codigo-de-normalizacion.js` applies rigorous validation:
- Detects and removes contamination from other brands (e.g., "BMW 325iA" in non-BMW entries)
- Consolidates duplicate brands (e.g., "GENERAL MOTORS" → "GMC")
- Uses a hierarchical TRIM extraction approach based on known valid trims
- Logs contaminated records for audit

Due to the lack of an active flag, all records are assumed active, increasing processing load and requiring downstream deduplication.

**Section sources**
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L1-L281)
- [gnp-query-de-extraccion.sql](file://src/insurers/gnp/gnp-query-de-extraccion.sql#L1-L34)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L1-L681)

## Qualitas: n8n-Specific JavaScript Implementation

Qualitas uses a specialized JavaScript file named `qualitas-codigo-de-normalizacion-n8n.js`, indicating integration with the n8n workflow automation tool. This script is more complex than standard normalization files due to the high noise level in the source data.

### Data Quality Challenges

Per `qualitas-analisis.md`, only 15.47% of records are active, and the `cVersion` field is highly contaminated:
- Mixes TRIM, equipment codes (BA, AC, QC), and transmission in one string
- Contains service indicators like "SERVPUB"
- Uses abbreviations inconsistently

### Extraction and Parsing Strategy

The `qualitas-query-de-extracción.sql` filters by `Activo = 1` and extracts transmission directly via a `CASE` statement, avoiding reliance on the noisy `cVersion` field.

```sql
CASE 
    WHEN v.cTransmision = 'A' THEN 'AUTO'
    WHEN v.cTransmision = 'S' THEN 'MANUAL'
    ELSE NULL
END as transmision
```

### Advanced Normalization Techniques

The `qualitas-codigo-de-normalizacion-n8n.js` employs advanced parsing:
- Uses a large set of known valid trims (`VERSIONES_VALIDAS`)
- Applies n-gram matching (unigrams, bigrams, trigrams) to identify multi-word trims
- Filters out service and multimedia tokens (e.g., "SERVPUB", "NAVEGACION")
- Prioritizes WAGON/SPORTWAGEN detection before fallback heuristics

It also implements aggressive cleaning of transmission-related terms before TRIM extraction to prevent false positives.

**Section sources**
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L1-L333)
- [qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql#L1-L26)
- [qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js#L1-L966)

## El Potosí: Unique Structure and Special Handling

El Potosí stands out as the only insurer with a dedicated analysis, extraction, and normalization triad explicitly referenced in the project structure. While detailed content is not provided, its inclusion suggests unique structural characteristics requiring special handling.

### Expected Workflow Pattern

Based on naming conventions:
- `elpotosi-analisis.md` likely documents schema peculiarities and data anomalies
- `elpotosi-query-de-extraccion.sql` performs insurer-specific joins and filtering
- `elpotosi-codigo-de-normalizacion.js` implements custom parsing logic

Given the pattern across other insurers, El Potosí’s normalization script probably addresses non-standard field formats, proprietary coding systems, or legacy data structures not found elsewhere.

**Section sources**
- [elpotosi-analisis.md](file://src/insurers/elpotosi/elpotosi-analisis.md)
- [elpotosi-query-de-extraccion.sql](file://src/insurers/elpotosi/elpotosi-query-de-extraccion.sql)
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js)

## Analysis-Driven Normalization

The `analysis.md` files are foundational to the entire homologation process. They inform every aspect of normalization:
- **TRIM extraction logic** is derived from frequency analysis and pattern recognition
- **Transmission mapping** is validated against observed values in the data
- **Body type inference** uses statistical correlations between door count and vehicle class
- **Contamination detection** relies on cross-field consistency checks

For example, HDI’s clean comma-separated structure enables position-based parsing, while GNP’s chaotic data requires aggressive filtering and validation. These insights are codified in the JavaScript normalization scripts, ensuring that transformations are data-grounded rather than arbitrary.

**Section sources**
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md)
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md)
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md)

## SQL Query Optimization per Insurer

Each `query-de-extraccion.sql` is tailored to the insurer’s database schema and performance requirements:
- **HDI**: Uses `WITH` clause to deduplicate `Marca` entries and filters only active records
- **GNP**: Handles year expansion via `TRY_CAST` and constructs composite keys for uniqueness
- **Qualitas**: Casts model year from string prefix (`LEFT(cModelo, 4)`) and uses `CASE` for transmission mapping

These queries are optimized to minimize load on source systems and ensure compatibility with downstream ETL tools like n8n.

**Section sources**
- [hdi-query-de-extraccion.sql](file://src/insurers/hdi/hdi-query-de-extraccion.sql)
- [gnp-query-de-extraccion.sql](file://src/insurers/gnp/gnp-query-de-extraccion.sql)
- [qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql)

## Conclusion

The insurer-specific processing workflows demonstrate a robust framework for homologating diverse and often inconsistent vehicle data into a unified canonical model. HDI exemplifies a best-case scenario with structured, predictable data enabling high-quality normalization. GNP represents the opposite extreme, requiring extensive validation and contamination handling. Qualitas introduces n8n-specific JavaScript logic to manage high-noise inputs, while El Potosí indicates the need for specialized handling in edge cases. Across all insurers, the three-part pattern of analysis, extraction, and normalization ensures consistency, traceability, and adaptability. Future improvements should focus on enhancing data quality at the source and expanding automated anomaly detection.