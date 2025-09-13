# Table Structure

<cite>
**Referenced Files in This Document**   
- [Tabla maestra.sql](file://src/supabase/Tabla maestra.sql)
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md)
- [Validacion y metricas.sql](file://src/supabase/Validacion y metricas.sql)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Core Field Definitions](#core-field-definitions)
3. [Technical Attributes](#technical-attributes)
4. [Metadata and Provenance](#metadata-and-provenance)
5. [Constraints and Indexes](#constraints-and-indexes)
6. [Generated Columns](#generated-columns)
7. [Data Consolidation Examples](#data-consolidation-examples)
8. [Schema Evolution and Design Rationale](#schema-evolution-and-design-rationale)
9. [Conflict Resolution and Upsert Logic](#conflict-resolution-and-upsert-logic)
10. [Performance and Query Optimization](#performance-and-query-optimization)

## Introduction
The `vehiculos_maestro` table serves as the canonical vehicle catalog that consolidates data from multiple insurance providers into a unified, normalized structure. This document details the schema design, field semantics, constraints, and operational logic that enable reliable data homogenization, provenance tracking, and efficient querying. The structure supports a master data management system where disparate insurer records are merged into single canonical entries using deterministic hashing and conflict resolution rules.

**Section sources**
- [Tabla maestra.sql](file://src/supabase/Tabla maestra.sql#L1-L100)
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L47-L91)

## Core Field Definitions

### id_canonico
Unique canonical identifier for each vehicle variant, serving as the primary key. This value is used in external systems such as multiquoting platforms to reference standardized vehicle configurations.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L6)

### hash_comercial
Deterministic hash derived from normalized values of `marca`, `modelo`, `anio`, and `transmision`. Used for grouping similar commercial variants across insurers before full canonical consolidation.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L18)

### marca
Normalized brand name (e.g., TOYOTA, HONDA). Enforced as NOT NULL to ensure every entry has a defined manufacturer.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L10)

### modelo
Normalized model name (e.g., YARIS, CIVIC). Required field ensuring consistent representation of vehicle models across sources.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L11)

### anio
Manufacturing year of the vehicle. Stored as integer with NOT NULL constraint to prevent ambiguous or missing temporal context.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L12)

**Section sources**
- [Tabla maestra.sql](file://src/supabase/Tabla maestra.sql#L10-L18)

## Technical Attributes

### transmision
Transmission type, limited to values: AUTO, MANUAL, or NULL. Represents the drivetrain mechanism (automatic or manual gearbox).

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L13)

### version
Consolidated trim or version designation (e.g., EXCLUSIVE, PREMIUM). Normalized across insurers to unify marketing nomenclature.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L14)

### motor_config
Engine configuration such as L4, V6, V8, or NULL. Encodes cylinder layout and serves as a technical differentiator between variants.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L15)

### carroceria
Body style classification including SEDAN, SUV, PICKUP, HATCHBACK, or NULL. Used to categorize vehicle form factors consistently.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L16)

### traccion
Drive system specification: 4X4, 2WD, AWD, or NULL. Normalized value indicating the vehicle's traction capabilities.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L17)

**Section sources**
- [Tabla maestra.sql](file://src/supabase/Tabla maestra.sql#L13-L17)

## Metadata and Provenance

### disponibilidad_aseguradoras
JSONB field storing per-insurer availability status and original data. Each key corresponds to an insurer (e.g., HDI, QUALITAS), containing:
- `activo`: boolean indicating current offer status
- `id_original`: source system identifier
- `hash_original`: source-specific hash
- `version_original`: raw version string from insurer
- `datos_originales`: additional technical attributes from source
- `fecha_actualizacion`: timestamp of last update

This structure enables full traceability of data lineage and supports reconciliation workflows.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L19-L45)

### metadata_homologacion
JSONB field capturing homologation process metadata:
- `metodo`: method used (EXACTO, FUZZY, ENRIQUECIDO)
- `confianza`: confidence score (0.0–1.0) in consolidation accuracy
- `fuente_enriquecimiento`: insurer providing enriched data
- `campos_inferidos`: list of fields inferred during consolidation
- `fecha_consolidacion`: timestamp of last consolidation

This field supports auditability and quality assessment of the homogenization process.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L66-L75)

**Section sources**
- [Tabla maestra.sql](file://src/supabase/Tabla maestra.sql#L19-L75)
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L72-L75)

## Constraints and Indexes

### Primary Key Constraint
The `id_canonico` field is defined as the primary key, ensuring global uniqueness of canonical vehicle entries.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L6)

### NOT NULL Constraints
Core descriptive fields (`marca`, `modelo`, `anio`, `hash_comercial`) are enforced as NOT NULL to maintain data integrity and completeness.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L10-L12)

### Check Constraints
While not explicitly defined in the current schema, business rules restrict `transmision` to predefined values (AUTO/MANUAL) and `carroceria`/`traccion` to standardized codes.

[SPEC SYMBOL](file://src/supabase/Replanteamiento homologacion.md#L58-L59)

### Indexes
Multiple indexes optimize query performance:
- `idx_marca_modelo_anio`: composite index on marca, modelo, anio for common filtering
- `idx_hash_comercial`: index on hash_comercial for fast grouping
- `idx_aseguradoras_activas`: GIN index on aseguradoras_activas array for insurer-based searches
- `idx_disponibilidad`: GIN index on disponibilidad_aseguradoras JSONB for deep querying

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L82-L85)

**Section sources**
- [Tabla maestra.sql](file://src/supabase/Tabla maestra.sql#L6-L85)

## Generated Columns

### aseguradoras_activas
Generated column that extracts the list of active insurers from `disponibilidad_aseguradoras`. Computed as:
```sql
ARRAY(SELECT key FROM jsonb_each(disponibilidad_aseguradoras) WHERE (value->>'activo')::boolean = true)
```
Stored physically for fast lookup and filtering without JSON parsing overhead.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L57-L64)

This column enables efficient queries such as "find all vehicles offered by at least two insurers" and supports homologation quality metrics.

[SPEC SYMBOL](file://src/supabase/Validacion y metricas.sql#L4-L7)

**Section sources**
- [Tabla maestra.sql](file://src/supabase/Tabla maestra.sql#L57-L64)
- [Validacion y metricas.sql](file://src/supabase/Validacion y metricas.sql#L4-L7)

## Data Consolidation Examples

### Sample Entry: Toyota Yaris
```json
{
  "id_canonico": "66b4fe23a96e8de9b1dac624069d9a03f96d3f17d7319673621254cb42c651dc",
  "marca": "TOYOTA",
  "modelo": "YARIS",
  "anio": 2020,
  "transmision": "AUTO",
  "version": "CORE",
  "motor_config": "L4",
  "carroceria": "SEDAN",
  "traccion": "FWD",
  "disponibilidad_aseguradoras": {
    "HDI": {
      "activo": true,
      "id_original": "HDI_3787",
      "version_original": "YARIS CORE L4 5.0 SUV"
    },
    "QUALITAS": {
      "activo": true,
      "id_original": "Q_156789",
      "version_original": "YARIS PREMIUM 1.5L SEDAN"
    }
  }
}
```

This example shows how two different insurer representations (HDI and QUALITAS) of similar Toyota Yaris variants are merged into a single canonical entry with preserved source provenance.

**Section sources**
- [Tabla maestra.sql](file://src/supabase/Tabla maestra.sql#L19-L45)

## Schema Evolution and Design Rationale

The current `vehiculos_maestro` schema evolved from an earlier design documented in `Replanteamiento homologacion.md`, which proposed a table named `catalogo_homologado`. Key design decisions include:

- **Canonical Identification**: Use of `id_canonico` as primary key ensures stable references across systems.
- **Commercial Hashing**: `hash_comercial` enables grouping by core commercial attributes before full consolidation.
- **Provenance Preservation**: JSONB storage of source data allows non-destructive merging while retaining audit trails.
- **Active Availability Tracking**: Generated `aseguradoras_activas` column optimizes queries for currently offered vehicles.

The design supports incremental updates and idempotent processing through the RPC interface, enabling reliable batch ingestion from multiple insurers.

[SPEC SYMBOL](file://src/supabase/Replanteamiento homologacion.md#L47-L91)

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L47-L91)

## Conflict Resolution and Upsert Logic

The system employs upsert operations based on `id_canonico` to handle updates from multiple insurers. During ingestion:

1. If `id_canonico` does not exist: INSERT new record with consolidated attributes.
2. If `id_canonico` exists: UPDATE only if canonical fields have changed.
3. Merge `disponibilidad_aseguradoras` by updating the specific insurer's entry while preserving others.
4. Set `activo=false` for delisted variants rather than deleting records, maintaining historical availability.

This approach ensures data permanence, supports reactivation of previously inactive models, and enables time-series analysis of insurer offerings.

[SPEC SYMBOL](file://src/supabase/Replanteamiento homologacion.md#L108-L114)

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L108-L114)

## Performance and Query Optimization

The schema includes several performance-oriented features:

- **Composite Index**: `idx_marca_modelo_anio` accelerates common search patterns by make, model, and year.
- **GIN Indexes**: On both `aseguradoras_activas` and `disponibilidad_aseguradoras` enable fast array and JSON queries.
- **Generated Column**: `aseguradoras_activas` avoids runtime JSON parsing for insurer availability checks.
- **Trigger Automation**: Automatic `fecha_actualizacion` updates reduce application logic complexity.

These optimizations support high-throughput ingestion and low-latency querying in production environments.

[SPEC SYMBOL](file://src/supabase/Tabla maestra.sql#L82-L85)

**Section sources**
- [Tabla maestra.sql](file://src/supabase/Tabla maestra.sql#L82-L85)
- [Tabla maestra.sql](file://src/supabase/Tabla maestra.sql#L87-L99)