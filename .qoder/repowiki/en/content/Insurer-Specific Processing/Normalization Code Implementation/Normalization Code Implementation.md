# Normalization Code Implementation

<cite>
**Referenced Files in This Document**   
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js)
- [qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js)
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Text Normalization and Field Mapping](#text-normalization-and-field-mapping)
3. [Trim and Version Extraction](#trim-and-version-extraction)
4. [Technical Specification Parsing](#technical-specification-parsing)
5. [Brand, Model, and Year Standardization](#brand-model-and-year-standardization)
6. [Displacement Parsing and Carrocería Inference](#displacement-parsing-and-carrocería-inference)
7. [Special Cases: Qualitas and El Potosí](#special-cases-qualitas-and-el-potosí)
8. [Error Handling, Logging, and Performance](#error-handling-logging-and-performance)
9. [Guidelines for New Insurer Scripts](#guidelines-for-new-insurer-scripts)

## Introduction
This document details the implementation of JavaScript transformation scripts used to normalize diverse vehicle data from multiple insurers into a canonical model. The normalization process standardizes data across various sources, ensuring consistency in brand, model, year, transmission, version (trim), technical specifications, and body type (carrocería). The system processes data from insurers such as GNP, HDI, Qualitas, El Potosí, and Zurich, each with unique data structures and challenges. The transformation pipeline includes text normalization, field mapping, trim extraction, technical specification parsing, and robust error handling. The goal is to create a unified vehicle catalog that supports accurate data analysis, pricing models, and risk assessment across the insurance platform.

## Text Normalization and Field Mapping
The normalization process begins with text standardization to ensure consistency across all data sources. A core utility function, `normalizarTexto`, is used across all insurer scripts to convert text to uppercase, remove accents using Unicode normalization (NFD), replace special characters with spaces, collapse multiple spaces, and trim whitespace. This function is applied to all textual fields including brand, model, and version descriptions.

Field mapping varies by insurer but follows a consistent pattern. The canonical model includes fields such as `marca` (brand), `modelo` (model), `anio` (year), `transmision` (transmission), `version` (trim), and technical specifications like `motor_config`, `cilindrada`, `traccion`, and `carroceria`. Each insurer's source fields are mapped to these canonical fields through dedicated normalization functions. For example, transmission codes (numeric or textual) are standardized to "MANUAL" or "AUTO", while model names are cleaned of redundant brand prefixes and common patterns like "SERIE X" or "CLASE Y" are reformatted for consistency.

**Section sources**
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L33-L43)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L31-L41)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js#L47-L56)
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js#L39-L49)
- [qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js#L16-L26)

## Trim and Version Extraction
Extracting the trim level (version) is one of the most complex aspects of normalization due to the unstructured nature of the source data. The process involves aggressive cleaning of the version string to remove technical specifications, transmission types, body styles, and other non-trim information, leaving only the trim level.

For GNP, the `extraerTrim` function first removes contamination from other brands (e.g., "BMW" appearing in a non-BMW vehicle's version string), then strips out technical specifications like engine configuration, displacement, transmission, traction, and body type. It then searches for known trim values from a prioritized list, returning the first match. If no valid trim is found, it may return a cleaned string if it appears meaningful.

HDI employs an even more aggressive cleaning strategy in its `normalizarVersion` function, eliminating problematic patterns like "BASE CP PUERTAS" and "CP PUERTAS" in all their variants before removing body types, transmissions, engine specs, and occupant counts. The cleaning order is optimized to remove the most problematic elements first. The function then searches for valid trims in a predefined set, checking for 3-word, 2-word, and single-word matches in that order.

Zurich's `normalizarVersion` function follows a similar pattern, using a comprehensive list of regex patterns to eliminate transmission types, engine specs, traction systems, body styles, equipment codes, and numerical specifications. It preserves only known valid trims from an exhaustive list, ensuring that only legitimate trim levels are retained.

**Section sources**
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L200-L259)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L230-L490)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js#L415-L770)

## Technical Specification Parsing
Technical specifications are extracted from the version string using pattern matching and regex-based parsing. The `extraerEspecificaciones` function (or equivalent) is responsible for identifying and isolating key technical attributes.

For GNP, the function extracts `motor_config` (e.g., "V6", "L4"), `cilindrada` (engine displacement in liters), turbo indication, `traccion` (traction system), `carroceria` (body type), and number of `puertas` (doors). It uses case-insensitive regex patterns to match common terms and validates values against reasonable ranges (e.g., displacement between 0.5L and 8.0L).

HDI's implementation is more comprehensive, extracting `configuracion_motor`, `cilindrada_l`, `traccion`, `tipo_carroceria`, and `numero_ocupantes`. It handles edge cases like "8.0L" explicitly and infers body type from door count when explicit indicators are missing. It also processes occupant information from both the version string and a separate original field.

Zurich's `extraerEspecificaciones` function is the most detailed, extracting `cilindrada_l`, `numero_cilindros`, `potencia_hp`, `traccion`, `tipo_carroceria`, `numero_puertas`, `numero_ocupantes`, and `configuracion_motor`. The motor configuration is built as a composite string including engine layout (V6, L4), forced induction (TURBO, BITURBO), fuel type (DIESEL), and hybrid/electric status (HYBRID, PHEV, ELECTRICO).

**Section sources**
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L262-L324)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L510-L623)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js#L257-L404)

## Brand, Model, and Year Standardization
Brand and model standardization ensures consistency across different insurers' naming conventions. The `normalizarMarca` function uses a dictionary of synonyms to map variant spellings and abbreviations to standardized brand names (e.g., "VW" → "VOLKSWAGEN", "CHEVY" → "CHEVROLET"). GNP includes a specific consolidation dictionary for brands like "GENERAL MOTORS" → "GMC", while other insurers use a shared synonym dictionary that is kept synchronized across implementations.

Model normalization, performed by `normalizarModelo`, removes the brand name from the model string if present and applies pattern replacements for common naming schemes (e.g., "SERIE 3" → "3 SERIES", "CLASE A" → "CLASE A"). HDI additionally removes parentheses and multimedia/equipment terms like "DVD" or "GPS" that may appear in the model field.

Year data is typically used as-is, but is converted to an integer and validated to ensure it falls within a reasonable range. The year is a critical component in the canonical vehicle identity and is used in hash generation for deduplication.

**Section sources**
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L63-L118)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L79-L119)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js#L85-L148)
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js#L69-L106)
- [qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js#L467-L477)

## Displacement Parsing and Carrocería Inference
Displacement parsing is handled as part of technical specification extraction. The system identifies engine displacement using regex patterns that match numbers followed by "L" or "T" (e.g., "1.5L", "2.0T"). The value is converted to a float and validated against a reasonable range (0.5L to 8.0L). Some implementations, like HDI, include special handling for edge cases like "8.0L".

Carrocería (body type) inference uses a multi-layered approach. The primary method is direct pattern matching in the version string for terms like "SEDAN", "SUV", "COUPE", "HATCHBACK", "PICKUP", "VAN", and "WAGON". When explicit indicators are missing, the system may infer body type from the number of doors (e.g., 2 doors → "COUPE", 5 doors → "HATCHBACK" or "SUV") or from known model names (e.g., "CR-V", "RAV4" → "SUV").

Qualitas implements a sophisticated inference system with priority rules, giving precedence to "WAGON" and "SPORTWAGEN" indicators and using cabin type (e.g., "CREW CAB") to identify pickups. It also uses a fallback based on known model names for common SUVs, pickups, and sedans.

**Section sources**
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L287-L313)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L570-L623)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js#L345-L370)
- [qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js#L620-L770)

## Special Cases: Qualitas and El Potosí
Qualitas and El Potosí present unique challenges that require specialized handling in their normalization scripts.

Qualitas uses n8n-specific JavaScript syntax and implements a more complex normalization strategy. Its script, `qualitas-codigo-de-normalizacion-n8n.js`, includes a large dictionary of valid trims (`VERSIONES_VALIDAS`) and uses n-gram analysis to identify multi-word trims. It employs a whitelist/blacklist approach, treating service and multimedia terms as stopwords that should never be considered trims. The script also handles domain-specific cases like "TRACTOS" and "REMOLQUES" as valid brands. The trim extraction process is robust, searching for 3-gram, 2-gram, and unigram matches in that order, and returns null when no valid trim is found, avoiding the creation of artificial trims.

El Potosí's data structure requires special handling due to the possibility of an empty `VersionCorta` field, necessitating a fallback to the `Descripcion` field. The script uses a `prepararVersion` function to clean and normalize the version text, removing prefixes of brand and model if present and stripping "Año: XXXX" suffixes. It strictly avoids inventing trims, returning null when no valid trim is identified. The script also processes only active records (where `Activo = 1`), filtering out inactive entries during normalization.

**Section sources**
- [qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js#L467-L799)
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js#L160-L240)

## Error Handling, Logging, and Performance
The normalization scripts implement robust error handling to ensure data integrity and system stability. Each record is processed within a try-catch block, allowing the system to continue processing subsequent records even if one fails. Errors are logged with descriptive messages and the original record data for debugging purposes.

Logging is used extensively for monitoring and debugging. GNP logs statistics on processed records, contaminated data, and missing trims. HDI and Zurich include console logs for error conditions and processing statistics. These logs help identify data quality issues and inform improvements to the normalization logic.

Performance considerations include the use of efficient regex patterns, minimizing string operations, and avoiding unnecessary computations. The scripts are designed to process large batches of records efficiently within the n8n workflow environment. Hash generation using SHA-256 ensures unique identification of vehicle configurations for deduplication, with separate `hash_comercial` (commercial hash) and `hash_tecnico` (technical hash) for different levels of granularity.

**Section sources**
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L630-L670)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L700-L718)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js#L720-L734)
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js#L580-L623)

## Guidelines for New Insurer Scripts
When developing normalization scripts for additional insurers, follow these guidelines to ensure consistency and maintainability:

1. **Reuse Common Functions**: Implement shared utility functions like `normalizarTexto` and `generarHash` consistently across all scripts to maintain uniformity.

2. **Standardize Field Mapping**: Map source fields to the canonical model fields (`marca`, `modelo`, `anio`, `transmision`, `version`, etc.) using the same logic and output format.

3. **Implement Robust Text Cleaning**: Use aggressive cleaning strategies to remove technical specifications, transmission types, and other non-trim information from version strings before trim extraction.

4. **Use Comprehensive Synonym Dictionaries**: Maintain and synchronize brand and model synonym dictionaries across all scripts to ensure consistent standardization.

5. **Prioritize Data Validation**: Validate extracted values against reasonable ranges (e.g., displacement, horsepower, year) and return null for invalid or missing data rather than default values.

6. **Handle Edge Cases Explicitly**: Document and handle insurer-specific edge cases, such as Qualitas's n8n syntax or El Potosí's fallback fields, with clear comments and error handling.

7. **Implement Comprehensive Logging**: Include error logging and processing statistics to aid in debugging and monitoring data quality.

8. **Ensure Idempotency and Deduplication**: Use hash generation (SHA-256) to create unique identifiers for vehicle configurations, enabling reliable deduplication across data sources.

By following these guidelines, new insurer scripts can be integrated seamlessly into the existing normalization pipeline, ensuring high data quality and consistency across the entire vehicle catalog.

**Section sources**
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L630-L670)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L700-L718)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js#L720-L734)
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js#L580-L623)
- [qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js#L467-L799)