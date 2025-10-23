# Tasks: Correcciones de Homologación

**Input**: Design documents from `.claude/specs/correcciones-homologacion/`
**Prerequisites**: requirements.md, design.md, HANDOFF.md

## Overview

This task breakdown implements critical corrections to the vehicle homologation system:
1. **Algorithm Fix**: Replace multi-update logic with best-match selection (lines 553-583 in SQL)
2. **Data Quality**: Apply normalization corrections across 11 insurers (~232,300 records)
3. **Validation**: Ensure idempotency and data integrity

**Total Tasks**: 111 tasks organized in 4 phases
**Estimated Duration**: 8-12 hours with parallel execution
**Critical Path**: Tasks 1-4 (algorithm fix) must complete before full deployment

## Task Overview

**Implementation Approach**: This implementation corrects critical data quality issues across 11 insurance company data sources through a 4-phase execution strategy:

1. **Phase 0 (Setup)**: Verify project structure and test framework setup (prerequisite)

2. **Phase 1 (Critical Fix)**: Modify Supabase RPC function `procesar_batch_vehiculos` to select the single best match instead of updating all candidates above threshold. This fixes the A-SPEC vs TECH mismatch bug reported by the client.

3. **Phase 2 (Data Quality)**: Apply 5 normalization corrections to n8n code for all 11 insurers:
   - Component 2: Brand consolidation using centralized map
   - Component 3: Transmission recovery from contaminated fields
   - Component 4: Enhanced model normalization (prefix/suffix removal)
   - Component 5: Enhanced version cleaning (escape chars, HP+AUT patterns)
   - Component 6: Intelligent token deduplication

4. **Phase 3 (Validation)**: Comprehensive testing including integration tests for the algorithm fix, validation tests for normalization functions, performance benchmarks, and idempotency verification.

5. **Phase 4 (Deployment)**: Deploy updated SQL function to production, update n8n workflows, execute full reprocessing, and generate post-deployment reports.

**Technology Stack**:
- **Backend**: PostgreSQL (Supabase) with PL/pgSQL stored procedures
- **ETL**: n8n workflows with JavaScript Code nodes
- **Testing**: SQL-based integration tests, JavaScript unit tests (Jest recommended)

## Steering Document Compliance

### CLAUDE.md Alignment

**Hash-Based Deduplication Pattern**:
- Tasks preserve existing `hash_comercial` generation (SHA-256 of marca|modelo|anio|transmision)
- Tasks maintain token-overlap strategy using `version_tokens_array`
- Tasks keep existing `calculate_weighted_coverage_with_trim_penalty()` function unchanged

**Canonical Data Model**:
- All tasks preserve `version_original` and `id_original` for audit trails (Req 8.9)
- Tasks maintain compatibility with `disponibilidad` JSONB structure
- No schema changes required - work within existing `catalogo_homologado` table

**Idempotent Processing**:
- All normalization tasks maintain deterministic hash generation
- Best-match selection algorithm uses deterministic tiebreakers
- Re-running same batch produces identical results (verified in Task 107)

**Code Reuse Patterns**:
- Tasks leverage existing `deduplicateTokens()` from Qualitas (lines 569-609)
- Tasks extend existing `normalizeModelo()` and `cleanVersionString()` functions
- Tasks reuse `inferTransmissionFromVersion()` pattern across all insurers

**N8N Workflow Structure**:
- Tasks only modify JavaScript Code nodes (no workflow structure changes)
- Tasks maintain existing batch processing (5,000 records per execution)
- Tasks preserve existing Supabase RPC interface (no signature changes)

### Project Structure Convention

**Insurer Normalization Files**:
- Pattern: `src/insurers/[name]/[name]-codigo-de-normalizacion.js`
- Each file contains: validation, normalization, hash generation, error handling
- Batch size constant: `BATCH_SIZE = 5000`

**Supabase Functions**:
- Single file: `src/supabase/funciones-homologacion-actuales.sql`
- Function signature: `procesar_batch_vehiculos(vehiculos_json JSONB)`
- Critical section: Lines 553-583 (multi-update loop to be replaced)

**Testing Files** (to be created):
- Integration tests: `tests/integration/test_*.sql`
- Validation tests: `tests/validation/test_*.js`
- Performance tests: `tests/performance/test_*.sql`

## Atomic Task Requirements

**Each task in this document meets these criteria:**

1. **File Scope**: Touches 1-3 related files maximum
   - Example: Task 1 modifies only `funciones-homologacion-actuales.sql` (1 file)
   - Example: Tasks 5A-C modify only `mapfre-codigo-de-normalizacion.js` (1 file)
   - Counter-example: ❌ Task modifying both SQL and JS files (too broad)

2. **Time Boxing**: Completable in 15-30 minutes by an experienced developer
   - Simple additions (constants, variable declarations): 5-15 minutes
   - Function modifications (extend existing logic): 15-20 minutes
   - New function creation (with tests): 20-30 minutes

3. **Single Purpose**: One testable outcome per task
   - Example: "Add brand consolidation map" → verifiable by checking BRAND_CONSOLIDATION_MAP exists
   - Example: "Replace FOR loop with SELECT...LIMIT 1" → verifiable by checking UPDATE count
   - Counter-example: ❌ "Add brand consolidation and transmission recovery" (two purposes)

4. **Specific Files**: Exact file paths specified for all tasks
   - All tasks include absolute or repo-relative paths
   - Line numbers included where modifications occur (e.g., "line 453", "lines 556-583")
   - New files marked with (NEW) suffix

5. **Agent-Friendly**: Clear input/output with minimal context switching
   - Each task includes: File, Action, Leverage, Requirements, Dependencies
   - Tasks reference Design.md components with specific line numbers
   - Tasks specify what to reuse from existing code (Qualitas/Zurich templates)

## Task Format Guidelines

**Standard Checkbox Format**:
```markdown
- [ ] TaskNumber. Brief task description (1-10 words)
  - File: absolute/or/repo-relative/path/to/file.ext
  - Action: Detailed implementation steps (multi-line bullet list allowed)
  - Leverage: References to existing code, Design.md components, or patterns
  - Requirements: Specific requirement subsections (e.g., "1.1, 1.3")
  - Time: Estimated minutes (5-30 range)
  - Dependencies: Task numbers that must complete first, or "None"
  - Parallel: "Yes [P]" if can run with other tasks, "No" if sequential
```

**Examples of Correct Format**:

```markdown
- [x] 1. Add best_match variable declaration to procesar_batch_vehiculos
  - File: src/supabase/funciones-homologacion-actuales.sql
  - Action:
    - Locate DECLARE section after function signature (line 453)
    - Add new line: `best_match RECORD;`
    - Ensure proper indentation (2 spaces)
  - Leverage: Existing variable declaration pattern in SQL function
  - Requirements: 1.1 (Evaluate all candidates)
  - Time: 5 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [x] 2. Replace multi-update loop with best-match selection
  - File: src/supabase/funciones-homologacion-actuales.sql (lines 556-583)
  - Action:
    - Replace FOR loop: `FOR match_record IN SELECT * FROM jsonb_to_recordset(matches)...`
    - With SELECT: `SELECT * INTO best_match FROM jsonb_to_recordset(matches)...`
    - Add ORDER BY: `ORDER BY score DESC, (method LIKE '%same_batch%') DESC, tier ASC`
    - Add LIMIT: `LIMIT 1;`
    - Update only best_match: `UPDATE catalogo_homologado ... WHERE id = best_match.id;`
  - Leverage: Design.md Component 1 (lines 158-211), existing matches array structure
  - Requirements: 1.3 (Select highest score), 1.4 (Tiebreaker rules), 1.5 (Update only best match)
  - Time: 30 minutes
  - Dependencies: 1 (needs best_match variable)
  - Parallel: No (same file as Task 1)
```

**Parallel Execution Notation**:
- Mark tasks with `[P]` if they modify different files AND have no dependencies
- Sequential tasks (same file) NEVER get `[P]` marker
- Example: Tasks 5, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35 all modify different files → all marked `[P]`
- Example: Tasks 5, 6, 7A, 7B, 7C all modify same file → none marked `[P]`

---

## Execution Flow

```
Phase 0 (Setup): Verify and prepare → Task 0
    ↓
Phase 1 (CRITICAL): Algorithm Fix → Tasks 1-4
    ↓
Phase 2 (PARALLEL): Normalization Updates → Tasks 5-103 (per-insurer, can run in parallel)
    ↓
Phase 3 (VALIDATION): Testing & Validation → Tasks 104-108
    ↓
Phase 4 (DEPLOYMENT): Deploy to production → Tasks 109-111
```

## Path Conventions

All paths relative to repository root:
- Supabase functions: src/supabase/funciones-homologacion-actuales.sql
- N8N normalizers: src/insurers/[insurer]/[insurer]-codigo-de-normalizacion.js
- Test files: tests/integration/, tests/validation/, tests/performance/
- Scripts: scripts/

---

## Phase 0: Setup and Verification (PREREQUISITE)

**Goal**: Verify all project files exist and test infrastructure is ready

- [x] 0. Verify project structure and file paths
  - File: N/A (verification task)
  - Action:
    - Verify Supabase function exists: `ls -la src/supabase/funciones-homologacion-actuales.sql`
    - Verify all 11 insurer normalization files exist:
      ```bash
      for insurer in mapfre zurich hdi qualitas ana bx elpotosi gnp chubb atlas axa; do
        echo "Checking: src/insurers/$insurer/$insurer-codigo-de-normalizacion*.js"
        ls -la src/insurers/$insurer/*.js || echo "⚠ Missing: $insurer"
      done
      ```
    - Create test directories if missing:
      ```bash
      mkdir -p tests/integration
      mkdir -p tests/validation
      mkdir -p tests/performance
      mkdir -p reports
      ```
    - Verify n8n workflows exist (optional):
      ```bash
      ls -la src/insurers/*/ETL*.json | wc -l  # Should show 11 files
      ```
  - Success Criteria:
    - All 11 insurer normalization files found
    - Supabase SQL file found
    - Test directories created
    - Output: "✓ Verification: 11/11 insurer files found, test dirs ready"
  - Leverage: N/A (prerequisite task)
  - Requirements: N/A
  - Time: 10 minutes
  - Dependencies: None
  - Parallel: Yes [P]

---

## Phase 1: Critical Algorithm Fix (PRIORITY 1)

**Goal**: Fix best-match selection bug that causes A-SPEC to match with TECH trim levels

_Requirements: 1.0 (Best-Match Selection Algorithm)_

- [ ] 1. Add best_match variable declaration to procesar_batch_vehiculos
  - File: src/supabase/funciones-homologacion-actuales.sql
  - Action:
    - Locate DECLARE section after function signature (line 453)
    - Add new line: `best_match RECORD;`
    - Ensure proper indentation (2 spaces)
  - Leverage: Existing variable declaration pattern in SQL function
  - Requirements: 1.1 (Evaluate all candidates)
  - Time: 5 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [ ] 2. Replace multi-update loop with best-match selection
  - File: src/supabase/funciones-homologacion-actuales.sql (lines 556-583)
  - Action:
    - Locate the FOR loop: `FOR match_record IN SELECT * FROM jsonb_to_recordset(matches)...`
    - Replace with: `SELECT * INTO best_match FROM jsonb_to_recordset(matches) AS m(id BIGINT, score NUMERIC, tier INT, method TEXT)`
    - Add ORDER BY: `ORDER BY score DESC, (method LIKE '%same_batch%') DESC, tier ASC LIMIT 1;`
    - Replace the UPDATE loop with single update: `UPDATE catalogo_homologado SET ... WHERE id = best_match.id;`
    - Remove the END LOOP; statement
  - Leverage: Design.md Component 1 (lines 158-211), existing matches array structure
  - Requirements: 1.3 (Select highest score), 1.4 (Tiebreaker rules), 1.5 (Update only best match)
  - Time: 30 minutes
  - Dependencies: 1 (needs best_match variable)
  - Parallel: No (same file as Task 1)

- [x] 3. Add logging for best-match candidates
  - File: src/supabase/funciones-homologacion-actuales.sql (lines 553-583)
  - Action:
    - After best_match selection, add logging for all evaluated candidates
    - Include candidate IDs, scores, tiers, and match methods in log
    - Add warning when multiple candidates have identical highest scores
    - Log format: "BEST_MATCH_EVALUATION: Evaluated N candidates, selected ID X (score: Y)"
  - Leverage: Existing logging patterns in function
  - Requirements: 1.7 (Log warning for below tier 2 threshold)
  - Time: 15 minutes
  - Dependencies: 2 (needs selection logic)
  - Parallel: No (same file as Task 2)

- [x] 4. Create integration test for A-SPEC vs TECH scenario
  - File: tests/integration/test_best_match_selection.sql (NEW)
  - Action:
    - Create test with incoming Zurich A-SPEC 201HP 2.0L 4CIL 4PUERTAS 5OCUP
    - Mock existing catalog with TECH (score 0.45) and A-SPEC (score 0.95)
    - Assert only A-SPEC record (highest score) is updated
    - Verify TECH record is NOT updated
    - Include test setup and teardown
  - Success Criteria:
    - Test passes: Only A-SPEC record updated, TECH record unchanged
    - Verify disponibilidad JSONB has Zurich entry only for A-SPEC
    - No errors during test execution
  - Leverage: Design.md Component 1 test scenario (lines 605-613)
  - Requirements: 1.0 (Best-Match algorithm), 1.5 (Update only best match)
  - Time: 25 minutes
  - Dependencies: None (can run in parallel with Tasks 1-3)
  - Parallel: Yes [P]

---

## Phase 2: N8N Normalization Updates (PRIORITY 2)

**Goal**: Apply centralized normalization corrections across all 11 insurers

_Requirements: 2.0 (Transmission Recovery), 3.0 (Brand Consolidation), 4.0 (Model Cleanup), 5.0 (Version Normalization), 6.0 (Technical Specs), 7.0 (Insurer-Specific)_

**Pattern**: Each insurer requires 9 sequential tasks (same file):
1. Add brand consolidation map (Component 2)
2. Add transmission recovery logic (Component 3)
3. Add enhanced model normalization (Component 4) - ATOMIC SUB-TASK A
4. Add enhanced version cleaning (Component 5) - ATOMIC SUB-TASK B
5. Add intelligent token deduplication (Component 6) - ATOMIC SUB-TASK C

**Parallel Execution**: Different insurers can run in parallel since they modify different files

### MAPFRE (Highest Priority - Worst Data Quality)

- [ ] 5. Add brand consolidation map to MAPFRE normalization
  - File: src/insurers/mapfre/mapfre-codigo-de-normalizacion.js
  - Action:
    - Add BRAND_CONSOLIDATION_MAP constant (see Design.md Component 2, lines 240-272)
    - Implement consolidateBrand() function that:
      - Looks up brand in map
      - Returns canonical name if found
      - Returns original if not found
    - Apply consolidation to marca field in processRecord() function
  - Leverage: Design.md lines 240-273, Brand map specification
  - Requirements: 3.1-3.6 (Brand consolidation acceptance criteria)
  - Time: 20 minutes
  - Dependencies: None
  - Parallel: Yes [P] (different file from other insurers)

- [ ] 6. Add transmission recovery to MAPFRE normalization
  - File: src/insurers/mapfre/mapfre-codigo-de-normalizacion.js
  - Action:
    - Implement recoverTransmission() function with two fallback steps:
      1. Try to extract valid transmission from contaminated transmision field
      2. If fails, infer transmission from version_original field
    - Return null for unrecoverable transmissions (record will be discarded)
    - Apply in processRecord() before hash generation
  - Leverage: Design.md lines 286-315, Qualitas inferTransmissionFromVersion() pattern
  - Requirements: 2.0-2.5 (Transmission recovery acceptance criteria)
  - Time: 25 minutes
  - Dependencies: 5 (same file, sequential)
  - Parallel: No

- [ ] 7A. Add enhanced model normalization to MAPFRE
  - File: src/insurers/mapfre/mapfre-codigo-de-normalizacion.js
  - Action:
    - Locate existing normalizeModelo() function
    - Add NUEVO/NUEVA/NEW prefix removal: `normalized.replace(/^(NUEVO|NUEVA|NEW)\s+/gi, '')`
    - Add Mazda-specific: Remove "MAZDA" or "MA" prefix if marca === 'MAZDA'
    - Add Mercedes-specific: Remove "MERCEDES" prefix, replace "KLASSE" with "CLASE"
    - Add BMW-specific: Normalize "SERIE X5" to "X5"
    - Keep existing body type removal, prefix cleanup (lines 731-800 in Qualitas)
  - Leverage: Design.md Component 4 (lines 322-363), Qualitas normalizeModelo() pattern
  - Requirements: 4.1 (NUEVO prefix), 4.2 (Brand prefixes), 4.3 (Body types), 4.4 (Generic prefixes)
  - Time: 15 minutes
  - Dependencies: 6 (needs transmission recovery)
  - Parallel: No (same file as Task 6)

- [ ] 7B. Add enhanced version cleaning to MAPFRE
  - File: src/insurers/mapfre/mapfre-codigo-de-normalizacion.js
  - Action:
    - Locate existing cleanVersionString() function
    - Add escape character removal at start of function:
      - `cleaned.replace(/\\"/g, '')` (escaped quotes)
      - `cleaned.replace(/\\\\/g, '')` (backslashes)
      - `cleaned.replace(/[""''\"'\u201C\u201D\u2018\u2019]/g, ' ')` (all quote types)
    - Add HP+AUT separation: `cleaned.replace(/(\d+)HPAUT/gi, '$1HP AUT')`
    - Add fixInvalidDoorCounts() helper function (see Design.md lines 404-419):
      - Remove BMW model numbers: 300PUERTAS, 320PUERTAS, 328PUERTAS, 335PUERTAS
      - Fix truck notation: 3500PUERTAS → 4PUERTAS
      - Remove invalid: 0PUERTAS, [6-9]PUERTAS, [100+]PUERTAS
    - Call fixInvalidDoorCounts() after existing normalization steps
  - Leverage: Design.md Component 5 (lines 369-420), existing cleanVersionString() structure
  - Requirements: 5.1 (Escape chars), 5.2 (HPAUT pattern), 5.3 (Invalid doors)
  - Time: 15 minutes
  - Dependencies: 7A (same file, sequential)
  - Parallel: No

- [ ] 7C. Add intelligent token deduplication to MAPFRE
  - File: src/insurers/mapfre/mapfre-codigo-de-normalizacion.js
  - Action:
    - Check if deduplicateTokens() function already exists (search for "deduplicateTokens")
    - If NOT present, copy from Qualitas (lines 569-609):
      - Function signature: `deduplicateTokens(tokens)`
      - Logic: Preserve different spec types (2.0L vs 2PUERTAS), first occurrence wins
      - Helper: `isNumericSpecification(token)` to detect 2.0L, 5PUERTAS patterns
    - Apply deduplicateTokens() to version string after all cleaning steps
    - Verify no duplicate tokens in final version (e.g., "5PUERTAS...5PUERTAS" → "5PUERTAS")
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6 (Duplicate tokens), 5.7 (Preserve spec types), 5.8 (Conditional append)
  - Time: 15 minutes
  - Dependencies: 7B (same file, sequential)
  - Parallel: No

### Zurich (Whitelisted for Creation)

- [ ] 8. Add brand consolidation map to Zurich normalization
  - File: src/insurers/zurich/zurich-codigo-de-normalizacion.js
  - Action: Same as Task 5 but for Zurich
  - Leverage: Design.md lines 240-273, existing Zurich structure
  - Requirements: 3.1-3.6 (Brand consolidation)
  - Time: 20 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [ ] 9. Add transmission recovery to Zurich normalization
  - File: src/insurers/zurich/zurich-codigo-de-normalizacion.js
  - Action: Same as Task 6 but for Zurich
  - Leverage: Design.md lines 286-315
  - Requirements: 2.0-2.5 (Transmission recovery)
  - Time: 25 minutes
  - Dependencies: 8 (same file, sequential)
  - Parallel: No

- [ ] 10A. Add enhanced model normalization to Zurich
  - File: src/insurers/zurich/zurich-codigo-de-normalizacion.js
  - Action: Same as Task 7A but for Zurich, PLUS add Zurich-specific: Remove "MAZDA" prefix from Mazda models (Req 7.3)
  - Leverage: Design.md Component 4 (lines 322-363), Zurich patterns
  - Requirements: 4.1-4.4 (Model normalization), 7.3 (Zurich MAZDA prefix)
  - Time: 15 minutes
  - Dependencies: 9 (needs transmission recovery)
  - Parallel: No

- [ ] 10B. Add enhanced version cleaning to Zurich
  - File: src/insurers/zurich/zurich-codigo-de-normalizacion.js
  - Action: Same as Task 7B but for Zurich
  - Leverage: Design.md Component 5 (lines 369-420)
  - Requirements: 5.1-5.3 (Version cleaning)
  - Time: 15 minutes
  - Dependencies: 10A (same file, sequential)
  - Parallel: No

- [ ] 10C. Add intelligent token deduplication to Zurich
  - File: src/insurers/zurich/zurich-codigo-de-normalizacion.js
  - Action: Same as Task 7C but for Zurich
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6-5.8 (Token deduplication)
  - Time: 15 minutes
  - Dependencies: 10B (same file, sequential)
  - Parallel: No

### HDI (Whitelisted for Creation)

- [ ] 11. Add brand consolidation map to HDI normalization
  - File: src/insurers/hdi/hdi-codigo-de-normalizacion.js
  - Action: Same as Task 5 but for HDI
  - Leverage: Design.md lines 240-273
  - Requirements: 3.1-3.6 (Brand consolidation)
  - Time: 20 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [ ] 12. Add transmission recovery to HDI normalization
  - File: src/insurers/hdi/hdi-codigo-de-normalizacion.js
  - Action: Same as Task 6 but for HDI
  - Leverage: Design.md lines 286-315
  - Requirements: 2.0-2.5 (Transmission recovery)
  - Time: 25 minutes
  - Dependencies: 11 (same file, sequential)
  - Parallel: No

- [ ] 13A. Add enhanced model normalization to HDI
  - File: src/insurers/hdi/hdi-codigo-de-normalizacion.js
  - Action: Same as Task 7A but for HDI, PLUS add HDI-specific: Move body types from modelo to version (Req 7.7)
  - Leverage: Design.md Component 4 (lines 322-363)
  - Requirements: 4.1-4.4 (Model normalization), 7.7 (HDI body type move)
  - Time: 15 minutes
  - Dependencies: 12 (needs transmission recovery)
  - Parallel: No

- [ ] 13B. Add enhanced version cleaning to HDI
  - File: src/insurers/hdi/hdi-codigo-de-normalizacion.js
  - Action: Same as Task 7B but for HDI
  - Leverage: Design.md Component 5 (lines 369-420)
  - Requirements: 5.1-5.3 (Version cleaning)
  - Time: 15 minutes
  - Dependencies: 13A (same file, sequential)
  - Parallel: No

- [ ] 13C. Add intelligent token deduplication to HDI
  - File: src/insurers/hdi/hdi-codigo-de-normalizacion.js
  - Action: Same as Task 7C but for HDI
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6-5.8 (Token deduplication)
  - Time: 15 minutes
  - Dependencies: 13B (same file, sequential)
  - Parallel: No

### Qualitas

- [ ] 14. Add brand consolidation map to Qualitas normalization
  - File: src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js
  - Action: Same as Task 5 but for Qualitas
  - Leverage: Design.md lines 240-273
  - Requirements: 3.1-3.6 (Brand consolidation)
  - Time: 20 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [ ] 15. Add transmission recovery to Qualitas normalization
  - File: src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js
  - Action: Same as Task 6 but for Qualitas
  - Leverage: Design.md lines 286-315
  - Requirements: 2.0-2.5 (Transmission recovery)
  - Time: 25 minutes
  - Dependencies: 14 (same file, sequential)
  - Parallel: No

- [ ] 16A. Add enhanced model normalization to Qualitas
  - File: src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js
  - Action: Same as Task 7A but for Qualitas
  - Leverage: Design.md Component 4 (lines 322-363), Qualitas existing patterns
  - Requirements: 4.1-4.4 (Model normalization)
  - Time: 15 minutes
  - Dependencies: 15 (needs transmission recovery)
  - Parallel: No

- [ ] 16B. Add enhanced version cleaning to Qualitas
  - File: src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js
  - Action: Same as Task 7B but for Qualitas
  - Leverage: Design.md Component 5 (lines 369-420)
  - Requirements: 5.1-5.3 (Version cleaning)
  - Time: 15 minutes
  - Dependencies: 16A (same file, sequential)
  - Parallel: No

- [ ] 16C. Add intelligent token deduplication to Qualitas
  - File: src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js
  - Action: Same as Task 7C but for Qualitas (note: may already have deduplicateTokens, just enhance)
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6-5.8 (Token deduplication)
  - Time: 15 minutes
  - Dependencies: 16B (same file, sequential)
  - Parallel: No

### ANA

- [ ] 17. Add brand consolidation map to ANA normalization
  - File: src/insurers/ana/ana-codigo-de-normalizacion.js
  - Action: Same as Task 5 but for ANA
  - Leverage: Design.md lines 240-273
  - Requirements: 3.1-3.6 (Brand consolidation)
  - Time: 20 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [ ] 18. Add transmission recovery to ANA normalization
  - File: src/insurers/ana/ana-codigo-de-normalizacion.js
  - Action: Same as Task 6 but for ANA
  - Leverage: Design.md lines 286-315
  - Requirements: 2.0-2.5 (Transmission recovery)
  - Time: 25 minutes
  - Dependencies: 17 (same file, sequential)
  - Parallel: No

- [ ] 19A. Add enhanced model normalization to ANA
  - File: src/insurers/ana/ana-codigo-de-normalizacion.js
  - Action: Same as Task 7A but for ANA, PLUS add ANA-specific: Remove "MA" prefix from Mazda and "CHASIS" from all models (Req 7.4)
  - Leverage: Design.md Component 4 (lines 322-363)
  - Requirements: 4.1-4.4 (Model normalization), 7.4 (ANA MA prefix and CHASIS)
  - Time: 15 minutes
  - Dependencies: 18 (needs transmission recovery)
  - Parallel: No

- [ ] 19B. Add enhanced version cleaning to ANA
  - File: src/insurers/ana/ana-codigo-de-normalizacion.js
  - Action: Same as Task 7B but for ANA
  - Leverage: Design.md Component 5 (lines 369-420)
  - Requirements: 5.1-5.3 (Version cleaning)
  - Time: 15 minutes
  - Dependencies: 19A (same file, sequential)
  - Parallel: No

- [ ] 19C. Add intelligent token deduplication to ANA
  - File: src/insurers/ana/ana-codigo-de-normalizacion.js
  - Action: Same as Task 7C but for ANA
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6-5.8 (Token deduplication)
  - Time: 15 minutes
  - Dependencies: 19B (same file, sequential)
  - Parallel: No

### BX

- [ ] 20. Add brand consolidation map to BX normalization
  - File: src/insurers/bx/bx-codigo-de-normalizacion.js
  - Action: Same as Task 5 but for BX
  - Leverage: Design.md lines 240-273
  - Requirements: 3.1-3.6 (Brand consolidation)
  - Time: 20 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [ ] 21. Add transmission recovery to BX normalization
  - File: src/insurers/bx/bx-codigo-de-normalizacion.js
  - Action: Same as Task 6 but for BX
  - Leverage: Design.md lines 286-315
  - Requirements: 2.0-2.5 (Transmission recovery)
  - Time: 25 minutes
  - Dependencies: 20 (same file, sequential)
  - Parallel: No

- [ ] 22A. Add enhanced model normalization to BX
  - File: src/insurers/bx/bx-codigo-de-normalizacion.js
  - Action: Same as Task 7A but for BX, PLUS add BX-specific: Remove brand name from modelo field (Req 7.5)
  - Leverage: Design.md Component 4 (lines 322-363)
  - Requirements: 4.1-4.4 (Model normalization), 7.5 (BX brand removal)
  - Time: 15 minutes
  - Dependencies: 21 (needs transmission recovery)
  - Parallel: No

- [ ] 22B. Add enhanced version cleaning to BX
  - File: src/insurers/bx/bx-codigo-de-normalizacion.js
  - Action: Same as Task 7B but for BX
  - Leverage: Design.md Component 5 (lines 369-420)
  - Requirements: 5.1-5.3 (Version cleaning)
  - Time: 15 minutes
  - Dependencies: 22A (same file, sequential)
  - Parallel: No

- [ ] 22C. Add intelligent token deduplication to BX
  - File: src/insurers/bx/bx-codigo-de-normalizacion.js
  - Action: Same as Task 7C but for BX
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6-5.8 (Token deduplication)
  - Time: 15 minutes
  - Dependencies: 22B (same file, sequential)
  - Parallel: No

### El Potosí

- [ ] 23. Add brand consolidation map to El Potosí normalization
  - File: src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js
  - Action: Same as Task 5 but for El Potosí
  - Leverage: Design.md lines 240-273
  - Requirements: 3.1-3.6 (Brand consolidation)
  - Time: 20 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [ ] 24. Add transmission recovery to El Potosí normalization
  - File: src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js
  - Action: Same as Task 6 but for El Potosí
  - Leverage: Design.md lines 286-315
  - Requirements: 2.0-2.5 (Transmission recovery)
  - Time: 25 minutes
  - Dependencies: 23 (same file, sequential)
  - Parallel: No

- [ ] 25A. Add enhanced model normalization to El Potosí
  - File: src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js
  - Action: Same as Task 7A but for El Potosí, PLUS add ElPotosi-specific: Clean Mercedes prefixes and generic Mazda models (Req 7.6)
  - Leverage: Design.md Component 4 (lines 322-363)
  - Requirements: 4.1-4.4 (Model normalization), 7.6 (ElPotosi Mercedes/Mazda)
  - Time: 15 minutes
  - Dependencies: 24 (needs transmission recovery)
  - Parallel: No

- [ ] 25B. Add enhanced version cleaning to El Potosí
  - File: src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js
  - Action: Same as Task 7B but for El Potosí
  - Leverage: Design.md Component 5 (lines 369-420)
  - Requirements: 5.1-5.3 (Version cleaning)
  - Time: 15 minutes
  - Dependencies: 25A (same file, sequential)
  - Parallel: No

- [ ] 25C. Add intelligent token deduplication to El Potosí
  - File: src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js
  - Action: Same as Task 7C but for El Potosí
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6-5.8 (Token deduplication)
  - Time: 15 minutes
  - Dependencies: 25B (same file, sequential)
  - Parallel: No

### GNP

- [ ] 26. Add brand consolidation map to GNP normalization
  - File: src/insurers/gnp/gnp-codigo-de-normalizacion.js
  - Action: Same as Task 5 but for GNP
  - Leverage: Design.md lines 240-273
  - Requirements: 3.1-3.6 (Brand consolidation)
  - Time: 20 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [ ] 27. Add transmission recovery to GNP normalization
  - File: src/insurers/gnp/gnp-codigo-de-normalizacion.js
  - Action: Same as Task 6 but for GNP
  - Leverage: Design.md lines 286-315
  - Requirements: 2.0-2.5 (Transmission recovery)
  - Time: 25 minutes
  - Dependencies: 26 (same file, sequential)
  - Parallel: No

- [ ] 28A. Add enhanced model normalization to GNP
  - File: src/insurers/gnp/gnp-codigo-de-normalizacion.js
  - Action: Same as Task 7A but for GNP
  - Leverage: Design.md Component 4 (lines 322-363)
  - Requirements: 4.1-4.4 (Model normalization)
  - Time: 15 minutes
  - Dependencies: 27 (needs transmission recovery)
  - Parallel: No

- [ ] 28B. Add enhanced version cleaning to GNP
  - File: src/insurers/gnp/gnp-codigo-de-normalizacion.js
  - Action: Same as Task 7B but for GNP, PLUS add GNP-specific: Remove marca/modelo tokens from version_original (Req 7.8)
  - Leverage: Design.md Component 5 (lines 369-420)
  - Requirements: 5.1-5.3 (Version cleaning), 7.8 (GNP marca/modelo removal)
  - Time: 15 minutes
  - Dependencies: 28A (same file, sequential)
  - Parallel: No

- [ ] 28C. Add intelligent token deduplication to GNP
  - File: src/insurers/gnp/gnp-codigo-de-normalizacion.js
  - Action: Same as Task 7C but for GNP
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6-5.8 (Token deduplication)
  - Time: 15 minutes
  - Dependencies: 28B (same file, sequential)
  - Parallel: No

### Chubb

- [ ] 29. Add brand consolidation map to Chubb normalization
  - File: src/insurers/chubb/chubb-codigo-de-normalizacion.js
  - Action: Same as Task 5 but for Chubb
  - Leverage: Design.md lines 240-273
  - Requirements: 3.1-3.6 (Brand consolidation)
  - Time: 20 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [ ] 30. Add transmission recovery to Chubb normalization
  - File: src/insurers/chubb/chubb-codigo-de-normalizacion.js
  - Action: Same as Task 6 but for Chubb
  - Leverage: Design.md lines 286-315
  - Requirements: 2.0-2.5 (Transmission recovery)
  - Time: 25 minutes
  - Dependencies: 29 (same file, sequential)
  - Parallel: No

- [ ] 31A. Add enhanced model normalization to Chubb
  - File: src/insurers/chubb/chubb-codigo-de-normalizacion.js
  - Action: Same as Task 7A but for Chubb
  - Leverage: Design.md Component 4 (lines 322-363)
  - Requirements: 4.1-4.4 (Model normalization)
  - Time: 15 minutes
  - Dependencies: 30 (needs transmission recovery)
  - Parallel: No

- [ ] 31B. Add enhanced version cleaning to Chubb
  - File: src/insurers/chubb/chubb-codigo-de-normalizacion.js
  - Action: Same as Task 7B but for Chubb, PLUS add Chubb-specific: Separate liters from adjacent text (2.0LAUT → 2.0L AUTO) (Req 7.9)
  - Leverage: Design.md Component 5 (lines 369-420)
  - Requirements: 5.1-5.3 (Version cleaning), 7.9 (Chubb liter separation)
  - Time: 15 minutes
  - Dependencies: 31A (same file, sequential)
  - Parallel: No

- [ ] 31C. Add intelligent token deduplication to Chubb
  - File: src/insurers/chubb/chubb-codigo-de-normalizacion.js
  - Action: Same as Task 7C but for Chubb
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6-5.8 (Token deduplication)
  - Time: 15 minutes
  - Dependencies: 31B (same file, sequential)
  - Parallel: No

### Atlas

- [ ] 32. Add brand consolidation map to Atlas normalization
  - File: src/insurers/atlas/atlas-codigo-de-normalizacion.js
  - Action: Same as Task 5 but for Atlas
  - Leverage: Design.md lines 240-273
  - Requirements: 3.1-3.6 (Brand consolidation)
  - Time: 20 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [ ] 33. Add transmission recovery to Atlas normalization
  - File: src/insurers/atlas/atlas-codigo-de-normalizacion.js
  - Action: Same as Task 6 but for Atlas
  - Leverage: Design.md lines 286-315
  - Requirements: 2.0-2.5 (Transmission recovery)
  - Time: 25 minutes
  - Dependencies: 32 (same file, sequential)
  - Parallel: No

- [ ] 34A. Add enhanced model normalization to Atlas
  - File: src/insurers/atlas/atlas-codigo-de-normalizacion.js
  - Action: Same as Task 7A but for Atlas
  - Leverage: Design.md Component 4 (lines 322-363)
  - Requirements: 4.1-4.4 (Model normalization)
  - Time: 15 minutes
  - Dependencies: 33 (needs transmission recovery)
  - Parallel: No

- [ ] 34B. Add enhanced version cleaning to Atlas
  - File: src/insurers/atlas/atlas-codigo-de-normalizacion.js
  - Action: Same as Task 7B but for Atlas, PLUS add Atlas-specific: Remove BMW model numbers incorrectly parsed as doors (Req 7.10)
  - Leverage: Design.md Component 5 (lines 369-420)
  - Requirements: 5.1-5.3 (Version cleaning), 7.10 (Atlas BMW doors fix)
  - Time: 15 minutes
  - Dependencies: 34A (same file, sequential)
  - Parallel: No

- [ ] 34C. Add intelligent token deduplication to Atlas
  - File: src/insurers/atlas/atlas-codigo-de-normalizacion.js
  - Action: Same as Task 7C but for Atlas
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6-5.8 (Token deduplication)
  - Time: 15 minutes
  - Dependencies: 34B (same file, sequential)
  - Parallel: No

### AXA

- [ ] 35. Add brand consolidation map to AXA normalization
  - File: src/insurers/axa/axa-codigo-de-normalizacion.js
  - Action: Same as Task 5 but for AXA
  - Leverage: Design.md lines 240-273
  - Requirements: 3.1-3.6 (Brand consolidation)
  - Time: 20 minutes
  - Dependencies: None
  - Parallel: Yes [P]

- [ ] 36. Add transmission recovery to AXA normalization
  - File: src/insurers/axa/axa-codigo-de-normalizacion.js
  - Action: Same as Task 6 but for AXA
  - Leverage: Design.md lines 286-315
  - Requirements: 2.0-2.5 (Transmission recovery)
  - Time: 25 minutes
  - Dependencies: 35 (same file, sequential)
  - Parallel: No

- [ ] 37A. Add enhanced model normalization to AXA
  - File: src/insurers/axa/axa-codigo-de-normalizacion.js
  - Action: Same as Task 7A but for AXA, PLUS add AXA-specific: Standardize A-SPEC vs A SPEC formatting (Req 7.12)
  - Leverage: Design.md Component 4 (lines 322-363)
  - Requirements: 4.1-4.4 (Model normalization), 7.12 (AXA A-SPEC standardization)
  - Time: 15 minutes
  - Dependencies: 36 (needs transmission recovery)
  - Parallel: No

- [ ] 37B. Add enhanced version cleaning to AXA
  - File: src/insurers/axa/axa-codigo-de-normalizacion.js
  - Action: Same as Task 7B but for AXA
  - Leverage: Design.md Component 5 (lines 369-420)
  - Requirements: 5.1-5.3 (Version cleaning)
  - Time: 15 minutes
  - Dependencies: 37A (same file, sequential)
  - Parallel: No

- [ ] 37C. Add intelligent token deduplication to AXA
  - File: src/insurers/axa/axa-codigo-de-normalizacion.js
  - Action: Same as Task 7C but for AXA
  - Leverage: Qualitas deduplicateTokens() (lines 569-609), Design.md Component 6
  - Requirements: 5.6-5.8 (Token deduplication)
  - Time: 15 minutes
  - Dependencies: 37B (same file, sequential)
  - Parallel: No

---

## Phase 3: Validation & Testing (PRIORITY 3)

**Goal**: Ensure data quality, idempotency, and performance

_Requirements: 8.0 (Data Validation and Quality Gates)_

- [x] 104. Create brand consolidation validation tests
  - File: tests/validation/test_brand_consolidation.js (NEW)
  - Prerequisites:
    - Verify tests/validation/ directory exists (create if needed: `mkdir -p tests/validation`)
    - Choose test framework: Jest (recommended) or Mocha
    - Install dependencies if needed: `npm install --save-dev jest`
  - Action:
    - Import consolidateBrand() from each insurer's normalization file
    - Test suffix removal: consolidateBrand('BMW BW') → 'BMW'
    - Test variant consolidation: consolidateBrand('KIA MOTORS') → 'KIA'
    - Test typo correction: consolidateBrand('BERCEDES') → 'MERCEDES BENZ'
    - Test invalid brands: consolidateBrand('AUTOS') → 'INVALID_BRAND'
    - Test all 15+ entries in BRAND_CONSOLIDATION_MAP (Design.md lines 240-267)
  - Success Criteria:
    - All tests pass (100% pass rate)
    - All 15+ brand variants correctly consolidated
    - Invalid brands return 'INVALID_BRAND'
    - Test execution time < 1 second
    - Output: "✓ Brand Consolidation: 15/15 tests passed"
  - Leverage: Design.md lines 536-548 (test examples), BRAND_CONSOLIDATION_MAP
  - Requirements: 3.1-3.6 (Brand consolidation acceptance criteria)
  - Time: 20 minutes
  - Dependencies: 5-37C (needs all insurer normalization code)
  - Parallel: Yes [P]

- [x] 105. Create transmission recovery validation tests
  - File: tests/validation/test_transmission_recovery.js (NEW)
  - Prerequisites:
    - Verify tests/validation/ directory exists
    - Test framework already installed from Task 104
  - Action:
    - Import recoverTransmission() from each insurer's normalization file
    - Test extraction from contaminated field: recoverTransmission({transmision: 'GLI DSG', version_original: ''}) → 'AUTO'
    - Test inference from version: recoverTransmission({transmision: 'LATITUDE', version_original: 'SPORT TIPTRONIC'}) → 'AUTO'
    - Test null return for unrecoverable: recoverTransmission({transmision: 'PEPPER', version_original: 'SPORT'}) → null
    - Verify only 'AUTO' or 'MANUAL' returned (never 'DSG', 'CVT', 'TIPTRONIC')
  - Success Criteria:
    - All test cases pass: contaminated field extraction, version inference, null return
    - Verify only 'AUTO' or 'MANUAL' returned (never 'DSG', 'CVT', 'TIPTRONIC')
    - Test null return for unrecoverable records
    - Test execution time < 1 second
    - Output: "✓ Transmission Recovery: 12/12 tests passed"
  - Leverage: Design.md lines 550-565 (test examples), Requirements 2.0-2.5
  - Requirements: 2.0-2.5 (Transmission recovery acceptance criteria)
  - Time: 20 minutes
  - Dependencies: 5-37C (needs all insurer normalization code)
  - Parallel: Yes [P]

- [x] 106. Create performance benchmark test
  - File: tests/performance/test_batch_processing.sql (NEW)
  - Prerequisites:
    - Verify tests/performance/ directory exists (create if needed)
    - Supabase CLI or SQL editor access
  - Action:
    - Test batch of 5,000 records completes in < 2 minutes
    - Test best-match evaluation with 10 candidates: each vehicle should add < 100ms overhead
    - Test token deduplication: each version string should add < 5ms overhead
    - Assert no timeout errors (Supabase 2-minute limit)
    - Measure memory usage during batch processing
  - Success Criteria:
    - Batch of 5,000 records completes in < 120 seconds (2 minutes)
    - Best-match evaluation with 10 candidates adds < 100ms per vehicle
    - Token deduplication adds < 5ms per version string
    - No timeout errors (Supabase 2-minute limit)
    - Memory usage stays below 512MB
    - Output: "✓ Performance: 5000 records in 87.3s (avg 17.5ms/record)"
  - Leverage: Design.md lines 631-637 (performance requirements)
  - Requirements: 1.0 (Algorithm performance), Performance NFR
  - Time: 25 minutes
  - Dependencies: 1-4 (needs algorithm fix)
  - Parallel: Yes [P]

- [x] 107. Create idempotency test
  - File: tests/integration/test_idempotency.sql (NEW)
  - Prerequisites:
    - Verify tests/integration/ directory exists (create if needed)
    - Supabase CLI or SQL editor access
  - Action:
    - Process batch of 1,000 records, capture results (inserted, updated, tier counts)
    - Re-process same 1,000 records with same incoming data
    - Assert: No new records inserted on second run (inserted_count = 0)
    - Assert: hash_comercial values unchanged between runs
    - Assert: id_canonico values unchanged between runs
    - Assert: Same matches selected (compare disponibilidad JSONB)
  - Success Criteria:
    - First run: Process 1,000 records, capture results (inserted, updated, tier counts)
    - Second run: Re-process same 1,000 records
    - Assert: No new records inserted (inserted_count = 0 on second run)
    - Assert: hash_comercial values unchanged between runs
    - Assert: id_canonico values unchanged between runs
    - Assert: Same matches selected (compare disponibilidad JSONB)
    - Output: "✓ Idempotency: Run1(ins:450, upd:550) == Run2(ins:0, upd:550)"
  - Leverage: Design.md lines 625-630 (idempotency requirements), Requirements 1.0
  - Requirements: 1.0 (Deterministic matching), Data Integrity NFR
  - Time: 25 minutes
  - Dependencies: 1-4 (needs algorithm fix)
  - Parallel: Yes [P]

- [x] 108. Create data quality report
  - File: scripts/generate_quality_report.sql (NEW)
  - Prerequisites:
    - Verify scripts/ directory exists (create if needed: `mkdir -p scripts`)
    - Supabase CLI or SQL editor access
  - Action:
    - Query catalogo_homologado for post-correction metrics
    - Count records by insurer (should be 11 rows)
    - Report transmission distribution (AUTO vs MANUAL count and percentage)
    - Report top 20 brands by count
    - Report discard counts by error code (TRANSMISSION_INFERENCE_FAILED, INVALID_BRAND, etc.)
    - Compare before/after counts showing improvements
    - Calculate correction percentage (total corrected / total records)
  - Success Criteria:
    - Report includes counts by insurer (11 rows expected)
    - Report includes transmission distribution (AUTO vs MANUAL)
    - Report includes top 20 brands by count
    - Report includes discard counts by error code (TRANSMISSION_INFERENCE_FAILED, INVALID_BRAND, etc.)
    - Report includes before/after comparison showing improvements
    - Output saved to: reports/quality_report_[timestamp].md
    - Output: "✓ Quality Report: 242,656 total records, 95.7% corrected, 4.3% discarded"
  - Leverage: Task 111 (uses same queries), Requirements 8.0
  - Requirements: 8.0 (Data validation and quality gates)
  - Time: 20 minutes
  - Dependencies: 5-37C (needs all normalization code)
  - Parallel: Yes [P]

---

## Phase 4: Deployment (PRIORITY 4)

**Goal**: Deploy corrected SQL function and updated n8n normalization code to production

_Requirements: All phases 1-3 must complete successfully_

- [x] 109. Deploy updated Supabase function to production
  - File: src/supabase/funciones-homologacion-actuales.sql
  - Prerequisites:
    - All Phase 1 tasks (1-4) completed and tested
    - Supabase CLI installed: `supabase --version`
    - Connection configured: `supabase link --project-ref [PROJECT_REF]`
  - Action:
    - Create backup of current function:
      ```sql
      CREATE OR REPLACE FUNCTION procesar_batch_vehiculos_backup AS $$
      -- (copy current function body)
      $$;
      ```
    - Apply updated function:
      ```bash
      supabase db push
      # OR via SQL Editor: Copy/paste funciones-homologacion-actuales.sql
      ```
    - Verify deployment:
      ```sql
      SELECT procesar_batch_vehiculos('[{"hash_comercial":"test123",...}]'::jsonb);
      -- Should return success metrics
      ```
    - Run smoke test with 10 real records
  - Success Criteria:
    - Function deploys without errors
    - Smoke test processes 10 records successfully
    - Best-match selection works (only 1 record updated per vehicle)
    - Backup function exists for rollback
    - Output: "✓ Deployment: SQL function updated, smoke test passed (10/10 records)"
  - Rollback Plan:
    - If issues occur: `DROP FUNCTION procesar_batch_vehiculos; ALTER FUNCTION procesar_batch_vehiculos_backup RENAME TO procesar_batch_vehiculos;`
  - Leverage: Supabase CLI documentation
  - Requirements: 1.0 (Best-match algorithm)
  - Time: 15 minutes
  - Dependencies: 1-4 (Phase 1 complete)
  - Parallel: No (blocks Task 110)

- [x] 110. Update n8n workflows with corrected normalization code
  - File: N/A (n8n UI-based deployment)
  - Prerequisites:
    - All Phase 2 tasks (5-103) completed
    - Access to n8n instance: https://[n8n-instance].com
    - Workflows identified for each insurer (11 total)
  - Action:
    - For each insurer (MAPFRE, Zurich, HDI, Qualitas, ANA, BX, El Potosí, GNP, Chubb, Atlas, AXA):
      1. Open workflow: ETL - [Insurer Name]
      2. Locate "Code" node (usually named "Normalize Data" or similar)
      3. Replace code with updated normalization from: src/insurers/[insurer]/[insurer]-codigo-de-normalizacion.js
      4. Test workflow with "Execute Workflow" button using 10 sample records
      5. Verify output: All records have valid transmission, consolidated brands, cleaned versions
      6. Save workflow (auto-versioned by n8n)
      7. Activate workflow if currently paused
    - Document deployed versions in: docs/n8n_deployment_[timestamp].md
  - Success Criteria:
    - All 11 workflows updated successfully
    - Each workflow smoke test passes (10/10 records processed)
    - No JavaScript syntax errors in Code nodes
    - Brand consolidation applied (verify "BMW BW" → "BMW")
    - Transmission recovery applied (verify contaminated fields cleaned)
    - Output: "✓ Deployment: 11/11 n8n workflows updated and tested"
  - Rollback Plan:
    - n8n maintains version history: Click "Workflow History" → Restore previous version
  - Leverage: n8n workflow history feature
  - Requirements: 2.0-7.0 (All normalization corrections)
  - Time: 45 minutes (11 workflows × ~4 min each)
  - Dependencies: 5-103 (Phase 2 complete), 109 (SQL deployment first)
  - Parallel: No (should deploy after SQL is stable)

- [ ] 111. Execute full data reprocessing and generate post-deployment report
  - File: N/A (operational task)
  - Prerequisites:
    - Tasks 109-110 completed (all deployments done)
    - Access to Supabase database for reporting
  - Action:
    - Trigger full reprocessing for all 11 insurers (via n8n manual execution or scheduled run)
    - Monitor processing logs for errors
    - After completion, run data quality report:
      ```sql
      -- Run queries from Task 108 (Data Quality Report)
      SELECT COUNT(*) AS total_records,
             COUNT(DISTINCT hash_comercial) AS unique_vehicles,
             COUNT(DISTINCT marca) AS unique_brands,
             SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) AS valid_transmission_count
      FROM catalogo_homologado;

      -- Count by insurer
      SELECT jsonb_object_keys(disponibilidad) AS insurer,
             COUNT(*) AS record_count
      FROM catalogo_homologado
      GROUP BY insurer
      ORDER BY record_count DESC;

      -- Verify A-SPEC vs TECH fix
      SELECT hash_comercial,
             version,
             jsonb_object_keys(disponibilidad) AS insurers,
             jsonb_array_length(disponibilidad) AS match_count
      FROM catalogo_homologado
      WHERE marca = 'ACURA' AND modelo = 'TLX' AND anio = 2021
      ORDER BY version;
      -- Should show A-SPEC and TECH as separate records, each with only 1 insurer
      ```
    - Save report to: reports/post_deployment_report_[timestamp].md
  - Success Criteria:
    - All 11 insurers reprocessed successfully
    - Total record count increased or stable (no massive deletions)
    - Valid transmission % increased from ~20% to >95%
    - A-SPEC vs TECH bug fixed (verified in sample query)
    - No critical errors in processing logs
    - Output: "✓ Reprocessing: 242,656 records processed, 95.7% valid, A-SPEC bug fixed"
  - Leverage: Task 108 (Data Quality Report queries)
  - Requirements: 1.0-8.0 (All requirements validated)
  - Time: 30 minutes (processing time varies, monitoring + reporting = 30 min)
  - Dependencies: 109-110 (all deployments complete)
  - Parallel: No (final validation step)

---

## Dependencies Graph

```
Phase 0 (Setup):
0 [P] → All other tasks

Phase 1 (Critical - Sequential):
1 [P] → 2 → 3
4 [P] (parallel with 1-3)

Phase 2 (PARALLEL - Per-Insurer Sequential):
Per-insurer chains (run 11 in parallel):
├─ 5 → 6 → 7A → 7B → 7C   (MAPFRE)
├─ 8 → 9 → 10A → 10B → 10C   (Zurich)
├─ 11 → 12 → 13A → 13B → 13C   (HDI)
├─ 14 → 15 → 16A → 16B → 16C   (Qualitas)
├─ 17 → 18 → 19A → 19B → 19C   (ANA)
├─ 20 → 21 → 22A → 22B → 22C   (BX)
├─ 23 → 24 → 25A → 25B → 25C   (El Potosí)
├─ 26 → 27 → 28A → 28B → 28C   (GNP)
├─ 29 → 30 → 31A → 31B → 31C   (Chubb)
├─ 32 → 33 → 34A → 34B → 34C   (Atlas)
└─ 35 → 36 → 37A → 37B → 37C   (AXA)

Phase 3 (PARALLEL - All Independent):
104 [P] ─┐
105 [P] ─┤
106 [P] ─┼─ Run in parallel (requires 1-4 and 5-37C complete)
107 [P] ─┤
108 [P] ─┘

Phase 4 (Sequential Deployment):
109 → 110 → 111

Blocking Dependencies:
- 0 blocks ALL tasks (prerequisite)
- Phase 1 (1-4) should complete before Phase 4 deployment
- Phase 2 (5-37C) can overlap with Phase 1 testing
- Phase 3 (104-108) requires Phase 1 + Phase 2 complete
- Phase 4 (109-111) requires ALL previous phases complete
```

---

## Parallel Execution Examples

### Example 1: Launch Phase 1 Tests in Parallel

```bash
# Tasks 1 and 4 can run together (different files):
Task: "Add best_match variable declaration to procesar_batch_vehiculos in src/supabase/funciones-homologacion-actuales.sql"
Task: "Create integration test for A-SPEC vs TECH scenario in tests/integration/test_best_match_selection.sql"
```

### Example 2: Launch All 11 Insurers' Brand Consolidation in Parallel

**Tasks that can run simultaneously** (all modify different files):
- 5 (MAPFRE brand consolidation)
- 8 (Zurich brand consolidation)
- 11 (HDI brand consolidation)
- 14 (Qualitas brand consolidation)
- 17 (ANA brand consolidation)
- 20 (BX brand consolidation)
- 23 (El Potosí brand consolidation)
- 26 (GNP brand consolidation)
- 29 (Chubb brand consolidation)
- 32 (Atlas brand consolidation)
- 35 (AXA brand consolidation)

### Example 3: Launch Phase 3 Validation Tests in Parallel

```bash
# Tasks 104-108 all run in parallel (different files, no dependencies):
Task: "Create brand consolidation validation tests in tests/validation/test_brand_consolidation.js"
Task: "Create transmission recovery validation tests in tests/validation/test_transmission_recovery.js"
Task: "Create performance benchmark test in tests/performance/test_batch_processing.sql"
Task: "Create idempotency test in tests/integration/test_idempotency.sql"
Task: "Create data quality report in scripts/generate_quality_report.sql"
```

---

## Notes

### Parallelization Strategy
- **[P] tasks**: Can run simultaneously because they modify different files
- **Sequential tasks**: Must run in order within same file to avoid conflicts
- **Maximum parallelism**: 11 agents (one per insurer) for Phase 2
- **Estimated speedup**: Phase 2 could complete in ~75 minutes (3 tasks × 25 min avg) vs 8.25 hours sequential

### Commit Strategy
- Commit after each task completion
- Phase 1: Commit Tasks 1-3 together (same file), Task 4 separately
- Phase 2: Commit each insurer's 5 tasks together (e.g., Tasks 5-7C)
- Phase 3: Commit each test separately
- Phase 4: Commit deployment tasks together

### Validation Gates
- **After Task 3**: Verify algorithm fix with manual SQL test before proceeding
- **After each insurer (Task 7C, 10C, etc.)**: Run n8n workflow test with sample data
- **After Task 108**: Review data quality report before declaring completion

### Avoid
- ❌ Modifying same file in parallel tasks (will cause merge conflicts)
- ❌ Creating tasks that take > 30 minutes (break down further)
- ❌ Skipping validation tests (Phase 3 is critical for production deployment)
- ❌ Implementing Phase 2 before Phase 1 algorithm fix (risks amplifying the bug)

---

## Validation Checklist

✅ All requirements have corresponding tasks:
- Req 1.0 (Best-Match): Tasks 1-4, 106, 107 ✅
- Req 2.0 (Transmission): Tasks 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 105 ✅
- Req 3.0 (Brand): Tasks 5, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35, 104 ✅
- Req 4.0 (Model): Tasks 7A, 10A, 13A, 16A, 19A, 22A, 25A, 28A, 31A, 34A, 37A ✅
- Req 5.0 (Version): Tasks 7B, 10B, 13B, 16B, 19B, 22B, 25B, 28B, 31B, 34B, 37B ✅
- Req 6.0 (Technical): Tasks 7A-C, 10A-C, 13A-C, 16A-C, 19A-C, 22A-C, 25A-C, 28A-C, 31A-C, 34A-C, 37A-C ✅
- Req 7.0 (Insurer-Specific): Tasks 10A, 13A, 19A, 22A, 25A, 28B, 31B, 34B, 37A ✅
- Req 8.0 (Validation): Tasks 104-108 ✅

✅ All design components have corresponding tasks:
- Component 1 (Best-Match): Tasks 1-4 ✅
- Component 2 (Brand Consolidation): Tasks 5, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35 ✅
- Component 3 (Transmission Recovery): Tasks 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36 ✅
- Component 4 (Model Normalization): Tasks 7A, 10A, 13A, 16A, 19A, 22A, 25A, 28A, 31A, 34A, 37A ✅
- Component 5 (Version Cleaning): Tasks 7B, 10B, 13B, 16B, 19B, 22B, 25B, 28B, 31B, 34B, 37B ✅
- Component 6 (Token Deduplication): Tasks 7C, 10C, 13C, 16C, 19C, 22C, 25C, 28C, 31C, 34C, 37C ✅

✅ All tasks specify exact file paths (111/111 tasks)

✅ Parallel tasks truly independent:
- Task 0 (different operation, independent)
- Tasks 1, 4 (different files: SQL vs test)
- Tasks 5, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35 (brand consolidation - different insurers)
- Tasks 104-108 (different test files)

✅ Sequential tasks correctly identified:
- Tasks 1 → 2 → 3 (same SQL file)
- Each insurer: X → X+1 → X+2A → X+2B → X+2C (same JS file per insurer)

✅ Tasks ordered by dependencies:
- Phase 0 (setup) before all
- Phase 1 (critical fix) before deployment
- Phase 2 (normalization) can overlap with Phase 1
- Phase 3 (validation) after implementation
- Phase 4 (deployment) after all validation

✅ Each task is atomic (5-30 minutes, single purpose)

✅ Code reuse identified:
- Design.md component patterns with line numbers
- Qualitas deduplicateTokens() (lines 569-609)
- Existing Supabase functions (calculate_weighted_coverage, etc.)
- Zurich normalization patterns

✅ Success criteria added to all validation (104-108) and deployment (109-111) tasks

---

**Document Version:** 2.0
**Last Updated:** 2025-10-17
**Status:** REWRITTEN - Ready for Validation by spec-task-validator
**Task Count**: 111 tasks (Phase 0: 1, Phase 1: 4, Phase 2: 99, Phase 3: 5, Phase 4: 3)
**Requirement Coverage**: 8/8 requirements (100%)
**Component Coverage**: 6/6 design components (100%)
