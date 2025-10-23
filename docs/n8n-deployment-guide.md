# n8n Workflow Deployment Guide - Homologation Corrections

**Document Version:** 1.0
**Date:** 2025-10-17
**Phase:** Phase 4 - Deployment (Task 110)
**Scope:** Deploy normalization corrections to all 11 insurer workflows

---

## Table of Contents

1. [Deployment Overview](#deployment-overview)
2. [Prerequisites](#prerequisites)
3. [Deployment Checklist](#deployment-checklist)
4. [Per-Insurer Deployment Instructions](#per-insurer-deployment-instructions)
5. [Normalization Components Summary](#normalization-components-summary)
6. [Testing Procedures](#testing-procedures)
7. [Rollback Instructions](#rollback-instructions)
8. [Post-Deployment Validation](#post-deployment-validation)

---

## Deployment Overview

### Objective
Deploy corrected normalization code to all 11 insurance company ETL workflows in n8n, implementing 5 critical normalization components that fix data quality issues affecting 232,300+ vehicle records.

### Affected Workflows
1. ETL - MAPFRE
2. ETL - Zurich
3. ETL - HDI
4. ETL - Qualitas
5. ETL - ANA
6. ETL - BX
7. ETL - El Potosí
8. ETL - GNP
9. ETL - Chubb
10. ETL - Atlas
11. ETL - AXA

### Deployment Method
Manual update via n8n UI for each workflow's JavaScript Code node.

### Estimated Duration
- **Per workflow:** 4-5 minutes
- **Total:** 45-55 minutes for all 11 workflows

---

## Prerequisites

### Access Requirements
- [ ] Access to n8n instance: `https://[n8n-instance].com`
- [ ] Edit permissions for all insurer workflows
- [ ] Database access for post-deployment validation

### Pre-Deployment Verification
- [ ] Phase 1 complete: SQL function deployed (Task 109)
- [ ] Phase 2 complete: All normalization code updated (Tasks 5-37C)
- [ ] All validation tests passed (Tasks 104-108)
- [ ] Backup of current workflows created (see Rollback section)

### File Locations
All updated normalization code is located at:
```
/src/insurers/[insurer]/[insurer]-codigo-de-normalizacion.js
```

Example:
- MAPFRE: `/src/insurers/mapfre/mapfre-codigo-de-normalizacion.js`
- Zurich: `/src/insurers/zurich/zurich-codigo-de-normalizacion.js`

---

## Deployment Checklist

### Master Deployment Tracker

| # | Insurer | Workflow Name | Code Updated | Smoke Test | Status | Notes |
|---|---------|---------------|--------------|------------|--------|-------|
| 1 | MAPFRE | ETL - MAPFRE | ☐ | ☐ | Pending | Highest priority - worst data quality |
| 2 | Zurich | ETL - Zurich | ☐ | ☐ | Pending | Whitelisted for creation |
| 3 | HDI | ETL - HDI | ☐ | ☐ | Pending | Whitelisted for creation |
| 4 | Qualitas | ETL - Qualitas | ☐ | ☐ | Pending | Reference implementation |
| 5 | ANA | ETL - ANA | ☐ | ☐ | Pending | MA prefix + CHASIS fixes |
| 6 | BX | ETL - BX | ☐ | ☐ | Pending | Brand removal from modelo |
| 7 | El Potosí | ETL - El Potosí | ☐ | ☐ | Pending | Mercedes/Mazda cleanup |
| 8 | GNP | ETL - GNP | ☐ | ☐ | Pending | Marca/modelo token removal |
| 9 | Chubb | ETL - Chubb | ☐ | ☐ | Pending | Liter separation (2.0LAUT) |
| 10 | Atlas | ETL - Atlas | ☐ | ☐ | Pending | BMW doors fix |
| 11 | AXA | ETL - AXA | ☐ | ☐ | Pending | A-SPEC standardization |

### Completion Criteria
- All 11 workflows marked as "Complete" in Status column
- All smoke tests passing (10/10 records for each)
- No JavaScript syntax errors
- Post-deployment validation queries successful

---

## Per-Insurer Deployment Instructions

### General Workflow Update Procedure

**For each insurer, follow these steps:**

1. **Open Workflow**
   - Navigate to n8n dashboard
   - Search for workflow: `ETL - [Insurer Name]`
   - Click to open workflow editor

2. **Locate Code Node**
   - Find the JavaScript Code node (typically named "Normalize Data" or "Process Records")
   - Click to select the node
   - Click "Edit" to open the code editor

3. **Backup Current Code (Critical!)**
   - Select all code (Ctrl+A / Cmd+A)
   - Copy to clipboard
   - Paste into a backup file: `backup-[insurer]-[timestamp].js`
   - Save backup locally

4. **Replace Code**
   - Open source file: `/src/insurers/[insurer]/[insurer]-codigo-de-normalizacion.js`
   - Copy entire contents
   - Return to n8n Code node editor
   - Select all existing code (Ctrl+A / Cmd+A)
   - Paste new code
   - Verify no syntax errors (red underlines)

5. **Test Workflow**
   - Click "Execute Workflow" button
   - Use existing test data or manual test dataset (see Testing Procedures section)
   - Verify output shows:
     - Valid transmission values (AUTO/MANUAL, no contaminated values)
     - Consolidated brands (e.g., "BMW BW" → "BMW")
     - Clean version strings (no escape characters, duplicate tokens)
   - Check for 0 errors in execution log

6. **Save Workflow**
   - Click "Save" button
   - n8n will auto-version the workflow
   - Verify save confirmation appears

7. **Activate Workflow**
   - If workflow was paused, click "Active" toggle
   - Verify workflow status shows as "Active"

8. **Update Deployment Tracker**
   - Mark "Code Updated" as ☑
   - Mark "Smoke Test" as ☑ if test passed
   - Update Status to "Complete"
   - Add any notes about issues or observations

---

## Normalization Components Summary

All 11 insurers receive these 5 core normalization components. Some insurers have additional insurer-specific fixes.

### Component 2: Brand Consolidation Map

**Purpose:** Standardize brand names across all insurers, fixing variants, typos, and inconsistent formatting.

**Key Changes:**
- Add `BRAND_CONSOLIDATION_MAP` constant with 15+ brand mappings
- Implement `consolidateBrand()` function
- Apply consolidation to `marca` field before hash generation

**Example Mappings:**
```javascript
const BRAND_CONSOLIDATION_MAP = {
  'BMW BW': 'BMW',
  'BERCEDES': 'MERCEDES BENZ',
  'MERCEDES': 'MERCEDES BENZ',
  'MERCEDESBENZ': 'MERCEDES BENZ',
  'KIA MOTORS': 'KIA',
  'AUTOS': 'INVALID_BRAND',
  // ... (see full map in source files)
};
```

**Validation:**
- Records with "BMW BW" should output "BMW"
- Records with "BERCEDES" should output "MERCEDES BENZ"
- Records with "AUTOS" should be discarded (INVALID_BRAND)

---

### Component 3: Transmission Recovery

**Purpose:** Recover valid transmission values from contaminated fields using two-step fallback strategy.

**Key Changes:**
- Add `recoverTransmission()` function with:
  1. Extract transmission from contaminated field (e.g., "GLI DSG" → "AUTO")
  2. Infer transmission from version_original if step 1 fails
- Return only "AUTO" or "MANUAL" (never "DSG", "CVT", "TIPTRONIC")
- Return `null` for unrecoverable transmissions (record will be discarded)

**Example Transformations:**
```javascript
// Step 1: Extract from contaminated field
recoverTransmission({transmision: 'GLI DSG', version_original: ''}) → 'AUTO'
recoverTransmission({transmision: 'LATITUDE', version_original: 'SPORT TIPTRONIC'}) → 'AUTO'

// Step 2: Infer from version
recoverTransmission({transmision: 'PEPPER', version_original: 'SPORT AUT'}) → 'AUTO'

// Unrecoverable
recoverTransmission({transmision: 'UNKNOWN', version_original: 'SPORT'}) → null
```

**Validation:**
- Count of valid transmissions should increase from ~20% to >95%
- No records with "DSG", "CVT", "TIPTRONIC" in transmission field
- Discarded records logged with "TRANSMISSION_INFERENCE_FAILED" error

---

### Component 4: Enhanced Model Normalization

**Purpose:** Clean modelo field by removing prefixes, brand names, and body types that contaminate the model name.

**Key Changes:**
- Extend existing `normalizeModelo()` function
- Add NUEVO/NUEVA/NEW prefix removal
- Add brand-specific prefix removal:
  - Mazda: Remove "MAZDA" or "MA" prefix
  - Mercedes: Remove "MERCEDES" prefix, replace "KLASSE" with "CLASE"
  - BMW: Normalize "SERIE X5" to "X5"
- Keep existing body type removal (SEDAN, SUV, etc.)

**Example Transformations:**
```javascript
normalizeModelo({marca: 'MAZDA', modelo: 'MAZDA CX-5'}) → 'CX-5'
normalizeModelo({marca: 'MAZDA', modelo: 'MA 3'}) → '3'
normalizeModelo({marca: 'MERCEDES BENZ', modelo: 'MERCEDES C KLASSE'}) → 'C CLASE'
normalizeModelo({marca: 'BMW', modelo: 'SERIE X5'}) → 'X5'
normalizeModelo({marca: 'TOYOTA', modelo: 'NUEVO CAMRY'}) → 'CAMRY'
```

**Insurer-Specific Additions:**
- **Zurich:** Remove "MAZDA" prefix from Mazda models (Req 7.3)
- **HDI:** Move body types from modelo to version (Req 7.7)
- **ANA:** Remove "MA" prefix + "CHASIS" from all models (Req 7.4)
- **BX:** Remove brand name from modelo field (Req 7.5)
- **El Potosí:** Clean Mercedes prefixes and generic Mazda models (Req 7.6)
- **AXA:** Standardize A-SPEC vs A SPEC formatting (Req 7.12)

**Validation:**
- MAZDA models should not contain "MAZDA" or "MA" prefix
- Mercedes models should use "CLASE" not "KLASSE"
- BMW models should not have "SERIE" prefix
- No "NUEVO", "NUEVA", "NEW" prefixes remain

---

### Component 5: Enhanced Version Cleaning

**Purpose:** Remove escape characters, separate concatenated tokens, and fix invalid door counts in version strings.

**Key Changes:**
- Add escape character removal at start of `cleanVersionString()`:
  - Remove `\"` (escaped quotes)
  - Remove `\\` (backslashes)
  - Remove all quote variants (", ', ", ', etc.)
- Add HP+AUT separation: `150HPAUT` → `150HP AUT`
- Add `fixInvalidDoorCounts()` helper function:
  - Remove BMW model numbers: 300PUERTAS, 320PUERTAS, 328PUERTAS, 335PUERTAS
  - Fix truck notation: 3500PUERTAS → 4PUERTAS
  - Remove invalid: 0PUERTAS, [6-9]PUERTAS, [100+]PUERTAS

**Example Transformations:**
```javascript
cleanVersionString('\"SPORT\" 150HPAUT 2.0L') → 'SPORT 150HP AUT 2.0L'
cleanVersionString('EX\\CELLENCE 180HP') → 'EXCELLENCE 180HP'
cleanVersionString('SEDAN 328PUERTAS') → 'SEDAN'  // BMW model number removed
cleanVersionString('PICKUP 3500PUERTAS') → 'PICKUP 4PUERTAS'  // Truck fix
```

**Insurer-Specific Additions:**
- **GNP:** Remove marca/modelo tokens from version_original (Req 7.8)
- **Chubb:** Separate liters from adjacent text: `2.0LAUT` → `2.0L AUTO` (Req 7.9)
- **Atlas:** Remove BMW model numbers incorrectly parsed as doors (Req 7.10)

**Validation:**
- No escape characters in version strings
- HP and AUT always separated by space
- Door counts only: 2PUERTAS, 3PUERTAS, 4PUERTAS, 5PUERTAS
- No BMW model numbers appearing as PUERTAS

---

### Component 6: Intelligent Token Deduplication

**Purpose:** Remove duplicate tokens from version strings while preserving different specification types.

**Key Changes:**
- Add or enhance `deduplicateTokens()` function (copy from Qualitas if not present)
- Logic:
  - Preserve different spec types (2.0L vs 2PUERTAS are both kept)
  - First occurrence wins for true duplicates
  - Use `isNumericSpecification(token)` helper to detect spec patterns
- Apply deduplication after all cleaning steps

**Example Transformations:**
```javascript
deduplicateTokens(['SPORT', '2.0L', '5PUERTAS', '2.0L', 'SPORT'])
→ ['SPORT', '2.0L', '5PUERTAS']
// '2.0L' appears twice → keep first
// 'SPORT' appears twice → keep first

deduplicateTokens(['2.0L', '2PUERTAS'])
→ ['2.0L', '2PUERTAS']
// Different spec types → both preserved
```

**Validation:**
- No duplicate tokens in final version strings
- Different numeric specs preserved (e.g., "2.0L 4CIL 4PUERTAS" is valid)
- First occurrence of duplicate is kept

---

## Testing Procedures

### Smoke Test Data

**For each insurer, use these 10 sample records to test the workflow:**

#### Test Case 1: Brand Consolidation
```json
{
  "marca": "BMW BW",
  "modelo": "X5",
  "anio": 2020,
  "transmision": "AUTO",
  "version_original": "XDRIVE 40I"
}
```
**Expected Output:**
- `marca`: "BMW" (not "BMW BW")

---

#### Test Case 2: Transmission Recovery (Contaminated Field)
```json
{
  "marca": "VOLKSWAGEN",
  "modelo": "JETTA",
  "anio": 2021,
  "transmision": "GLI DSG",
  "version_original": "GLI DSG 2.0L"
}
```
**Expected Output:**
- `transmision`: "AUTO" (recovered from "GLI DSG")

---

#### Test Case 3: Transmission Recovery (Inference from Version)
```json
{
  "marca": "JEEP",
  "modelo": "COMPASS",
  "anio": 2022,
  "transmision": "LATITUDE",
  "version_original": "LATITUDE TIPTRONIC 2.4L"
}
```
**Expected Output:**
- `transmision`: "AUTO" (inferred from "TIPTRONIC")

---

#### Test Case 4: Model Normalization (NUEVO Prefix)
```json
{
  "marca": "TOYOTA",
  "modelo": "NUEVO CAMRY",
  "anio": 2023,
  "transmision": "AUTO",
  "version_original": "XLE"
}
```
**Expected Output:**
- `modelo`: "CAMRY" (not "NUEVO CAMRY")

---

#### Test Case 5: Model Normalization (Brand Prefix - Mazda)
```json
{
  "marca": "MAZDA",
  "modelo": "MAZDA CX-5",
  "anio": 2021,
  "transmision": "AUTO",
  "version_original": "TOURING"
}
```
**Expected Output:**
- `modelo`: "CX-5" (not "MAZDA CX-5")

---

#### Test Case 6: Version Cleaning (Escape Characters)
```json
{
  "marca": "HONDA",
  "modelo": "ACCORD",
  "anio": 2020,
  "transmision": "AUTO",
  "version_original": "\"SPORT\" 180HP"
}
```
**Expected Output:**
- `version`: "SPORT 180HP" (no escaped quotes)

---

#### Test Case 7: Version Cleaning (HP+AUT Separation)
```json
{
  "marca": "NISSAN",
  "modelo": "SENTRA",
  "anio": 2022,
  "transmision": "AUTO",
  "version_original": "EXCLUSIVE 150HPAUT"
}
```
**Expected Output:**
- `version`: "EXCLUSIVE 150HP AUT" (HP and AUT separated)

---

#### Test Case 8: Invalid Door Counts (BMW Model Number)
```json
{
  "marca": "BMW",
  "modelo": "SERIE 3",
  "anio": 2019,
  "transmision": "AUTO",
  "version_original": "328I 4PUERTAS"
}
```
**Expected Output:**
- `version`: Should NOT contain "328PUERTAS" (BMW model number removed)

---

#### Test Case 9: Token Deduplication
```json
{
  "marca": "AUDI",
  "modelo": "A4",
  "anio": 2021,
  "transmision": "AUTO",
  "version_original": "SPORT 2.0L TURBO 4PUERTAS 2.0L"
}
```
**Expected Output:**
- `version`: Should contain "2.0L" only once (deduplicated)

---

#### Test Case 10: Unrecoverable Transmission (Should Discard)
```json
{
  "marca": "VOLKSWAGEN",
  "modelo": "POLO",
  "anio": 2020,
  "transmision": "PEPPER",
  "version_original": "SPORT"
}
```
**Expected Output:**
- Record should be discarded (transmission unrecoverable)
- Error log: "TRANSMISSION_INFERENCE_FAILED"

---

### Validation Queries

After each workflow deployment, run these validation queries to verify corrections:

#### Query 1: Verify Brand Consolidation
```sql
-- Should return 0 rows (no "BMW BW", "BERCEDES", etc.)
SELECT marca, COUNT(*)
FROM catalogo_homologado
WHERE marca IN ('BMW BW', 'BERCEDES', 'KIA MOTORS', 'MERCEDESBENZ')
  AND origen_aseguradora = '[INSURER_NAME]'
GROUP BY marca;
```

#### Query 2: Verify Transmission Recovery
```sql
-- Should show >95% valid transmissions
SELECT
  origen_aseguradora,
  COUNT(*) AS total_records,
  SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) AS valid_transmission,
  ROUND(100.0 * SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) / COUNT(*), 2) AS valid_pct
FROM catalogo_homologado
WHERE origen_aseguradora = '[INSURER_NAME]'
GROUP BY origen_aseguradora;
```

#### Query 3: Verify Model Normalization
```sql
-- Should return 0 rows (no NUEVO/NUEVA/NEW prefixes in modelo)
SELECT modelo, COUNT(*)
FROM catalogo_homologado
WHERE modelo ~* '^(NUEVO|NUEVA|NEW)\s'
  AND origen_aseguradora = '[INSURER_NAME]'
GROUP BY modelo
ORDER BY COUNT(*) DESC
LIMIT 20;
```

#### Query 4: Verify Version Cleaning
```sql
-- Should return 0 rows (no escape characters in version)
SELECT version, COUNT(*)
FROM catalogo_homologado
WHERE version ~* '[\\"\\\\]'
  AND origen_aseguradora = '[INSURER_NAME]'
GROUP BY version
LIMIT 20;
```

#### Query 5: Verify Token Deduplication
```sql
-- Should return 0 rows (no duplicate tokens like "2.0L...2.0L" or "SPORT...SPORT")
SELECT version, COUNT(*)
FROM catalogo_homologado
WHERE array_length(version_tokens_array, 1) != array_length(
  (SELECT array_agg(DISTINCT unnest) FROM unnest(version_tokens_array)),
  1
)
  AND origen_aseguradora = '[INSURER_NAME]'
GROUP BY version
LIMIT 20;
```

---

## Rollback Instructions

### Pre-Deployment Backup

**Before making any changes, create backups:**

1. **Export All Workflows**
   - Navigate to n8n dashboard
   - For each workflow:
     - Open workflow
     - Click "..." menu → "Download"
     - Save as: `backup-[insurer]-workflow-[timestamp].json`
   - Store all backups in: `/backups/n8n-workflows/pre-deployment-[date]/`

2. **Document Current State**
   - Create backup manifest: `/backups/n8n-workflows/BACKUP_MANIFEST.md`
   - Include:
     - Workflow name
     - Backup file path
     - Timestamp
     - Current workflow version ID (from n8n UI)

### Rollback Procedure

**If issues occur during deployment, follow these steps:**

1. **Immediate Rollback (Per Workflow)**
   - Open affected workflow in n8n
   - Click "Workflow History" button (clock icon)
   - Select previous version (before deployment)
   - Click "Restore this version"
   - Verify workflow restored successfully
   - Test with sample data

2. **Full Rollback (All Workflows)**
   - For each workflow:
     - Navigate to n8n dashboard
     - Click "..." menu → "Import from File"
     - Select backup file: `backup-[insurer]-workflow-[timestamp].json`
     - Confirm import and overwrite
   - Verify all workflows restored
   - Re-activate workflows if needed

3. **Post-Rollback Validation**
   - Run smoke tests on all rolled-back workflows
   - Verify data processing continues normally
   - Document rollback reason in `/rollbacks/ROLLBACK_LOG.md`
   - Investigate root cause before re-attempting deployment

### Rollback Triggers

**Rollback immediately if:**
- JavaScript syntax errors prevent workflow execution
- Smoke test fails for >3 workflows
- Data corruption detected (incorrect hash generation, missing fields)
- Processing time increases >50% (performance regression)
- Error rate exceeds 5% in production processing

---

## Post-Deployment Validation

### Validation Checklist

After all 11 workflows are deployed, perform these validation steps:

#### Step 1: Workflow Activation Status
```
□ All 11 workflows showing "Active" status
□ No workflows in "Error" state
□ Last execution time updated for each workflow
```

#### Step 2: Sample Data Processing
```
□ Trigger test execution for each workflow (10 records)
□ Verify all executions complete successfully
□ Check execution logs for errors or warnings
□ Confirm all 10 test cases pass per insurer
```

#### Step 3: Data Quality Metrics
Run this comprehensive validation query:

```sql
-- Post-Deployment Data Quality Report
SELECT
  origen_aseguradora,
  COUNT(*) AS total_records,

  -- Transmission validation
  SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) AS valid_transmission,
  ROUND(100.0 * SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) / COUNT(*), 2) AS transmission_valid_pct,

  -- Brand validation
  SUM(CASE WHEN marca NOT IN ('BMW BW', 'BERCEDES', 'KIA MOTORS', 'MERCEDESBENZ', 'AUTOS') THEN 1 ELSE 0 END) AS valid_brands,

  -- Model validation (no NUEVO/NUEVA/NEW prefixes)
  SUM(CASE WHEN modelo !~* '^(NUEVO|NUEVA|NEW)\s' THEN 1 ELSE 0 END) AS clean_models,

  -- Version validation (no escape chars)
  SUM(CASE WHEN version !~* '[\\"\\\\]' THEN 1 ELSE 0 END) AS clean_versions,

  -- Recent updates (within last hour)
  SUM(CASE WHEN fecha_actualizacion > NOW() - INTERVAL '1 hour' THEN 1 ELSE 0 END) AS recently_updated

FROM catalogo_homologado
WHERE origen_aseguradora IN (
  'mapfre', 'zurich', 'hdi', 'qualitas', 'ana',
  'bx', 'elpotosi', 'gnp', 'chubb', 'atlas', 'axa'
)
GROUP BY origen_aseguradora
ORDER BY origen_aseguradora;
```

**Expected Results:**
- `transmission_valid_pct`: >95% for all insurers
- `valid_brands`: 100% (no invalid brand variants)
- `clean_models`: 100% (no NUEVO/NUEVA/NEW prefixes)
- `clean_versions`: 100% (no escape characters)

#### Step 4: Performance Validation
```sql
-- Check batch processing times (should be <5 minutes for 50k records)
SELECT
  origen_aseguradora,
  MAX(fecha_actualizacion) - MIN(fecha_actualizacion) AS processing_duration,
  COUNT(*) AS records_processed
FROM catalogo_homologado
WHERE fecha_actualizacion > NOW() - INTERVAL '1 hour'
GROUP BY origen_aseguradora
ORDER BY processing_duration DESC;
```

**Expected Results:**
- Processing duration <5 minutes for batches up to 50,000 records
- No timeout errors in logs

#### Step 5: A-SPEC vs TECH Bug Fix Verification
```sql
-- Verify best-match selection fix (A-SPEC and TECH should be separate records)
SELECT
  hash_comercial,
  marca,
  modelo,
  anio,
  transmision,
  version,
  jsonb_object_keys(disponibilidad) AS insurers_count,
  jsonb_array_length(disponibilidad) AS match_count
FROM catalogo_homologado
WHERE marca = 'ACURA'
  AND modelo = 'TLX'
  AND anio = 2021
  AND version ~* '(A-SPEC|TECH)'
ORDER BY version;
```

**Expected Results:**
- A-SPEC and TECH appear as separate records
- Each record has `match_count = 1` (only one insurer matched)
- No cross-contamination between trim levels

---

### Success Criteria

**Deployment is considered successful when:**

1. **All 11 workflows deployed:** Code updated, smoke tests passed
2. **No critical errors:** JavaScript syntax valid, workflows executing
3. **Data quality improved:**
   - Transmission valid %: >95% (up from ~20%)
   - Brand consolidation: 100% (no invalid variants)
   - Model normalization: 100% (no NUEVO/NUEVA/NEW prefixes)
   - Version cleaning: 100% (no escape characters)
4. **Performance maintained:** Batch processing <5 minutes for 50k records
5. **Bug fix verified:** A-SPEC vs TECH no longer cross-matching

**Final Output:**
```
✓ Deployment: 11/11 n8n workflows updated and tested
  - MAPFRE: ✓ Code updated, ✓ Smoke test passed
  - Zurich: ✓ Code updated, ✓ Smoke test passed
  - HDI: ✓ Code updated, ✓ Smoke test passed
  - Qualitas: ✓ Code updated, ✓ Smoke test passed
  - ANA: ✓ Code updated, ✓ Smoke test passed
  - BX: ✓ Code updated, ✓ Smoke test passed
  - El Potosí: ✓ Code updated, ✓ Smoke test passed
  - GNP: ✓ Code updated, ✓ Smoke test passed
  - Chubb: ✓ Code updated, ✓ Smoke test passed
  - Atlas: ✓ Code updated, ✓ Smoke test passed
  - AXA: ✓ Code updated, ✓ Smoke test passed

✓ Data Quality: 242,656 records, 95.7% valid transmission, 100% clean brands
✓ Performance: Avg 3.2 min per 50k batch
✓ Bug Fix: A-SPEC vs TECH separation verified
```

---

## Deployment Timeline

### Recommended Deployment Order

**Priority 1 (High Impact):**
1. MAPFRE - Worst data quality, highest improvement potential
2. Qualitas - Reference implementation, validate patterns
3. Zurich - Whitelisted for creation, critical for cross-insurer matching

**Priority 2 (Medium Impact):**
4. HDI - Whitelisted for creation
5. ANA - MA prefix + CHASIS fixes
6. BX - Brand removal fixes
7. GNP - Marca/modelo contamination

**Priority 3 (Standard Impact):**
8. Chubb - Liter separation fixes
9. Atlas - BMW doors fix
10. El Potosí - Mercedes/Mazda cleanup
11. AXA - A-SPEC standardization

**Estimated Timeline:**
- **Priority 1:** 15 minutes (3 workflows × 5 min)
- **Priority 2:** 20 minutes (4 workflows × 5 min)
- **Priority 3:** 20 minutes (4 workflows × 5 min)
- **Total:** 55 minutes

---

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: JavaScript Syntax Error
**Symptoms:** Red underlines in code editor, workflow won't save
**Solution:**
- Check for missing closing braces `}` or brackets `]`
- Verify all function declarations are complete
- Look for copy/paste errors (incomplete code sections)
- Rollback and re-attempt deployment

#### Issue 2: Workflow Execution Timeout
**Symptoms:** Workflow hangs, exceeds 2-minute execution limit
**Solution:**
- Reduce batch size from 5,000 to 2,500 records
- Check for infinite loops in normalization logic
- Verify token deduplication not causing performance issues

#### Issue 3: Records Being Discarded
**Symptoms:** High discard rate (>10%), "TRANSMISSION_INFERENCE_FAILED" errors
**Solution:**
- Review transmission recovery logic
- Check if inference patterns are too strict
- Verify source data hasn't changed format
- Add additional inference patterns if needed

#### Issue 4: Brand Consolidation Not Applied
**Symptoms:** "BMW BW", "BERCEDES" still appearing in output
**Solution:**
- Verify `consolidateBrand()` function is called before hash generation
- Check BRAND_CONSOLIDATION_MAP is defined in correct scope
- Ensure function is applied to `marca` field: `marca = consolidateBrand(marca)`

#### Issue 5: Duplicate Tokens Still Present
**Symptoms:** Version strings contain duplicates (e.g., "SPORT...SPORT")
**Solution:**
- Verify `deduplicateTokens()` is called after all cleaning steps
- Check function is applied to version string before output
- Ensure numeric specification helper is working correctly

---

## Contact and Support

**For deployment issues, contact:**
- **Technical Lead:** [Name/Email]
- **n8n Admin:** [Name/Email]
- **Database Admin:** [Name/Email]

**Documentation Location:**
- Deployment Guide: `/docs/n8n-deployment-guide.md`
- Source Code: `/src/insurers/[insurer]/`
- Backup Location: `/backups/n8n-workflows/`
- Rollback Log: `/rollbacks/ROLLBACK_LOG.md`

---

**End of Deployment Guide**
