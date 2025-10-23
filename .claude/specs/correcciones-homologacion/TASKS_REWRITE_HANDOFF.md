# Tasks.md Full Rewrite - Agent Handoff Document

## Mission Statement

**Objective**: Rewrite `.claude/specs/correcciones-homologacion/tasks.md` to achieve 9.5/10 quality score from spec-task-validator by fixing all template compliance issues, splitting non-atomic tasks, and adding missing information.

**Current Status**: 7/10 - NEEDS_IMPROVEMENT
**Target Status**: 9.5/10 - READY FOR IMPLEMENTATION
**Estimated Rewrite Time**: 4-5 hours
**Complexity**: High (requires careful restructuring of 42 tasks into 99+ atomic tasks)

---

## Context Documents You MUST Read

### 1. **Primary Documents** (READ FIRST)
```
.claude/specs/correcciones-homologacion/tasks.md              ← Current draft (7/10)
.specify/templates/tasks-template.md                          ← Template to follow
.claude/specs/correcciones-homologacion/requirements.md       ← 8 requirements to cover
.claude/specs/correcciones-homologacion/design.md             ← 6 components to implement
.claude/specs/correcciones-homologacion/HANDOFF.md            ← Original handoff with guidance
```

### 2. **Reference Documents** (READ AS NEEDED)
```
CLAUDE.md                                                      ← Architecture patterns
src/supabase/funciones-homologacion-actuales.sql             ← SQL function to modify
src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js ← Template for normalization
src/insurers/zurich/zurich-codigo-de-normalizacion.js        ← Template for normalization
```

### 3. **Validation Report** (EMBEDDED BELOW)
- The spec-task-validator identified 4 CRITICAL issues and 3 MISSING INFORMATION areas
- All issues documented in detail below

---

## Complete List of Issues to Fix

### CRITICAL ISSUE #1: Template Compliance - Missing Sections

**Problem**: Current tasks.md is missing required sections from `.specify/templates/tasks-template.md`

**Required Sections to Add**:

#### 1.1 Task Overview Section
**Location**: After the "Overview" section, before "Execution Flow"
**Required Content**:
```markdown
## Task Overview

**Implementation Approach**: This implementation corrects critical data quality issues across 11 insurance company data sources through a 3-phase execution strategy:

1. **Phase 1 (Critical Fix)**: Modify Supabase RPC function `procesar_batch_vehiculos` to select the single best match instead of updating all candidates above threshold. This fixes the A-SPEC vs TECH mismatch bug reported by the client.

2. **Phase 2 (Data Quality)**: Apply 5 normalization corrections to n8n code for all 11 insurers:
   - Component 2: Brand consolidation using centralized map
   - Component 3: Transmission recovery from contaminated fields
   - Component 4: Enhanced model normalization (prefix/suffix removal)
   - Component 5: Enhanced version cleaning (escape chars, HP+AUT patterns)
   - Component 6: Intelligent token deduplication

3. **Phase 3 (Validation)**: Comprehensive testing including integration tests for the algorithm fix, validation tests for normalization functions, performance benchmarks, and idempotency verification.

**Technology Stack**:
- **Backend**: PostgreSQL (Supabase) with PL/pgSQL stored procedures
- **ETL**: n8n workflows with JavaScript Code nodes
- **Testing**: SQL-based integration tests, JavaScript unit tests (framework TBD)
```

#### 1.2 Steering Document Compliance Section
**Location**: After "Task Overview", before "Execution Flow"
**Required Content**:
```markdown
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
- Re-running same batch produces identical results (verified in T041)

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
- Pattern: `/src/insurers/[name]/[name]-codigo-de-normalizacion.js`
- Each file contains: validation, normalization, hash generation, error handling
- Batch size constant: `BATCH_SIZE = 5000`

**Supabase Functions**:
- Single file: `/src/supabase/funciones-homologacion-actuales.sql`
- Function signature: `procesar_batch_vehiculos(vehiculos_json JSONB)`
- Critical section: Lines 553-583 (multi-update loop to be replaced)

**Testing Files** (to be created):
- Integration tests: `tests/integration/test_*.sql`
- Validation tests: `tests/validation/test_*.js`
- Performance tests: `tests/performance/test_*.sql`
```

#### 1.3 Atomic Task Requirements Section
**Location**: After "Steering Document Compliance", before "Execution Flow"
**Required Content**:
```markdown
## Atomic Task Requirements

**Each task in this document meets these criteria:**

1. **File Scope**: Touches 1-3 related files maximum
   - Example: T001 modifies only `funciones-homologacion-actuales.sql` (1 file)
   - Example: T005A-C modify only `mapfre-codigo-de-normalizacion.js` (1 file)
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

**Non-Atomic Task Example (AVOID)**:
```markdown
❌ Add enhanced model and version normalization to MAPFRE
   - Implements 3 components (Model, Version, Token deduplication)
   - Takes 30 minutes (at upper limit)
   - Multiple purposes (normalization + cleaning + deduplication)
```

**Atomic Task Example (CORRECT)**:
```markdown
✅ Add enhanced model normalization to MAPFRE
   - Implements 1 component (Model normalization only)
   - Takes 15 minutes
   - Single purpose (prefix/suffix removal from modelo field)
```
```

#### 1.4 Task Format Guidelines Section
**Location**: Before "Phase 1" section
**Required Content**:
```markdown
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
- Example: T005A, T008A, T011A all modify different files → all marked `[P]`
- Example: T005A → T005B → T005C all modify same file → none marked `[P]`
```

---

### CRITICAL ISSUE #2: Wrong Checkbox Format

**Problem**: Current tasks use header format `### T001:` instead of checkbox format `- [ ] 1.`

**Required Changes**:

**BEFORE (Current - WRONG)**:
```markdown
### T001: Add best_match variable declaration
- **File**: `src/supabase/funciones-homologacion-actuales.sql` (line 453)
- **Action**: Add `best_match RECORD;` to DECLARE section
- **Time**: 5 minutes
```

**AFTER (Required - CORRECT)**:
```markdown
- [ ] 1. Add best_match variable declaration to procesar_batch_vehiculos
  - File: src/supabase/funciones-homologacion-actuales.sql (line 453)
  - Action: Add `best_match RECORD;` to DECLARE section after line 453
  - Leverage: Existing variable declaration pattern in SQL function
  - Requirements: 1.1 (Evaluate all candidates)
  - Time: 5 minutes
  - Dependencies: None
  - Parallel: Yes [P]
```

**Key Differences**:
1. Use `- [ ]` checkbox instead of `###` header
2. Number tasks sequentially (1, 2, 3...) not (T001, T002, T003...)
3. Remove bold formatting from field names (**File** → File)
4. Remove backticks from file paths (`src/...` → src/...)
5. Add missing fields: Leverage, Requirements, Dependencies, Parallel
6. Keep indentation consistent (2 spaces for nested bullets)

**Apply to ALL 42+ tasks in the document**

---

### CRITICAL ISSUE #3: Non-Atomic Tasks (Must Split)

**Problem**: Tasks T007, T010, T013, T016, T019, T022, T025, T028, T031, T034, T037 (11 tasks) combine 3 components and take 30 minutes each. Must split into atomic 15-minute tasks.

**Pattern to Apply**: Each composite task becomes 3 atomic tasks (33 tasks total become 99 tasks)

#### 3.1 Splitting Pattern (Apply to All 11 Insurers)

**BEFORE (Current - NON-ATOMIC)**:
```markdown
### T007: Add enhanced model and version normalization to MAPFRE
- **File**: `src/insurers/mapfre/mapfre-codigo-de-normalizacion.js`
- **Action**:
  - Extend normalizeModelo() with NUEVO prefix removal, body type cleanup
  - Extend cleanVersionString() with escape char removal, HP+AUT separation
  - Implement fixInvalidDoorCounts() for BMW model numbers
  - Add deduplicateTokens() if not present
- **Time**: 30 minutes
- **Dependencies**: T006 (same file, sequential)
- **Parallel**: No
```

**AFTER (Required - ATOMIC)**:
```markdown
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
```

#### 3.2 Tasks to Split (11 Insurers × 3 Sub-Tasks = 33 New Tasks)

**Original Task Numbers** → **New Task Numbers**:
- T007 (MAPFRE) → 7A, 7B, 7C
- T010 (Zurich) → 10A, 10B, 10C (PLUS add Zurich-specific: remove "MAZDA" prefix in 10A)
- T013 (HDI) → 13A, 13B, 13C (PLUS add HDI-specific: move body types to version in 13A)
- T016 (Qualitas) → 16A, 16B, 16C (SKIP 16C if deduplicateTokens already exists)
- T019 (ANA) → 19A, 19B, 19C (PLUS add ANA-specific: remove "MA" prefix, "CHASIS" in 19A)
- T022 (BX) → 22A, 22B, 22C (PLUS add BX-specific: remove brand from modelo in 22A)
- T025 (El Potosí) → 25A, 25B, 25C (PLUS add ElPotosi-specific: Mercedes + Mazda cleanup in 25A)
- T028 (GNP) → 28A, 28B, 28C (PLUS add GNP-specific: remove marca/modelo from version in 28A)
- T031 (Chubb) → 31A, 31B, 31C (PLUS add Chubb-specific: separate "2.0LAUT" → "2.0L AUTO" in 31B)
- T034 (Atlas) → 34A, 34B, 34C (PLUS add Atlas-specific: BMW doors fix in 31B)
- T037 (AXA) → 37A, 37B, 37C (PLUS add AXA-specific: A-SPEC vs A SPEC standardization in 37A)

**Insurer-Specific Additions** (from Requirements 7.0):
| Task | Insurer | Component | Specific Addition | Requirement |
|------|---------|-----------|-------------------|-------------|
| 10A | Zurich | Model | Remove "MAZDA" prefix from Mazda models | 7.3 |
| 13A | HDI | Model | Move body types from modelo to version | 7.7 |
| 19A | ANA | Model | Remove "MA" prefix + "CHASIS" from all models | 7.4 |
| 22A | BX | Model | Remove brand name from modelo field | 7.5 |
| 25A | El Potosí | Model | Clean Mercedes prefixes + generic Mazda models | 7.6 |
| 28A | GNP | Version | Remove marca/modelo tokens from version_original | 7.8 |
| 31B | Chubb | Version | Separate liters: "2.0LAUT" → "2.0L AUTO" | 7.9 |
| 34B | Atlas | Version | Remove BMW model numbers as doors | 7.10 |
| 37A | AXA | Model | Standardize "A-SPEC" vs "A SPEC" | 7.12 |

**Final Task Count After Splitting**:
- Phase 1: 4 tasks (unchanged)
- Phase 2: 33 original → 99 atomic tasks (11 insurers × 9 tasks each)
- Phase 3: 5 tasks (unchanged)
- **TOTAL: 108 tasks** (was 42)

---

### CRITICAL ISSUE #4: Missing Success Criteria for Validation Tasks

**Problem**: Tasks T038-T042 (now renumbered to T104-T108) don't specify what "passing" means

**Required Addition**: Add "Success Criteria" bullet to each validation task

#### 4.1 Example: Add Success Criteria to All Validation Tasks

**BEFORE (Current - MISSING CRITERIA)**:
```markdown
- [ ] T038: Add validation for brand consolidation
  - File: tests/validation/test_brand_consolidation.js (NEW)
  - Action: Test all brand variants, verify corrections, assert invalid brands
  - Time: 20 minutes
```

**AFTER (Required - WITH CRITERIA)**:
```markdown
- [ ] 104. Create brand consolidation validation tests
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
  - Dependencies: 5-37 (needs all insurer normalization code)
  - Parallel: Yes [P]
```

#### 4.2 Success Criteria for Each Validation Task

**Task 105 (Transmission Recovery Validation)**:
```markdown
Success Criteria:
- All test cases pass: contaminated field extraction, version inference, null return
- Verify only 'AUTO' or 'MANUAL' returned (never 'DSG', 'CVT', 'TIPTRONIC')
- Test null return for unrecoverable: recoverTransmission({transmision: 'PEPPER', version_original: 'SPORT'}) → null
- Test execution time < 1 second
- Output: "✓ Transmission Recovery: 12/12 tests passed"
```

**Task 106 (Performance Benchmark)**:
```markdown
Success Criteria:
- Batch of 5,000 records completes in < 120 seconds (2 minutes)
- Best-match evaluation with 10 candidates adds < 100ms per vehicle
- Token deduplication adds < 5ms per version string
- No timeout errors (Supabase 2-minute limit)
- Memory usage stays below 512MB
- Output: "✓ Performance: 5000 records in 87.3s (avg 17.5ms/record)"
```

**Task 107 (Idempotency Test)**:
```markdown
Success Criteria:
- First run: Process 1,000 records, capture results (inserted, updated, tier counts)
- Second run: Re-process same 1,000 records
- Assert: No new records inserted (inserted_count = 0 on second run)
- Assert: hash_comercial values unchanged between runs
- Assert: id_canonico values unchanged between runs
- Assert: Same matches selected (compare disponibilidad JSONB)
- Output: "✓ Idempotency: Run1(ins:450, upd:550) == Run2(ins:0, upd:550)"
```

**Task 108 (Data Quality Report)**:
```markdown
Success Criteria:
- Report includes counts by insurer (11 rows expected)
- Report includes transmission distribution (AUTO vs MANUAL)
- Report includes top 20 brands by count
- Report includes discard counts by error code (TRANSMISSION_INFERENCE_FAILED, INVALID_BRAND, etc.)
- Report includes before/after comparison showing improvements
- Output saved to: reports/quality_report_[timestamp].md
- Output: "✓ Quality Report: 242,656 total records, 95.7% corrected, 4.3% discarded"
```

---

### MISSING INFORMATION #1: File Path Verification

**Problem**: Tasks assume all insurer files exist, but paths not verified

**Required Addition**: Add Task 0 (setup task) to verify file structure

**New Task to Add at Beginning**:
```markdown
## Phase 0: Setup and Verification (PREREQUISITE)

- [ ] 0. Verify project structure and file paths
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
```

---

### MISSING INFORMATION #2: Deployment Tasks

**Problem**: No tasks for deploying changes to production

**Required Addition**: Add Phase 4 with deployment tasks

**New Phase to Add at End**:
```markdown
## Phase 4: Deployment (PRIORITY 4)

**Goal**: Deploy corrected SQL function and updated n8n normalization code to production

_Requirements: All phases 1-3 must complete successfully_

- [ ] 109. Deploy updated Supabase function to production
  - File: src/supabase/funciones-homologacion-actuales.sql
  - Prerequisites:
    - All Phase 1 tasks (1-4) completed and tested
    - Supabase CLI installed: `supabase --version`
    - Connection configured: `supabase link --project-ref [PROJECT_REF]`
  - Action:
    - Create backup of current function:
      ```sql
      -- In Supabase SQL Editor
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

- [ ] 110. Update n8n workflows with corrected normalization code
  - File: N/A (n8n UI-based deployment)
  - Prerequisites:
    - All Phase 2 tasks (5-103) completed
    - Access to n8n instance: https://[n8n-instance].com
    - Workflows identified for each insurer (11 total)
  - Action:
    - For each insurer (MAPFRE, Zurich, HDI, Qualitas, ANA, BX, El Potosí, GNP, Chubb, Atlas, AXA):
      1. Open workflow: `ETL - [Insurer Name]`
      2. Locate "Code" node (usually named "Normalize Data" or similar)
      3. Replace code with updated normalization from: `src/insurers/[insurer]/[insurer]-codigo-de-normalizacion.js`
      4. Test workflow with "Execute Workflow" button using 10 sample records
      5. Verify output: All records have valid transmission, consolidated brands, cleaned versions
      6. Save workflow (auto-versioned by n8n)
      7. Activate workflow if currently paused
    - Document deployed versions in: `docs/n8n_deployment_[timestamp].md`
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
    - Save report to: `reports/post_deployment_report_[timestamp].md`
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
```

---

### MISSING INFORMATION #3: Test Framework Details

**Problem**: Test tasks don't specify how to run tests

**Required Addition**: Add test framework setup to Task 0 or early tasks

**Example Addition to Task 0**:
```markdown
- [ ] 0B. Setup test framework (optional, if tests don't exist)
  - File: package.json (if using JavaScript tests)
  - Action:
    - Check if package.json exists: `ls -la package.json`
    - If yes, check for test dependencies: `cat package.json | grep jest`
    - If Jest not installed, add it:
      ```bash
      npm install --save-dev jest @types/jest
      # OR for SQL tests
      npm install --save-dev pg  # PostgreSQL client for Node.js
      ```
    - Create test script in package.json:
      ```json
      {
        "scripts": {
          "test": "jest",
          "test:validation": "jest tests/validation",
          "test:integration": "jest tests/integration",
          "test:performance": "jest tests/performance"
        }
      }
      ```
    - For SQL tests, create runner script: `scripts/run_sql_tests.sh`
  - Success Criteria:
    - Test framework installed
    - Test scripts configured
    - Sample test runs: `npm test` (may fail, but should execute)
  - Leverage: Jest documentation, pg library docs
  - Requirements: 8.0 (Validation and quality gates)
  - Time: 15 minutes
  - Dependencies: 0 (after file verification)
  - Parallel: No (extends Task 0)
```

---

## Renumbering Tasks After Changes

**Original Count**: 42 tasks (T001-T042)
**After Splitting**: 108 tasks + 3 setup/deployment = **111 tasks total**

**New Numbering Scheme**:
```
Phase 0: Setup
├─ 0: Verify project structure (NEW)
└─ 0B: Setup test framework (NEW, optional)

Phase 1: Critical Algorithm Fix
├─ 1: Add best_match variable (was T001)
├─ 2: Replace multi-update loop (was T002)
├─ 3: Add logging for candidates (was T003)
└─ 4: Create A-SPEC vs TECH integration test (was T004)

Phase 2: N8N Normalization Updates
├─ MAPFRE (was T005-T007, now 3 tasks)
│  ├─ 5: Add brand consolidation map (was T005)
│  ├─ 6: Add transmission recovery (was T006)
│  ├─ 7A: Add enhanced model normalization (NEW - split from T007)
│  ├─ 7B: Add enhanced version cleaning (NEW - split from T007)
│  └─ 7C: Add token deduplication (NEW - split from T007)
├─ Zurich (was T008-T010, now 9 tasks)
│  ├─ 8: Add brand consolidation map
│  ├─ 9: Add transmission recovery
│  ├─ 10A: Add enhanced model normalization + MAZDA prefix removal
│  ├─ 10B: Add enhanced version cleaning
│  └─ 10C: Add token deduplication
├─ HDI (was T011-T013, now 9 tasks)
│  ├─ 11: Brand consolidation
│  ├─ 12: Transmission recovery
│  ├─ 13A: Model normalization + body type move
│  ├─ 13B: Version cleaning
│  └─ 13C: Token deduplication
├─ [Continue pattern for remaining 8 insurers...]
│  Qualitas: 14-16C
│  ANA: 17-19C
│  BX: 20-22C
│  El Potosí: 23-25C
│  GNP: 26-28C
│  Chubb: 29-31C
│  Atlas: 32-34C
│  AXA: 35-37C

Phase 3: Validation & Testing
├─ 104: Brand consolidation validation (was T038)
├─ 105: Transmission recovery validation (was T039)
├─ 106: Performance benchmark (was T040)
├─ 107: Idempotency test (was T041)
└─ 108: Data quality report (was T042)

Phase 4: Deployment (NEW PHASE)
├─ 109: Deploy Supabase function (NEW)
├─ 110: Update n8n workflows (NEW)
└─ 111: Full reprocessing + report (NEW)
```

**Task Numbering Rules**:
- Use sequential numbers (1, 2, 3...) not task codes (T001, T002)
- Sub-tasks use letters (7A, 7B, 7C) for same-insurer atomic tasks
- Maintain visual grouping by insurer (5-7C = MAPFRE, 8-10C = Zurich, etc.)

---

## Parallel Execution Documentation

**Required Update**: Rewrite "Parallel Execution Examples" section with new task numbers

**Example - Launch All Insurer Brand Consolidation Tasks**:
```markdown
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

**Agent Command**:
```bash
# Launch 11 agents in parallel
Task: "Add brand consolidation map to MAPFRE in src/insurers/mapfre/mapfre-codigo-de-normalizacion.js"
Task: "Add brand consolidation map to Zurich in src/insurers/zurich/zurich-codigo-de-normalizacion.js"
Task: "Add brand consolidation map to HDI in src/insurers/hdi/hdi-codigo-de-normalizacion.js"
# ... (continue for all 11 insurers)
```

**Expected Result**: All 11 tasks complete in ~20 minutes (parallelized from 3.7 hours sequential)
```

---

## Dependencies Graph Update

**Required Update**: Rewrite dependencies graph with new task structure

**New Dependencies Structure**:
```
Phase 0 (Setup):
0 [P] → All other tasks
0B [P] → All test tasks (104-111)

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
106 [P] ─┼─ Run in parallel (requires 1-37C complete)
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

## Validation Checklist Update

**Required Update**: Update validation checklist with new task counts

**New Checklist**:
```markdown
## Validation Checklist

✅ All requirements have corresponding tasks:
- Req 1.0 (Best-Match): Tasks 1-4 ✅
- Req 2.0 (Transmission): Tasks 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 105 ✅
- Req 3.0 (Brand): Tasks 5, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35, 104 ✅
- Req 4.0 (Model): Tasks 7A, 10A, 13A, 16A, 19A, 22A, 25A, 28A, 31A, 34A, 37A ✅
- Req 5.0 (Version): Tasks 7B, 10B, 13B, 16B, 19B, 22B, 25B, 28B, 31B, 34B, 37B ✅
- Req 6.0 (Technical): Tasks 7A-C, 10A-C, 13A-C, 16A-C, 19A-C, 22A-C, 25A-C, 28A-C, 31A-C, 34A-C, 37A-C ✅
- Req 7.0 (Insurer-Specific): Tasks 10A, 13A, 19A, 22A, 25A, 28A, 31B, 34B, 37A ✅
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
- Tasks 0, 4 (different files from Phase 1)
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

✅ Success criteria added to all validation and deployment tasks
```

---

## Rewrite Workflow Instructions

### Step 1: Read All Reference Documents (30 minutes)
1. Re-read `.specify/templates/tasks-template.md` - YOUR SOURCE OF TRUTH for format
2. Re-read current `tasks.md` - understand what needs to change
3. Read `requirements.md` - understand all 8 requirements and acceptance criteria
4. Read `design.md` - understand all 6 components with specific line references
5. Skim `HANDOFF.md` - understand original guidance

### Step 2: Create New Document Structure (15 minutes)
1. Copy template structure from `.specify/templates/tasks-template.md`
2. Replace example content with correcciones-homologacion specifics
3. Add all required sections identified in CRITICAL ISSUE #1 above

### Step 3: Convert Task Format (60 minutes)
1. Convert all 42 task headers from `### T001:` to `- [ ] 1.` format
2. Remove bold formatting, add missing fields (Leverage, Requirements, Dependencies, Parallel)
3. Ensure consistent 2-space indentation for nested bullets

### Step 4: Split Non-Atomic Tasks (90 minutes)
1. Split tasks T007, T010, T013, T016, T019, T022, T025, T028, T031, T034, T037 into A/B/C sub-tasks
2. Add insurer-specific requirements to appropriate sub-tasks (see table in CRITICAL ISSUE #3)
3. Update dependencies (XA → XB → XC chains)
4. Renumber all subsequent tasks (T038 becomes 104, etc.)

### Step 5: Add Success Criteria (45 minutes)
1. Add "Success Criteria" bullet to tasks 4, 104-111
2. Specify pass/fail conditions, expected output, verification methods
3. Include performance thresholds (2 min for 5k records, < 100ms per match, etc.)

### Step 6: Add Missing Tasks (30 minutes)
1. Add Task 0: Verify project structure
2. Add Task 0B: Setup test framework (optional)
3. Add Phase 4 with tasks 109-111 (deployment)

### Step 7: Update Supporting Sections (30 minutes)
1. Rewrite "Parallel Execution Examples" with new task numbers
2. Update "Dependencies Graph" with new structure
3. Update "Validation Checklist" with new task counts
4. Update "Notes" section with new commit strategy

### Step 8: Validate Rewrite (15 minutes)
1. Check all checkboxes use `- [ ]` format (not `###`)
2. Verify all 111 tasks have: File, Action, Leverage, Requirements, Time, Dependencies, Parallel
3. Confirm all 8 requirements mapped to tasks
4. Confirm all 6 components mapped to tasks
5. Verify task numbers sequential (no gaps: 0, 0B, 1, 2, 3, 4, 5, 6, 7A, 7B, 7C, 8...)

### Step 9: Final Quality Check (15 minutes)
1. Read entire document as if you were an implementing agent
2. Verify each task has enough detail to execute without additional context
3. Check that parallel tasks truly modify different files
4. Ensure success criteria are measurable and clear

**Total Estimated Time**: ~5 hours

---

## Success Criteria for Rewrite

**The rewritten tasks.md will be considered complete when**:

1. ✅ **Template Compliance**: All required sections present (Task Overview, Steering Document Compliance, Atomic Task Requirements, Task Format Guidelines)
2. ✅ **Checkbox Format**: All 111 tasks use `- [ ] Number.` format (not `### TX:`)
3. ✅ **Atomicity**: All tasks 5-30 minutes, single purpose (no 30-minute composite tasks remaining)
4. ✅ **Success Criteria**: Tasks 4, 104-111 have clear pass/fail conditions
5. ✅ **Deployment Coverage**: Phase 4 exists with 3 deployment tasks (109-111)
6. ✅ **File Verification**: Task 0 verifies all file paths exist
7. ✅ **Complete Fields**: Every task has File, Action, Leverage, Requirements, Time, Dependencies, Parallel
8. ✅ **Requirement Coverage**: All 8 requirements (1.0-8.0) mapped to specific tasks
9. ✅ **Component Coverage**: All 6 design components mapped to specific tasks
10. ✅ **Validation Score**: spec-task-validator returns 9.0-10.0 score (EXCELLENT)

---

## Common Pitfalls to Avoid

1. ❌ **Don't**: Keep composite tasks together ("Add model, version, and token deduplication")
   ✅ **Do**: Split into 3 atomic tasks (XA, XB, XC)

2. ❌ **Don't**: Use vague actions ("Clean up modelo field")
   ✅ **Do**: Use specific actions ("Remove NUEVO/NUEVA/NEW prefix using regex: /^(NUEVO|NUEVA|NEW)\s+/gi")

3. ❌ **Don't**: Forget insurer-specific additions (Zurich's MAZDA prefix, HDI's body types, etc.)
   ✅ **Do**: Explicitly list all insurer-specific requirements from Req 7.0

4. ❌ **Don't**: Use relative requirement references ("Requirements: 4.0")
   ✅ **Do**: Use specific acceptance criteria ("Requirements: 4.1 (NUEVO prefix), 4.2 (Brand prefixes)")

5. ❌ **Don't**: Mark sequential tasks as parallel ("Tasks 5, 6, 7A-C all marked [P]")
   ✅ **Do**: Only mark first task of chain as [P] (Task 5 [P], but 6-7C not parallel)

6. ❌ **Don't**: Assume test framework exists without verification
   ✅ **Do**: Add Task 0B to setup test framework with explicit commands

7. ❌ **Don't**: End at implementation without deployment
   ✅ **Do**: Add Phase 4 with SQL deployment, n8n updates, and reprocessing

8. ❌ **Don't**: Write success criteria as vague ("Test passes")
   ✅ **Do**: Write measurable criteria ("All 15/15 brand variants correctly consolidated, output: ✓ Brand: 15/15")

---

## Validation After Rewrite

**After completing the rewrite, you MUST**:

1. Use the spec-task-validator agent to validate the new tasks.md
2. Ensure score is 9.0+ (EXCELLENT or READY FOR IMPLEMENTATION)
3. Address any remaining issues identified by validator
4. Present final tasks.md to user for approval

**Validation Command**:
```
Task: "Validate the rewritten tasks.md for correcciones-homologacion specification"
Agent: spec-task-validator
Input: .claude/specs/correcciones-homologacion/tasks.md
Expected: Quality score 9.0-10.0, status READY FOR IMPLEMENTATION
```

---

## Questions to Ask User (If Needed)

**Only ask if critical information is missing or ambiguous**:

1. **Test Framework**: "Which test framework should be used for JavaScript validation tests (Tasks 104-105)? Jest (recommended) or Mocha?"
2. **SQL Test Runner**: "How should SQL integration tests (Task 4, 106, 107) be executed? Via Supabase SQL Editor, pg client, or custom runner?"
3. **Insurer File Names**: "Some insurers may have varying file name patterns (e.g., `elpotosi` vs `el-potosi`). Should I verify exact names before writing tasks, or proceed with hyphenated names?"
4. **Deployment Permissions**: "Do we have Supabase CLI access for Task 109, or should deployment be manual via SQL Editor?"

**If user doesn't provide answers**: Proceed with reasonable defaults (Jest, Supabase SQL Editor, hyphenated names, manual deployment) and note assumptions in task descriptions.

---

## Files You Will Modify

**Primary Output**:
- `.claude/specs/correcciones-homologacion/tasks.md` (REWRITE - replace entire file)

**Reference Only** (do NOT modify):
- `.specify/templates/tasks-template.md`
- `.claude/specs/correcciones-homologacion/requirements.md`
- `.claude/specs/correcciones-homologacion/design.md`
- `.claude/specs/correcciones-homologacion/HANDOFF.md`

---

## Document Version

**Handoff Document Version**: 1.0
**Created**: 2025-10-17
**Author**: Claude Code (Sonnet 4.5)
**Target Agent**: Claude Code (Haiku 4.5)
**Estimated Completion**: 4-5 hours
**Expected Result**: tasks.md with 9.5/10 quality score, 111 atomic tasks, ready for implementation

---

**IMPORTANT**: This handoff document contains ALL information needed to perform the rewrite. Read it thoroughly before starting. Follow the step-by-step workflow. Validate your work with spec-task-validator before presenting to user.

**Good luck!** 🚀
