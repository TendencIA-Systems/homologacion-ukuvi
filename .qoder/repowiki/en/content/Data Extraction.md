# Data Extraction

<cite>
**Referenced Files in This Document**   
- [qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql)
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md)
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md)
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md)
- [hdi-query-de-extraccion.sql](file://src/insurers/hdi/hdi-query-de-extraccion.sql)
- [gnp-query-de-extraccion.sql](file://src/insurers/gnp/gnp-query-de-extraccion.sql)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Query Design Principles](#query-design-principles)
3. [Insurer-Specific Extraction Strategies](#insurer-specific-extraction-strategies)
4. [Performance Considerations](#performance-considerations)
5. [Downstream Data Structuring](#downstream-data-structuring)
6. [Query Development Best Practices](#query-development-best-practices)
7. [Validation and Quality Assurance](#validation-and-quality-assurance)
8. [Conclusion](#conclusion)

## Introduction

The data extraction phase is a critical component in the vehicle catalog homologation process, serving as the foundation for downstream normalization and standardization. This document details how insurer-specific SQL queries are designed and implemented to extract vehicle catalog data from disparate source databases, with a focus on Qualitas, HDI, and GNP as representative examples. The extraction process must account for significant variations in schema design, data quality, and business logic across insurers while ensuring efficient, reliable, and maintainable data retrieval. The extracted data is structured to facilitate seamless processing in n8n workflows for subsequent normalization into a canonical format.

**Section sources**
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L1-L333)
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L1-L525)
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L1-L281)

## Query Design Principles

Effective extraction queries follow several key design principles to ensure data quality, performance, and maintainability. These principles include filtering for active records, selecting only relevant fields, handling source-specific data quirks, and structuring output for downstream processing.

### Filtering for Active Records

A critical design principle is filtering to include only active vehicle records, as inactive records represent outdated or discontinued models that should not be included in the current catalog. The implementation of this filter varies significantly between insurers:

- **Qualitas**: Uses an `Activo` field where only records with value `1` are considered active. This represents only 15.47% of total records (39,715 out of 256,803), making this filter essential for data relevance.
- **HDI**: Also implements an `Activo` field, with 45.15% of records marked as active (38,186 out of 84,579), indicating a more current catalog structure.
- **GNP**: Lacks any active/vigent field, requiring all available records to be processed without the ability to filter obsolete entries—a significant data quality challenge.

The absence of an active flag in GNP's schema represents a critical limitation that affects data freshness and relevance.

### Selecting Relevant Fields

Extraction queries are designed to select only the fields necessary for downstream normalization, minimizing data transfer and processing overhead. Core fields consistently extracted include:

- **Origin insurer identifier**: A constant value identifying the source (e.g., 'QUALITAS')
- **Original ID**: The primary key from the source system for traceability
- **Brand and model**: Vehicle manufacturer and model designation
- **Year**: Model year, typically filtered between 2000-2030
- **Version string**: The raw version/trim description containing technical specifications
- **Transmission**: Drive system information, either as a code or description
- **Active status**: The record's active/inactive designation

Additional fields may be included for debugging or validation purposes but are excluded from the final normalized output.

### Handling Source-Specific Quirks

Each insurer's database schema presents unique challenges that must be addressed in the extraction query or subsequent processing:

- **Qualitas**: The `cModelo` field contains the year as a string prefix (e.g., "2023ABC"), requiring `LEFT(cModelo, 4)` extraction and casting to integer.
- **HDI**: Brand information requires a JOIN with the `Marca` table using `IdMarca`, as the version table only contains the ID, not the descriptive name.
- **GNP**: Year data is stored as a string in the `Modelo` table and must be CAST to integer, with validation to ensure it falls within the 2000-2030 range.

These source-specific adaptations ensure consistent data types and formats across insurers despite schema differences.

**Section sources**
- [qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql#L1-L26)
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L1-L333)
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L1-L525)
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L1-L281)

## Insurer-Specific Extraction Strategies

The extraction approach varies significantly based on the data quality, schema design, and business rules of each insurer. Qualitas, HDI, and GNP represent three distinct profiles that require tailored extraction strategies.

### Qualitas: High-Volume, Low-Activity Extraction

Qualitas presents a high-volume extraction scenario with a large total dataset but a low percentage of active records. The extraction strategy focuses on efficiency and data relevance:

```sql
-- Query optimized for Qualitas with active record filtering
SELECT 
    'QUALITAS' as origen_aseguradora,
    v.ID as id_original,
    m.cMarcaLarga as marca,
    mo.cTipo as modelo,
    CAST(LEFT(v.cModelo, 4) as INT) as anio,
    v.cVersion as version_original,
    CASE 
        WHEN v.cTransmision = 'A' THEN 'AUTO'
        WHEN v.cTransmision = 'S' THEN 'MANUAL'
        ELSE NULL
    END as transmision,
    v.Activo as activo
FROM qualitas.Version v
INNER JOIN qualitas.Modelo mo ON v.ModeloID = mo.ID
INNER JOIN qualitas.Marca m ON mo.MarcaID = m.ID
WHERE 
    v.Activo = 1
    AND CAST(LEFT(v.cModelo, 4) as INT) BETWEEN 2000 AND 2030
ORDER BY m.cMarcaLarga, mo.cTipo, CAST(LEFT(v.cModelo, 4) as INT)
```

The query is optimized for n8n processing by limiting results to active records only, reducing the dataset from over 250,000 to approximately 40,000 records. The `cVersion` field is extracted in its raw form for downstream parsing, as it contains a complex mix of trim levels, technical specifications, and equipment codes that require sophisticated normalization.

**Section sources**
- [qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql#L1-L26)
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L1-L333)

### HDI: Structured and Predictable Extraction

HDI's data structure is significantly cleaner than Qualitas, with a highly standardized `ClaveVersion` field that follows a consistent comma-separated pattern. This allows for more reliable parsing in the normalization phase:

```sql
-- Optimized extraction query for HDI with necessary joins
SELECT
    v.IdVersion as id_original,
    m.Descripcion as marca,
    v.ClaveSubMarca as modelo,
    v.Anio as anio,
    v.ClaveVersion as version_completa,
    v.Activo as activo,
    v.IdMarca,
    v.DbCatalogosModeloID,
    v.DbCatalogosVersionID
FROM hdi.Version v
INNER JOIN (
    SELECT DISTINCT IdMarca, Descripcion
    FROM hdi.Marca
) m ON v.IdMarca = m.IdMarca
WHERE
    v.Activo = 1
    AND v.Anio BETWEEN 2000 AND 2030
ORDER BY
    m.Descripcion,
    v.ClaveSubMarca,
    v.Anio,
    v.ClaveVersion;
```

The extraction strategy leverages HDI's structured data format, where the `ClaveVersion` field consistently separates trim, engine configuration, displacement, power, doors, transmission, and extras with commas. This predictable structure enables more accurate extraction of individual components during normalization. The query includes a subquery to ensure distinct brand mappings, addressing potential duplication in the source data.

**Section sources**
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L1-L525)
- [hdi-query-de-extraccion.sql](file://src/insurers/hdi/hdi-query-de-extraccion.sql#L1-L20)

### GNP: Problematic and Unstructured Extraction

GNP presents the most challenging extraction scenario due to the absence of an active record flag and severe data contamination issues in the `VersionCorta` field:

```sql
-- Extraction query for GNP without active filtering
SELECT
    v.IdVersion as id_original,
    a.Armadora as marca,
    c.Carroceria as modelo,
    CAST(m.Modelo as INT) as anio,
    v.Transmision as transmision_codigo,
    v.TipoVehiculo as tipo_vehiculo,
    v.VersionCorta as version_completa,
    v.PickUp as es_pickup
FROM gnp.Version v
INNER JOIN gnp.Carroceria c ON v.ClaveCarroceria = c.Clave
INNER JOIN gnp.Armadora a ON c.ClaveArmadora = a.Clave
INNER JOIN gnp.Modelo m ON m.ClaveCarroceria = c.Clave
    AND m.ClaveVersion = v.Clave
WHERE TRY_CAST(m.Modelo as INT) BETWEEN 2000 AND 2030
ORDER BY a.Armadora, c.Carroceria, m.Modelo;
```

The extraction strategy must process all records due to the lack of an active flag, increasing the risk of including obsolete models. The `VersionCorta` field contains significant data contamination, with approximately 8% of records containing incorrect brand or model information (e.g., "MERCEDES BENZ ML 500 CGI BITURBO" in a Honda Civic record). This requires aggressive cleaning and validation in the normalization phase. The query extracts transmission as a code (0, 1, 2) rather than a description, requiring mapping to canonical values ('MANUAL', 'AUTO') downstream.

**Section sources**
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L1-L281)
- [gnp-query-de-extraccion.sql](file://src/insurers/gnp/gnp-query-de-extraccion.sql#L1-L20)

## Performance Considerations

Efficient query design is essential to prevent timeouts and ensure reliable data extraction, particularly when integrated with n8n workflows that have execution time limits.

### Avoiding Full Table Scans

Extraction queries are designed to avoid full table scans through strategic filtering and indexing. The WHERE clause always includes filters on year (2000-2030) and active status where available. These filters should be supported by appropriate indexes on the source database:

- **Qualitas**: Indexes on `Version.Activo` and the leading characters of `Version.cModelo`
- **HDI**: Indexes on `Version.Activo` and `Version.Anio`
- **GNP**: Indexes on `Modelo.Modelo` (for year filtering) and join keys

Without these indexes, query performance would degrade significantly, especially for Qualitas with over 250,000 records.

### LIMIT Clauses and Batch Processing

While the extraction queries themselves do not include LIMIT clauses (to ensure complete data retrieval), the overall process is designed for batch processing in n8n. The filtered result sets are manageable in size:

- Qualitas: ~39,715 active records
- HDI: ~38,186 active records  
- GNP: ~11,674 records (all processed)

These result sets are processed in batches of 10,000 records in n8n to prevent memory issues and allow for checkpointing. The ORDER BY clause ensures consistent batch boundaries across executions.

### Join Optimization

Query performance is further optimized by minimizing expensive JOIN operations:

- **HDI**: Uses a subquery with `DISTINCT` to reduce the size of the `Marca` lookup table
- **Qualitas**: Direct JOINs are efficient due to established relationships between `Version`, `Modelo`, and `Marca` tables
- **GNP**: Multiple JOINs are required but are optimized by filtering in the WHERE clause before joining

These optimizations ensure that the extraction phase completes within acceptable timeframes for integration with downstream systems.

**Section sources**
- [qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql#L1-L26)
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L1-L525)
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L1-L281)

## Downstream Data Structuring

The extracted data is structured to facilitate seamless normalization in n8n workflows, with a consistent output schema across all insurers despite source variations.

### Output Schema Design

All extraction queries produce a consistent set of fields that map to the canonical model:

- **origen_aseguradora**: Source insurer identifier
- **id_original**: Source system primary key for traceability
- **marca**: Vehicle brand (normalized)
- **modelo**: Vehicle model (normalized)  
- **anio**: Model year (integer)
- **version_original**: Raw version string for parsing
- **transmision**: Transmission type (canonical: 'AUTO'/'MANUAL')
- **activo**: Active status flag

Additional insurer-specific fields (e.g., `transmision_codigo` in GNP) may be included for debugging but are not part of the core schema.

### Data Type Standardization

The extraction queries perform initial data type standardization:

- String-to-integer conversion for year fields
- Code-to-description mapping for transmission types
- Field renaming to consistent canonical names

This standardization reduces the complexity of downstream transformations in n8n, where the data undergoes further parsing and normalization.

### Preparation for Normalization

The raw `version_original` field is preserved in its entirety for the normalization phase, where JavaScript functions parse it into discrete components:

- **Trim/Version**: Extracted using pattern matching and whitelist validation
- **Engine configuration**: Identified by patterns like L4, V6, I4
- **Displacement**: Extracted as numeric value from patterns like 1.5L, 2.0T
- **Transmission**: Redundant with the dedicated field but used for validation
- **Doors**: Extracted from patterns like 4P, 5P
- **Drive type**: Identified by AWD, 4X4, FWD, RWD
- **Electrification**: Detected by HEV, PHEV, EV, etc.

The extraction phase ensures this raw data is delivered completely and accurately for the normalization functions to process.

**Section sources**
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L1-L333)
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L1-L525)
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L1-L281)

## Query Development Best Practices

Developing effective extraction queries requires adherence to several best practices to ensure reliability, maintainability, and performance.

### Documentation and Comments

All extraction queries include comprehensive comments explaining their purpose, critical filters, and optimization considerations. For example, the Qualitas query explicitly documents that it extracts only active records (15.47% of total) and is optimized for n8n to prevent timeouts. This documentation is essential for maintenance and troubleshooting.

### Testing with Real Data

Queries are developed and tested against actual production data to ensure they handle edge cases and data quality issues. This includes testing with:

- Records containing special characters or encoding issues
- Boundary conditions (year 2000, year 2030)
- Records with missing or null values in critical fields
- Data contamination cases (particularly for GNP)

### Version Control and Change Management

Extraction queries are stored in version control with clear file naming conventions (e.g., `{insurer}-query-de-extraccion.sql`). Changes to queries are documented with the rationale for the change, ensuring auditability and facilitating rollback if needed.

### Performance Monitoring

Query execution time and result set size are monitored regularly to detect performance degradation or data anomalies. Sudden increases in result set size could indicate issues with the active record filter or data quality problems in the source system.

**Section sources**
- [qualitas-query-de-extracción.sql](file://src/insurers/qualitas/qualitas-query-de-extracción.sql#L1-L26)
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L1-L525)
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L1-L281)

## Validation and Quality Assurance

Rigorous validation is performed on extracted data to ensure quality before normalization.

### Data Completeness Checks

Each insurer's data undergoes completeness validation:

- **Qualitas**: Verify that only records with `Activo = 1` are included
- **HDI**: Confirm that brand JOINs are successful for all records
- **GNP**: Validate that year casting succeeds for all records (using TRY_CAST)

### Schema Conformance

The extracted data is validated against the expected schema, checking for:

- Correct data types (e.g., year as integer, not string)
- Required fields present and non-null where expected
- Value ranges (e.g., year between 2000-2030)
- Transmission values limited to 'AUTO', 'MANUAL', or NULL

### Anomaly Detection

Statistical analysis identifies anomalies:

- Unexpectedly high or low record counts
- Unusual distributions of transmission types
- Outliers in year distribution
- Duplicate records based on canonical identifiers

For GNP, additional validation detects cross-brand contamination in the `VersionCorta` field, flagging records that mention brands not matching the `marca` field.

**Section sources**
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L1-L333)
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L1-L525)
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L1-L281)

## Conclusion

The data extraction phase is a critical foundation for the vehicle catalog homologation process, requiring insurer-specific SQL queries that account for significant variations in schema design, data quality, and business rules. The strategies for Qualitas, HDI, and GNP illustrate a spectrum of data quality challenges, from Qualitas's high-volume, low-activity dataset to HDI's clean, structured data and GNP's problematic, unstructured records. Effective extraction queries filter for active records where possible, select only relevant fields, handle source-specific quirks, and structure output for downstream normalization in n8n. Performance considerations such as avoiding full table scans and enabling batch processing are essential for reliable integration. The extracted data is then subjected to rigorous validation to ensure quality before normalization into a canonical format. Continued monitoring and refinement of extraction queries will be necessary as source systems evolve and data quality issues are addressed.

**Section sources**
- [qualitas-analisis.md](file://src/insurers/qualitas/qualitas-analisis.md#L1-L333)
- [hdi-analisis.md](file://src/insurers/hdi/hdi-analisis.md#L1-L525)
- [gnp-analisis.md](file://src/insurers/gnp/gnp-analisis.md#L1-L281)