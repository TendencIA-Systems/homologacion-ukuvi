# Requirements Document - Spacing Normalization Analysis

## Introduction

This feature specification addresses critical spacing inconsistencies in vehicle version strings that are fragmenting token-based matching across insurance company catalogs. The token overlap algorithm compares normalized token arrays to identify identical vehicles across insurers. However, inconsistent spacing (e.g., "I GRAND TOURING" vs "IGRAND TOURING") creates artificial token differences that prevent correct matches, resulting in duplicate records and failed homologation.

**Value to Users:**
- **Data Engineers**: Reduced false negatives in vehicle matching, fewer duplicate catalog entries
- **Business Intelligence Teams**: More accurate cross-insurer vehicle distribution analysis
- **Insurance Underwriters**: Improved catalog quality for vehicle validation and pricing
- **System Performance**: Higher match rates translating to reduced null records and improved data quality metrics

## Alignment with Product Vision

This feature directly supports multiple success metrics and business objectives outlined in product.md:

**Success Metrics:**
- **Match Accuracy**: Target >90% of identical vehicles correctly identified across insurers (currently impacted by spacing fragmentation)
- **Data Quality**: Target >95% of records normalized correctly (currently affected by inconsistent spacing patterns)

**Business Objectives:**
- **Improve Quote Accuracy**: Enable more accurate cross-insurer vehicle comparisons by resolving spacing-related matching failures
- **Maintain Data Quality**: Ensure consistency and correctness of the master catalog through systematic spacing normalization

**Problem Statement Alignment:**
The fragmentation caused by spacing inconsistencies is a root cause of "inconsistent data formats" and "inability to identify identical vehicles across different insurers" mentioned in the product vision.

## Requirements

### Requirement 1: Pattern Identification and Analysis

**User Story:** As a data engineer, I want a comprehensive analysis of spacing patterns across all 11 insurer catalogs, so that I can understand the scope and impact of spacing-related matching failures.

#### Acceptance Criteria

1. WHEN the analysis script executes THEN the system SHALL scan all 11 insurer origin CSV files (`data/origin/*-sample.csv`)
2. WHEN analyzing version strings THEN the system SHALL identify spacing patterns in these categories:
   - Trim prefixes with spaces (e.g., "I GRAND", "S GRAND", "GT SPORT")
   - Fragmented acronyms (e.g., "T D I" vs "TDI", "F S I" vs "FSI")
   - Number spacing inconsistencies (e.g., "2 0" vs "20", "1 5 L" vs "1.5L")
   - Model prefix separations (e.g., "E TRON" vs "E-TRON")
3. WHEN patterns are identified THEN the system SHALL count frequency per insurer and total occurrences
4. WHEN variants exist THEN the system SHALL group related patterns (e.g., ["I GRAND TOURING", "IGRAND TOURING", "I-GRAND TOURING"])
5. WHEN the analysis completes THEN the system SHALL produce a markdown report (`ANALISIS-SPACING-ISSUES.md`) with minimum 20 unique patterns documented

### Requirement 2: Cross-Insurer Inconsistency Detection

**User Story:** As a data engineer, I want to identify which insurers use different spacing conventions for the same vehicle, so that I can prioritize normalization rules that maximize match improvements.

#### Acceptance Criteria

1. WHEN comparing versions across insurers THEN the system SHALL identify vehicles with identical `hash_comercial` (marca|modelo|anio|transmision)
2. WHEN vehicles match commercially THEN the system SHALL detect spacing variations in version strings across insurers
3. WHEN inconsistencies are found THEN the system SHALL document which insurers use which spacing variant
4. IF one insurer uses "I GRAND TOURING" AND another uses "IGRAND TOURING" THEN the system SHALL flag this as a cross-insurer inconsistency
5. WHEN inconsistencies are documented THEN the system SHALL indicate the canonical form to normalize to

### Requirement 3: Token Overlap Impact Calculation

**User Story:** As a data engineer, I want to measure the current and projected token overlap scores for spacing-affected vehicles, so that I can quantify the improvement potential of normalization fixes.

#### Acceptance Criteria

1. WHEN calculating current overlap THEN the system SHALL use the existing `tokenize_version` algorithm from `funciones-homologacion-v2.8.1-trims-expanded.sql`
2. WHEN comparing variants THEN the system SHALL calculate overlap score as `|tokens_A ∩ tokens_B| / max(|tokens_A|, |tokens_B|)`
3. WHEN simulating normalization THEN the system SHALL apply proposed spacing fixes and recalculate overlap scores
4. WHEN reporting impact THEN the system SHALL show both current and projected scores with delta
5. IF current score is <0.90 AND projected score is >=0.90 THEN the system SHALL flag this as "high impact fix"

### Requirement 4: Client-Reported Case Analysis

**User Story:** As a data engineer, I want to analyze the specific vehicle cases reported by the client in `/correcciones/` PDFs, so that I can verify if spacing issues contributed to their matching problems.

#### Acceptance Criteria

1. WHEN analyzing client reports THEN the system SHALL examine both PDF files in `/correcciones/`:
   - `catalogo_revision_zurich_comparacion_versiones.pdf`
   - `catalogo_revision_zurich_hdi_comparacion_versiones_2.pdf`
2. WHEN examining cases THEN the system SHALL extract version strings for the 4 reported vehicle examples:
   - Honda HR-V 2020
   - Mazda CX-5 2020
   - Nissan Versa 2020
   - VW Jetta 2020
3. WHEN versions are extracted THEN the system SHALL identify if spacing patterns contributed to matching failures
4. IF spacing contributed THEN the system SHALL document the specific pattern and proposed fix
5. IF spacing did NOT contribute THEN the system SHALL document the actual cause for client reference

### Requirement 5: Normalization Solution Design

**User Story:** As a data engineer, I want a technical implementation plan for spacing normalization, so that I can apply consistent fixes across all 11 insurer normalization scripts.

#### Acceptance Criteria

1. WHEN designing solutions THEN the system SHALL create JavaScript normalization maps for each pattern category
2. WHEN defining trim prefixes THEN the system SHALL create map: `TRIM_PREFIX_NORMALIZATION = { "I GRAND": "I-GRAND", "S GRAND": "S-GRAND", ... }`
3. WHEN defining acronyms THEN the system SHALL create map: `ACRONYM_NORMALIZATION = { "T D I": "TDI", "F S I": "FSI", ... }`
4. WHEN specifying implementation THEN the system SHALL provide integration instructions for each insurer's `cleanVersion()` function
5. WHEN the solution is documented THEN the system SHALL produce `SOLUCION-SPACING-NORMALIZATION.md` with code examples

### Requirement 6: Validation Script Creation

**User Story:** As a data engineer, I want executable Python validation scripts, so that I can verify the normalization improvements before deploying to production.

#### Acceptance Criteria

1. WHEN creating analysis script THEN the system SHALL produce `/scripts/identify_spacing_issues.py` using Python standard library only
2. WHEN the script executes THEN the system SHALL read all 11 CSV files from `/data/origin/`
3. WHEN patterns are detected THEN the system SHALL output frequency tables and variant groupings
4. WHEN creating validation script THEN the system SHALL produce `/scripts/test_spacing_normalization.py` to simulate fixes
5. WHEN validation runs THEN the system SHALL calculate before/after overlap scores for affected vehicles

## Non-Functional Requirements

### Performance
- Analysis script SHALL complete processing of all 11 insurer catalogs in <5 minutes
- Pattern detection SHALL use efficient regex compilation to minimize processing time
- CSV reading SHALL use streaming/chunking for memory efficiency with large files

### Security
- Scripts SHALL only READ from data files, NEVER modify origin CSVs
- Analysis SHALL NOT expose sensitive vehicle pricing or underwriting data
- Reports SHALL focus on technical patterns, not business-confidential information

### Reliability
- Analysis script SHALL handle missing/malformed CSV files gracefully with error messages
- Pattern detection SHALL tolerate encoding issues (UTF-8, Latin-1) in source CSVs
- Report generation SHALL succeed even if some insurers have zero matching patterns

### Usability
- Analysis reports SHALL use clear markdown formatting with tables and examples
- Pattern documentation SHALL include before/after examples for each fix
- Solution document SHALL provide copy-paste ready JavaScript code for implementation
- Scripts SHALL include progress indicators and verbose logging for transparency
