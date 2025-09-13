# RPC Function Reference

<cite>
**Referenced Files in This Document**   
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql)
- [Funcion RPC.sql](file://src/supabase/Funcion RPC.sql)
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md)
- [instrucciones.md](file://instrucciones.md)
- [casos de prueba función rpc.sql](file://src/supabase/casos de prueba función rpc.sql)
</cite>

## Table of Contents
1. [Function Overview](#function-overview)
2. [Function Signature](#function-signature)
3. [Input Parameters](#input-parameters)
4. [Return Values](#return-values)
5. [Upsert Logic and Conflict Handling](#upsert-logic-and-conflict-handling)
6. [JSONB Availability Field Merging](#jsonb-availability-field-merging)
7. [Input Validation and Error Handling](#input-validation-and-error-handling)
8. [Transaction Safety](#transaction-safety)
9. [Performance Considerations](#performance-considerations)
10. [Usage Examples](#usage-examples)
11. [Version Differences and Migration Guidance](#version-differences-and-migration-guidance)

## Function Overview

The `procesar_batch_homologacion` function is a Supabase RPC function designed to process batches of normalized vehicle records from multiple insurance providers. It serves as the core integration point between external data sources and the canonical vehicle catalog, enabling homogenization of disparate insurance catalogs into a unified master dataset.

The function implements a sophisticated matching and merging strategy that handles three primary scenarios: creating new vehicle entries, enriching existing entries with additional technical specifications, and updating availability information for existing vehicles. It maintains complete traceability by tracking which insurance provider contributed each piece of information through the JSONB disponibilidad field.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L0-L429)
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L1-L280)

## Function Signature

```sql
CREATE OR REPLACE FUNCTION public.procesar_batch_homologacion(
    p_vehiculos_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
```

The function accepts a single JSONB parameter containing a batch of vehicle records and returns a JSONB object with processing results, metrics, warnings, and errors. The SECURITY DEFINER setting allows the function to operate with elevated privileges, while the explicit search_path ensures consistent behavior regardless of the caller's schema search path.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L1-L10)

## Input Parameters

The function accepts a JSONB parameter `p_vehiculos_json` that can be structured in two ways:
1. Direct array of vehicle objects
2. Object with a "vehiculos_json" key containing the array of vehicle objects

Each vehicle record in the batch must contain the following fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id_canonico | VARCHAR(64) | Yes | SHA-256 hash of normalized vehicle specifications |
| hash_comercial | VARCHAR(64) | Yes | SHA-256 hash of commercial vehicle attributes |
| string_comercial | TEXT | Yes | Pipe-delimited string of commercial attributes |
| string_tecnico | TEXT | Yes | Pipe-delimited string of technical attributes |
| marca | VARCHAR(100) | Yes | Vehicle brand (normalized to uppercase) |
| modelo | VARCHAR(150) | Yes | Vehicle model (normalized to uppercase) |
| anio | INTEGER | Yes | Model year (must be between 2000 and 2030) |
| transmision | VARCHAR(20) | No | Transmission type (AUTO, MANUAL, or NULL) |
| version | VARCHAR(200) | No | Vehicle trim/version |
| motor_config | VARCHAR(50) | No | Engine configuration (L4, V6, etc.) |
| carroceria | VARCHAR(50) | No | Body type (SEDAN, SUV, HATCHBACK, etc.) |
| traccion | VARCHAR(20) | No | Drive type (4X4, 4X2, AWD, FWD, RWD) |
| origen_aseguradora | VARCHAR(50) | Yes | Source insurance provider |
| id_original | VARCHAR(100) | Yes | Original ID from source system |
| version_original | TEXT | No | Original version description from source |
| activo | BOOLEAN | Yes | Whether the vehicle is active in the provider's catalog |

The function performs initial validation to ensure the input is a valid JSONB array and that each record contains the required fields.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L11-L40)
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L47-L91)

## Return Values

The function returns a JSONB object containing comprehensive processing results:

```json
{
  "success": true,
  "received": 5,
  "staged": 5,
  "procesados": {
    "nuevos": 2,
    "enriquecidos": 1,
    "actualizados": 1,
    "conflictos": 0,
    "multiples_matches": 1
  },
  "warnings": [],
  "errors": []
}
```

The return structure includes:

| Field | Type | Description |
|-------|------|-------------|
| success | BOOLEAN | Overall success status of the operation |
| received | INTEGER | Number of records received in the input |
| staged | INTEGER | Number of records successfully loaded into the staging table |
| procesados | OBJECT | Detailed processing metrics |
| procesados.nuevos | INTEGER | Number of new vehicle records created |
| procesados.enriquecidos | INTEGER | Number of existing records enriched with additional specifications |
| procesados.actualizados | INTEGER | Number of existing records with updated availability |
| procesados.conflictos | INTEGER | Number of records that conflicted with existing entries |
| procesados.multiples_matches | INTEGER | Number of records with multiple potential matches |
| warnings | ARRAY | Array of warning messages |
| errors | ARRAY | Array of error messages (empty if success is true) |

In case of failure, the function returns a simplified error object with success=false and an error message describing the issue.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L375-L415)
- [casos de prueba función rpc.sql](file://src/supabase/casos de prueba función rpc.sql#L1-L256)

## Upsert Logic and Conflict Handling

The function implements a multi-phase upsert strategy using the `id_canonico` field as the primary conflict resolution key. The process follows these steps:

1. **Exact Match by id_canonico**: First, the function attempts to match incoming records with existing entries using the `id_canonico` field. When a match is found, the function updates only the availability information for the source insurance provider without modifying the canonical vehicle specifications.

2. **Compatibility Matching**: For records without an exact `id_canonico` match, the function performs a compatibility check based on core vehicle attributes (marca, modelo, anio) and exact matches on transmission and version (when specified). The function allows enrichment of technical specifications (motor_config, carroceria, traccion) when they are missing in the existing record.

3. **Conflict Detection**: The function identifies true conflicts when incoming records have incompatible specifications with existing entries (e.g., different transmission types, versions, or body styles). These conflicts are reported as warnings to alert data stewards of potential data quality issues.

```mermaid
flowchart TD
Start([Start Processing]) --> ValidateInput["Validate Input Format"]
ValidateInput --> CreateTemp["Create Temporary Staging Table"]
CreateTemp --> LoadData["Load and Normalize Batch Data"]
LoadData --> ExactMatch["Search for Exact id_canonico Matches"]
ExactMatch --> UpdateAvailability["Update Availability for Matches"]
UpdateAvailability --> CompatibilityCheck["Check for Compatible Vehicles"]
CompatibilityCheck --> EnrichRecords["Enrich Existing Records"]
EnrichRecords --> NewRecords["Create New Records for Unmatched"]
NewRecords --> DetectConflicts["Detect and Report Conflicts"]
DetectConflicts --> ReturnResults["Return Processing Results"]
```

**Diagram sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L100-L374)

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L100-L374)
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L47-L91)

## JSONB Availability Field Merging

The function uses JSONB merging to update the `disponibilidad` field for each insurance provider while preserving information from other providers. When processing a vehicle record, the function performs the following operations on the `disponibilidad` field:

1. **Merge Operation**: Uses the JSONB concatenation operator (`||`) to merge the new provider data with existing availability information.

2. **Provider-Specific Updates**: For the source insurance provider (`origen_aseguradora`), updates the following fields:
   - `activo`: Current active status from the input
   - `id_original`: Original ID from the source system
   - `version_original`: Original version description
   - `fecha_actualizacion`: Current timestamp (NOW())

3. **Preservation of Other Providers**: Leaves the availability information for all other insurance providers unchanged.

The merging strategy ensures that each insurance provider's contribution to the vehicle catalog is preserved with complete traceability, enabling analysis of availability patterns across providers and historical tracking of catalog changes.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L291-L327)
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L67-L87)

## Input Validation and Error Handling

The function implements comprehensive input validation and error handling to ensure data integrity and provide meaningful feedback:

### Input Validation
- Validates that the input is either a JSONB array or an object containing a "vehiculos_json" array
- Checks that each record has required fields (id_canonico, hash_comercial, marca, modelo, anio, origen_aseguradora, activo)
- Filters records to only include vehicles with model years between 2000 and 2030
- Normalizes text fields by trimming whitespace and converting to uppercase

### Error Handling
The function uses PostgreSQL's exception handling to catch and report errors:

```mermaid
flowchart TD
Start([Function Execution]) --> ProcessBatch["Process Batch"]
ProcessBatch --> Success{"Success?"}
Success --> |Yes| ReturnSuccess["Return Success Response"]
Success --> |No| CheckException["Check Exception Type"]
CheckException --> UniqueViolation{"Unique Violation?"}
UniqueViolation --> |Yes| ReturnUniqueError["Return Unique Violation Error"]
UniqueViolation --> |No| ReturnGeneralError["Return General Error"]
ReturnSuccess --> End([End])
ReturnUniqueError --> End
ReturnGeneralError --> End
```

The function specifically handles `unique_violation` exceptions to provide more informative error messages, while other exceptions are caught by the general `WHEN OTHERS` clause. All errors include the SQLERRM message for debugging purposes.

**Diagram sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L375-L429)

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L11-L40)
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L375-L429)

## Transaction Safety

The `procesar_batch_homologacion` function operates within a single database transaction, ensuring atomicity of the entire batch processing operation. Either all records in the batch are processed successfully, or the entire operation is rolled back in case of errors.

The function uses a temporary staging table (`tmp_batch`) with `ON COMMIT DROP` semantics, which ensures that the temporary table is automatically cleaned up at the end of the transaction regardless of success or failure. This approach provides several transaction safety benefits:

1. **Atomic Processing**: All operations on the batch are treated as a single unit of work
2. **Automatic Cleanup**: Temporary data is automatically removed, preventing resource leaks
3. **Isolation**: The staging table is only visible within the current session
4. **Rollback Safety**: In case of errors, all changes are reverted automatically

The function's design supports idempotent execution, meaning that reprocessing the same batch will not create duplicate records or alter the state beyond the initial processing. This is achieved through the use of `id_canonico` as a unique identifier and careful conflict resolution logic.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L41-L45)
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L118-L122)

## Performance Considerations

The function's performance is influenced by several factors, including batch size, indexing strategy, and locking behavior:

### Batch Size Limits
- **Recommended Batch Size**: 10,000 to 50,000 records
- **Rationale**: Balances transaction overhead with memory usage and lock duration
- **Too Small**: Increased overhead from transaction management
- **Too Large**: Risk of memory pressure and long lock durations

### Indexing Strategy
The function benefits from the following indexes on the `catalogo_homologado` table:

```sql
CREATE INDEX idx_id_canonico_hom ON catalogo_homologado(id_canonico);
CREATE INDEX idx_marca_modelo_anio_hom ON catalogo_homologado(marca, modelo, anio);
CREATE INDEX idx_hash_comercial_hom ON catalogo_homologado(hash_comercial);
CREATE INDEX idx_disponibilidad_gin_hom ON catalogo_homologado USING GIN(disponibilidad);
```

These indexes optimize the various lookup operations performed during the matching process.

### Locking Behavior
The function acquires row-level locks during UPDATE operations on the `catalogo_homologado` table. The duration of these locks depends on the batch size and processing complexity. To minimize contention:

1. Process batches during periods of lower database activity
2. Monitor for lock wait times and adjust batch sizes accordingly
3. Consider staggering batch processing for different insurance providers

The temporary staging table approach minimizes the time spent holding locks on the main table, as most processing occurs on the temporary structure before final updates.

**Section sources**
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L135-L145)
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L47-L91)

## Usage Examples

### Valid Payload Example
```json
{
  "vehiculos_json": [
    {
      "id_canonico": "a7a8fbec4e5bed8535f19ab418fe9bb83bda4eb4d26058eb0e2d2b9218069221",
      "hash_comercial": "98d9e4baceb9ed37cbe3e24512c24e62cb30b125a2d25cbb27348468340990b2",
      "string_comercial": "TOYOTA|YARIS|2014|AUTO",
      "string_tecnico": "TOYOTA|YARIS|2014|AUTO|PREMIUM|NULL|NULL|NULL|SEDAN|NULL",
      "marca": "TOYOTA",
      "modelo": "YARIS",
      "anio": 2014,
      "transmision": "AUTO",
      "version": "PREMIUM",
      "motor_config": null,
      "carroceria": "SEDAN",
      "traccion": null,
      "origen_aseguradora": "QUALITAS",
      "id_original": "Q-123456",
      "version_original": "PREMIUM SEDAN 1.5L AUTO",
      "activo": true
    }
  ]
}
```

### Invalid Payload Example
```json
{
  "vehiculos_json": [
    {
      "marca": "TOYOTA",
      "modelo": "YARIS",
      "anio": 1995,
      "transmision": "AUTO",
      "origen_aseguradora": "QUALITAS",
      "activo": true
    }
  ]
}
```

This payload would be rejected because:
1. Missing required fields (id_canonico, hash_comercial, string_comercial, string_tecnico)
2. Model year (1995) is outside the valid range (2000-2030)

### API Call Example
```bash
curl -X POST 'https://your-project.supabase.co/rest/v1/rpc/procesar_batch_homologacion' \
  -H 'apikey: YOUR_API_KEY' \
  -H 'Authorization: Bearer YOUR_SERVICE_ROLE_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{
    "vehiculos_json": [
      {
        "id_canonico": "example_hash_1",
        "hash_comercial": "example_hash_2",
        "string_comercial": "TOYOTA|YARIS|2014|AUTO",
        "string_tecnico": "TOYOTA|YARIS|2014|AUTO|PREMIUM|NULL|NULL|NULL|SEDAN|NULL",
        "marca": "TOYOTA",
        "modelo": "YARIS",
        "anio": 2014,
        "transmision": "AUTO",
        "version": "PREMIUM",
        "carroceria": "SEDAN",
        "origen_aseguradora": "QUALITAS",
        "id_original": "Q-123456",
        "activo": true
      }
    ]
  }'
```

**Section sources**
- [casos de prueba función rpc.sql](file://src/supabase/casos de prueba función rpc.sql#L1-L256)
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L103-L117)

## Version Differences and Migration Guidance

The repository contains two versions of the RPC function:
- `Funcion RPC.sql`: Legacy implementation using hash_tecnico as the conflict key
- `Funcion RPC Nueva.sql`: Current implementation using id_canonico as the conflict key

### Key Differences

| Aspect | Legacy Version (Funcion RPC.sql) | Current Version (Funcion RPC Nueva.sql) |
|-------|----------------------------------|----------------------------------------|
| Conflict Key | hash_tecnico | id_canonico |
| Data Structure | Simple upsert | Multi-phase matching |
| Enrichment | No technical specification enrichment | Supports enrichment of missing specs |
| Matching Logic | Exact hash match only | Hierarchical matching with compatibility |
| Response Format | Simple success/failure | Detailed metrics and warnings |
| Error Handling | Generic error messages | Specific unique violation handling |

### Migration Guidance

1. **Update Client Code**: Modify all clients to use the new function name `procesar_batch_homologacion` instead of the legacy function.

2. **Adjust Input Structure**: Ensure all inputs include the `id_canonico` field, which should be calculated as the SHA-256 hash of the normalized vehicle specifications.

3. **Update Error Handling**: Adapt error handling code to expect the more detailed error response format with specific error types.

4. **Monitor Warnings**: Implement logging for warnings to identify potential data quality issues detected during processing.

5. **Batch Size Adjustment**: Review and potentially adjust batch sizes based on the new function's performance characteristics.

6. **Testing**: Thoroughly test the migration with representative data sets, including edge cases and known conflict scenarios.

The new version provides significant improvements in data quality, traceability, and error reporting, making it the recommended choice for all new integrations.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L1-L429)
- [Funcion RPC.sql](file://src/supabase/Funcion RPC.sql#L1-L96)
- [Replanteamiento homologacion.md](file://src/supabase/Replanteamiento homologacion.md#L1-L280)