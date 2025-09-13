# Database Schema Design

<cite>
**Referenced Files in This Document**   
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento%20homologacion.md)
- [Tabla maestra.sql](file://src/supabase/Tabla%20maestra.sql)
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion%20RPC%20Nueva.sql)
- [Validacion y metricas.sql](file://src/supabase/Validacion%20y%20metricas.sql)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Core Data Model](#core-data-model)
3. [Primary Keys and Constraints](#primary-keys-and-constraints)
4. [Indexing Strategy](#indexing-strategy)
5. [Disponibilidad JSONB Field Structure](#disponibilidad-jsonb-field-structure)
6. [Data Deduplication and Conflict Resolution](#data-deduplication-and-conflict-resolution)
7. [Historical Tracking and Availability Management](#historical-tracking-and-availability-management)
8. [Sample Data Entries](#sample-data-entries)
9. [Entity Relationship Diagram](#entity-relationship-diagram)
10. [Performance Considerations](#performance-considerations)

## Introduction

This document provides comprehensive documentation for the `catalogo_homologado` table and related schema elements in the vehicle catalog homogenization system. The schema is designed to unify vehicle catalogs from multiple insurance providers into a canonical model while maintaining traceability, availability status, and historical tracking. The system supports deduplication, conflict resolution, and efficient querying across brands, models, and years.

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento%20homologacion.md#L1-L20)

## Core Data Model

The `catalogo_homologado` table serves as the master vehicle catalog that consolidates data from multiple insurers. Each record represents a canonical vehicle configuration with normalized attributes and availability tracking per insurer.

### Field Definitions

**Identification Fields**
- **`id`**: BIGSERIAL PRIMARY KEY - Auto-incrementing surrogate key
- **`id_canonico`**: VARCHAR(64) UNIQUE NOT NULL - SHA-256 hash uniquely identifying the complete technical specification
- **`hash_comercial`**: VARCHAR(64) NOT NULL - SHA-256 hash of commercial attributes (marca, modelo, anio, transmision)

**Traceability Strings**
- **`string_comercial`**: TEXT NOT NULL - Pipe-delimited commercial identifier (e.g., "TOYOTA|YARIS|2020|AUTO")
- **`string_tecnico`**: TEXT NOT NULL - Pipe-delimited technical identifier including all specifications

**Normalized Master Data**
- **`marca`**: VARCHAR(100) NOT NULL - Normalized brand name
- **`modelo`**: VARCHAR(150) NOT NULL - Normalized model name
- **`anio`**: INTEGER NOT NULL CHECK (anio BETWEEN 2000 AND 2030) - Model year with validation constraint
- **`transmision`**: VARCHAR(20) CHECK (transmision IN ('AUTO','MANUAL', NULL)) - Transmission type
- **`version`**: VARCHAR(200) - Normalized version name
- **`motor_config`**: VARCHAR(50) - Engine configuration (L4, V6, V8, ELECTRIC, HYBRID, MHEV, PHEV)
- **`carroceria`**: VARCHAR(50) - Body type (SEDAN, SUV, HATCHBACK, PICKUP, COUPE, VAN, WAGON)
- **`traccion`**: VARCHAR(20) - Drive type (4X4, 4X2, AWD, FWD, RWD)

**Availability and Metadata**
- **`disponibilidad`**: JSONB DEFAULT '{}' - Per-insurer availability status and metadata
- **`confianza_score`**: DECIMAL(3,2) DEFAULT 1.0 - Confidence score in data accuracy
- **`fecha_creacion`**: TIMESTAMP DEFAULT NOW() - Creation timestamp
- **`fecha_actualizacion`**: TIMESTAMP DEFAULT NOW() - Last update timestamp

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento%20homologacion.md#L47-L91)
- [Tabla maestra.sql](file://src/supabase/Tabla%20maestra.sql#L4-L99)

## Primary Keys and Constraints

The schema implements multiple constraints to ensure data integrity and support the homogenization process.

### Primary Key
- **`id`**: BIGSERIAL PRIMARY KEY provides a stable surrogate key for database operations
- **`id_canonico`**: VARCHAR(64) UNIQUE constraint ensures each technical configuration exists only once

### Check Constraints
- **`anio`**: CHECK constraint limits values to the range 2000-2030, preventing invalid years
- **`transmision`**: CHECK constraint restricts values to 'AUTO', 'MANUAL', or NULL

### Unique Constraints
- **`id_canonico`**: UNIQUE constraint prevents duplicate canonical entries, serving as the primary deduplication mechanism

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento%20homologacion.md#L47-L91)

## Indexing Strategy

The schema includes multiple indexes optimized for different query patterns and performance requirements.

### Index Definitions
```sql
CREATE INDEX idx_marca_modelo_anio_hom ON catalogo_homologado(marca, modelo, anio);
CREATE INDEX idx_hash_comercial_hom ON catalogo_homologado(hash_comercial);
CREATE INDEX idx_disponibilidad_gin_hom ON catalogo_homologado USING GIN(disponibilidad);
CREATE INDEX idx_id_canonico_hom ON catalogo_homologado(id_canonico);
```

### Index Purpose
- **`idx_marca_modelo_anio_hom`**: Optimized for queries filtering by brand, model, and year combinations
- **`idx_hash_comercial_hom`**: Supports fast lookups by commercial hash for deduplication
- **`idx_disponibilidad_gin_hom`**: GIN index enables efficient querying within the JSONB availability field
- **`idx_id_canonico_hom`**: Accelerates lookups by canonical ID, critical for upsert operations

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento%20homologacion.md#L88-L101)

## Disponibilidad JSONB Field Structure

The `disponibilidad` JSONB field tracks per-insurer availability status and metadata, enabling comprehensive traceability.

### Field Structure
```json
{
  "QUALITAS": {
    "activo": true,
    "id_original": "372340",
    "version_original": "ADVANCE 5P L4 1.5T AUT., 05 OCUP.",
    "fecha_actualizacion": "2025-01-15T10:00:00Z"
  },
  "HDI": {
    "activo": true,
    "id_original": "HDI_3787",
    "version_original": "YARIS CORE L4 5.0 SUV",
    "fecha_actualizacion": "2025-01-15T10:00:00Z"
  }
}
```

### Key Properties
- **Insurer Code**: Top-level key represents the insurance provider (e.g., QUALITAS, HDI)
- **`activo`**: Boolean indicating whether the insurer currently offers this vehicle
- **`id_original`**: Original identifier from the insurer's system
- **`version_original`**: Original version description as provided by the insurer
- **`fecha_actualizacion`**: Timestamp of last update from the insurer

### Availability Rules
- A vehicle is considered **active** if at least one insurer reports `activo=true`
- Inactive status (`activo=false`) is preserved with metadata for historical tracking
- The RPC function updates availability without deleting records, maintaining history

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento%20homologacion.md#L69-L87)

## Data Deduplication and Conflict Resolution

The system implements a sophisticated deduplication and conflict resolution strategy to maintain data integrity.

### Canonical Identification
- **`hash_comercial`**: Generated from normalized `(marca|modelo|anio|transmision)`
- **`id_canonico`**: Generated from normalized `(hash_comercial|version|motor_config|carroceria|traccion)`
- Normalization includes: UPPER case, trimming, removing double spaces, and mapping abbreviations

### Deduplication Process
1. **Exact Match**: Records with matching `id_canonico` are updated rather than inserted
2. **Compatible Match**: Records with matching commercial attributes but missing technical details can enrich existing entries
3. **New Entry**: Records without matches are inserted as new canonical entries

### Conflict Resolution
- **Transmission/Version Conflicts**: Require exact matches; differences create separate entries
- **Technical Specification Conflicts**: Conflicts in motor_config, carroceria, or traccion are detected and logged
- **Multiple Matches**: When multiple potential matches exist, a new record is created with reduced confidence score

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento%20homologacion.md#L103-L108)
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion%20RPC%20Nueva.sql#L1-L429)

## Historical Tracking and Availability Management

The schema supports comprehensive historical tracking of vehicle availability across insurers.

### Active/Inactive Definition
- **Active (per insurer)**: The insurer declares the vehicle as currently offerable
- **Inactive (per insurer)**: The insurer has discontinued or removed the vehicle from their catalog
- **Globally Active**: A canonical entry is active if at least one insurer reports it as active

### Persistence Rules
- The RPC function **never deletes** records; it only updates the `disponibilidad` field
- Inactivation updates preserve `id_original` and `version_original` while setting `activo=false`
- Reactivation updates set `activo=true` and refresh the `fecha_actualizacion` timestamp

### Deprecation Strategy
- Records where **all insurers** report `activo=false` for more than N days (e.g., 180) can be marked for archival
- This separate job prevents premature removal of temporarily inactive vehicles

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento%20homologacion.md#L110-L130)

## Sample Data Entries

The following examples illustrate how multiple insurer records merge into a single canonical entry.

### Example 1: Multiple Insurers for Same Vehicle
```json
{
  "id_canonico": "66b4fe23a96e8de9b1dac624069d9a03f96d3f17d7319673621254cb42c651dc",
  "hash_comercial": "7cc9374cee0e1c1bc8638521b2690cb010dae9729134790042f19c05346f8d45",
  "string_comercial": "ACURA|ADX|2025|AUTO",
  "string_tecnico": "ACURA|ADX|2025|AUTO|ADVANCE|L4|SUV",
  "marca": "ACURA",
  "modelo": "ADX",
  "anio": 2025,
  "transmision": "AUTO",
  "version": "ADVANCE",
  "motor_config": "L4",
  "carroceria": "SUV",
  "traccion": null,
  "disponibilidad": {
    "QUALITAS": {
      "activo": true,
      "id_original": "372340",
      "version_original": "ADVANCE 5P L4 1.5T AUT., 05 OCUP.",
      "fecha_actualizacion": "2025-01-15T10:00:00Z"
    },
    "HDI": {
      "activo": true,
      "id_original": "HDI_3787",
      "version_original": "YARIS CORE L4 5.0 SUV",
      "fecha_actualizacion": "2025-01-15T10:00:00Z"
    }
  }
}
```

### Example 2: Mixed Active/Inactive Status
```json
{
  "id_canonico": "5955a60b6849b49cd47478385fa2948dcea4f55e5017493e73c0af58b743fd4d",
  "hash_comercial": "7cc9374cee0e1c1bc8638521b2690cb010dae9729134790042f19c05346f8d45",
  "string_comercial": "ACURA|ADX|2025|AUTO",
  "string_tecnico": "ACURA|ADX|2025|AUTO|A-SPEC|L4|SUV",
  "marca": "ACURA",
  "modelo": "ADX",
  "anio": 2025,
  "transmision": "AUTO",
  "version": "A-SPEC",
  "motor_config": "L4",
  "carroceria": "SUV",
  "traccion": null,
  "disponibilidad": {
    "QUALITAS": {
      "activo": false,
      "id_original": "372341",
      "version_original": "A-SPEC 5P L4 1.5T AUT., 05 OCUP.",
      "fecha_actualizacion": "2025-01-15T10:00:00Z"
    },
    "ZURICH": {
      "activo": true,
      "id_original": "ZUR_8890",
      "version_original": "A-SPEC 2025 AUT",
      "fecha_actualizacion": "2025-01-15T10:00:00Z"
    }
  }
}
```

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento%20homologacion.md#L132-L200)

## Entity Relationship Diagram

```mermaid
erDiagram
CATALOGO_HOMOLOGADO {
bigint id PK
varchar(64) id_canonico UK
varchar(64) hash_comercial
text string_comercial
text string_tecnico
varchar(100) marca
varchar(150) modelo
integer anio
varchar(20) transmision
varchar(200) version
varchar(50) motor_config
varchar(50) carroceria
varchar(20) traccion
jsonb disponibilidad
decimal(3,2) confianza_score
timestamp fecha_creacion
timestamp fecha_actualizacion
}
INSURER_DATA {
varchar(50) insurer_name PK
varchar(100) id_original PK
boolean activo
text version_original
timestamp fecha_actualizacion
}
CATALOGO_HOMOLOGADO ||--o{ INSURER_DATA : "contains"
```

**Diagram sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento%20homologacion.md#L47-L91)
- [Tabla maestra.sql](file://src/supabase/Tabla%20maestra.sql#L4-L99)

## Performance Considerations

The schema design incorporates several performance optimizations for handling large datasets.

### Query Performance
- **Brand/Model/Year Queries**: The composite index `idx_marca_modelo_anio_hom` enables efficient filtering
- **Hash Lookups**: Dedicated indexes on `hash_comercial` and `id_canonico` support O(log n) lookups
- **JSONB Queries**: The GIN index on `disponibilidad` allows efficient querying of insurer-specific data

### Batch Processing
- The RPC function processes batches of 10k-50k records for optimal throughput
- Idempotent design allows safe reprocessing of batches
- Temporary staging table minimizes lock contention during processing

### Scalability Recommendations
- **Partitioning**: Consider range partitioning by `anio` for very large datasets
- **Materialized Views**: Create views for active vehicles only to improve common query performance
- **Index Maintenance**: Regularly analyze and vacuum the GIN index on the JSONB field
- **Connection Pooling**: Use connection pooling for n8n to Supabase communication

### Validation Metrics
The system includes validation queries to monitor homogenization quality:
- Percentage of vehicles covered by 2+ insurers
- Average number of insurers per vehicle
- Maximum number of insurers covering a single vehicle

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento%20homologacion.md#L5-L279)
- [Validacion y metricas.sql](file://src/supabase/Validacion%20y%20metricas.sql#L0-L18)