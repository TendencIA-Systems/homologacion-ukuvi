# Adding New Insurers

<cite>
**Referenced Files in This Document**   
- [instrucciones.md](file://instrucciones.md)
- [src/insurers/qualitas/qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md)
- [src/insurers/hdi/hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md)
- [src/insurers/gnp/gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md)
- [src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js)
- [src/insurers/hdi/hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js)
- [src/insurers/qualitas/qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql)
- [src/insurers/hdi/hdi-query-de-extraccion.sql](file://src/insurers/hdi/hdi-query-de-extraccion.sql)
- [src/insurers/gnp/gnp-query-de-extraccion.sql](file://src/insurers/gnp/gnp-query-de-extraccion.sql)
</cite>

## Table of Contents
1. [Directory Creation and File Structure](#directory-creation-and-file-structure)
2. [Source Data Analysis Using Templates](#source-data-analysis-using-templates)
3. [Writing Extraction SQL Queries](#writing-extraction-sql-queries)
4. [Implementing JavaScript Normalization Logic](#implementing-javascript-normalization-logic)
5. [Handling Special Cases](#handling-special-cases)
6. [Code Structure and Integration with n8n Workflows](#code-structure-and-integration-with-n8n-workflows)
7. [Common Pitfalls and Troubleshooting](#common-pitfalls-and-troubleshooting)

## Directory Creation and File Structure

When adding a new insurer to the homologation system, the first step is to create a dedicated directory under `src/insurers/`. This directory should be named using the insurer's short code (e.g., `qualitas`, `hdi`, `gnp`). Inside this directory, three core files must be created:

1. `[insurer]-analisis.md`: Contains the analysis of the insurer's data structure, field mappings, and normalization rules.
2. `[insurer]-query-de-extraccion.sql`: Contains the SQL query for extracting raw data from the insurer's database.
3. `[insurer]-codigo-de-normalizacion.js` or `[insurer]-codigo-de-normalizacion-n8n.js`: Contains the JavaScript logic for normalizing the extracted data to the canonical model.

The naming convention follows a strict pattern: all lowercase, hyphen-separated, with the insurer code as the prefix. This ensures consistency across the codebase and facilitates automated processing by n8n workflows.

**Section sources**
- [instrucciones.md](file://instrucciones.md#L1-L280)

## Source Data Analysis Using Templates

The analysis process begins with the `insurer-analisis.md` template, which provides a structured framework for documenting the insurer's data characteristics. This document must include:

- **Executive Summary**: Key metrics such as total records, active/inactive ratio, unique brands/models, and year range.
- **Field Anatomy**: Detailed breakdown of key fields (e.g., `cVersion` for Qualitas, `ClaveVersion` for HDI) showing how information is structured and contaminated.
- **Element Statistics**: Quantitative analysis of which technical specifications (transmission, doors, engine config) are present and their frequency.
- **Mapping Strategy**: Clear definition of how source fields map to canonical model fields.
- **Special Cases**: Documentation of anomalies, data contamination, and edge cases.

For example, the Qualitas analysis reveals that only 57.82% of records have an identifiable TRIM, while HDI's data is much cleaner with TRIM always appearing before the first comma. The GNP analysis highlights critical issues like the absence of an active/inactive field and severe data contamination in the `VersionCorta` field.

This analysis directly informs the design of both the extraction query and normalization logic, ensuring that the implementation addresses the specific challenges of each insurer's data structure.

**Section sources**
- [src/insurers/qualitas/qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L0-L333)
- [src/insurers/hdi/hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L0-L525)
- [src/insurers/gnp/gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L0-L281)

## Writing Extraction SQL Queries

The SQL extraction query is responsible for retrieving raw data from the insurer's database with minimal transformation. The query must:

1. **Filter for Active Records**: Where possible, include a `WHERE Activo = 1` clause to process only active offerings (e.g., Qualitas, HDI).
2. **Join Necessary Tables**: Combine data from multiple tables to get a complete record (e.g., joining `hdi.Version` with `hdi.Marca`).
3. **Select All Relevant Fields**: Include both the raw fields for normalization and metadata like original IDs.
4. **Apply Year Range Filter**: Restrict results to the valid year range (2000-2030).
5. **Order Results**: Sort by brand, model, year, and version for consistency.

For HDI, the query joins the `Version` and `Marca` tables to get the brand description, while for GNP, a complex join across `Version`, `Carroceria`, `Armadora`, and `Modelo` tables is required due to the fragmented data structure. The query must be optimized for performance, especially given the large dataset sizes (over 250,000 records for Qualitas).

**Section sources**
- [src/insurers/qualitas/qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L310-L333)
- [src/insurers/hdi/hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L480-L505)
- [src/insurers/gnp/gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L240-L281)
- [src/insurers/qualitas/qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql)
- [src/insurers/hdi/hdi-query-de-extraccion.sql](file://src/insurers/hdi/hdi-query-de-extraccion.sql)
- [src/insurers/gnp/gnp-query-de-extraccion.sql](file://src/insurers/gnp/gnp-query-de-extraccion.sql)

## Implementing JavaScript Normalization Logic

The normalization logic, implemented in JavaScript, transforms the raw data into the canonical model. This process involves several key functions:

1. **Text Normalization**: Standardizing text through uppercasing, accent removal, and whitespace cleanup.
2. **Field Extraction**: Parsing the raw version string to extract TRIM, engine configuration, transmission, etc.
3. **Data Mapping**: Converting source-specific values to standardized canonical values.
4. **Hash Generation**: Creating `hash_comercial` and `id_canonico` for deduplication and identification.

The implementation varies significantly between insurers based on data quality. For Qualitas, the `extraerTrim` function uses a whitelist of valid TRIMs and processes the string from left to right. For HDI, the `normalizarVersion` function performs aggressive cleaning, removing transmission codes, horsepower, and door counts before extracting the TRIM. The GNP implementation requires particularly aggressive filtering due to severe data contamination.

The code must be idempotent and handle edge cases gracefully, returning `null` rather than inventing values when information is genuinely missing.

**Section sources**
- [src/insurers/qualitas/qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L100-L310)
- [src/insurers/hdi/hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L200-L480)
- [src/insurers/gnp/gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L150-L240)
- [src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js)
- [src/insurers/hdi/hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js)

## Handling Special Cases

Several special cases require careful handling in the normalization logic:

### Trim Extraction
Trim extraction strategies vary by insurer. Qualitas uses a priority-ordered whitelist where premium trims like "TYPE S" and "A-SPEC" are checked first. HDI leverages the consistent comma-separated structure, taking everything before the first comma as the TRIM. GNP requires aggressive filtering to remove contamination from other brands before attempting TRIM extraction.

### Version Parsing
Version parsing must account for inconsistent formatting. The system uses regular expressions to extract engine configuration (`L4`, `V6`), displacement (`1.5L`, `2.0T`), and transmission (`AUT`, `STD`). For Qualitas, turbo detection looks for patterns like "TURBO" or "TBO", while HDI uses a more comprehensive list including "TSI" and "TDI".

### Technical Specification Standardization
Technical specifications are standardized into a consistent format. Transmission is normalized to "AUTO" or "MANUAL". Carrocería (body type) is inferred from keywords and door count, with special handling for cases like "SPORTWAGEN" which should be classified as "WAGON" regardless of door count. Tracción (drive type) is mapped from various source terms to standardized values like "4X4", "AWD", "FWD".

The system prioritizes data integrity over completeness, preferring `null` values to potentially incorrect inferences, especially for insurers with low data quality like GNP.

**Section sources**
- [src/insurers/qualitas/qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L50-L310)
- [src/insurers/hdi/hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L100-L480)
- [src/insurers/gnp/gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L100-L240)

## Code Structure and Integration with n8n Workflows

The code structure follows a consistent pattern across insurers, with each implementation containing:

- **Utility Functions**: For text normalization, hash generation, and regex escaping.
- **Dictionary Constants**: For brand synonyms, valid trims, and technical specifications.
- **Normalization Functions**: For each major data transformation step.
- **Main Processing Loop**: That orchestrates the transformation pipeline.

The JavaScript code is designed to run within n8n workflows, where it receives input data, processes it, and returns the normalized output. The workflow handles batching (10,000-50,000 records), deduplication by `id_canonico`, and calling the Supabase RPC function `procesar_batch_homologacion`. The integration is idempotent, allowing reprocessing of batches without creating duplicates.

The naming convention for the JavaScript file (`-n8n.js` suffix) clearly indicates its intended execution environment, distinguishing it from potential server-side implementations.

**Section sources**
- [instrucciones.md](file://instrucciones.md#L100-L280)
- [src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js)
- [src/insurers/hdi/hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js)

## Common Pitfalls and Troubleshooting

Several common pitfalls can occur when adding new insurers:

### Inconsistent Source Formats
Insurers like GNP have highly inconsistent data formats, with contamination from other brands and models. This requires aggressive filtering and validation. The solution is to implement strict validation rules and extensive logging of anomalous cases.

### Missing Data
Critical fields like active/inactive status may be missing (as in GNP). When this occurs, all records must be processed, potentially introducing obsolete offerings into the catalog. The long-term solution is to work with the insurer to add the missing field.

### Debugging Normalization Logic
Debugging normalization logic requires a systematic approach:
1. **Input Validation**: Verify the raw data matches expectations.
2. **Step-by-Step Execution**: Test each normalization function in isolation.
3. **Edge Case Testing**: Focus on records with minimal data (e.g., "A", "B") or maximum contamination.
4. **Logging**: Implement comprehensive logging to track the transformation process.
5. **Validation Checks**: Use the checklist from the analysis document to verify all rules are applied.

For Qualitas, debugging often focuses on ensuring that equipment codes (BA, AC, ABS) are properly removed from the version string. For HDI, the focus is on verifying that the aggressive cleaning doesn't remove valid TRIM information. The system's modular design allows for targeted testing and debugging of individual components.

**Section sources**
- [src/insurers/qualitas/qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L280-L333)
- [src/insurers/hdi/hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L440-L525)
- [src/insurers/gnp/gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L200-L281)