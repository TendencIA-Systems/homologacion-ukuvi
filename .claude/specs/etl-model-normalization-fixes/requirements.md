# Requirements Document: ETL Model Normalization Fixes

## Introduction

This specification addresses critical data quality issues in the vehicle homologation ETL system that prevent accurate cross-insurer vehicle matching. Client-reported errors reveal systematic failures in the normalization logic, causing valid vehicles from different insurers to be treated as separate entities despite representing the same physical vehicle.

The system currently processes vehicle data from 11 insurance companies (Qualitas, HDI, AXA, GNP, Mapfre, Chubb, Zurich, Atlas, BX, El Potosí, ANA), normalizing each insurer's data format into a canonical master catalog. Matching relies on SHA-256 hashing of `marca|modelo|anio|transmision` to group similar vehicles, followed by token-overlap analysis on the `version` field to identify exact matches.

**Business Impact:**
- **Current State**: Client reports show 40-70% matching failure rate for tested vehicles
- **Root Cause**: Inconsistent modelo field normalization creating different hashes for identical vehicles
- **Customer Impact**: Inaccurate quote comparisons, reduced confidence in platform data quality
- **Financial Impact**: Manual reconciliation overhead, potential customer churn

## Alignment with Product Vision

Per `product.md`, the platform's vision is to provide a "unified vehicle catalog that consolidates vehicle data from 11 major Mexican insurance companies into a single canonical master catalog, enabling intelligent cross-insurer vehicle matching."

This feature directly supports the following product objectives:

1. **Improve Quote Accuracy**: By fixing modelo normalization, we enable accurate cross-insurer vehicle comparisons, supporting the core business goal of quote accuracy improvement.

2. **Maintain Data Quality**: Addresses the success metric of ">95% of records normalized correctly with proper standardization" by fixing systematic normalization gaps.

3. **Reduce Manual Work**: Eliminates the need for manual reconciliation of mismatched vehicles, supporting the product objective of automation.

4. **Match Accuracy**: Directly improves the ">90% of identical vehicles correctly identified across insurers" success metric by ensuring consistent hashing.

## Requirements

### Requirement 1: HONDA Model Hyphenation Normalization

**User Story:** As a data engineer, I want HONDA modelo fields to use consistent hyphenation (HR-V, CR-V, BR-V) across all insurers, so that identical vehicles generate the same commercial hash and can be properly matched.

#### Acceptance Criteria

1. WHEN processing HONDA vehicles from El Potosi with modelo="HRV" THEN the system SHALL normalize to "HR-V"
2. WHEN processing HONDA vehicles from any insurer with modelo containing "HRV", "CRV", or "BRV" (without hyphens) THEN the system SHALL insert hyphens to create "HR-V", "CR-V", "BR-V" respectively
3. WHEN generating hash_comercial for HONDA HR-V 2020 AUTO THEN all insurers SHALL produce identical hash `sha256(honda|hr-v|2020|auto)`
4. IF source data already contains correct hyphenation (e.g., "HR-V") THEN the system SHALL preserve it unchanged
5. WHEN running test validation THEN HONDA HR-V UNIQ 2020 AUTO from Zurich SHALL match with El Potosi HRV UNIQ 2020 AUTO

**Success Metrics:**
- El Potosi HONDA HRV records (previously unmatched) show >90% token overlap with Zurich HR-V equivalents
- Zero hash collisions between different HONDA models after normalization

### Requirement 2: MAZDA Model Hyphenation and Brand Prefix Removal

**User Story:** As a data engineer, I want MAZDA modelo fields to (1) use consistent hyphenation (CX-5, MX-5) and (2) remove brand prefix contamination (MAZDA CX-5 → CX-5), so that all MAZDA vehicles generate consistent commercial hashes.

#### Acceptance Criteria

1. WHEN processing MAZDA vehicles from ANA or Qualitas with modelo="CX5" (no hyphen) THEN the system SHALL normalize to "CX-5"
2. WHEN processing MAZDA vehicles from Zurich or BX with modelo="MAZDA CX-5" THEN the system SHALL remove "MAZDA " prefix to produce "CX-5"
3. WHEN normalizing MAZDA modelo fields THEN the system SHALL apply hyphenation to all CX/MX models: CX3→CX-3, CX5→CX-5, CX7→CX-7, CX9→CX-9, CX30→CX-30, CX50→CX-50, CX90→CX-90, MX5→MX-5
4. WHEN generating hash_comercial for MAZDA CX-5 2020 AUTO THEN all insurers SHALL produce identical hash `sha256(mazda|cx-5|2020|auto)`
5. IF modelo contains both brand prefix and missing hyphen (e.g., "MAZDA CX5") THEN the system SHALL apply both fixes to produce "CX-5"

**Success Metrics:**
- Zurich MAZDA CX-5 records (previously showing brand prefix) match with ANA CX5 equivalents at >92% token overlap
- ANA/Qualitas CX5 records show 100% hash match with other CX-5 records after normalization

### Requirement 3: VOLKSWAGEN JETTA Generation Prefix Removal

**User Story:** As a data engineer, I want VOLKSWAGEN JETTA modelo fields to have all generation/trim prefixes removed (MK VII, MKVII, GEN. 7, A7) across all insurers, so that vehicles from different model years generate consistent hashes.

#### Acceptance Criteria

1. WHEN processing VOLKSWAGEN vehicles from Atlas with modelo="JETTA MKVII" THEN the system SHALL normalize to "JETTA"
2. WHEN processing VOLKSWAGEN vehicles from ANA with modelo="JETTA MK VII" (with spaces) THEN the system SHALL normalize to "JETTA"
3. WHEN processing VOLKSWAGEN vehicles from El Potosi with modelo="JETTA GEN. 7" THEN the system SHALL normalize to "JETTA"
4. WHEN processing VOLKSWAGEN JETTA vehicles from any insurer with formato="JETTA A7" THEN the system SHALL normalize to "JETTA"
5. WHEN generating hash_comercial for VOLKSWAGEN JETTA 2020 AUTO THEN all insurers SHALL produce identical hash `sha256(volkswagen|jetta|2020|auto)` regardless of generation code in source data
6. IF modelo contains multiple generation indicators (e.g., "JETTA MK VII A7") THEN the system SHALL remove all of them to produce "JETTA"

**Success Metrics:**
- Atlas "JETTA MKVII", ANA "JETTA MK VII", and El Potosi "JETTA GEN. 7" records show 100% hash match after normalization
- JETTA COMFORTLINE 2020 AUTO from Zurich matches with Atlas/ANA/El Potosi equivalents at >92% token overlap

### Requirement 4: Mapfre Modelo Field Version Contamination Cleanup

**User Story:** As a data engineer, I want Mapfre vehicle records to have version strings removed from the modelo field (e.g., "HR-V PRIME 1.8 CVT" → "HR-V"), so that Mapfre vehicles generate the same commercial hash as other insurers.

#### Acceptance Criteria

1. WHEN processing Mapfre HONDA vehicles with modelo="HR-V PRIME 1.8 CVT" THEN the system SHALL extract only "HR-V" for hash generation
2. WHEN processing Mapfre MAZDA vehicles with modelo="CX-5 I GRAND TOURING TA" THEN the system SHALL extract only "CX-5" for hash generation
3. WHEN processing Mapfre VOLKSWAGEN vehicles with modelo="JETTA COMFORTLINE 1.4L 150HP TIP" THEN the system SHALL extract only "JETTA" for hash generation
4. IF Mapfre modelo contains both version details and hyphenation issues THEN the system SHALL apply both cleanups (e.g., "HRV UNIQ 1.8 CVT" → "HR-V")
5. WHEN preserving original data THEN the system SHALL maintain full modelo value in `id_original` and `version_original` fields for audit trails

**Success Metrics:**
- Mapfre HONDA HR-V records (previously showing version contamination) show 100% hash match with clean HR-V records
- All Mapfre normalized records have modelo field length <20 characters (removes verbose version strings)

### Requirement 5: Centralized Modelo Normalization Map

**User Story:** As a data engineer, I want a centralized, reusable modelo normalization map that applies consistently across all 11 insurer normalization scripts, so that normalization rules are maintainable and DRY.

#### Acceptance Criteria

1. WHEN adding a new modelo normalization rule THEN the engineer SHALL add it to a single centralized `MODEL_NORMALIZATION_MAP` object
2. WHEN each insurer normalization script executes THEN it SHALL reference the centralized map for modelo transformations
3. WHEN the centralized map includes brand-specific rules THEN it SHALL be structured as `{ MARCA: { pattern: replacement } }`
4. IF multiple patterns apply to the same modelo THEN the system SHALL apply all applicable transformations in sequence
5. WHEN normalizing modelo="HRV" for HONDA THEN the system SHALL look up HONDA→HRV in the map and return "HR-V"

**Example Map Structure:**
```javascript
const MODEL_NORMALIZATION_MAP = {
  HONDA: {
    "HRV": "HR-V",
    "BRV": "BR-V",
    "CRV": "CR-V"
  },
  MAZDA: {
    "CX3": "CX-3",
    "CX5": "CX-5",
    "CX30": "CX-30",
    "MX5": "MX-5"
  },
  VOLKSWAGEN: {
    "JETTA MKVII": "JETTA",
    "JETTA MK VII": "JETTA",
    "JETTA GEN. 7": "JETTA"
  }
};
```

**Success Metrics:**
- All 11 insurer normalization scripts import and use the centralized map
- Adding new modelo normalization requires changing only 1 file (the centralized map)
- Test coverage includes verification that all map entries are applied correctly

### Requirement 6: NISSAN VERSA/SENTRA Data Quality Validation

**User Story:** As a data quality analyst, I want the system to flag potential data quality issues where NISSAN SENTRA appears where NISSAN VERSA is expected (different vehicles with different engines), so that incorrect source data can be identified and corrected.

#### Acceptance Criteria

1. WHEN processing NISSAN vehicles with modelo="SENTRA" AND anio>=2020 THEN the system SHALL add a warning: "SENTRA may be incorrect - verify if VERSA was intended (different engines: SENTRA=1.8L/2.0L, VERSA=1.6L)"
2. WHEN processing batch results THEN the system SHALL include warnings count in response metrics
3. IF NISSAN SENTRA record has 1.6L engine displacement THEN the system SHALL flag as high-priority data quality issue (likely mislabeled VERSA)
4. WHEN generating hash_comercial THEN the system SHALL NOT normalize SENTRA→VERSA (they are different vehicles)
5. WHEN data quality reports are generated THEN they SHALL list all SENTRA records from AXA, El Potosi, Mapfre, and Atlas for manual review

**Success Metrics:**
- Data quality report identifies all NISSAN SENTRA records (estimated 40+ records across 4 insurers)
- Zero false matches between VERSA and SENTRA vehicles (different hash_comercial values)
- Client receives data quality report with SENTRA→VERSA recommendations for source data correction

### Requirement 7: Idempotent Reprocessing

**User Story:** As a data engineer, I want to be able to reprocess all vehicle batches from all insurers after fixing normalization logic, so that existing incorrect matches are corrected and new matches are created.

#### Acceptance Criteria

1. WHEN reprocessing previously loaded vehicle batches THEN the system SHALL update existing records with new normalized modelo values
2. WHEN hash_comercial changes due to normalization fixes THEN the system SHALL reassign vehicles to new hash groups and recalculate token overlap
3. IF a vehicle previously created a new master record (due to hash mismatch) AND normalization fixes create a hash match THEN the system SHALL merge the duplicate into the correct master record via disponibilidad update
4. WHEN reprocessing completes THEN the system SHALL return metrics showing: records_updated, new_matches_created, duplicates_merged
5. IF reprocessing the same batch twice (no normalization changes) THEN the system SHALL produce identical results (idempotent operation)

**Success Metrics:**
- Reprocessing all 11 insurers completes within 60 minutes for full catalog (~200k records)
- Post-reprocessing validation shows >90% of client-reported mismatches are resolved
- Audit logs show before/after hash values for all updated records

## Non-Functional Requirements

### Performance

- **Batch Processing Time**: Normalization logic SHALL NOT increase average batch processing time by >10% (currently <5 minutes for 50k records)
- **Hash Calculation**: Modelo normalization SHALL complete before hash generation with <1ms overhead per record
- **Map Lookup**: Centralized modelo normalization map lookups SHALL use O(1) hash table access

### Security

- **Data Integrity**: All normalization changes SHALL preserve original source data in `version_original` and `id_original` fields
- **Audit Trail**: System SHALL log all modelo transformations with before/after values for compliance auditing
- **No Data Loss**: Reprocessing SHALL NOT delete any existing records; duplicates SHALL be merged via disponibilidad updates

### Reliability

- **Error Isolation**: If normalization fails for a single record, it SHALL NOT break batch processing for remaining records
- **Rollback Support**: System SHALL support rolling back normalization changes by reprocessing with previous code version
- **Validation**: Post-processing validation SHALL verify that hash_comercial values are correctly generated from normalized modelo values

### Usability

- **Logging**: Normalization warnings SHALL include specific record identifiers (id_original, origen_aseguradora) for traceability
- **Metrics**: Batch processing response SHALL include normalization statistics: records_normalized, warnings_generated, duplicates_merged
- **Documentation**: All modelo normalization rules SHALL be documented in centralized map with comments explaining rationale

## Out of Scope

The following items are explicitly **NOT** included in this specification:

1. **Version Field Normalization Changes**: This spec focuses only on modelo field issues; version field cleaning rules remain unchanged
2. **New Insurer Integration**: Adding 12th insurer is not part of this fix
3. **Database Schema Changes**: No changes to `catalogo_homologado` table structure
4. **UI/Frontend Changes**: No changes to user-facing interfaces
5. **Source Data Correction**: We document SENTRA/VERSA issues but do NOT modify insurer source databases
6. **Historical Data Migration**: Fixes apply to new batches and reprocessing; no automatic backfilling of old records without reprocessing

## Testing & Validation Approach

### Unit Testing
- Test centralized modelo normalization map with all known patterns
- Verify hash_comercial generation matches expected values after normalization
- Test edge cases: null modelo, empty modelo, special characters

### Integration Testing
- Process test batches for each insurer with known problematic vehicles
- Verify hash consolidation: same vehicle from different insurers produces same hash
- Validate token overlap scores improve for previously mismatched vehicles

### Regression Testing
- Verify existing correct matches remain intact after normalization changes
- Ensure no new mismatches are introduced for previously working vehicles
- Validate performance metrics stay within acceptable bounds

### End-to-End Validation
- Reprocess full catalog from all 11 insurers
- Generate before/after matching report for client-identified problem vehicles
- Verify client-reported issues (HONDA HR-V, MAZDA CX-5, NISSAN VERSA, VW JETTA) are resolved

## Acceptance Criteria Summary

This specification is considered complete when:

1. ✅ All 11 insurer normalization scripts apply centralized modelo normalization map
2. ✅ HONDA HR-V from El Potosi matches Zurich HR-V with >90% token overlap
3. ✅ MAZDA CX-5 from ANA/Qualitas matches Zurich/HDI CX-5 with >90% token overlap
4. ✅ VOLKSWAGEN JETTA from Atlas/ANA/El Potosi matches Zurich JETTA with >90% token overlap
5. ✅ Mapfre version-contaminated modelo values are cleaned to base model only
6. ✅ NISSAN SENTRA records generate data quality warnings
7. ✅ Full catalog reprocessing completes successfully with <5% error rate
8. ✅ Client validation confirms >90% of reported issues are resolved
9. ✅ Comprehensive test suite covers all normalization rules
10. ✅ Documentation updated with all new normalization patterns
