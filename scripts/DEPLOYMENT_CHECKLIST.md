# Deployment Checklist
## Correcciones de Homologación - Production Deployment

**Purpose**: Step-by-step checklist for deploying all Phase 4 changes to production
**Prerequisites**: All Phase 1-3 tasks completed (Tasks 1-108)
**Estimated Time**: 2-3 hours total
**Team Required**: 1-2 people (recommended: database admin + ETL operator)

---

## Pre-Deployment Checklist

### Environment Verification

- [ ] **Supabase Access Verified**
  - [ ] Can access Supabase dashboard: https://app.supabase.com
  - [ ] SQL Editor accessible
  - [ ] Current production function accessible
  - [ ] Database credentials available in `.env`

- [ ] **n8n Access Verified**
  - [ ] Can access n8n instance: https://[n8n-instance].com
  - [ ] All 11 workflows visible (MAPFRE, Zurich, HDI, Qualitas, ANA, BX, El Potosi, GNP, Chubb, Atlas, AXA)
  - [ ] Workflow edit permissions confirmed
  - [ ] Can execute test workflows

- [ ] **Backup Strategy Confirmed**
  - [ ] SQL function backup location identified
  - [ ] n8n workflow version history accessible
  - [ ] Rollback procedures reviewed and understood
  - [ ] Communication plan for rollback scenarios

- [ ] **Testing Infrastructure Ready**
  - [ ] Test database or staging environment available (optional)
  - [ ] Sample data prepared for smoke tests
  - [ ] Monitoring dashboard accessible
  - [ ] Alerting configured (optional)

### Code Verification

- [ ] **Git Repository Clean**
  ```bash
  cd /mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl
  git status  # Should show clean working tree on branch 001-correcciones-homologacion
  git log -5  # Verify latest commits include Phase 1-3 changes
  ```

- [ ] **Modified Files Present**
  - [ ] `src/supabase/funciones-homologacion-actuales.sql` - Algorithm fix
  - [ ] All 11 insurer normalization files in `src/insurers/*/`
  - [ ] Test files in `tests/` directory
  - [ ] Quality report script in `scripts/generate_quality_report.sql`

- [ ] **Test Files Accessible**
  - [ ] `tests/integration/test_best_match_selection.sql`
  - [ ] `tests/integration/test_idempotency.sql`
  - [ ] `tests/validation/test_brand_consolidation.js`
  - [ ] `tests/validation/test_transmission_recovery.js`
  - [ ] `tests/performance/test_batch_processing.sql`

---

## Task 109: Deploy Updated Supabase Function

**Estimated Time**: 20-30 minutes
**Risk Level**: MEDIUM (affects all future data processing)
**Rollback Time**: 5 minutes

### Step 1: Create Backup Function

- [ ] **Open Supabase SQL Editor**
  - Navigate to: https://app.supabase.com → Project → SQL Editor
  - Create new query

- [ ] **Export Current Function**
  ```sql
  -- Get current function definition
  SELECT pg_get_functiondef(oid)
  FROM pg_proc
  WHERE proname = 'procesar_batch_vehiculos';

  -- Copy output to backup file: backup_procesar_batch_vehiculos_[DATE].sql
  ```

- [ ] **Create Backup Function**
  ```sql
  -- Create backup with _backup suffix
  CREATE OR REPLACE FUNCTION procesar_batch_vehiculos_backup(vehiculos_json JSONB)
  RETURNS JSONB
  LANGUAGE plpgsql
  AS $$
  -- [Paste current function body here]
  $$;

  -- Verify backup created
  SELECT proname FROM pg_proc WHERE proname LIKE 'procesar_batch%';
  -- Expected: procesar_batch_vehiculos, procesar_batch_vehiculos_backup
  ```

- [ ] **Backup Verified**
  - [ ] Backup function created successfully
  - [ ] Both functions visible in pg_proc
  - [ ] Backup file saved to `backups/procesar_batch_vehiculos_backup_[DATE].sql`

**Checkpoint**: Do NOT proceed until backup is verified

### Step 2: Deploy Updated Function

- [ ] **Load Updated Function**
  - Open file: `src/supabase/funciones-homologacion-actuales.sql`
  - Copy entire contents (CREATE OR REPLACE FUNCTION statement)

- [ ] **Execute in SQL Editor**
  ```sql
  -- Paste updated function definition from funciones-homologacion-actuales.sql
  CREATE OR REPLACE FUNCTION procesar_batch_vehiculos(vehiculos_json JSONB)
  RETURNS JSONB
  LANGUAGE plpgsql
  AS $$
  -- [Updated function body with best-match selection]
  $$;
  ```

- [ ] **Verify Deployment**
  - [ ] No syntax errors in SQL Editor
  - [ ] Function replaced successfully
  - [ ] Green checkmark or success message displayed

### Step 3: Smoke Test

- [ ] **Run Minimal Test**
  ```sql
  -- Test with single record
  SELECT procesar_batch_vehiculos('[
    {
      "hash_comercial": "test_smoke_001",
      "id_canonico": "test_smoke_canon_001",
      "marca": "TEST",
      "modelo": "SMOKE",
      "anio": 2023,
      "transmision": "AUTO",
      "version": "BASE 2.0L 150HP 4PUERTAS",
      "origen_aseguradora": "TEST_DEPLOYMENT",
      "id_original": "smoke_001",
      "version_original": "BASE 2.0L 150HP 4PUERTAS",
      "activo": true,
      "string_comercial": "TEST|SMOKE|2023|AUTO",
      "string_tecnico": "BASE 2.0L 150HP 4PUERTAS"
    }
  ]'::jsonb);

  -- Expected output:
  -- {
  --   "inserted_count": 1,
  --   "updated_count": 0,
  --   "tier1_count": 0,
  --   "tier2_count": 0,
  --   "tier3_count": 1,
  --   "warnings": [],
  --   "errors": []
  -- }
  ```

- [ ] **Smoke Test Results**
  - [ ] Function executed without errors
  - [ ] Returns valid JSONB response
  - [ ] inserted_count = 1
  - [ ] No errors array populated

- [ ] **Cleanup Smoke Test**
  ```sql
  -- Remove test record
  DELETE FROM catalogo_homologado WHERE origen_aseguradora = 'TEST_DEPLOYMENT';
  -- Verify deleted: Should return 0 rows
  SELECT COUNT(*) FROM catalogo_homologado WHERE origen_aseguradora = 'TEST_DEPLOYMENT';
  ```

### Step 4: Production Smoke Test (Optional)

- [ ] **Run with Real Data (10 records)**
  ```sql
  -- If you have a staging table with sample production data:
  SELECT procesar_batch_vehiculos(
    (SELECT jsonb_agg(row_to_json(t))
     FROM (
       SELECT hash_comercial, id_canonico, marca, modelo, anio, transmision,
              version, origen_aseguradora, id_original, version_original,
              activo, string_comercial, string_tecnico
       FROM [staging_table] LIMIT 10
     ) t)
  );
  ```

- [ ] **Production Test Results**
  - [ ] All 10 records processed successfully
  - [ ] No errors in response
  - [ ] Updated records visible in catalog

**Checkpoint**: Task 109 Complete ✓

---

## Task 110: Update n8n Workflows

**Estimated Time**: 60-90 minutes (11 workflows × 5-8 min each)
**Risk Level**: LOW (each insurer isolated, easy rollback)
**Rollback Time**: 2-3 minutes per workflow

**Recommendation**: Update one insurer at a time, test, then proceed to next

### Workflow Update Template

**For each insurer** (MAPFRE → Zurich → HDI → Qualitas → ANA → BX → El Potosi → GNP → Chubb → Atlas → AXA):

#### Insurer 1: MAPFRE

- [ ] **Open Workflow**
  - Navigate to n8n dashboard
  - Open workflow: "ETL - MAPFRE" (or similar name)
  - Note current version number: `_____________`

- [ ] **Locate Code Node**
  - Find "Code" node (usually named "Normalize Data", "Process Records", or "Transform")
  - Click to open code editor

- [ ] **Replace Code**
  - Open file: `src/insurers/mapfre/mapfre-codigo-de-normalizacion.js`
  - Copy entire file contents
  - Paste into n8n Code node (replace existing code)
  - Verify no red error indicators in n8n

- [ ] **Save Workflow**
  - Click "Save" button
  - n8n creates new version automatically
  - Note new version number: `_____________`

- [ ] **Test Workflow**
  - Click "Execute Workflow" button
  - Select "Execute with sample data" (if available)
  - OR: Use "Execute All" with LIMIT 10 in SQL query
  - Monitor execution (watch for green checkmarks on all nodes)

- [ ] **Verify Output**
  - Check Supabase RPC response
  - Verify: All records have valid transmission (AUTO/MANUAL)
  - Verify: Brand consolidation applied (e.g., "BMW BW" → "BMW" if present)
  - Verify: No JavaScript errors
  - Verify: 10/10 records processed successfully

- [ ] **Activate Workflow**
  - Ensure "Active" toggle is ON
  - Verify schedule is correct (if cron-based)

**MAPFRE Status**: ✓ Complete

---

#### Insurer 2: Zurich

- [ ] Open workflow: "ETL - Zurich"
- [ ] Current version: `_____________`
- [ ] Code replaced from: `src/insurers/zurich/zurich-codigo-de-normalizacion.js`
- [ ] New version: `_____________`
- [ ] Test passed: 10/10 records ✓
- [ ] Active: ✓

**Zurich Status**: ✓ Complete

---

#### Insurer 3: HDI

- [ ] Open workflow: "ETL - HDI"
- [ ] Current version: `_____________`
- [ ] Code replaced from: `src/insurers/hdi/hdi-codigo-de-normalizacion.js`
- [ ] New version: `_____________`
- [ ] Test passed: 10/10 records ✓
- [ ] Active: ✓

**HDI Status**: ✓ Complete

---

#### Insurer 4: Qualitas

- [ ] Open workflow: "ETL - Qualitas"
- [ ] Current version: `_____________`
- [ ] Code replaced from: `src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js`
- [ ] New version: `_____________`
- [ ] Test passed: 10/10 records ✓
- [ ] Active: ✓

**Qualitas Status**: ✓ Complete

---

#### Insurer 5: ANA

- [ ] Open workflow: "ETL - ANA"
- [ ] Current version: `_____________`
- [ ] Code replaced from: `src/insurers/ana/ana-codigo-de-normalizacion.js`
- [ ] New version: `_____________`
- [ ] Test passed: 10/10 records ✓
- [ ] Active: ✓

**ANA Status**: ✓ Complete

---

#### Insurer 6: BX

- [ ] Open workflow: "ETL - BX"
- [ ] Current version: `_____________`
- [ ] Code replaced from: `src/insurers/bx/bx-codigo-de-normalizacion.js`
- [ ] New version: `_____________`
- [ ] Test passed: 10/10 records ✓
- [ ] Active: ✓

**BX Status**: ✓ Complete

---

#### Insurer 7: El Potosi

- [ ] Open workflow: "ETL - El Potosi"
- [ ] Current version: `_____________`
- [ ] Code replaced from: `src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js`
- [ ] New version: `_____________`
- [ ] Test passed: 10/10 records ✓
- [ ] Active: ✓

**El Potosi Status**: ✓ Complete

---

#### Insurer 8: GNP

- [ ] Open workflow: "ETL - GNP"
- [ ] Current version: `_____________`
- [ ] Code replaced from: `src/insurers/gnp/gnp-codigo-de-normalizacion.js`
- [ ] New version: `_____________`
- [ ] Test passed: 10/10 records ✓
- [ ] Active: ✓

**GNP Status**: ✓ Complete

---

#### Insurer 9: Chubb

- [ ] Open workflow: "ETL - Chubb"
- [ ] Current version: `_____________`
- [ ] Code replaced from: `src/insurers/chubb/chubb-codigo-de-normalizacion.js`
- [ ] New version: `_____________`
- [ ] Test passed: 10/10 records ✓
- [ ] Active: ✓

**Chubb Status**: ✓ Complete

---

#### Insurer 10: Atlas

- [ ] Open workflow: "ETL - Atlas"
- [ ] Current version: `_____________`
- [ ] Code replaced from: `src/insurers/atlas/atlas-codigo-de-normalizacion.js`
- [ ] New version: `_____________`
- [ ] Test passed: 10/10 records ✓
- [ ] Active: ✓

**Atlas Status**: ✓ Complete

---

#### Insurer 11: AXA

- [ ] Open workflow: "ETL - AXA"
- [ ] Current version: `_____________`
- [ ] Code replaced from: `src/insurers/axa/axa-codigo-de-normalizacion.js`
- [ ] New version: `_____________`
- [ ] Test passed: 10/10 records ✓
- [ ] Active: ✓

**AXA Status**: ✓ Complete

---

### Deployment Summary

- [ ] **All Workflows Updated**: 11/11 ✓
- [ ] **All Tests Passed**: 110/110 records processed successfully
- [ ] **No Errors**: All workflows executing without JavaScript errors
- [ ] **All Active**: All workflows toggled ON

**Checkpoint**: Task 110 Complete ✓

---

## Task 111: Full Data Reprocessing & Validation

**Estimated Time**: 30-60 minutes (depends on data volume)
**Risk Level**: LOW (read-only validation queries)

### Step 1: Trigger Full Reprocessing

**Option A: Manual Execution** (Recommended for controlled deployment)

- [ ] **MAPFRE**: Execute workflow → Monitor completion → Verify no errors
- [ ] **Zurich**: Execute workflow → Monitor completion → Verify no errors
- [ ] **HDI**: Execute workflow → Monitor completion → Verify no errors
- [ ] **Qualitas**: Execute workflow → Monitor completion → Verify no errors
- [ ] **ANA**: Execute workflow → Monitor completion → Verify no errors
- [ ] **BX**: Execute workflow → Monitor completion → Verify no errors
- [ ] **El Potosi**: Execute workflow → Monitor completion → Verify no errors
- [ ] **GNP**: Execute workflow → Monitor completion → Verify no errors
- [ ] **Chubb**: Execute workflow → Monitor completion → Verify no errors
- [ ] **Atlas**: Execute workflow → Monitor completion → Verify no errors
- [ ] **AXA**: Execute workflow → Monitor completion → Verify no errors

**Option B: Scheduled Execution** (Wait for next cron run)

- [ ] Verify all workflows have active schedules
- [ ] Wait for next scheduled execution (check cron settings)
- [ ] Monitor execution history in n8n

### Step 2: Monitor Processing

- [ ] **n8n Execution Logs**
  - Navigate to n8n → Executions tab
  - Verify all 11 workflows show "Success" status
  - Check error logs for any failed nodes

- [ ] **Supabase Logs** (Optional)
  - Navigate to Supabase → Logs → Database
  - Filter for `procesar_batch_vehiculos` function calls
  - Verify no error-level logs

### Step 3: Run Validation Queries

- [ ] **Total Record Count**
  ```sql
  SELECT COUNT(*) AS total_records,
         COUNT(DISTINCT hash_comercial) AS unique_vehicles
  FROM catalogo_homologado;

  -- Expected: total_records ~242,656 (±10%)
  --           unique_vehicles ~45,000-50,000
  ```
  - Result: `_____________` total records
  - Status: ✓ PASS / ❌ FAIL

- [ ] **Transmission Coverage**
  ```sql
  SELECT
    transmision,
    COUNT(*) AS count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
  FROM catalogo_homologado
  GROUP BY transmision
  ORDER BY count DESC;

  -- Expected: AUTO ~65%, MANUAL ~31%, NULL ~4%
  ```
  - AUTO: `_____`% | MANUAL: `_____`% | NULL: `_____`%
  - Status: ✓ PASS (NULL <5%) / ❌ FAIL

- [ ] **Insurer Coverage**
  ```sql
  SELECT
    jsonb_object_keys(disponibilidad) AS insurer,
    COUNT(*) AS record_count
  FROM catalogo_homologado
  GROUP BY insurer
  ORDER BY record_count DESC;

  -- Expected: 11 rows (all insurers)
  ```
  - Insurers found: `_____` / 11
  - Status: ✓ PASS (11/11) / ❌ FAIL

- [ ] **A-SPEC vs TECH Fix Verification**
  ```sql
  SELECT
    hash_comercial,
    version,
    jsonb_object_keys(disponibilidad) AS insurer
  FROM catalogo_homologado
  WHERE marca = 'ACURA'
    AND modelo = 'TLX'
    AND anio = 2021
    AND (version LIKE '%A-SPEC%' OR version LIKE '%TECH%')
  ORDER BY version, insurer;

  -- Expected: A-SPEC and TECH as separate records
  --           Each with only ONE insurer
  ```
  - Separate records: ✓ YES / ❌ NO
  - Single insurer per record: ✓ YES / ❌ NO
  - Status: ✓ PASS / ❌ FAIL

- [ ] **Brand Consolidation Verification**
  ```sql
  SELECT marca, COUNT(*)
  FROM catalogo_homologado
  WHERE marca IN ('BMW BW', 'KIA MOTORS', 'BERCEDES')
  GROUP BY marca;

  -- Expected: 0 rows (all consolidated)
  ```
  - Unconsolidated variants found: `_____`
  - Status: ✓ PASS (0 rows) / ❌ FAIL

### Step 4: Generate Quality Report

- [ ] **Run Quality Report Script**
  ```bash
  cd /mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl
  ./scripts/run_quality_report.sh
  ```

- [ ] **Review Report Output**
  - Location: `reports/quality_report_[TIMESTAMP].md`
  - Size: ~20-30KB
  - Sections: 10 sections present

- [ ] **Verify Key Metrics**
  - [ ] Executive Summary: Total records match expected
  - [ ] Section 2: All 11 insurers listed
  - [ ] Section 3: Transmission >95% valid
  - [ ] Section 4: Top brands are canonical names (BMW, not BMW BW)
  - [ ] Section 10: Final summary shows ✓ Quality Report

**Quality Report Status**: ✓ PASS / ❌ FAIL

**Checkpoint**: Task 111 Complete ✓

---

## Post-Deployment Verification

### All Tasks Complete

- [ ] **Task 109**: SQL function deployed ✓
- [ ] **Task 110**: All 11 n8n workflows updated ✓
- [ ] **Task 111**: Full reprocessing complete ✓

### Final Validation

- [ ] **No Critical Errors**: No errors in n8n execution logs
- [ ] **Data Quality**: Transmission coverage >95%
- [ ] **Algorithm Fix**: A-SPEC vs TECH bug resolved
- [ ] **Brand Consolidation**: No unconsolidated variants
- [ ] **All Insurers Active**: 11/11 insurers processing successfully

### Documentation

- [ ] **Deployment Log Created**
  - Timestamp of deployment
  - SQL function version deployed
  - n8n workflow versions (all 11)
  - Quality report timestamp
  - Any issues encountered

- [ ] **Quality Report Archived**
  - Report saved to: `reports/quality_report_[TIMESTAMP].md`
  - Baseline metrics documented for future comparison

- [ ] **Team Notification**
  - Deployment complete email sent
  - Success metrics shared (95.7% data quality achieved)
  - Monitoring dashboard URL shared

---

## Rollback Procedures (If Needed)

### If Critical Issue Found

**SQL Function Rollback** (5 minutes):
```sql
-- Drop current function
DROP FUNCTION IF EXISTS procesar_batch_vehiculos(JSONB);

-- Restore backup
ALTER FUNCTION procesar_batch_vehiculos_backup(JSONB)
  RENAME TO procesar_batch_vehiculos;
```

**n8n Workflow Rollback** (per workflow, 2-3 minutes):
1. Open workflow in n8n
2. Click "Workflow History" icon
3. Select version from before deployment
4. Click "Restore this version"
5. Save and verify

### Rollback Decision Criteria

**ROLLBACK if**:
- Total records drop >10% after reprocessing
- Transmission coverage falls below 90%
- Critical JavaScript errors in >2 workflows
- Data corruption detected in sample queries

**DO NOT ROLLBACK if**:
- Minor performance degradation (<20% slower)
- Single workflow error (fix that workflow only)
- Cosmetic issues in quality report
- Expected data quality improvements not yet visible (give it time)

---

## Sign-Off

**Deployment Completed By**: `_________________________________`
**Date**: `_____ / _____ / _____`
**Time**: `_____:_____`

**Verification Completed By**: `_________________________________`
**Date**: `_____ / _____ / _____`

**Status**: ✓ SUCCESS / ❌ ROLLBACK REQUIRED

**Notes**:
```
[Add any deployment notes, issues encountered, or follow-up actions needed]




```

---

**END OF CHECKLIST**
