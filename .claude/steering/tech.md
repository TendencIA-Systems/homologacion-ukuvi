# Technology Steering Document

## Architecture Overview

```
Insurance Databases (11 sources)
           ↓
      SQL Extraction (per insurer)
           ↓
     n8n Workflows (normalization)
           ↓
   Batch Processing (5k-50k records)
           ↓
  Supabase RPC Functions (intelligent matching)
           ↓
  Master Catalog (catalogo_homologado)
```

## Core Technology Stack

### Backend & Database
- **Database**: Supabase (PostgreSQL 13+)
- **RPC Framework**: PostgreSQL PL/pgSQL stored procedures
- **Connection Method**: REST API via `/rest/v1/rpc/` endpoints
- **Key Feature**: JSONB for flexible per-insurer metadata storage

### ETL & Data Processing
- **Orchestration**: n8n workflows for extraction, transformation, and loading
- **Normalization**: JavaScript Code nodes in n8n for data transformation
- **Batch Processing**: Chunked processing (5,000-50,000 records per batch)
- **Error Handling**: Isolated error recording without batch failure propagation

### Languages & Patterns
- **SQL**: Data extraction queries and PostgreSQL function implementations
- **JavaScript**: n8n normalization code and batch processing logic
- **Python**: Utility scripts and data validation
- **JSON**: Workflow definitions and configuration

## Data Model Patterns

### Hash-Based Deduplication
```
hash_comercial = SHA-256(marca | modelo | anio | transmision)
```
Used for initial vehicle grouping within insurance companies.

### Token-Overlap Matching
```
Token Overlap = |existing_tokens ∩ incoming_tokens| / max(|existing|, |incoming|)
Thresholds:
  - Same insurer reprocessing: ≥0.92
  - Cross-insurer matching: ≥0.50
```

### Canonical Record Structure
```json
{
  "id": "BIGSERIAL",
  "id_canonico": "SHA-256 hash of complete record",
  "hash_comercial": "SHA-256(marca|modelo|anio|transmision)",
  "marca": "standardized brand",
  "modelo": "standardized model",
  "anio": 2020,
  "transmision": "MANUAL|AUTO|null",
  "version": "INTEGRATED SPECS: TRIM BODY POWER DISPLACEMENT CYLINDERS DOORS TRACTION",
  "version_tokens_array": ["trim", "body", "power", "displacement", ...],
  "string_comercial": "original format for traceability",
  "string_tecnico": "detailed specs for debugging",
  "version_original": "preserved raw data",
  "id_original": "source system ID",
  "disponibilidad": {"qualitas": {...}, "zurich": {...}},
  "origen_aseguradora": "source insurer",
  "activo": true,
  "fecha_actualizacion": "2024-10-17T12:00:00Z"
}
```

## Key Technical Decisions

### All-in-One Version String
- **Decision**: All technical specifications integrated into single `version` field
- **Rationale**: Flexibility across insurer formats, reduces schema changes
- **Format**: `[TRIM] [BODY] [POWER] [DISPLACEMENT] [CYLINDERS] [DOORS] [TRACTION]`
- **Example**: `"ADVANCE SEDAN 145HP 2L 4CIL 4PUERTAS AWD"`

### Immutable Original Data
- **Decision**: Preserve `version_original` and `id_original` for all records
- **Rationale**: Enables audit trails and debugging of normalization issues
- **Access**: Stored but not used in matching algorithms

### Per-Insurer Availability Tracking
- **Decision**: JSONB `disponibilidad` field instead of separate status records
- **Rationale**: Single record per vehicle with flexible per-insurer metadata
- **Benefit**: Supports adding new insurers without schema changes

### Token Deduplication
- **Decision**: Deduplicate token array before similarity calculation
- **Rationale**: Prevents inflated overlap scores from duplicate tokens
- **Exception**: Preserve hyphenated trims (A-SPEC, TYPE-S, S-LINE)

## Algorithm & Processing

### Best-Match Selection (Critical Fix)
```
1. Find all candidates with same hash_comercial
2. Calculate coverage score for each candidate
3. Select candidate with HIGHEST score
4. Tiebreaker: same insurer → most recent
5. Update ONLY selected candidate
6. Create new record if no match exceeds threshold
```

### Normalization Pipeline (Per Insurer)
```
1. Validate input record structure
2. Standardize marca (brand consolidation map)
3. Normalize modelo (remove prefixes/suffixes)
4. Extract transmission (recovery from contaminated fields)
5. Clean version string (remove features, escape chars)
6. Generate hash_comercial (SHA-256)
7. Generate id_canonico (SHA-256 full record)
8. Deduplicate tokens intelligently
9. Prepare batch payload
```

### Batch Processing
```
1. Split records into BATCH_SIZE (5,000) chunks
2. Validate each batch before submission
3. Submit to Supabase RPC endpoint
4. Record response metrics (new/updated/matched counts)
5. Collect warnings and errors
6. Continue with next batch even if one fails
```

## Integration Points

### n8n → Supabase RPC
- **Endpoint**: `POST /rest/v1/rpc/procesar_batch_vehiculos`
- **Payload**: Array of normalized vehicle records in JSONB format
- **Response**: Processing metrics and conflict warnings

### Data Source Connection
- **Method**: SQL extraction queries per insurer
- **Schedule**: Configurable via n8n workflows
- **Error Handling**: Connection retry logic with exponential backoff

## Performance Requirements

- **Batch Processing**: <5 minutes for 50,000 records
- **Token Matching**: Indexed queries using GIN on `version_tokens_array`
- **Memory Usage**: Managed batch sizes to prevent OOM
- **Concurrency**: Support parallel processing of different insurers

## Testing Framework

### Test Types
1. **Unit Tests**: JavaScript normalization functions (Jest)
2. **Integration Tests**: SQL RPC function behavior
3. **Validation Tests**: Data quality checks after normalization
4. **Performance Tests**: Batch processing benchmarks
5. **Idempotency Tests**: Verify re-running same batch produces identical results

### Test Data
- Sample records from each insurer covering edge cases
- Duplicates to verify matching logic
- Cross-insurer vehicles for token overlap validation

## Security & Access

- **Database Access**: PostgreSQL credentials in `.env` (not committed)
- **API Authentication**: Supabase service role key for RPC calls
- **Audit Logging**: All updates tracked via `fecha_actualizacion` timestamps
- **Data Retention**: No deletion; inactivation via `activo` flag

## Development Tools

- **n8n Instance**: Self-hosted or cloud deployment
- **PostgreSQL Client**: psql or Supabase dashboard
- **Version Control**: Git for normalization code and SQL functions
- **Logging**: Structured logging via n8n nodes and PostgreSQL functions
