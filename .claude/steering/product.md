# Product Steering Document

## Vision
Unified vehicle catalog platform that consolidates vehicle data from 11 major Mexican insurance companies into a single canonical master catalog, enabling intelligent cross-insurer vehicle matching and accurate insurance quotation comparisons.

## Problem Statement
Insurance companies maintain separate vehicle catalogs with inconsistent data formats, naming conventions, and technical specifications. This fragmentation causes:
- Manual data matching and deduplication efforts
- Inaccurate quote comparisons across insurers
- Data quality inconsistencies in the master catalog
- Inability to identify identical vehicles across different insurers

## Primary Users
- **Data Engineers**: Build and maintain ETL pipelines for vehicle data normalization
- **Insurance Underwriters**: Use the master catalog for vehicle validation and pricing
- **Business Intelligence Teams**: Analyze vehicle distribution and trends across insurers
- **Platform Engineers**: Maintain system reliability and performance

## Key Features
1. **Multi-Source Data Extraction**: Connects to 11 insurance company databases (Qualitas, HDI, AXA, GNP, Mapfre, Chubb, Zurich, Atlas, BX, El Potosí, ANA)
2. **Intelligent Normalization**: Standardizes vehicle data using insurer-specific rules and transformations
3. **Smart Vehicle Matching**: Uses token-overlap algorithms to identify identical vehicles across insurers despite format differences
4. **Canonical Master Catalog**: Single source of truth with integrated technical specifications and per-insurer availability tracking
5. **Idempotent Processing**: Re-running same batch produces identical results for reliability and auditability

## Business Objectives
- **Reduce Manual Work**: Automate vehicle matching across insurers
- **Improve Quote Accuracy**: Enable more accurate cross-insurer vehicle comparisons
- **Maintain Data Quality**: Ensure consistency and correctness of the master catalog
- **Scale to More Insurers**: Support adding new insurance company data sources

## Success Metrics
- **Data Quality**: >95% of records normalized correctly with proper standardization
- **Match Accuracy**: >90% of identical vehicles correctly identified across insurers
- **Processing Efficiency**: Batch processing time <5 minutes for 50k records
- **System Reliability**: >99% uptime for RPC functions
- **Coverage**: All 11 insurers processing successfully with <0.1% error rate

## Key Constraints
- **Idempotency**: All processing must be repeatable without side effects
- **Audit Trails**: Original data must be preserved for traceability and debugging
- **Incremental Updates**: Support processing new/updated records without full catalog reprocessing
- **Performance**: Handle 200k+ records efficiently without timeout

## Data Architecture
- **Master Table**: `catalogo_homologado` in Supabase PostgreSQL
- **Per-Insurer Modules**: Dedicated normalization logic for each insurer's data format
- **Availability Tracking**: JSONB field storing per-insurer active/inactive status
- **Hash-Based Grouping**: SHA-256 commercial hash (marca|modelo|anio|transmision) for initial matching
- **Token Overlap Matching**: Normalized token comparison for cross-insurer vehicle identification

## Roadmap Phases
1. **Phase 0**: Verify project structure and test framework setup
2. **Phase 1**: Fix critical best-match selection algorithm (A-SPEC vs TECH mismatch)
3. **Phase 2**: Apply normalization corrections across all 11 insurers
4. **Phase 3**: Comprehensive validation and testing
5. **Phase 4**: Production deployment and full catalog reprocessing
