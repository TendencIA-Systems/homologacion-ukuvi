# Exception Handling

<cite>
**Referenced Files in This Document**   
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Exception Types](#exception-types)
3. [Error Response Structure](#error-response-structure)
4. [Unique Constraint Violation (unique_violation)](#unique-constraint-violation-unique_violation)
5. [General SQL Exceptions (OTHERS)](#general-sql-exceptions-others)
6. [Scenario Examples](#scenario-examples)
7. [Troubleshooting Guidance](#troubleshooting-guidance)
8. [Best Practices for Client Applications](#best-practices-for-client-applications)

## Introduction
The `procesar_batch_homologacion` function in the Supabase database implements a robust exception handling mechanism to manage errors during batch processing of vehicle homologation data. This documentation details the two primary exception types caught by the function: `unique_violation` and `OTHERS`. It explains how each exception is transformed into a structured JSONB response containing success status, error message, SQL state, and received count. The document also provides insight into error message formatting, real-world scenarios that trigger these exceptions, and guidance for developers on interpreting and handling these errors effectively.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L410-L428)

## Exception Types
The `procesar_batch_homologacion` function specifically handles two types of exceptions using PostgreSQL's PL/pgSQL exception block:

1. **`unique_violation`**: Triggered when an attempt is made to insert a record that violates a unique constraint in the database.
2. **`OTHERS`**: A catch-all category that captures any other SQL exception not explicitly handled.

These exceptions are processed within a dedicated EXCEPTION block that ensures graceful error reporting without exposing raw database errors to client applications.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L413-L420)

## Error Response Structure
When an exception occurs, the function returns a standardized JSONB object with the following structure:

```json
{
  "success": false,
  "error": "Error message",
  "detail": "SQLSTATE code",
  "received": number_of_received_records
}
```

- **`success`**: Always set to `false` when an exception is caught.
- **`error`**: Contains a descriptive error message, formatted differently depending on the exception type.
- **`detail`**: Contains the SQLSTATE error code for precise error identification.
- **`received`**: Indicates the number of vehicle records received in the original request, preserving context even when processing fails.

This consistent structure enables client applications to reliably parse and respond to error conditions.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L413-L428)

## Unique Constraint Violation (unique_violation)
The `unique_violation` exception is raised when an INSERT operation attempts to add a record with a duplicate value in a column constrained by a UNIQUE index. In the context of `procesar_batch_homologacion`, this most commonly occurs when attempting to insert a vehicle with a duplicate `id_canonico`, which is defined as a unique key in the `catalogo_homologado` table.

When this exception is caught, the function formats the error message as:
```
"Violación de unicidad: " || SQLERRM
```

This prefixes the native PostgreSQL error message (`SQLERRM`) with a descriptive label in Spanish indicating a uniqueness violation. The `detail` field contains the SQLSTATE code `23505`, which is the standard code for unique constraint violations.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L413-L417)

## General SQL Exceptions (OTHERS)
The `OTHERS` exception handler acts as a fallback for any SQL error not explicitly caught by other exception types. This includes a wide range of potential database errors such as foreign key violations, check constraint failures, data type mismatches, or system-level database issues.

When an `OTHERS` exception is caught, the function returns a JSONB response with:
- `error`: The raw `SQLERRM` message from PostgreSQL
- `detail`: The SQLSTATE code corresponding to the specific error type
- `received`: The count of received records from the input

This approach ensures that no database error goes unreported while maintaining a consistent response format. However, it may expose more technical details than the `unique_violation` handler.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L420-L426)

## Scenario Examples
### Duplicate id_canonico Insert
A `unique_violation` exception occurs when the function attempts to insert a new vehicle record with an `id_canonico` that already exists in the `catalogo_homologado` table. For example, if two different insurers submit vehicle data with the same canonical ID, the second insertion will trigger this exception.

### Unexpected Database Errors
The `OTHERS` exception can be triggered by various scenarios, such as:
- Invalid data types in the input JSON (e.g., non-integer values for `anio`)
- Violation of the `anio` check constraint (values outside 2000-2030 range)
- Database connectivity issues or resource constraints
- Schema evolution conflicts or missing indexes

These scenarios result in the generic error handler returning the raw SQL error message and state code.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L291-L327)
- [instrucciones.md](file://instrucciones.md#L150-L155)

## Troubleshooting Guidance
Developers should use the following approach when troubleshooting exceptions from `procesar_batch_homologacion`:

1. **Check the `detail` field**: The SQLSTATE code provides precise error classification. For example:
   - `23505`: Unique constraint violation
   - `23503`: Foreign key violation
   - `23514`: Check constraint violation

2. **Examine the `error` message**: For `unique_violation`, look for "Violación de unicidad" to confirm the error type. For `OTHERS`, analyze the `SQLERRM` content for specific clues.

3. **Verify input data**: Ensure that `id_canonico` values are properly calculated and unique across the dataset. Validate that all required fields meet type and constraint requirements.

4. **Review recent schema changes**: Confirm that database constraints and indexes have not changed in ways that might affect the insertion logic.

5. **Check data volume and batching**: Large batches may trigger resource limits or timeouts, resulting in `OTHERS` exceptions.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L410-L428)
- [instrucciones.md](file://instrucciones.md#L145-L155)

## Best Practices for Client Applications
Client applications should implement the following practices when handling responses from `procesar_batch_homologacion`:

1. **Always check the `success` field** before processing results to detect exceptions.

2. **Implement error-specific handling**:
   - For `unique_violation` (SQLSTATE 23505): Consider deduplicating input data or using UPSERT logic.
   - For other SQLSTATE codes: Validate input against known constraints before resubmission.

3. **Log the `detail` field** for monitoring and debugging, as it provides precise error classification.

4. **Preserve context with `received`**: Use the received count to correlate errors with specific batches.

5. **Implement retry logic with backoff** for transient `OTHERS` exceptions, but avoid retrying `unique_violation` errors without data modification.

6. **Sanitize error display**: When showing errors to end users, use the `detail` code to map to user-friendly messages rather than displaying raw `error` content.

These practices ensure robust integration with the homologation service while maintaining data integrity and user experience.

**Section sources**
- [Funcion RPC Nueva.sql](file://src/supabase/Funcion RPC Nueva.sql#L410-L428)
- [instrucciones.md](file://instrucciones.md#L250-L270)