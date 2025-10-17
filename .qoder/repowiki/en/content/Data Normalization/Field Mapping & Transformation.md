# Field Mapping & Transformation

<cite>
**Referenced Files in This Document**   
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js)
- [ana-analisis.md](file://src/insurers/ana/ana-analisis.md)
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md)
- [elpotosi-analisis.md](file://src/insurers/elpotosi/elpotosi-analisis.md)
- [WARP.md](file://WARP.md)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Core Field Mapping Principles](#core-field-mapping-principles)
3. [HDI Normalization Strategy](#hdi-normalization-strategy)
4. [GNP Normalization Strategy](#gnp-normalization-strategy)
5. [Cross-Insurer Field Mapping Patterns](#cross-insurer-field-mapping-patterns)
6. [Data Transformation Techniques](#data-transformation-techniques)
7. [Handling Missing and Null Fields](#handling-missing-and-null-fields)
8. [Consistent Naming Conventions](#consistent-naming-conventions)
9. [Conflict Resolution in Field Meanings](#conflict-resolution-in-field-meanings)
10. [Maintaining Readability and Traceability](#maintaining-readability-and-traceability)

## Introduction
This document details the field mapping and transformation processes used in the vehicle catalog homologation system that unifies data from multiple Mexican insurance companies into a canonical schema. The system normalizes source-specific fields from insurer databases to a standardized format, enabling consistent vehicle identification and comparison across different providers. The normalization process involves complex text parsing, pattern recognition, and business logic to extract meaningful information from inconsistently formatted source data.

The homologation system processes data from 11 insurance companies including HDI, GNP, Qualitas, AXA, Mapfre, Chubb, Zurich, Atlas, BX, El Potosí, and ANA. Each insurer provides vehicle catalog data with unique structures, naming conventions, and data quality characteristics. The normalization process transforms these diverse data sources into a unified canonical model with consistent field names, data types, and value representations.

The system uses JavaScript-based normalization functions executed within n8n workflows to transform the data before loading it into a Supabase PostgreSQL database. The process includes text normalization, field mapping, value transformation, and the generation of unique identifiers to ensure data consistency and enable deduplication.

**Section sources**
- [WARP.md](file://WARP.md#L0-L413)

## Core Field Mapping Principles
The field mapping process follows several core principles to ensure consistency and reliability across different insurers. The primary goal is to transform source-specific fields into a canonical schema with standardized field names such as "marca" → "brand", "modelo" → "model", "anio" → "year", and "transmision" → "transmission". This transformation enables cross-insurer comparison and aggregation of vehicle data.

The mapping process prioritizes the use of dedicated fields when available, falling back to text parsing when necessary. For example, transmission information is preferably taken from dedicated transmission code fields rather than being inferred from text descriptions. When extracting information from unstructured text fields like "VersionCorta", the system uses pattern recognition and validation against known value lists to ensure accuracy.

Data quality varies significantly between insurers, requiring different normalization strategies. Some insurers like ANA have well-structured data with dedicated fields for key attributes, while others like Qualitas have highly contaminated data fields that mix trim levels, technical specifications, and equipment codes. The normalization process must be robust enough to handle these variations while maintaining consistency in the output schema.

The system generates unique identifiers using SHA-256 hashes of key attribute combinations. The "hash_comercial" is generated from brand, model, year, and transmission, while the "hash_tecnico" includes additional technical specifications. These hashes enable deduplication and ensure that identical vehicles from different insurers are recognized as the same entity in the canonical model.

**Section sources**
- [WARP.md](file://WARP.md#L256-L319)
- [ana-analisis.md](file://src/insurers/ana/ana-analisis.md#L0-L324)

## HDI Normalization Strategy
HDI's normalization strategy focuses on aggressive cleaning of contaminated data fields, particularly the "VersionCorta" field which contains mixed information. The process involves multiple stages of pattern-based removal to extract clean trim levels while preserving meaningful vehicle specifications.

The normalization begins with text standardization using the "normalizarTexto" function, which converts text to uppercase, removes accents, and replaces special characters with spaces. This creates a consistent base for pattern matching. The "normalizarMarca" function then applies synonym mapping to standardize brand names, converting variants like "VW" and "VOLKS WAGEN" to "VOLKSWAGEN", and "MERCEDES" and "MB" to "MERCEDES BENZ".

The most complex aspect of HDI's normalization is the "normalizarVersion" function, which systematically removes problematic patterns in a specific order. First, it eliminates "BASE" designations and door count specifications (e.g., "CP PUERTAS"). Then it removes body types (SEDAN, SUV, COUPE), followed by transmission types (AUTOMATICA, MANUAL, SPEEDSHIFT), engine specifications (V6, 2.0L), power ratings (HP, CV), drivetrain information (4X4, AWD), fuel types (DIESEL, GASOLINA), and occupancy information (PASAJEROS).

After this aggressive cleaning, the function validates the remaining text against a comprehensive list of known valid trim levels such as "EXCLUSIVE", "ADVANCE", "LIMITED", "PREMIUM", "SPORT", and performance designations like "AMG", "M", and "RS". If no valid trim is found, the function applies additional rules to determine if the remaining text represents a reasonable trim level based on length and content.

The "extraerEspecificaciones" function runs in parallel to extract technical specifications from the original version text. It identifies engine configuration (V6, L4), displacement in liters, drivetrain type, body type, and occupancy. This information is stored separately from the trim level, creating a cleaner separation of concerns in the canonical schema.

**Section sources**
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L0-L717)

## GNP Normalization Strategy
GNP's normalization strategy addresses significant data quality issues, including an 8% contamination rate where vehicle versions contain brand names from other manufacturers. The process includes specific contamination detection and cleaning logic to ensure data integrity.

The "limpiarContaminacion" function is a critical component of GNP's normalization, designed to detect and remove brand names that appear in the version field but don't match the vehicle's actual brand. For example, if a Chevrolet record contains "BMW" at the beginning of the version text, the function identifies this as contamination and removes it. This prevents incorrect trim extraction and ensures that vehicles are properly categorized.

GNP's data lacks an active/inactive flag, so all records are processed as active. This differs from other insurers like Qualitas and ANA which have explicit active status fields. The normalization process must account for this difference by not filtering records based on activity status.

The "extraerTrim" function follows a multi-step process to extract trim levels from GNP's data. First, it applies the contamination cleaning. Then it removes technical specifications including engine configuration, displacement, transmission type, drivetrain, turbo designation, door count, wheel size, equipment codes, body type, and hybrid/electric designations. After this cleaning, it searches for matches against a prioritized list of valid trims.

GNP's valid trim list includes brand-specific designations like "SPORT LINE", "S LINE", "GT LINE", "M SPORT", and "AMG LINE", as well as common trim levels like "LIMITED", "PREMIUM", "EXCLUSIVE", and "ADVANCE". The function also accepts reasonably sized text fragments (3-20 characters) that aren't purely numeric as potential trims, acknowledging that many GNP records lack standardized trim designations.

The "inferirCarroceria" function uses multiple sources to determine body type, prioritizing the "TipoVehiculo" field when available, then falling back to specifications extracted from the version text, model name patterns, and door count inference. This multi-source approach compensates for incomplete data in individual records.

**Section sources**
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L0-L680)

## Cross-Insurer Field Mapping Patterns
Analysis of multiple insurers reveals common patterns in field mapping and transformation that inform the overall normalization strategy. These patterns highlight both similarities in data structures and important differences that require insurer-specific handling.

Brand normalization follows a consistent pattern across insurers, with each implementing a "normalizarMarca" function that maps variants to standard names. Common synonym groups include "VW" → "VOLKSWAGEN", "CHEVY" → "CHEVROLET", "MB" → "MERCEDES BENZ", and "GMC" → "GENERAL MOTORS". However, each insurer has unique brand variants that require specific handling, such as GNP's "GENERAL MOTORS 2" → "GMC" mapping.

Transmission mapping shows both consistency and variation. Most insurers use numeric codes (1=MANUAL, 2=AUTO) or text abbreviations (AUT, STD) that are mapped to standardized "MANUAL" and "AUTO" values. HDI's approach is more sophisticated, recognizing a wider range of transmission types including CVT, DSG, PDK, DCT, and various "TRONIC" variants, all mapped to "AUTO".

The treatment of trim levels varies significantly between insurers. HDI employs aggressive cleaning to remove all non-trim information, while GNP focuses on contamination detection. Qualitas uses a list-based approach with over 100 valid trim names, and ANA implements a multi-step cleaning process that removes prefixes, transmission, door count, displacement, engine configuration, and equipment codes before trim extraction.

Body type inference follows similar patterns across insurers, typically using a hierarchy of sources: explicit body type fields, keywords in version text (SEDAN, SUV, COUPE), and inference from door count (2=COUPE, 3=HATCHBACK, 4=SEDAN, 5=SUV/HATCHBACK). The specific implementation details vary, with some insurers like El Potosí having dedicated vehicle type codes that inform the inference process.

**Section sources**
- [ana-analisis.md](file://src/insurers/ana/ana-analisis.md#L0-L324)
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L0-L332)
- [elpotosi-analisis.md](file://src/insurers/elpotosi/elpotosi-analisis.md#L0-L363)

## Data Transformation Techniques
The normalization system employs several advanced data transformation techniques to handle the complexities of insurer data. These techniques ensure consistent output despite variations in input format and quality.

Text normalization is a foundational technique used by all insurers. The "normalizarTexto" function standardizes text by converting to uppercase, removing accents via Unicode normalization, replacing special characters with spaces, collapsing multiple spaces, and trimming whitespace. This creates a consistent base for pattern matching and comparison.

Regular expressions are extensively used for pattern extraction and removal. The system employs regex patterns to identify engine configurations (/\b([VLIH])(\d+)\b/), displacement (/\b(\d+\.?\d*)[LT]\b/), door count (/\b(\d+)\s*(PTAS?|PUERTAS)\b/), occupancy (/\b(\d+)\s*(PASAJEROS?|OCUPANTES?)\b/), and drivetrain (/\b(4X4|AWD|FWD|RWD)\b/). These patterns are applied in a specific order to avoid conflicts and ensure accurate extraction.

Hash generation is used to create unique identifiers for deduplication. The "generarHash" function creates SHA-256 hashes of concatenated field values, with "hash_comercial" based on brand, model, year, and transmission, and "hash_tecnico" including additional technical specifications. These hashes enable reliable identification of identical vehicles across different insurers.

Conditional logic is used extensively to handle edge cases and data quality issues. For example, HDI's version normalization includes validation to prevent returning single characters or pure numbers as trim levels. GNP's contamination detection includes logic to return empty strings when contamination leaves no meaningful content. These conditional rules improve data quality by preventing invalid transformations.

The system also employs list-based validation, maintaining comprehensive lists of valid values for trims, brands, and other attributes. These lists serve as reference points for validation and help prevent the propagation of invalid or inconsistent values into the canonical model.

**Section sources**
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L0-L717)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L0-L680)

## Handling Missing and Null Fields
The normalization process includes robust handling of missing and null fields, which are common in insurer data. The system distinguishes between truly missing data and data that should be null due to business rules.

For required fields like brand, model, and year, the system treats missing values as data quality issues that should be logged and potentially trigger alerts. However, for optional fields like trim level, technical specifications, and equipment, missing values are expected and handled gracefully by setting the canonical field to null.

The system uses a consistent approach to null value representation, using JavaScript null rather than empty strings or placeholder values. This ensures that missing data is clearly distinguishable from actual values in the canonical model. During hash generation, null values are represented as "null" strings to ensure consistent hashing behavior.

Some insurers have different conventions for representing missing data. For example, GNP uses 0 for unspecified transmission, while other insurers might use empty strings or null values. The normalization functions convert these insurer-specific representations to a consistent null value in the canonical schema.

The system also handles fields that are missing due to business rules. For example, GNP does not provide occupancy information, so the "numero_ocupantes" field is consistently null for all GNP records. This is documented and accepted as a characteristic of the data source rather than a data quality issue.

When multiple sources could provide the same information, the system implements fallback logic. For example, if the primary version field is empty, some insurers use a description field as a fallback. This ensures that potentially valuable information is not lost due to missing primary fields.

**Section sources**
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L0-L680)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L0-L717)

## Consistent Naming Conventions
The system enforces consistent naming conventions across all insurers to ensure maintainability and readability of the normalization code. These conventions apply to function names, variable names, and field names in the canonical schema.

Function names follow a consistent pattern using the "normalizar" prefix for transformation functions (normalizarMarca, normalizarModelo, normalizarTransmision) and "extraer" for extraction functions (extraerEspecificaciones, extraerTrim). This makes the purpose of each function immediately clear to developers.

Variable names in the canonical schema are standardized across insurers, with fields like "marca", "modelo", "anio", "transmision", "version", "motor_config", "cilindrada", "traccion", "carroceria", and "numero_ocupantes". This consistency enables uniform processing and querying of the homologated data.

The system uses consistent data types for equivalent fields across insurers. String fields are consistently uppercase with standardized spelling, numeric fields use appropriate JavaScript number types, and boolean fields use true/false values. This prevents type-related issues when combining data from different sources.

Constants and configuration objects follow naming conventions that indicate their purpose. For example, "sinonimos" contains brand name mappings, "TRIMS_VALIDOS" contains valid trim levels, and "ASEGURADORA" contains the insurer identifier. These names are descriptive and follow camelCase convention.

The use of consistent naming extends to the generation of derived fields like "main_specs" and "tech_specs", which are pipe-delimited strings used as inputs to hash functions. This consistency ensures that the same vehicle characteristics produce the same hash values regardless of the source insurer.

**Section sources**
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L0-L717)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L0-L680)

## Conflict Resolution in Field Meanings
The system addresses conflicts in field meanings across insurers through business logic and prioritization rules. These conflicts arise when the same field name has different meanings or when different fields contain the same information.

One common conflict is the representation of transmission type. Some insurers use numeric codes (1=MANUAL, 2=AUTO), others use abbreviations (STD, AUT), and some include detailed transmission names (CVT, DSG, PDK). The normalization process resolves this by mapping all variations to the standardized values "MANUAL" and "AUTO", with detailed transmission types being captured separately when available.

Another conflict involves the representation of trim levels. Some insurers include technical specifications in the trim name, while others keep them separate. The system resolves this by aggressively cleaning trim fields to remove technical specifications, creating a cleaner separation between trim level and technical attributes in the canonical schema.

Brand representation conflicts are resolved through comprehensive synonym mapping. For example, "MERCEDES BENZ" may appear as "MERCEDES", "MB", or "MERCEDES-BENZ" across different insurers. The normalization process maps all variants to the standard "MERCEDES BENZ" format, ensuring consistency in the canonical model.

The system also resolves conflicts in body type classification. Some insurers use broad categories while others use specific types. The normalization process uses a standardized set of body types (SEDAN, SUV, COUPE, HATCHBACK, PICKUP, VAN, CONVERTIBLE, WAGON) and maps insurer-specific classifications to these standard types.

When conflicts cannot be resolved through automated rules, the system logs the discrepancies for manual review. For example, GNP's 8% contamination rate triggers warning messages that can be analyzed to improve the normalization rules over time.

**Section sources**
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L0-L717)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L0-L680)

## Maintaining Readability and Traceability
The normalization system prioritizes readability and traceability in its mapping rules to ensure maintainability and auditability. This is achieved through clear code structure, comprehensive documentation, and the preservation of source data.

Each normalization file includes detailed comments explaining the purpose of the code, changes between versions, and the rationale for specific transformation rules. Function names are descriptive and follow consistent patterns, making the code self-documenting. Complex algorithms are broken down into discrete steps with clear comments explaining each stage.

The system maintains traceability by preserving the original source data alongside the normalized data. The canonical records include fields like "id_original" and "version_original" that reference the source data, enabling reconciliation and debugging. This allows analysts to trace any canonical record back to its source.

Error handling and logging are implemented to capture issues during the normalization process. For example, GNP's code includes console warnings when contamination is detected, and both HDI and GNP code include try-catch blocks to prevent processing failures from stopping the entire batch.

The use of standardized patterns across insurers enhances readability. Once a developer understands the normalization approach for one insurer, they can quickly understand the others due to the consistent structure and naming conventions. This reduces the learning curve and improves maintainability.

The system also includes validation and quality metrics that are logged after processing. For example, GNP's normalization logs the number of contaminated records and records without identifiable trims, providing visibility into data quality issues that can inform future improvements to the normalization rules.

**Section sources**
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L0-L717)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L0-L680)