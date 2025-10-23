# n8n Deployment Checklist - Homologation Corrections

**Document Version:** 1.0
**Date:** 2025-10-17
**Phase:** Phase 4 - Deployment (Task 110)
**Deployment Date:** [TO BE FILLED]
**Deployer:** [TO BE FILLED]

---

## Pre-Deployment Checklist

### Prerequisites Verification

- [ ] **Phase 1 Complete:** SQL function deployed successfully (Task 109)
  - [ ] Best-match selection algorithm verified
  - [ ] Smoke test passed (10/10 records)
  - [ ] Backup function created for rollback

- [ ] **Phase 2 Complete:** All normalization code updated (Tasks 5-37C)
  - [ ] MAPFRE: 5 components implemented
  - [ ] Zurich: 5 components implemented
  - [ ] HDI: 5 components implemented
  - [ ] Qualitas: 5 components implemented
  - [ ] ANA: 5 components implemented
  - [ ] BX: 5 components implemented
  - [ ] El Potosí: 5 components implemented
  - [ ] GNP: 5 components implemented
  - [ ] Chubb: 5 components implemented
  - [ ] Atlas: 5 components implemented
  - [ ] AXA: 5 components implemented

- [ ] **Phase 3 Complete:** All validation tests passed (Tasks 104-108)
  - [ ] Brand consolidation tests: PASSED
  - [ ] Transmission recovery tests: PASSED
  - [ ] Performance benchmark: PASSED (batch < 5 min)
  - [ ] Idempotency test: PASSED (no new inserts on re-run)
  - [ ] Data quality report: Generated

- [ ] **Access Verified:**
  - [ ] n8n instance accessible: `https://[n8n-instance].com`
  - [ ] Edit permissions for all workflows confirmed
  - [ ] Database access for validation queries confirmed

- [ ] **Documentation Prepared:**
  - [ ] Deployment guide reviewed: `/docs/n8n-deployment-guide.md`
  - [ ] Per-insurer changes reviewed: `/docs/n8n-per-insurer-changes.md`
  - [ ] Rollback plan understood

- [ ] **Backups Created:**
  - [ ] All 11 workflow JSON files exported
  - [ ] Backup manifest created: `/backups/n8n-workflows/BACKUP_MANIFEST.md`
  - [ ] Backup timestamp recorded: [TIMESTAMP]

- [ ] **Test Data Prepared:**
  - [ ] 10 smoke test cases ready for each insurer
  - [ ] Validation queries prepared in SQL editor

---

## Deployment Execution Tracker

### Deployment Priority Order

**Priority 1 (High Impact) - Deploy First:**

#### 1. MAPFRE
- **Workflow Name:** ETL - MAPFRE
- **Source File:** `/src/insurers/mapfre/mapfre-codigo-de-normalizacion.js`
- **Start Time:** [TIME]
- **Steps:**
  - [ ] Workflow opened in n8n
  - [ ] Code node located: "Normalize Data"
  - [ ] Current code backed up: `backup-mapfre-[timestamp].js`
  - [ ] New code copied from source file
  - [ ] Code pasted into editor
  - [ ] Syntax check: No errors
  - [ ] Workflow saved successfully
  - [ ] Smoke test executed: [PASS/FAIL]
  - [ ] Smoke test results: [X/10 records passed]
  - [ ] Workflow activated: [YES/NO]
- **End Time:** [TIME]
- **Duration:** [MINUTES]
- **Status:** [PENDING/COMPLETE/FAILED]
- **Notes:** [Any issues or observations]

---

#### 2. Qualitas
- **Workflow Name:** ETL - Qualitas
- **Source File:** `/src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js`
- **Start Time:** [TIME]
- **Steps:**
  - [ ] Workflow opened in n8n
  - [ ] Code node located: "Normalize Data"
  - [ ] Current code backed up: `backup-qualitas-[timestamp].js`
  - [ ] New code copied from source file
  - [ ] Code pasted into editor
  - [ ] Syntax check: No errors
  - [ ] Workflow saved successfully
  - [ ] Smoke test executed: [PASS/FAIL]
  - [ ] Smoke test results: [X/10 records passed]
  - [ ] Workflow activated: [YES/NO]
- **End Time:** [TIME]
- **Duration:** [MINUTES]
- **Status:** [PENDING/COMPLETE/FAILED]
- **Notes:** [Any issues or observations]

---

#### 3. Zurich
- **Workflow Name:** ETL - Zurich
- **Source File:** `/src/insurers/zurich/zurich-codigo-de-normalizacion.js`
- **Start Time:** [TIME]
- **Steps:**
  - [ ] Workflow opened in n8n
  - [ ] Code node located: "Normalize Data"
  - [ ] Current code backed up: `backup-zurich-[timestamp].js`
  - [ ] New code copied from source file
  - [ ] Code pasted into editor
  - [ ] Syntax check: No errors
  - [ ] Workflow saved successfully
  - [ ] Smoke test executed: [PASS/FAIL]
  - [ ] Smoke test results: [X/10 records passed]
  - [ ] Workflow activated: [YES/NO]
- **End Time:** [TIME]
- **Duration:** [MINUTES]
- **Status:** [PENDING/COMPLETE/FAILED]
- **Notes:** [Any issues or observations]

---

**Priority 2 (Medium Impact) - Deploy Second:**

#### 4. HDI
- **Workflow Name:** ETL - HDI
- **Source File:** `/src/insurers/hdi/hdi-codigo-de-normalizacion.js`
- **Start Time:** [TIME]
- **Steps:**
  - [ ] Workflow opened in n8n
  - [ ] Code node located: "Normalize Data"
  - [ ] Current code backed up: `backup-hdi-[timestamp].js`
  - [ ] New code copied from source file
  - [ ] Code pasted into editor
  - [ ] Syntax check: No errors
  - [ ] Workflow saved successfully
  - [ ] Smoke test executed: [PASS/FAIL]
  - [ ] Smoke test results: [X/10 records passed]
  - [ ] Workflow activated: [YES/NO]
- **End Time:** [TIME]
- **Duration:** [MINUTES]
- **Status:** [PENDING/COMPLETE/FAILED]
- **Notes:** [Any issues or observations]

---

#### 5. ANA
- **Workflow Name:** ETL - ANA
- **Source File:** `/src/insurers/ana/ana-codigo-de-normalizacion.js`
- **Start Time:** [TIME]
- **Steps:**
  - [ ] Workflow opened in n8n
  - [ ] Code node located: "Normalize Data"
  - [ ] Current code backed up: `backup-ana-[timestamp].js`
  - [ ] New code copied from source file
  - [ ] Code pasted into editor
  - [ ] Syntax check: No errors
  - [ ] Workflow saved successfully
  - [ ] Smoke test executed: [PASS/FAIL]
  - [ ] Smoke test results: [X/10 records passed]
  - [ ] Workflow activated: [YES/NO]
- **End Time:** [TIME]
- **Duration:** [MINUTES]
- **Status:** [PENDING/COMPLETE/FAILED]
- **Notes:** [Any issues or observations]

---

#### 6. BX
- **Workflow Name:** ETL - BX
- **Source File:** `/src/insurers/bx/bx-codigo-de-normalizacion.js`
- **Start Time:** [TIME]
- **Steps:**
  - [ ] Workflow opened in n8n
  - [ ] Code node located: "Normalize Data"
  - [ ] Current code backed up: `backup-bx-[timestamp].js`
  - [ ] New code copied from source file
  - [ ] Code pasted into editor
  - [ ] Syntax check: No errors
  - [ ] Workflow saved successfully
  - [ ] Smoke test executed: [PASS/FAIL]
  - [ ] Smoke test results: [X/10 records passed]
  - [ ] Workflow activated: [YES/NO]
- **End Time:** [TIME]
- **Duration:** [MINUTES]
- **Status:** [PENDING/COMPLETE/FAILED]
- **Notes:** [Any issues or observations]

---

#### 7. GNP
- **Workflow Name:** ETL - GNP
- **Source File:** `/src/insurers/gnp/gnp-codigo-de-normalizacion.js`
- **Start Time:** [TIME]
- **Steps:**
  - [ ] Workflow opened in n8n
  - [ ] Code node located: "Normalize Data"
  - [ ] Current code backed up: `backup-gnp-[timestamp].js`
  - [ ] New code copied from source file
  - [ ] Code pasted into editor
  - [ ] Syntax check: No errors
  - [ ] Workflow saved successfully
  - [ ] Smoke test executed: [PASS/FAIL]
  - [ ] Smoke test results: [X/10 records passed]
  - [ ] Workflow activated: [YES/NO]
- **End Time:** [TIME]
- **Duration:** [MINUTES]
- **Status:** [PENDING/COMPLETE/FAILED]
- **Notes:** [Any issues or observations]

---

**Priority 3 (Standard Impact) - Deploy Last:**

#### 8. Chubb
- **Workflow Name:** ETL - Chubb
- **Source File:** `/src/insurers/chubb/chubb-codigo-de-normalizacion.js`
- **Start Time:** [TIME]
- **Steps:**
  - [ ] Workflow opened in n8n
  - [ ] Code node located: "Normalize Data"
  - [ ] Current code backed up: `backup-chubb-[timestamp].js`
  - [ ] New code copied from source file
  - [ ] Code pasted into editor
  - [ ] Syntax check: No errors
  - [ ] Workflow saved successfully
  - [ ] Smoke test executed: [PASS/FAIL]
  - [ ] Smoke test results: [X/10 records passed]
  - [ ] Workflow activated: [YES/NO]
- **End Time:** [TIME]
- **Duration:** [MINUTES]
- **Status:** [PENDING/COMPLETE/FAILED]
- **Notes:** [Any issues or observations]

---

#### 9. Atlas
- **Workflow Name:** ETL - Atlas
- **Source File:** `/src/insurers/atlas/atlas-codigo-de-normalizacion.js`
- **Start Time:** [TIME]
- **Steps:**
  - [ ] Workflow opened in n8n
  - [ ] Code node located: "Normalize Data"
  - [ ] Current code backed up: `backup-atlas-[timestamp].js`
  - [ ] New code copied from source file
  - [ ] Code pasted into editor
  - [ ] Syntax check: No errors
  - [ ] Workflow saved successfully
  - [ ] Smoke test executed: [PASS/FAIL]
  - [ ] Smoke test results: [X/10 records passed]
  - [ ] Workflow activated: [YES/NO]
- **End Time:** [TIME]
- **Duration:** [MINUTES]
- **Status:** [PENDING/COMPLETE/FAILED]
- **Notes:** [Any issues or observations]

---

#### 10. El Potosí
- **Workflow Name:** ETL - El Potosí
- **Source File:** `/src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js`
- **Start Time:** [TIME]
- **Steps:**
  - [ ] Workflow opened in n8n
  - [ ] Code node located: "Normalize Data"
  - [ ] Current code backed up: `backup-elpotosi-[timestamp].js`
  - [ ] New code copied from source file
  - [ ] Code pasted into editor
  - [ ] Syntax check: No errors
  - [ ] Workflow saved successfully
  - [ ] Smoke test executed: [PASS/FAIL]
  - [ ] Smoke test results: [X/10 records passed]
  - [ ] Workflow activated: [YES/NO]
- **End Time:** [TIME]
- **Duration:** [MINUTES]
- **Status:** [PENDING/COMPLETE/FAILED]
- **Notes:** [Any issues or observations]

---

#### 11. AXA
- **Workflow Name:** ETL - AXA
- **Source File:** `/src/insurers/axa/axa-codigo-de-normalizacion.js`
- **Start Time:** [TIME]
- **Steps:**
  - [ ] Workflow opened in n8n
  - [ ] Code node located: "Normalize Data"
  - [ ] Current code backed up: `backup-axa-[timestamp].js`
  - [ ] New code copied from source file
  - [ ] Code pasted into editor
  - [ ] Syntax check: No errors
  - [ ] Workflow saved successfully
  - [ ] Smoke test executed: [PASS/FAIL]
  - [ ] Smoke test results: [X/10 records passed]
  - [ ] Workflow activated: [YES/NO]
- **End Time:** [TIME]
- **Duration:** [MINUTES]
- **Status:** [PENDING/COMPLETE/FAILED]
- **Notes:** [Any issues or observations]

---

## Deployment Summary

### Overall Statistics
- **Total Workflows:** 11
- **Successfully Deployed:** [COUNT]
- **Failed Deployments:** [COUNT]
- **Total Duration:** [MINUTES]
- **Average Duration per Workflow:** [MINUTES]

### Smoke Test Results
- **Total Test Cases:** 110 (10 per insurer × 11 insurers)
- **Passed:** [COUNT]
- **Failed:** [COUNT]
- **Success Rate:** [PERCENTAGE]%

### Issues Encountered
- [List any issues, errors, or unexpected behavior]

---

## Post-Deployment Validation

### Immediate Validation (Within 1 Hour)

- [ ] **All Workflows Active:**
  ```sql
  -- Check all workflows are processing
  -- (Run in n8n or check execution logs)
  ```

- [ ] **Brand Consolidation Verified:**
  ```sql
  -- Should return 0 rows
  SELECT marca, COUNT(*)
  FROM catalogo_homologado
  WHERE marca IN ('BMW BW', 'BERCEDES', 'KIA MOTORS', 'MERCEDESBENZ')
    AND fecha_actualizacion > NOW() - INTERVAL '1 hour'
  GROUP BY marca;
  ```
  **Result:** [ROWS RETURNED]

- [ ] **Transmission Recovery Verified:**
  ```sql
  -- Should show >95% valid
  SELECT
    origen_aseguradora,
    COUNT(*) AS total,
    ROUND(100.0 * SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) / COUNT(*), 2) AS valid_pct
  FROM catalogo_homologado
  WHERE fecha_actualizacion > NOW() - INTERVAL '1 hour'
  GROUP BY origen_aseguradora;
  ```
  **Result:** [AVERAGE VALID %]

- [ ] **Model Normalization Verified:**
  ```sql
  -- Should return 0 rows
  SELECT modelo, COUNT(*)
  FROM catalogo_homologado
  WHERE modelo ~* '^(NUEVO|NUEVA|NEW)\s'
    AND fecha_actualizacion > NOW() - INTERVAL '1 hour'
  GROUP BY modelo
  LIMIT 10;
  ```
  **Result:** [ROWS RETURNED]

- [ ] **Version Cleaning Verified:**
  ```sql
  -- Should return 0 rows
  SELECT version, COUNT(*)
  FROM catalogo_homologado
  WHERE version ~* '[\\"\\\\]'
    AND fecha_actualizacion > NOW() - INTERVAL '1 hour'
  GROUP BY version
  LIMIT 10;
  ```
  **Result:** [ROWS RETURNED]

- [ ] **Performance Check:**
  ```sql
  -- Check batch processing times
  SELECT
    origen_aseguradora,
    MAX(fecha_actualizacion) - MIN(fecha_actualizacion) AS duration,
    COUNT(*) AS records
  FROM catalogo_homologado
  WHERE fecha_actualizacion > NOW() - INTERVAL '1 hour'
  GROUP BY origen_aseguradora;
  ```
  **Result:** [MAX DURATION]

---

### Extended Validation (Within 24 Hours)

- [ ] **A-SPEC vs TECH Fix Verified:**
  ```sql
  -- Verify best-match selection (A-SPEC and TECH separate)
  SELECT
    hash_comercial,
    version,
    jsonb_object_keys(disponibilidad) AS insurers,
    COUNT(*) AS match_count
  FROM catalogo_homologado
  WHERE marca = 'ACURA'
    AND modelo = 'TLX'
    AND anio = 2021
    AND version ~* '(A-SPEC|TECH)'
  GROUP BY hash_comercial, version
  ORDER BY version;
  ```
  **Result:** [DESCRIPTION]

- [ ] **Data Quality Report Generated:**
  - Report location: `/reports/post_deployment_report_[timestamp].md`
  - Total records processed: [COUNT]
  - Valid transmission %: [PERCENTAGE]
  - Brand consolidation %: [PERCENTAGE]
  - Model normalization %: [PERCENTAGE]
  - Version cleaning %: [PERCENTAGE]

- [ ] **No Critical Errors in Logs:**
  - n8n execution logs reviewed: [YES/NO]
  - Supabase function logs reviewed: [YES/NO]
  - Critical errors found: [COUNT]

---

## Rollback Decision Matrix

### When to Rollback

**Immediate Rollback Required If:**
- [ ] >3 workflows failed deployment (JavaScript syntax errors)
- [ ] Smoke test success rate <70% (>33 failed test cases)
- [ ] Data corruption detected (incorrect hash_comercial generation)
- [ ] Processing time increased >50% (performance regression)
- [ ] Error rate >5% in production processing

**Partial Rollback Considered If:**
- [ ] 1-2 workflows failed deployment (isolate issue, rollback only affected workflows)
- [ ] Smoke test success rate 70-90% (investigate failures, may proceed with caution)
- [ ] Minor data quality issues detected (can be fixed with subsequent deployment)

**Proceed with Monitoring If:**
- [ ] All workflows deployed successfully
- [ ] Smoke test success rate >90%
- [ ] No data corruption detected
- [ ] Processing time within acceptable range (<10% increase)
- [ ] Error rate <2%

### Rollback Execution

**If rollback is required, follow these steps:**

1. **Pause All Workflows:**
   - Navigate to n8n dashboard
   - For each affected workflow, toggle "Active" to OFF

2. **Restore from Backup:**
   - For each workflow requiring rollback:
     - Open workflow
     - Click "Workflow History" → Select pre-deployment version → "Restore"
     - OR: Import from backup file: `backup-[insurer]-[timestamp].json`

3. **Verify Restoration:**
   - Check workflow code matches backup
   - Run smoke test with 5 sample records
   - Confirm no errors

4. **Re-activate Workflows:**
   - Toggle "Active" to ON for each restored workflow

5. **Document Rollback:**
   - Create rollback log: `/rollbacks/ROLLBACK_LOG_[timestamp].md`
   - Include:
     - Rollback reason
     - Workflows affected
     - Restoration timestamp
     - Root cause analysis
     - Remediation plan

6. **Notify Stakeholders:**
   - Send rollback notification email
   - Include: reason, affected systems, timeline for fix

---

## Success Criteria Final Verification

### Deployment Success Checklist

- [ ] **All 11 workflows deployed:** Code updated, no syntax errors
- [ ] **All smoke tests passed:** 110/110 test cases successful
- [ ] **Brand consolidation:** 0 invalid brand variants in new records
- [ ] **Transmission recovery:** >95% valid transmission values
- [ ] **Model normalization:** 0 NUEVO/NUEVA/NEW prefixes
- [ ] **Version cleaning:** 0 escape characters in version strings
- [ ] **Token deduplication:** No duplicate tokens in version arrays
- [ ] **Performance maintained:** Batch processing <5 min for 50k records
- [ ] **A-SPEC bug fixed:** A-SPEC and TECH as separate records

### Final Output

**When all criteria met, record final status:**

```
✓ Deployment: 11/11 n8n workflows updated and tested
  ✓ MAPFRE: Code updated, smoke test passed (10/10)
  ✓ Zurich: Code updated, smoke test passed (10/10)
  ✓ HDI: Code updated, smoke test passed (10/10)
  ✓ Qualitas: Code updated, smoke test passed (10/10)
  ✓ ANA: Code updated, smoke test passed (10/10)
  ✓ BX: Code updated, smoke test passed (10/10)
  ✓ El Potosí: Code updated, smoke test passed (10/10)
  ✓ GNP: Code updated, smoke test passed (10/10)
  ✓ Chubb: Code updated, smoke test passed (10/10)
  ✓ Atlas: Code updated, smoke test passed (10/10)
  ✓ AXA: Code updated, smoke test passed (10/10)

✓ Validation:
  - Brand consolidation: 100% (0 invalid variants)
  - Transmission recovery: 95.7% valid
  - Model normalization: 100% (0 NUEVO/NUEVA/NEW)
  - Version cleaning: 100% (0 escape chars)
  - Performance: Avg 3.2 min per 50k batch
  - A-SPEC bug: FIXED (verified)

Status: DEPLOYMENT SUCCESSFUL
Date: [DATE]
Deployer: [NAME]
```

---

## Sign-Off

**Deployment Completed By:**
- Name: [NAME]
- Date: [DATE]
- Signature: [SIGNATURE]

**Validated By:**
- Name: [NAME]
- Date: [DATE]
- Signature: [SIGNATURE]

**Approved By:**
- Name: [NAME]
- Date: [DATE]
- Signature: [SIGNATURE]

---

**End of Deployment Checklist**
