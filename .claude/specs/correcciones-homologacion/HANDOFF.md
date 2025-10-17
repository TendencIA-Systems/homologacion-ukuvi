# Specification Handoff - Correcciones Homologación

## Current Status

**Specification Name:** `correcciones-homologacion`
**Phase:** Design Complete - Ready for Tasks Breakdown
**Progress:** 60% (Requirements ✅ | Design ✅ | Tasks ⏳ | Implementation ⏳)

---

## Work Completed

### ✅ Phase 1: Requirements (APPROVED)

**File:** `.claude/specs/correcciones-homologacion/requirements.md`
**Status:** Complete and validated by spec-requirements-validator
**Quality Score:** 9.5/10 (PASS)

**Key Requirements Defined:**
1. **Requirement 1 (CRITICAL):** Fix best-match selection algorithm - currently updates ALL matches instead of selecting the best one
2. **Requirement 2:** Transmission field recovery for ~194,000 contaminated records
3. **Requirement 3:** Brand consolidation for ~25,000 inconsistent records
4. **Requirement 4:** Model field contamination cleanup
5. **Requirement 5:** Version string normalization improvements
6. **Requirement 6:** Technical specification standardization
7. **Requirement 7:** Insurer-specific normalization updates (all 11 insurers)
8. **Requirement 8:** Data validation and quality gates

**Critical Client Issue Addressed:**
- A-SPEC vehicles incorrectly matched with TECH trim levels
- Root cause: System updates ALL candidates above threshold instead of selecting BEST match

### ✅ Phase 2: Design (CORRECTED & APPROVED)

**File:** `.claude/specs/correcciones-homologacion/design.md`
**Status:** Complete after critical correction by spec-design-validator
**Quality Score:** Initial MAJOR_ISSUES → Corrected to PASS

**Initial Problem Identified by Validator:**
- Original design misdiagnosed the bug as "first-match" logic
- Validator correctly identified the actual bug: "multi-update" logic in lines 553-583

**Design Correction Applied:**
- Component 1 now correctly targets the multi-update loop (lines 556-583)
- Keeps existing candidate collection logic (lines 487-551) - already works correctly
- Replaces FOR loop that updates all matches with SELECT LIMIT 1 that picks best match
- Added backward compatibility impact analysis
- Added variable declaration requirements

**6 Components Designed:**
1. **Component 1:** Best-match selection algorithm (Supabase RPC - CRITICAL FIX)
2. **Component 2:** Centralized brand consolidation map (n8n JavaScript)
3. **Component 3:** Enhanced transmission recovery (n8n JavaScript)
4. **Component 4:** Enhanced model normalization (n8n JavaScript)
5. **Component 5:** Enhanced version cleaning (n8n JavaScript)
6. **Component 6:** Intelligent token deduplication (reuse from Qualitas)

---

## Files Created/Modified

### Created Files:
```
.claude/specs/correcciones-homologacion/
├── requirements.md          ✅ Complete (9.5/10)
├── design.md               ✅ Complete (Corrected)
├── tasks.md                ⏳ NOT YET CREATED
└── HANDOFF.md              ✅ This file
```

### Files to Reference During Implementation:
```
Source Code References:
├── src/supabase/funciones-homologacion-actuales.sql    (Lines 437-602 - Main RPC function)
├── src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js
├── src/insurers/zurich/zurich-codigo-de-normalizacion.js
└── src/insurers/[10 other insurers]/[name]-codigo-de-normalizacion.js

Correction Documentation:
├── correcciones/correcciones-adicionales-del-cliente.md
├── correcciones/reporte_normalizacion_ukuvi.md
├── correcciones/REPORTE_PROBLEMAS_ADICIONALES_UKUVI.md
└── correcciones/NOTEBOOK_ACTUALIZADO_UKUVI_HOMOLOGACION.md

Project Documentation:
└── CLAUDE.md                                            (Architecture patterns, conventions)
```

---

## Critical Decisions Made

### 1. Algorithm Fix Approach
- **Decision:** Modify lines 553-583 only (update logic), NOT lines 487-551 (collection logic)
- **Rationale:** Existing collection logic already works correctly; bug is in multi-update behavior
- **Impact:** Minimal code changes, preserves existing matching thresholds

### 2. Transmission Recovery Strategy
- **Decision:** Records without recoverable transmission will be DISCARDED (not set to null or unknown)
- **Rationale:** Invalid transmission makes vehicle unusable for insurance quotations
- **Impact:** Some records will be excluded; logged for manual review

### 3. Backward Compatibility
- **Decision:** Breaking change accepted - will only update best match going forward
- **Rationale:** Current multi-update behavior is the bug we're fixing
- **Impact:** Historical multi-match entries in `disponibilidad` will be preserved

### 4. Code Reuse Priority
- **Decision:** Extend existing functions (Qualitas/Zurich as templates) rather than create new ones
- **Rationale:** Maintains consistency, reduces testing surface
- **Impact:** Faster implementation, lower risk

---

## Known Issues & Constraints

### Technical Constraints:
1. **Timeout:** Supabase RPC has 2-minute timeout (current batch size: 500-5,000 records)
2. **Idempotency:** All changes must be deterministic and repeatable
3. **No Schema Changes:** Must work with existing `catalogo_homologado` table structure
4. **Backward Compatibility:** Cannot break existing `disponibilidad` JSONB structure

### Data Quality Issues:
1. **95.7% of records** (~232,300) have some form of data quality issue
2. **80% of records** (~194,000) have transmission contamination
3. **25,000 records** have brand inconsistencies
4. **11 different insurers** with unique data patterns

### Performance Requirements:
- Best-match algorithm: O(n) where n = candidates with same hash_comercial
- Token deduplication: < 5ms per version string
- Batch processing: 5,000-10,000 records in < 2 minutes

---

## Next Steps (Task Breakdown Phase)

### Immediate Actions Required:

1. **Create tasks.md** following the tasks template
   - Break down each component into atomic, file-scoped tasks
   - Each task should touch 1-3 files maximum
   - Time-boxed to 15-30 minutes per task
   - Include specific file paths and line numbers

2. **Validate tasks.md** using spec-task-validator agent
   - Ensure atomicity (single purpose, specific files)
   - Verify agent-friendliness (clear input/output)
   - Check requirement traceability
   - Confirm implementability

3. **Get user approval** for task breakdown

4. **Generate task commands** (if user approves)
   - Run: `claude-code-spec-workflow generate-task-commands correcciones-homologacion`
   - Creates individual slash commands: `/correcciones-homologacion-task-1`, etc.

---

## Task Breakdown Guidance

### Priority 1: Critical Algorithm Fix (Component 1)
**Estimated Tasks:** 3-4 tasks
- Task: Add `best_match RECORD` variable declaration to function
- Task: Replace multi-update FOR loop with SELECT...ORDER BY...LIMIT 1
- Task: Update single best match with disponibilidad
- Task: Write unit test for best-match selection

**Files to Modify:**
- `src/supabase/funciones-homologacion-actuales.sql` (Lines 453, 556-583)

### Priority 2: Centralized Normalization (Components 2-6)
**Estimated Tasks:** 33 tasks (3 per insurer × 11 insurers)

**Per Insurer Pattern:**
- Task: Add brand consolidation map to [insurer] normalization
- Task: Add transmission recovery to [insurer] normalization
- Task: Add enhanced model cleanup to [insurer] normalization

**11 Insurers:**
1. MAPFRE (highest priority - worst data quality)
2. Zurich (whitelisted for creation)
3. HDI (whitelisted for creation)
4. Qualitas
5. ANA
6. BX
7. El Potosí
8. GNP
9. Chubb
10. Atlas
11. AXA

### Priority 3: Validation & Testing
**Estimated Tasks:** 5-6 tasks
- Task: Add validation for brand consolidation
- Task: Add validation for transmission recovery
- Task: Create integration test for A-SPEC vs TECH scenario
- Task: Create performance benchmark test
- Task: Create idempotency test

---

## Code Patterns to Follow

### 1. Brand Consolidation (Component 2)
```javascript
const BRAND_CONSOLIDATION_MAP = {
  'BMW BW': 'BMW',
  'KIA MOTORS': 'KIA',
  // ... (see design.md Component 2 for full map)
};

function consolidateBrand(marca) {
  const normalized = marca.toUpperCase().trim();
  return BRAND_CONSOLIDATION_MAP[normalized] || normalized;
}
```

### 2. Transmission Recovery (Component 3)
```javascript
function recoverTransmission(record) {
  // Step 1: Extract from contaminated field
  // Step 2: Infer from version_original
  // Step 3: Return null if unrecoverable (will discard record)
}
```

### 3. Model Normalization (Component 4)
```javascript
function normalizeModelo(marca, modelo) {
  // Remove NUEVO/NUEVA/NEW prefix
  // Remove brand-specific prefixes (MAZDA, MERCEDES, etc.)
  // Remove body types, generation markers
  // Return cleaned modelo
}
```

### 4. Best-Match Selection (Component 1)
```sql
-- Replace lines 556-583:
SELECT * INTO best_match
FROM jsonb_to_recordset(matches) AS m(...)
ORDER BY score DESC, (method LIKE '%same_batch%') DESC, tier ASC
LIMIT 1;

UPDATE catalogo_homologado ... WHERE id = best_match.id;
```

---

## Testing Strategy

### Unit Tests (n8n Normalization):
- Test each brand consolidation case
- Test transmission recovery scenarios
- Test model cleanup patterns
- Test version normalization fixes

### Integration Tests (End-to-End):
- **Critical:** A-SPEC vs TECH mismatch prevention test
- Transmission recovery from MAPFRE data
- Brand consolidation across insurers
- Idempotency verification

### Performance Tests:
- Batch of 5,000 records in < 2 minutes
- Best-match evaluation with 10 candidates < 100ms overhead
- Token deduplication < 5ms per string

---

## Validation Checklist for Tasks Phase

Before proceeding to implementation:

- [ ] All 8 requirements mapped to specific tasks
- [ ] Each task is atomic (1-3 files, 15-30 minutes)
- [ ] File paths and line numbers specified
- [ ] Requirement references included (_Requirements: X.Y_)
- [ ] Code reuse identified (_Leverage: path/to/file_)
- [ ] Tasks validated by spec-task-validator
- [ ] User approved task breakdown
- [ ] Task commands generated (if user requested)

---

## Risks & Mitigation

### Risk 1: Breaking Change in Matching Behavior
**Mitigation:**
- Preserve `multi_match_count` metric for monitoring
- Log all candidates considered before selecting best
- Implement gradual rollout per insurer

### Risk 2: Transmission Recovery Discards Too Many Records
**Mitigation:**
- Log all discarded records with full context
- Provide manual review queue
- Monitor discard rate per insurer

### Risk 3: Performance Degradation from Best-Match Selection
**Mitigation:**
- Use O(n) algorithm with existing candidate collection
- Benchmark before/after with real data
- Keep batch size configurable

---

## Contact & Resources

**Specification Documents:**
- Requirements: `.claude/specs/correcciones-homologacion/requirements.md`
- Design: `.claude/specs/correcciones-homologacion/design.md`
- Tasks: `.claude/specs/correcciones-homologacion/tasks.md` (TO BE CREATED)

**Key Reference Files:**
- Architecture: `CLAUDE.md`
- Current RPC Function: `src/supabase/funciones-homologacion-actuales.sql`
- Template Normalizers: `src/insurers/qualitas/`, `src/insurers/zurich/`
- Correction Reports: `correcciones/*.md`

**Validation Agents:**
- Requirements: `spec-requirements-validator`
- Design: `spec-design-validator`
- Tasks: `spec-task-validator`
- Implementation: `spec-task-executor`

---

## Prompt for Next Agent Session

Use this exact prompt to continue the work:

```
I need to continue working on the correcciones-homologacion specification. The requirements and design phases are complete and approved.

Current Status:
- ✅ Requirements complete (9.5/10 validation score)
- ✅ Design complete (corrected after validator feedback)
- ⏳ Tasks breakdown - THIS IS THE NEXT STEP

Read the handoff document first:
.claude/specs/correcciones-homologacion/HANDOFF.md

Then read the completed specifications:
1. .claude/specs/correcciones-homologacion/requirements.md
2. .claude/specs/correcciones-homologacion/design.md

Now create the tasks.md file following the /tasks command workflow:
1. Load the tasks template
2. Create atomic, file-scoped tasks for all 6 components
3. Follow the task breakdown guidance in HANDOFF.md
4. Validate with spec-task-validator agent
5. Present to me for approval
6. Generate task commands if I approve

CRITICAL: Component 1 (best-match selection) is the highest priority. The bug is in lines 553-583 of funciones-homologacion-actuales.sql where it updates ALL matches instead of selecting the best one.

Remember: Each task should be atomic (1-3 files, 15-30 minutes, single purpose) and agent-friendly.
```

---

**Document Created:** 2025-10-17
**Status:** Ready for Task Breakdown Phase
**Next Phase Owner:** [To be assigned]
