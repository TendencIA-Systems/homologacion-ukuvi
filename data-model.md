## Core Entities

### ZurichVehicleRecord

**Description**: Raw vehicle record extracted from Zurich database
**Fields**:

- `id_original`: String - Zurich's internal vehicle ID (fiId)
- `marca`: String - Vehicle brand name from Zurich.Marcas.fcMarca
- `modelo`: String - Vehicle model name from Zurich.SubMarcas.fcSubMarca
- `anio`: Number - Model year from Zurich.Version.fiModelo (2000-2030)
- `version_original`: String - Original version string from VersionCorta or fcVersion
- `transmision_codigo`: Number - Transmission code (1=Manual, 2=Auto, 0=Unspecified)
- `transmision`: String - Normalized transmission ('MANUAL', 'AUTO', NULL)
- `activo`: Number - Active flag (always 1 for Zurich)
  **Validation Rules**:
- `anio` must be between 2000 and 2030
- `marca` and `modelo` cannot be empty or null
- `id_original` must be unique within extraction batch

### NormalizedVehicleRecord

**Description**: Processed and normalized vehicle record ready for homologation
**Fields**:

- `origen_aseguradora`: String - Insurance provider supplying the record
- `id_original`: String - Preserved from source record
- `marca_normalizada`: String - Trimmed and standardized brand name
- `modelo_normalizado`: String - Trimmed and standardized model name
- `anio`: Number - Validated model year
- `version_limpia`: String - Version string cleaned of comfort/safety tokens and duplicate model names, with door and occupant counts translated
- `transmision`: String - Normalized transmission value
- `hash_comercial`: String - SHA-256 hash of marca + modelo + anio + transmision
- `fecha_procesamiento`: DateTime - Processing timestamp
- `errores_validacion`: Array - Validation errors encountered
  **Validation Rules**:
- `hash_comercial` must be unique within processing batch
- `version_limpia` cannot be empty after normalization

### HomologatedVehicleEntry

**Description**: Final homologated record in master catalog
**Fields**:

- `id`: BIGSERIAL - Auto-generated primary key
- `hash_comercial`: String - Commercial hash for matching
- `marca`: String - Standardized brand name
- `modelo`: String - Standardized model name
- `anio`: Number - Model year
- `transmision`: String - Standardized transmission
- `version`: String - Normalized version string
- `version_tokens`: TSVECTOR - Text-search vector generated from `version`
- `version_tokens_array`: Array<String> - Distinct normalized tokens used for overlap scoring
- `disponibilidad`: JSONB - Availability and provenance by insurer (stores per-insurer `confianza_score` and `version_original`)
- `fecha_creacion`: DateTime - Record creation timestamp
- `fecha_actualizacion`: DateTime - Last update timestamp
  **JSONB Structure**:

```javascript
disponibilidad: {
  "ZURICH": {
    "aseguradora": "ZURICH",
    "id_original": "12345",
    "version_original": "ADVANCE SEDAN AUT 145HP 2L 4CIL 4P 5OCUP",
    "disponible": true,
    "confianza_score": 1.0,
    "origen": true,
    "fecha_actualizacion": "2025-01-13T10:00:00Z"
  }
}
// Each insurer entry stores provenance, availability and scoring metadata
// for traceability and incremental catalog updates
```

## State Transitions

### Extraction State

```
Raw Zurich Data → ZurichVehicleRecord
- Validation: Check required fields
- Transformation: Map database fields to entity
- Error handling: Log invalid records
```

### Normalization State

```
ZurichVehicleRecord → NormalizedVehicleRecord
- Brand/Model normalization: Trim, standardize case
- Version cleaning: Remove comfort/security tokens and duplicate model names
- Door and occupant translation: `3P`→`3PUERTAS`, `5OCUP` stays appended
- Transmission mapping: Convert codes to standard values or infer from version
- Hash generation: Create commercial hash
```

### Homologation State

```
NormalizedVehicleRecord → HomologatedVehicleEntry
- Hash lookup: Search existing records by commercial hash
- Token overlap: Compare normalized token sets to compute intersection ratio
Decision logic:
  - Exact hash match + high combined score (≥0.92 same insurer, ≥0.50 cross insurer): Update availability
  - Exact hash match + low overlap: Create new variant
  - No hash match: Create new entry
  - Availability update: Add insurer to availability list
```

## Relationships

### One-to-Many: ZurichVehicleRecord → NormalizedVehicleRecord

- Multiple Zurich records may normalize to same hash (duplicates)
- Deduplication occurs at normalization stage
- Latest record by processing timestamp takes precedence

### Many-to-One: NormalizedVehicleRecord → HomologatedVehicleEntry

- Multiple insurer records may match to same homologated entry
- Token-overlap scoring determines relationship strength
- Availability JSONB tracks all contributing insurers

## Data Quality Rules

### Required Fields Validation

```javascript
function validateZurichRecord(record) {
  const errors = [];
  if (!record.marca || record.marca.trim() === "") {
    errors.push("marca is required");
  }
  if (!record.modelo || record.modelo.trim() === "") {
    errors.push("modelo is required");
  }
  if (!record.anio || record.anio < 2000 || record.anio > 2030) {
    errors.push("anio must be between 2000-2030");
  }
  return {
    isValid: errors.length === 0,
    errors,
  };
}
```

### Normalization Quality Checks

```javascript
function validateNormalizedRecord(record) {
  const warnings = [];
  if (!record.version_limpia || record.version_limpia.trim() === "") {
    warnings.push("version_limpia is empty after normalization");
  }
  if (!record.hash_comercial || record.hash_comercial.length !== 64) {
    warnings.push("Invalid hash_comercial format");
  }
  return warnings;
}
```

## Performance Considerations

### Batch Processing Sizes

- **Extraction batch**: 5,000 records per n8n Code node execution
- **Normalization batch**: Process all extracted records in single pass
- **Homologation batch**: 50,000 records per Supabase RPC call

### Memory Management

- Use streaming processing for large datasets
- Clear processed batches from memory after each iteration
- Monitor n8n payload limits (16MB maximum)

### Database Optimization

- Index on `hash_comercial` for fast lookups
- GIN index on `disponibilidad` JSONB for insurer queries
- Trigram index on `version` (legacy fuzzy support) and GIN index on `version_tokens` for token overlap comparisons

### Revised `catalogo_homologado` table

```sql
create table public.catalogo_homologado (
  id bigserial primary key,
  hash_comercial varchar(64) not null,
  marca varchar(100) not null,
  modelo varchar(150) not null,
  anio integer not null check (anio between 2000 and 2030),
  transmision varchar(20) null,
  version varchar(200) null,
  version_tokens tsvector,
  version_tokens_array text[],
  disponibilidad jsonb default '{}'::jsonb,
  fecha_creacion timestamptz default now(),
  fecha_actualizacion timestamptz default now(),
  unique (hash_comercial, version)
);
create index if not exists idx_hash_comercial_hom on public.catalogo_homologado (hash_comercial);
create index if not exists idx_version_trgm_hom on public.catalogo_homologado using gin (version gin_trgm_ops);
create index if not exists idx_version_tokens_hom on public.catalogo_homologado using gin (version_tokens);
create index if not exists idx_disponibilidad_gin_hom on public.catalogo_homologado using gin (disponibilidad);
```

## Error Handling Strategies

### Validation Errors

- Continue processing with error flagged records
- Log validation errors for manual review
- Preserve original record data for debugging

### Processing Errors

- Isolate failed records to prevent batch failure
- Retry logic for transient errors
- Dead letter queue for persistent failures

### Data Integrity

- Foreign key constraints on reference data
- Check constraints on year ranges and enum values
- Unique constraints on hash_comercial within batches
