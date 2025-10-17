# Requirements Document - Sistema de Homologación: Correcciones

## Introduction

This specification addresses critical data quality issues identified in the vehicle homologation system that consolidates data from 11 insurance companies into a master catalog. The system currently processes ~242,656 records representing 40,559 unique vehicles, but analysis has revealed that approximately **95.7% of records (~232,300)** require corrections due to normalization inconsistencies, invalid data, and systematic parsing errors.

Additionally, a critical algorithmic flaw has been identified where the matching algorithm selects the first qualifying match instead of the best match, resulting in incorrect homologations like A-SPEC being matched with TECH trim levels.

The corrections will be implemented across two main components:
1. **N8N Normalization Code** - JavaScript normalization scripts for each of the 11 insurers
2. **Supabase RPC Functions** - PostgreSQL functions that handle token-based matching and deduplication

## Alignment with Product Vision

The homologation system serves as the foundation for vehicle insurance quotations across multiple insurers. Accurate data normalization is critical for:
- **Cross-insurer matching**: Ensuring vehicles from different insurers are correctly identified as the same model
- **User experience**: Providing accurate quote comparisons for end users
- **Data integrity**: Maintaining a reliable master catalog for business intelligence and analytics

These corrections directly address the client's reported issues where different vehicle trims (A-SPEC vs TECH) are being incorrectly matched, and missing data causes failed homologations.

## Requirements

### Requirement 1: Fix Best-Match Selection Algorithm (CRITICAL)

**User Story:** As a homologation system user, I want the system to select the best matching vehicle based on coverage score, so that distinct trim levels (A-SPEC vs TECH) are not incorrectly matched together.

#### Acceptance Criteria

1. WHEN processing an incoming vehicle with a `hash_comercial` that exists in the catalog THEN the system SHALL evaluate ALL candidate matches before selecting one
2. WHEN multiple candidates exist THEN the system SHALL calculate coverage scores for each candidate
3. WHEN coverage scores are calculated THEN the system SHALL select the candidate with the HIGHEST score
4. IF multiple candidates have identical highest scores THEN the system SHALL select based on secondary criteria (same insurer preference, then most recent)
5. WHEN a best match is selected THEN only that match SHALL be updated with availability data
6. WHEN no candidate exceeds the minimum threshold THEN the system SHALL create a new record (if insurer is whitelisted) or skip
7. WHEN the best match is below tier 2 threshold but above tier 3 THEN the system SHALL log a warning for manual review

**Example Scenario:**
- Incoming: Zurich A-SPEC 201HP 2.0L 4CIL 4PUERTAS 5OCUP
- Candidate 1: TECH 4P L4 2.4L AUTO 5OCUP (score: 0.45)
- Candidate 2: A-SPEC 200HP 2.0L 4CIL 4PUERTAS 5OCUP (score: 0.95)
- Expected: Select Candidate 2 (highest score)
- Current Bug: Selects Candidate 1 (first evaluated)

### Requirement 2: Critical Transmission Field Recovery

**User Story:** As a data engineer, I want to recover valid transmission values from contaminated fields, so that 80% of the database (~194,000 records) have correct transmission classification.

#### Acceptance Criteria

1. WHEN a record has an invalid transmission value (e.g., "GLI DSG", "COMFORTLSLINE DSG", "LATITUDE", "PEPPER AT") THEN the system SHALL attempt to extract a valid transmission from the field
2. IF no valid transmission can be extracted from the field THEN the system SHALL infer transmission from the `version_original` field using pattern matching
3. WHEN transmission is recovered from `version_original` THEN the system SHALL prioritize tokens: DSG, AUTO, AUTOMATIC, TIPTRONIC, CVT → AUTO; MANUAL, STD, MT → MANUAL
4. IF no transmission can be inferred from either field THEN the system SHALL discard the record and log it with error code TRANSMISSION_INFERENCE_FAILED for that insurer
5. WHEN processing is complete THEN valid transmission values SHALL only be "AUTO" or "MANUAL" (records without valid transmission are excluded)

### Requirement 3: Brand Consolidation and Standardization

**User Story:** As a data analyst, I want all brand variations consolidated to canonical names, so that ~25,000 records with brand inconsistencies are standardized for accurate cross-insurer matching.

#### Acceptance Criteria

1. WHEN a record has a brand suffix (e.g., "BMW BW", "VOLKSWAGEN VW", "CHEVROLET GM") THEN the system SHALL remove the suffix and normalize to the canonical brand name
2. WHEN a record has a brand variant (e.g., "KIA MOTORS", "TESLA MOTORS", "MERCEDES BENZ II") THEN the system SHALL consolidate to the standard name
3. WHEN a record has a typo brand (e.g., "BERCEDES", "BUIK") THEN the system SHALL correct to the proper spelling
4. IF a record has an invalid brand category (AUTOS, MOTOCICLETAS, MULTIMARCA, LEGALIZADO) THEN the system SHALL flag for deletion
5. WHEN "MINI" appears as a BMW model THEN the system SHALL separate it to brand=MINI and update the modelo field accordingly
6. WHEN processing multiple brand variations THEN the system SHALL apply the consolidation map consistently across all 11 insurers

### Requirement 4: Model Field Contamination Cleanup

**User Story:** As a data quality specialist, I want model fields cleaned of contamination patterns, so that hash_comercial generation is consistent and deduplication works correctly.

#### Acceptance Criteria

1. WHEN a Mazda model starts with "MAZDA" or "MA" prefix THEN the system SHALL remove the prefix (e.g., "MAZDA 3" → "3", "MA 2" → "2")
2. WHEN a Mercedes model starts with "MERCEDES" prefix THEN the system SHALL remove the prefix (e.g., "MERCEDES CLASE C" → "CLASE C")
3. WHEN a Mercedes model contains "KLASSE" (German) THEN the system SHALL replace with "CLASE" (Spanish)
4. WHEN a model field contains body type suffixes (SEDAN, HATCHBACK, SUV, COUPE) THEN the system SHALL remove them
5. WHEN a model field contains generic prefixes (PICK UP, CAMIONETA, VAN) THEN the system SHALL remove them
6. WHEN a model field contains generation markers (MK VII, GEN 4) or trim-generation suffixes THEN the system SHALL remove them
7. WHEN a BMW model is "SERIE X5" THEN the system SHALL normalize to "X5"
8. WHEN a model contains "NUEVO/NUEVA/NEW" prefix THEN the system SHALL remove it
9. WHEN processing modelo fields THEN all changes SHALL preserve the original value in `version_original` for audit trails

### Requirement 5: Version String Normalization Improvements

**User Story:** As a normalization engineer, I want enhanced version string cleaning, so that technical specifications are consistent and token matching works accurately.

#### Acceptance Criteria

1. WHEN a version contains escape characters (backslashes, quotes) THEN the system SHALL remove them
2. WHEN a version contains "HPAUT" pattern (e.g., "170HPAUT") THEN the system SHALL separate to "HP AUT" (e.g., "170HP AUT")
3. WHEN a version contains invalid door counts (e.g., "300PUERTAS", "335PUERTAS", "0PUERTAS") THEN the system SHALL either correct or remove them
4. IF door count is a model number (300, 320, 328, 335, 3500) THEN the system SHALL remove it entirely
5. IF door count is salvageable truck notation (300, 3500) THEN the system SHALL replace with "4PUERTAS"
6. WHEN a version contains duplicate tokens (e.g., "TECH 5PUERTAS ... 5PUERTAS") THEN the system SHALL deduplicate intelligently
7. WHEN deduplicating THEN the system SHALL preserve different spec types (2.0L and 2PUERTAS can coexist)
8. WHEN appending extracted specs (doors/occupants) THEN the system SHALL only append if not already present in version

### Requirement 6: Technical Specification Standardization

**User Story:** As a token matching specialist, I want technical specifications standardized across all insurers, so that the weighted token coverage algorithm produces accurate match scores.

#### Acceptance Criteria

1. WHEN a version contains standalone trims (TECHNOLOGY PACKAGE, TECHNOLOGY) THEN the system SHALL normalize to "TECH"
2. WHEN a version contains compound trims with spaces (SPORT LINE, M SPORT) THEN the system SHALL add hyphens (SPORT-LINE, M-SPORT)
3. WHEN a version contains BMW IA/I variations (120I, 120 I, 120IA) THEN the system SHALL standardize the format
4. WHEN a version contains wheel sizes (R15, R16, R17) THEN the system SHALL remove them
5. WHEN a version contains "0TON" or invalid tonnage THEN the system SHALL remove it
6. WHEN a version contains generation/trim prefixes (A7, MK VII) THEN the system SHALL remove them from version (already removed from model)
7. WHEN a version contains body types (SEDAN, SUV) THEN the system SHALL remove them (body type should not affect version matching)

### Requirement 7: Insurer-Specific Normalization Updates

**User Story:** As an ETL pipeline maintainer, I want insurer-specific normalization rules updated, so that each insurer's data peculiarities are handled correctly.

#### Acceptance Criteria

1. WHEN processing MAPFRE records THEN the system SHALL apply transmission recovery logic from contaminated fields
2. WHEN processing MAPFRE records THEN the system SHALL clean modelo fields of technical specifications (V6, 4X4, TA, TM)
3. WHEN processing Zurich records THEN the system SHALL remove "MAZDA" prefix from Mazda models
4. WHEN processing ANA records THEN the system SHALL remove "MA" prefix from Mazda models and "CHASIS" from all models
5. WHEN processing BX records THEN the system SHALL remove brand name from modelo field
6. WHEN processing EL POTOSI records THEN the system SHALL clean Mercedes prefixes and generic Mazda models
7. WHEN processing HDI records THEN the system SHALL move body types from modelo to version
8. WHEN processing GNP records THEN the system SHALL remove marca and modelo tokens that appear within the version_original field content
9. WHEN processing Chubb records THEN the system SHALL separate liters from adjacent text (2.0LAUT → 2.0L AUTO)
10. WHEN processing Atlas records THEN the system SHALL remove BMW model numbers incorrectly parsed as doors
11. WHEN processing Qualitas records THEN the system SHALL apply enhanced deduplication for version tokens
12. WHEN processing AXA records THEN the system SHALL standardize A-SPEC vs A SPEC formatting

### Requirement 8: Data Validation and Quality Gates

**User Story:** As a quality assurance analyst, I want comprehensive validation rules applied during processing, so that only valid data enters the master catalog.

#### Acceptance Criteria

1. WHEN validating transmision THEN only "AUTO" or "MANUAL" SHALL be accepted
2. WHEN validating puertas THEN only values [2, 3, 4, 5, 7] SHALL be accepted
3. WHEN validating ocupantes THEN values SHALL be between 2 and 23
4. WHEN validating anio THEN values SHALL be between 2000 and 2030
5. WHEN validating marca THEN empty or whitespace-only values SHALL be rejected
6. WHEN validating modelo THEN empty or whitespace-only values SHALL be rejected
7. WHEN a record fails validation THEN it SHALL be logged with specific error codes
8. WHEN processing batches THEN failed records SHALL be isolated and not break entire batch processing

## Non-Functional Requirements

### Performance
- Batch processing SHALL maintain current throughput of 5,000-10,000 records per execution
- Best-match algorithm SHALL evaluate all candidates with O(n) time complexity where n is the number of candidates with matching hash_comercial
- Normalization functions SHALL complete within existing timeout constraints (2 minutes per batch in Supabase)
- Token deduplication SHALL not increase processing time by more than 10%

### Data Integrity
- ALL original values SHALL be preserved in `version_original` and `id_original` fields
- Normalization SHALL be idempotent (re-running produces identical results)
- Hash generation SHALL remain deterministic for identical normalized values
- Best-match selection SHALL be deterministic (same candidates always produce same result)

### Maintainability
- Normalization dictionaries SHALL be centralized and reusable across insurers
- Validation logic SHALL be extracted to shared functions
- Brand consolidation maps SHALL be maintained in a single source of truth
- Matching algorithm SHALL be well-documented with clear decision logic

### Auditability
- Each normalization change SHALL be traceable through source fields
- Processing metadata SHALL include timestamps and confidence scores
- Match selection SHALL log all candidates evaluated and their scores
- Error logs SHALL include original record data for debugging

### Compatibility
- Changes SHALL maintain compatibility with existing `procesar_batch_vehiculos` RPC function signature
- N8N workflow structure SHALL remain unchanged (only Code node logic updated)
- Database schema SHALL not require migration (fields already exist)
- Existing `disponibilidad` JSONB structure SHALL be preserved

---

**Document Version:** 1.0
**Last Updated:** 2025-10-17
**Status:** Draft - Awaiting Approval
