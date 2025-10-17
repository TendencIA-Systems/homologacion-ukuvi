# id_canonico Calculation

<cite>
**Referenced Files in This Document**   
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js)
- [qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Normalization Process](#normalization-process)
3. [Hash Generation Logic](#hash-generation-logic)
4. [id_canonico as Primary Key](#id_canonico-as-primary-key)
5. [Edge Cases and Data Completeness](#edge-cases-and-data-completeness)
6. [Performance Considerations](#performance-considerations)

## Introduction

The `id_canonico` serves as a unique canonical identifier for vehicle grouping across multiple insurers in the homologation system. This identifier is generated through a deterministic hashing process that ensures functionally identical vehicles from different insurance providers are assigned the same `id_canonico`, enabling effective deduplication and standardization in the `catalogo_homologado` table. The hash is computed using SHA-256 on a normalized combination of key vehicle attributes, with consistent preprocessing applied to ensure cross-source consistency.

**Section sources**
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js#L1-L50)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L1-L50)

## Normalization Process

Before hash computation, vehicle attributes undergo a rigorous normalization process to ensure consistency across disparate data sources. The normalization pipeline applies the following transformations to each attribute:

- **Case Standardization**: All text is converted to uppercase using `.toUpperCase()`
- **Accent Removal**: Diacritical marks are stripped via Unicode normalization (`NFD`) and regex filtering
- **Character Sanitization**: Non-alphanumeric characters (except spaces and hyphens) are replaced with spaces
- **Whitespace Collapsing**: Multiple consecutive spaces are reduced to a single space
- **Trimming**: Leading and trailing whitespace is removed

This normalization is consistently implemented across all insurer-specific scripts using the `normalizarTexto` function. The process ensures that variations such as "Volkswagen", "VOLKSWAGEN", and "volkswagën" are all transformed into the standardized form "VOLKSWAGEN" before hashing.

Additionally, brand names are further normalized using synonym dictionaries to map common variations (e.g., "VW" → "VOLKSWAGEN", "MB" → "MERCEDES BENZ") to their canonical forms. Model names are processed to remove redundant brand prefixes (e.g., "TOYOTA COROLLA" becomes "COROLLA" when the brand is already specified separately).

**Section sources**
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js#L54-L100)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L54-L100)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L64-L100)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js#L64-L100)

## Hash Generation Logic

The `id_canonico` is generated using the SHA-256 cryptographic hash function applied to a pipe-delimited string of normalized vehicle attributes. The hash is created through the `generarHash` function, which is implemented consistently across all insurer normalization scripts with minor variations in null handling.

The function takes variable arguments representing vehicle attributes, filters out undefined, null, or empty values, joins them with a pipe (`|`) delimiter, converts the result to uppercase, and computes the SHA-256 hash:

```javascript
function generarHash(...componentes) {
  const texto = componentes
    .filter((c) => c !== undefined && c !== null && c !== "")
    .join("|")
    .toUpperCase();
  return crypto.createHash("sha256").update(texto).digest("hex");
}
```

The specific attributes included in the `id_canonico` calculation vary slightly by insurer but generally include: brand, model, year, transmission, version (trim), motor configuration, body type, and traction. For example, in the El Potosí implementation, the hash is generated from eight components:

```javascript
const idCanonico = generarHash(
  marcaNormalizada,
  modeloNormalizado,
  anio,
  transmisionNormalizada,
  versionTrim,
  motorConfig,
  carroceria,
  traccion
);
```

This comprehensive attribute set ensures that vehicles with identical specifications across insurers receive the same `id_canonico`, while meaningful differences in configuration result in different hashes, enabling precise vehicle grouping and deduplication.

**Section sources**
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js#L54-L60)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L48-L54)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L64-L70)
- [qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js#L28-L34)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js#L64-L67)

## id_canonico as Primary Key

The `id_canonico` serves as the primary key in the `catalogo_homologado` table, functioning as the central mechanism for vehicle deduplication and cross-insurer data integration. When records from different insurers are processed, their normalized attributes are hashed to generate the `id_canonico`. Vehicles with identical specifications across insurers produce the same hash value, allowing the system to recognize them as the same canonical vehicle.

This approach enables the creation of a unified vehicle catalog where multiple representations of the same vehicle (e.g., "Toyota Corolla 2020" from different insurers) are grouped under a single `id_canonico`. The hash-based primary key ensures referential integrity and eliminates data redundancy, as all insurer-specific records reference the same canonical vehicle entry.

The deterministic nature of the hashing process guarantees consistency: any vehicle with identical normalized attributes will always generate the same `id_canonico`, regardless of when or from which insurer it is processed. This stability is critical for maintaining data integrity across batch processing jobs and incremental updates to the catalog.

**Section sources**
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js#L569-L569)
- [qualitas-codigo-de-normalizacion-n8n.js](file://src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js#L929-L929)

## Edge Cases and Data Completeness

The system handles missing or incomplete data through consistent null filtering in the hash generation process. When attributes such as displacement (engine size) are missing, they are excluded from the hash computation rather than substituted with default values. This approach maintains hash stability across records with varying data completeness.

The `generarHash` function's filtering logic ensures that undefined, null, or empty string values do not affect the resulting hash. This means that a vehicle record with complete specifications and another from a different insurer with the same specifications but missing displacement data will still generate the same `id_canonico` if all other attributes match.

However, this approach creates a trade-off: vehicles that differ only in the presence or absence of displacement data may be incorrectly grouped together. The system prioritizes cross-insurer consistency over granular differentiation, assuming that displacement is rarely the sole differentiating factor between vehicle variants.

Insurers with particularly inconsistent data (such as GNP, which lacks an active status field) are processed with additional validation rules to prevent contamination of the canonical catalog. The normalization process includes insurer-specific cleaning rules to address known data quality issues, such as removing contaminating brand names from version fields.

**Section sources**
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L1-L50)
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js#L54-L60)

## Performance Considerations

The SHA-256 hash computation is designed to be efficient for large-scale batch processing of vehicle data. The normalization and hashing operations are implemented as pure functions without external dependencies, enabling parallel processing of records. Each insurer's normalization script processes records independently, allowing for horizontal scaling across multiple processing nodes.

The computational complexity of SHA-256 is O(n) with respect to input size, where n is the total length of concatenated attributes. Given that vehicle attribute strings are typically short (under 200 characters), the hashing overhead per record is minimal. The Node.js `crypto` module provides optimized implementations that leverage native cryptographic libraries for maximum performance.

For batch processing of large datasets, the system can process thousands of records per second on modest hardware. The primary performance bottleneck is typically I/O operations (reading source data and writing results) rather than the hash computation itself. The use of consistent normalization rules across insurers reduces the need for post-processing reconciliation, further improving overall throughput.

Memory usage is optimized by processing records in a streaming fashion within the n8n workflow environment, avoiding the need to load entire datasets into memory. Error handling is implemented to allow processing to continue even when individual records fail, ensuring that data quality issues in a small subset of records do not block the entire batch job.

**Section sources**
- [elpotosi-codigo-de-normalizacion.js](file://src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js#L1-L50)
- [gnp-codigo-de-normalizacion.js](file://src/insurers/gnp/gnp-codigo-de-normalizacion.js#L1-L50)
- [hdi-codigo-de-normalizacion.js](file://src/insurers/hdi/hdi-codigo-de-normalizacion.js#L1-L50)
- [zurich-codigo-de-normalizacion.js](file://src/insurers/zurich/zurich-codigo-de-normalizacion.js#L1-L50)