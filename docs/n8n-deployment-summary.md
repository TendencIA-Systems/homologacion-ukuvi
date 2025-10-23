# n8n Deployment Documentation Summary

**Document Version:** 1.0
**Date:** 2025-10-17
**Task:** 110 - Update n8n workflows with corrected normalization code
**Phase:** Phase 4 - Deployment

---

## Documentation Package Overview

This deployment package contains comprehensive documentation for deploying normalization corrections to all 11 insurance company ETL workflows in n8n.

### Document Structure

```
docs/
├── n8n-deployment-summary.md          ← THIS FILE (navigation and overview)
├── n8n-deployment-guide.md            ← Main deployment procedures
├── n8n-per-insurer-changes.md         ← Detailed code changes per insurer
├── n8n-deployment-checklist.md        ← Step-by-step deployment tracker
└── n8n-smoke-test-cases.md            ← Test cases for validation
```

---

## Quick Start Guide

### For Deployment Engineers

**Read these documents in order:**

1. **START HERE:** [n8n-deployment-guide.md](./n8n-deployment-guide.md)
   - Deployment overview and objectives
   - Prerequisites verification
   - General workflow update procedure
   - Testing procedures and validation queries
   - Rollback instructions

2. **Per-Insurer Reference:** [n8n-per-insurer-changes.md](./n8n-per-insurer-changes.md)
   - Detailed code changes for each insurer
   - Insurer-specific normalization rules
   - Component matrix showing which fixes apply where

3. **Execution Tracker:** [n8n-deployment-checklist.md](./n8n-deployment-checklist.md)
   - Step-by-step checklist for each workflow
   - Pre-deployment verification
   - Post-deployment validation
   - Rollback decision matrix

4. **Testing Guide:** [n8n-smoke-test-cases.md](./n8n-smoke-test-cases.md)
   - 10 universal test cases for all insurers
   - Insurer-specific test cases
   - Expected results and validation points

---

## Deployment Overview

### What This Deployment Does

This deployment updates JavaScript normalization code in 11 n8n workflows to implement 5 critical data quality corrections:

1. **Component 2:** Brand Consolidation - Fix brand variants and typos
2. **Component 3:** Transmission Recovery - Recover valid transmission from contaminated fields
3. **Component 4:** Enhanced Model Normalization - Remove prefixes and brand names from modelo
4. **Component 5:** Enhanced Version Cleaning - Remove escape chars, fix door counts
5. **Component 6:** Intelligent Token Deduplication - Remove duplicate tokens from version strings

### Affected Systems

- **n8n Instance:** 11 ETL workflows (one per insurer)
- **Supabase Database:** `catalogo_homologado` table (~242,656 records)
- **Data Quality Impact:** Expected improvement from ~20% to >95% valid transmission values

### Deployment Scope

| Metric | Value |
|--------|-------|
| Workflows to Update | 11 |
| Code Files Modified | 11 (one per insurer) |
| Normalization Components | 5 core + 9 insurer-specific |
| Test Cases | 119 total (10 universal × 11 + 9 specific) |
| Estimated Duration | 45-55 minutes |
| Expected Data Quality Improvement | 75+ percentage points |

---

## Normalization Components Summary

### Component 2: Brand Consolidation

**Problem:** Brand name variants and typos cause failed matches
- Examples: "BMW BW" vs "BMW", "BERCEDES" vs "MERCEDES BENZ"

**Solution:** Centralized `BRAND_CONSOLIDATION_MAP` with 15+ mappings

**Impact:**
- ~500 records affected across all insurers
- Invalid brands ("AUTOS") will be discarded

**Validation:**
```sql
-- Should return 0 rows after deployment
SELECT marca, COUNT(*)
FROM catalogo_homologado
WHERE marca IN ('BMW BW', 'BERCEDES', 'KIA MOTORS')
GROUP BY marca;
```

---

### Component 3: Transmission Recovery

**Problem:** Contaminated transmission field prevents hash matching
- Examples: "GLI DSG" instead of "AUTO", "LATITUDE" instead of inferred "AUTO"

**Solution:** Two-step recovery:
1. Extract valid transmission from contaminated field
2. Infer transmission from version_original if step 1 fails

**Impact:**
- ~185,000+ records affected (improvement from 20% to >95% valid)
- Unrecoverable records will be discarded

**Validation:**
```sql
-- Should show >95% valid transmission
SELECT
  COUNT(*) AS total,
  SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) AS valid,
  ROUND(100.0 * SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct
FROM catalogo_homologado;
```

---

### Component 4: Enhanced Model Normalization

**Problem:** Prefixes and brand names contaminate modelo field
- Examples: "NUEVO CAMRY" → "CAMRY", "MAZDA CX-5" → "CX-5", "BMW X5" → "X5"

**Solution:**
- Remove NUEVO/NUEVA/NEW prefixes
- Remove brand-specific prefixes (Mazda, Mercedes, BMW patterns)
- Keep existing body type removal

**Impact:**
- ~8,000 records affected across all insurers
- Cleaner modelo field improves hash grouping

**Validation:**
```sql
-- Should return 0 rows after deployment
SELECT modelo, COUNT(*)
FROM catalogo_homologado
WHERE modelo ~* '^(NUEVO|NUEVA|NEW)\s'
GROUP BY modelo;
```

---

### Component 5: Enhanced Version Cleaning

**Problem:** Escape characters, concatenated tokens, invalid door counts
- Examples: `\"SPORT\"` → `SPORT`, `150HPAUT` → `150HP AUT`, `328PUERTAS` → (removed)

**Solution:**
- Remove all escape characters and quotes
- Separate HP+AUT patterns
- Fix invalid door counts with `fixInvalidDoorCounts()`

**Impact:**
- ~15,000 records affected across all insurers
- Cleaner version strings improve token matching

**Validation:**
```sql
-- Should return 0 rows after deployment
SELECT version, COUNT(*)
FROM catalogo_homologado
WHERE version ~* '[\\"\\\\]'
GROUP BY version;
```

---

### Component 6: Intelligent Token Deduplication

**Problem:** Duplicate tokens inflate similarity scores
- Examples: "SPORT 2.0L...SPORT 2.0L" → "SPORT 2.0L"

**Solution:**
- Deduplicate tokens while preserving different spec types
- First occurrence wins for true duplicates
- Use `isNumericSpecification()` to detect spec patterns

**Impact:**
- ~5,000 records affected across all insurers
- More accurate token overlap matching

**Validation:**
```sql
-- Should return 0 rows after deployment
SELECT version, COUNT(*)
FROM catalogo_homologado
WHERE array_length(version_tokens_array, 1) != array_length(
  (SELECT array_agg(DISTINCT unnest) FROM unnest(version_tokens_array)),
  1
)
GROUP BY version;
```

---

## Insurer-Specific Corrections

In addition to the 5 core components, some insurers have additional fixes:

| Insurer | Specific Correction | Requirement | Impact |
|---------|---------------------|-------------|--------|
| Zurich | Remove "MAZDA" prefix from Mazda models | Req 7.3 | ~500 records |
| HDI | Move body types from modelo to version | Req 7.7 | ~1,200 records |
| ANA | Remove "MA" prefix + "CHASIS" from models | Req 7.4 | ~800 records |
| BX | Remove brand name from modelo field | Req 7.5 | ~600 records |
| El Potosí | Clean Mercedes prefixes, generic Mazda models | Req 7.6 | ~400 records |
| GNP | Remove marca/modelo tokens from version | Req 7.8 | ~1,500 records |
| Chubb | Separate liters from adjacent text (2.0LAUT) | Req 7.9 | ~900 records |
| Atlas | Remove BMW model numbers as door counts | Req 7.10 | ~300 records |
| AXA | Standardize A-SPEC vs A SPEC formatting | Req 7.12 | ~700 records |

**See [n8n-per-insurer-changes.md](./n8n-per-insurer-changes.md) for detailed implementation.**

---

## Deployment Workflow

### Phase 1: Pre-Deployment (15 minutes)

1. ✓ Verify SQL function deployed (Task 109)
2. ✓ Verify all Phase 2 code updates complete (Tasks 5-37C)
3. ✓ Verify all Phase 3 validation tests passed (Tasks 104-108)
4. ✓ Export all 11 workflows as backup
5. ✓ Create backup manifest

**Checkpoint:** All prerequisites verified, backups created

---

### Phase 2: Deployment Execution (45-55 minutes)

**Priority 1 (High Impact) - 15 minutes:**
1. MAPFRE (5 min)
2. Qualitas (5 min)
3. Zurich (5 min)

**Priority 2 (Medium Impact) - 20 minutes:**
4. HDI (5 min)
5. ANA (5 min)
6. BX (5 min)
7. GNP (5 min)

**Priority 3 (Standard Impact) - 20 minutes:**
8. Chubb (5 min)
9. Atlas (5 min)
10. El Potosí (5 min)
11. AXA (5 min)

**Checkpoint:** All 11 workflows deployed, smoke tests passed

---

### Phase 3: Post-Deployment Validation (10-15 minutes)

1. Run validation queries for all 5 components
2. Verify A-SPEC vs TECH bug fixed
3. Check performance (batch processing <5 min)
4. Generate data quality report
5. Document any issues or rollbacks

**Checkpoint:** All validation queries passed, metrics improved

---

## Success Criteria

### Deployment Success

- [ ] All 11 workflows deployed with no JavaScript syntax errors
- [ ] All smoke tests passed (119/119 test cases successful)
- [ ] No critical errors in n8n execution logs

### Data Quality Success

- [ ] Brand consolidation: 0 invalid brand variants in new records
- [ ] Transmission recovery: >95% valid transmission values (up from ~20%)
- [ ] Model normalization: 0 NUEVO/NUEVA/NEW prefixes
- [ ] Version cleaning: 0 escape characters in version strings
- [ ] Token deduplication: No duplicate tokens in version arrays

### Performance Success

- [ ] Batch processing <5 minutes for 50k records (no regression)
- [ ] Error rate <2% in production processing
- [ ] No timeout errors (Supabase 2-minute limit)

### Bug Fix Verification

- [ ] A-SPEC vs TECH separation verified (SQL algorithm fix from Task 109)
- [ ] Best-match selection working correctly (only 1 record updated per vehicle)

---

## Rollback Plan

### When to Rollback

**Immediate rollback if:**
- >3 workflows failed deployment (>27% failure rate)
- Smoke test success rate <70% (<83/119 test cases passed)
- Data corruption detected (incorrect hash generation)
- Processing time increased >50% (performance regression)
- Error rate >5% in production

### How to Rollback

1. **Pause all affected workflows** (toggle Active to OFF)
2. **Restore from backup:**
   - Option A: Use n8n "Workflow History" → Restore previous version
   - Option B: Import from backup JSON files
3. **Verify restoration:** Run smoke test with 5 sample records
4. **Re-activate workflows:** Toggle Active to ON
5. **Document rollback:** Create rollback log with root cause analysis

**See [n8n-deployment-guide.md](./n8n-deployment-guide.md#rollback-instructions) for detailed steps.**

---

## Documentation Usage Guide

### For Deployment Engineers

**Before Deployment:**
1. Read [n8n-deployment-guide.md](./n8n-deployment-guide.md) - Overview and procedures
2. Review [n8n-per-insurer-changes.md](./n8n-per-insurer-changes.md) - Code changes
3. Print [n8n-deployment-checklist.md](./n8n-deployment-checklist.md) - Execution tracker
4. Prepare [n8n-smoke-test-cases.md](./n8n-smoke-test-cases.md) - Test data

**During Deployment:**
1. Follow [n8n-deployment-checklist.md](./n8n-deployment-checklist.md) step-by-step
2. Reference [n8n-per-insurer-changes.md](./n8n-per-insurer-changes.md) for insurer-specific details
3. Run test cases from [n8n-smoke-test-cases.md](./n8n-smoke-test-cases.md)
4. Record results in [n8n-deployment-checklist.md](./n8n-deployment-checklist.md)

**After Deployment:**
1. Complete validation section in [n8n-deployment-checklist.md](./n8n-deployment-checklist.md)
2. Use validation queries from [n8n-deployment-guide.md](./n8n-deployment-guide.md)
3. Document issues or rollbacks in [n8n-deployment-checklist.md](./n8n-deployment-checklist.md)
4. Archive completed checklist and test results

---

### For Technical Reviewers

**To Understand Changes:**
1. Read this summary for high-level overview
2. Review [n8n-per-insurer-changes.md](./n8n-per-insurer-changes.md) for implementation details
3. Check component matrix to see which fixes apply to which insurers

**To Validate Deployment:**
1. Review completed [n8n-deployment-checklist.md](./n8n-deployment-checklist.md)
2. Verify all smoke tests passed in [n8n-smoke-test-cases.md](./n8n-smoke-test-cases.md)
3. Run post-deployment validation queries from [n8n-deployment-guide.md](./n8n-deployment-guide.md)

---

### For Project Managers

**Deployment Metrics:**
- **Scope:** 11 workflows, 5 normalization components
- **Duration:** 45-55 minutes execution + 15 min pre + 15 min post = ~1.5 hours total
- **Risk Level:** Medium (comprehensive backups and rollback plan in place)
- **Impact:** High (improves data quality from ~20% to >95% valid transmission)

**Status Tracking:**
- Use [n8n-deployment-checklist.md](./n8n-deployment-checklist.md) for real-time progress
- Monitor "Deployment Summary" section for overall statistics
- Review "Issues Encountered" section for blockers

**Go/No-Go Decision:**
- All prerequisites in [n8n-deployment-checklist.md](./n8n-deployment-checklist.md) must be checked
- SQL function deployment (Task 109) must be successful
- Rollback plan understood and backups created

---

## Key Files Reference

### Source Code Files (Read-Only During Deployment)

```
/src/insurers/mapfre/mapfre-codigo-de-normalizacion.js
/src/insurers/zurich/zurich-codigo-de-normalizacion.js
/src/insurers/hdi/hdi-codigo-de-normalizacion.js
/src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js
/src/insurers/ana/ana-codigo-de-normalizacion.js
/src/insurers/bx/bx-codigo-de-normalizacion.js
/src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js
/src/insurers/gnp/gnp-codigo-de-normalizacion.js
/src/insurers/chubb/chubb-codigo-de-normalizacion.js
/src/insurers/atlas/atlas-codigo-de-normalizacion.js
/src/insurers/axa/axa-codigo-de-normalizacion.js
```

### Backup Files (Created During Pre-Deployment)

```
/backups/n8n-workflows/pre-deployment-[date]/
  ├── backup-mapfre-[timestamp].json
  ├── backup-zurich-[timestamp].json
  ├── backup-hdi-[timestamp].json
  ├── backup-qualitas-[timestamp].json
  ├── backup-ana-[timestamp].json
  ├── backup-bx-[timestamp].json
  ├── backup-elpotosi-[timestamp].json
  ├── backup-gnp-[timestamp].json
  ├── backup-chubb-[timestamp].json
  ├── backup-atlas-[timestamp].json
  ├── backup-axa-[timestamp].json
  └── BACKUP_MANIFEST.md
```

### Deployment Documentation (This Package)

```
/docs/
  ├── n8n-deployment-summary.md          ← THIS FILE
  ├── n8n-deployment-guide.md            ← Main procedures
  ├── n8n-per-insurer-changes.md         ← Code changes
  ├── n8n-deployment-checklist.md        ← Execution tracker
  └── n8n-smoke-test-cases.md            ← Test cases
```

---

## Contact Information

**For Deployment Support:**
- Technical Lead: [Name/Email]
- n8n Administrator: [Name/Email]
- Database Administrator: [Name/Email]
- Project Manager: [Name/Email]

**For Issues or Questions:**
- Create issue in project tracker
- Tag with: `deployment`, `n8n`, `phase-4`
- Include: workflow name, error message, timestamp

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-10-17 | Initial deployment documentation package | [Name] |

---

## Appendix: Quick Reference

### Component Matrix

| Insurer | Comp 2 | Comp 3 | Comp 4 | Comp 5 | Comp 6 | Specific |
|---------|--------|--------|--------|--------|--------|----------|
| MAPFRE | ✓ | ✓ | ✓ | ✓ | ✓ | - |
| Zurich | ✓ | ✓ | ✓ | ✓ | ✓ | 7.3 |
| HDI | ✓ | ✓ | ✓ | ✓ | ✓ | 7.7 |
| Qualitas | ✓ | ✓ | ✓ | ✓ | ✓ | - |
| ANA | ✓ | ✓ | ✓ | ✓ | ✓ | 7.4 |
| BX | ✓ | ✓ | ✓ | ✓ | ✓ | 7.5 |
| El Potosí | ✓ | ✓ | ✓ | ✓ | ✓ | 7.6 |
| GNP | ✓ | ✓ | ✓ | ✓ | ✓ | 7.8 |
| Chubb | ✓ | ✓ | ✓ | ✓ | ✓ | 7.9 |
| Atlas | ✓ | ✓ | ✓ | ✓ | ✓ | 7.10 |
| AXA | ✓ | ✓ | ✓ | ✓ | ✓ | 7.12 |

### Validation Queries Quick Copy

```sql
-- 1. Brand Consolidation (should return 0)
SELECT marca, COUNT(*) FROM catalogo_homologado
WHERE marca IN ('BMW BW', 'BERCEDES', 'KIA MOTORS') GROUP BY marca;

-- 2. Transmission Recovery (should show >95%)
SELECT ROUND(100.0 * SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) / COUNT(*), 2)
FROM catalogo_homologado;

-- 3. Model Normalization (should return 0)
SELECT modelo, COUNT(*) FROM catalogo_homologado
WHERE modelo ~* '^(NUEVO|NUEVA|NEW)\s' GROUP BY modelo LIMIT 10;

-- 4. Version Cleaning (should return 0)
SELECT version, COUNT(*) FROM catalogo_homologado
WHERE version ~* '[\\"\\\\]' GROUP BY version LIMIT 10;

-- 5. A-SPEC Fix (should show separate records)
SELECT version, COUNT(*) FROM catalogo_homologado
WHERE marca = 'ACURA' AND modelo = 'TLX' AND anio = 2021
GROUP BY version ORDER BY version;
```

---

**End of Deployment Summary**

**Ready to deploy? Start with [n8n-deployment-guide.md](./n8n-deployment-guide.md)**
