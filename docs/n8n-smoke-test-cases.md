# n8n Smoke Test Cases - All Insurers

**Document Version:** 1.0
**Date:** 2025-10-17
**Phase:** Phase 4 - Deployment (Task 110)
**Purpose:** Standard test cases for validating all 11 insurer workflows

---

## Test Case Format

Each test case includes:
- **Input:** Raw record from insurer source
- **Expected Output:** Normalized record after all transformations
- **Validation Points:** Specific checks to verify

---

## Universal Test Cases (All Insurers)

These 10 test cases should be run for EVERY insurer workflow to validate the 5 core normalization components.

### Test Case 1: Brand Consolidation - BMW Variant

**Component:** Brand Consolidation (Component 2)

**Input:**
```json
{
  "marca": "BMW BW",
  "modelo": "X5",
  "anio": 2020,
  "transmision": "AUTO",
  "version_original": "XDRIVE 40I 3.0L 340HP"
}
```

**Expected Output:**
```json
{
  "marca": "BMW",
  "modelo": "X5",
  "anio": 2020,
  "transmision": "AUTO",
  "version": "XDRIVE 40I 3.0L 340HP",
  "hash_comercial": "[SHA-256 of BMW|X5|2020|AUTO]"
}
```

**Validation Points:**
- ✓ `marca` changed from "BMW BW" to "BMW"
- ✓ `hash_comercial` uses consolidated "BMW" (not "BMW BW")
- ✓ Record NOT discarded

---

### Test Case 2: Brand Consolidation - Invalid Brand

**Component:** Brand Consolidation (Component 2)

**Input:**
```json
{
  "marca": "AUTOS",
  "modelo": "SEDAN",
  "anio": 2021,
  "transmision": "MANUAL",
  "version_original": "BASE"
}
```

**Expected Output:**
```
Record DISCARDED with error: "INVALID_BRAND"
```

**Validation Points:**
- ✓ Record discarded (not inserted into output)
- ✓ Error logged: "INVALID_BRAND"
- ✓ Error details include original marca value

---

### Test Case 3: Transmission Recovery - Contaminated Field (AUTO)

**Component:** Transmission Recovery (Component 3)

**Input:**
```json
{
  "marca": "VOLKSWAGEN",
  "modelo": "JETTA",
  "anio": 2021,
  "transmision": "GLI DSG",
  "version_original": "GLI DSG 2.0L TURBO"
}
```

**Expected Output:**
```json
{
  "marca": "VOLKSWAGEN",
  "modelo": "JETTA",
  "anio": 2021,
  "transmision": "AUTO",
  "version": "GLI 2.0L TURBO",
  "hash_comercial": "[SHA-256 of VOLKSWAGEN|JETTA|2021|AUTO]"
}
```

**Validation Points:**
- ✓ `transmision` recovered as "AUTO" (from "GLI DSG")
- ✓ "DSG" NOT in final transmission field
- ✓ `hash_comercial` uses "AUTO" (not "GLI DSG")
- ✓ Version cleaned: "DSG" removed

---

### Test Case 4: Transmission Recovery - Contaminated Field (MANUAL)

**Component:** Transmission Recovery (Component 3)

**Input:**
```json
{
  "marca": "HONDA",
  "modelo": "CIVIC",
  "anio": 2022,
  "transmision": "SI MANUAL",
  "version_original": "SI MANUAL 2.0L"
}
```

**Expected Output:**
```json
{
  "marca": "HONDA",
  "modelo": "CIVIC",
  "anio": 2022,
  "transmision": "MANUAL",
  "version": "SI 2.0L",
  "hash_comercial": "[SHA-256 of HONDA|CIVIC|2022|MANUAL]"
}
```

**Validation Points:**
- ✓ `transmision` recovered as "MANUAL" (from "SI MANUAL")
- ✓ "SI" NOT in final transmission field
- ✓ Version cleaned: "MANUAL" removed

---

### Test Case 5: Transmission Recovery - Inference from Version

**Component:** Transmission Recovery (Component 3)

**Input:**
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
```json
{
  "marca": "JEEP",
  "modelo": "COMPASS",
  "anio": 2022,
  "transmision": "AUTO",
  "version": "LATITUDE 2.4L",
  "hash_comercial": "[SHA-256 of JEEP|COMPASS|2022|AUTO]"
}
```

**Validation Points:**
- ✓ `transmision` inferred as "AUTO" (from "TIPTRONIC" in version)
- ✓ "LATITUDE" NOT treated as transmission value
- ✓ "TIPTRONIC" removed from final version
- ✓ `hash_comercial` uses "AUTO"

---

### Test Case 6: Transmission Recovery - Unrecoverable

**Component:** Transmission Recovery (Component 3)

**Input:**
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
```
Record DISCARDED with error: "TRANSMISSION_INFERENCE_FAILED"
```

**Validation Points:**
- ✓ Record discarded (transmission unrecoverable)
- ✓ Error logged: "TRANSMISSION_INFERENCE_FAILED"
- ✓ No AUTO/MANUAL pattern found in either field

---

### Test Case 7: Model Normalization - NUEVO Prefix

**Component:** Enhanced Model Normalization (Component 4)

**Input:**
```json
{
  "marca": "TOYOTA",
  "modelo": "NUEVO CAMRY",
  "anio": 2023,
  "transmision": "AUTO",
  "version_original": "XLE 2.5L"
}
```

**Expected Output:**
```json
{
  "marca": "TOYOTA",
  "modelo": "CAMRY",
  "anio": 2023,
  "transmision": "AUTO",
  "version": "XLE 2.5L",
  "hash_comercial": "[SHA-256 of TOYOTA|CAMRY|2023|AUTO]"
}
```

**Validation Points:**
- ✓ `modelo` changed from "NUEVO CAMRY" to "CAMRY"
- ✓ "NUEVO" prefix removed
- ✓ `hash_comercial` uses "CAMRY" (not "NUEVO CAMRY")

---

### Test Case 8: Version Cleaning - Escape Characters

**Component:** Enhanced Version Cleaning (Component 5)

**Input:**
```json
{
  "marca": "HONDA",
  "modelo": "ACCORD",
  "anio": 2020,
  "transmision": "AUTO",
  "version_original": "\\\"SPORT\\\" 180HP 1.5L"
}
```

**Expected Output:**
```json
{
  "marca": "HONDA",
  "modelo": "ACCORD",
  "anio": 2020,
  "transmision": "AUTO",
  "version": "SPORT 180HP 1.5L",
  "hash_comercial": "[SHA-256 of HONDA|ACCORD|2020|AUTO]"
}
```

**Validation Points:**
- ✓ Escape characters removed: `\"` → (empty)
- ✓ Backslashes removed: `\\` → (empty)
- ✓ Final version clean: "SPORT 180HP 1.5L"

---

### Test Case 9: Version Cleaning - HP+AUT Separation

**Component:** Enhanced Version Cleaning (Component 5)

**Input:**
```json
{
  "marca": "NISSAN",
  "modelo": "SENTRA",
  "anio": 2022,
  "transmision": "AUTO",
  "version_original": "EXCLUSIVE 150HPAUT 1.8L"
}
```

**Expected Output:**
```json
{
  "marca": "NISSAN",
  "modelo": "SENTRA",
  "anio": 2022,
  "transmision": "AUTO",
  "version": "EXCLUSIVE 150HP AUT 1.8L",
  "hash_comercial": "[SHA-256 of NISSAN|SENTRA|2022|AUTO]"
}
```

**Validation Points:**
- ✓ "150HPAUT" separated to "150HP AUT"
- ✓ Space inserted between HP and AUT
- ✓ Final version properly tokenized

---

### Test Case 10: Token Deduplication

**Component:** Intelligent Token Deduplication (Component 6)

**Input:**
```json
{
  "marca": "AUDI",
  "modelo": "A4",
  "anio": 2021,
  "transmision": "AUTO",
  "version_original": "SPORT 2.0L TURBO 4PUERTAS 2.0L SPORT"
}
```

**Expected Output:**
```json
{
  "marca": "AUDI",
  "modelo": "A4",
  "anio": 2021,
  "transmision": "AUTO",
  "version": "SPORT 2.0L TURBO 4PUERTAS",
  "version_tokens_array": ["SPORT", "2.0L", "TURBO", "4PUERTAS"],
  "hash_comercial": "[SHA-256 of AUDI|A4|2021|AUTO]"
}
```

**Validation Points:**
- ✓ "2.0L" appears only ONCE (first occurrence kept)
- ✓ "SPORT" appears only ONCE (first occurrence kept)
- ✓ Different spec types preserved: "2.0L" and "4PUERTAS" both kept
- ✓ `version_tokens_array` has no duplicates

---

## Insurer-Specific Test Cases

### Zurich - MAZDA Prefix Removal (Req 7.3)

**Input:**
```json
{
  "marca": "MAZDA",
  "modelo": "MAZDA CX-5",
  "anio": 2021,
  "transmision": "AUTO",
  "version_original": "TOURING 2.5L"
}
```

**Expected Output:**
```json
{
  "marca": "MAZDA",
  "modelo": "CX-5",
  "anio": 2021,
  "transmision": "AUTO",
  "version": "TOURING 2.5L",
  "hash_comercial": "[SHA-256 of MAZDA|CX-5|2021|AUTO]"
}
```

**Validation Points:**
- ✓ `modelo` changed from "MAZDA CX-5" to "CX-5"
- ✓ "MAZDA" prefix removed (insurer-specific)

---

### HDI - Body Type Move to Version (Req 7.7)

**Input:**
```json
{
  "marca": "HONDA",
  "modelo": "ACCORD SEDAN",
  "anio": 2022,
  "transmision": "AUTO",
  "version_original": "SPORT 1.5L"
}
```

**Expected Output:**
```json
{
  "marca": "HONDA",
  "modelo": "ACCORD",
  "anio": 2022,
  "transmision": "AUTO",
  "version": "SEDAN SPORT 1.5L",
  "hash_comercial": "[SHA-256 of HONDA|ACCORD|2022|AUTO]"
}
```

**Validation Points:**
- ✓ `modelo` changed from "ACCORD SEDAN" to "ACCORD"
- ✓ "SEDAN" moved to version field
- ✓ "SEDAN" appears at start of version

---

### ANA - MA Prefix + CHASIS Removal (Req 7.4)

**Input:**
```json
{
  "marca": "MAZDA",
  "modelo": "MA 3",
  "anio": 2020,
  "transmision": "MANUAL",
  "version_original": "I SPORT"
}
```

**Expected Output:**
```json
{
  "marca": "MAZDA",
  "modelo": "3",
  "anio": 2020,
  "transmision": "MANUAL",
  "version": "I SPORT",
  "hash_comercial": "[SHA-256 of MAZDA|3|2020|MANUAL]"
}
```

**Validation Points:**
- ✓ `modelo` changed from "MA 3" to "3"
- ✓ "MA" prefix removed (ANA-specific)

**Second Test Case - CHASIS:**

**Input:**
```json
{
  "marca": "FORD",
  "modelo": "F-150 CHASIS",
  "anio": 2021,
  "transmision": "AUTO",
  "version_original": "XL 5.0L"
}
```

**Expected Output:**
```json
{
  "marca": "FORD",
  "modelo": "F-150",
  "anio": 2021,
  "transmision": "AUTO",
  "version": "XL 5.0L",
  "hash_comercial": "[SHA-256 of FORD|F-150|2021|AUTO]"
}
```

**Validation Points:**
- ✓ `modelo` changed from "F-150 CHASIS" to "F-150"
- ✓ "CHASIS" removed (ANA-specific)

---

### BX - Brand Removal from Modelo (Req 7.5)

**Input:**
```json
{
  "marca": "BMW",
  "modelo": "BMW X5",
  "anio": 2020,
  "transmision": "AUTO",
  "version_original": "XDRIVE 40I"
}
```

**Expected Output:**
```json
{
  "marca": "BMW",
  "modelo": "X5",
  "anio": 2020,
  "transmision": "AUTO",
  "version": "XDRIVE 40I",
  "hash_comercial": "[SHA-256 of BMW|X5|2020|AUTO]"
}
```

**Validation Points:**
- ✓ `modelo` changed from "BMW X5" to "X5"
- ✓ Brand name removed from modelo (BX-specific)

---

### El Potosí - Mercedes Prefix Cleanup (Req 7.6)

**Input:**
```json
{
  "marca": "MERCEDES BENZ",
  "modelo": "MERCEDES C KLASSE",
  "anio": 2021,
  "transmision": "AUTO",
  "version_original": "C300 2.0L"
}
```

**Expected Output:**
```json
{
  "marca": "MERCEDES BENZ",
  "modelo": "C CLASE",
  "anio": 2021,
  "transmision": "AUTO",
  "version": "C300 2.0L",
  "hash_comercial": "[SHA-256 of MERCEDES BENZ|C CLASE|2021|AUTO]"
}
```

**Validation Points:**
- ✓ `modelo` changed from "MERCEDES C KLASSE" to "C CLASE"
- ✓ "MERCEDES" prefix removed
- ✓ "KLASSE" replaced with "CLASE"

---

### GNP - Marca/Modelo Token Removal from Version (Req 7.8)

**Input:**
```json
{
  "marca": "TOYOTA",
  "modelo": "CAMRY",
  "anio": 2023,
  "transmision": "AUTO",
  "version_original": "TOYOTA CAMRY XLE 2.5L"
}
```

**Expected Output:**
```json
{
  "marca": "TOYOTA",
  "modelo": "CAMRY",
  "anio": 2023,
  "transmision": "AUTO",
  "version": "XLE 2.5L",
  "hash_comercial": "[SHA-256 of TOYOTA|CAMRY|2023|AUTO]"
}
```

**Validation Points:**
- ✓ `version` changed from "TOYOTA CAMRY XLE 2.5L" to "XLE 2.5L"
- ✓ "TOYOTA" removed (marca token)
- ✓ "CAMRY" removed (modelo token)
- ✓ Only unique version tokens remain

---

### Chubb - Liter Separation (Req 7.9)

**Input:**
```json
{
  "marca": "HONDA",
  "modelo": "CR-V",
  "anio": 2022,
  "transmision": "AUTO",
  "version_original": "EX 2.0LAUT TURBO"
}
```

**Expected Output:**
```json
{
  "marca": "HONDA",
  "modelo": "CR-V",
  "anio": 2022,
  "transmision": "AUTO",
  "version": "EX 2.0L AUTO TURBO",
  "hash_comercial": "[SHA-256 of HONDA|CR-V|2022|AUTO]"
}
```

**Validation Points:**
- ✓ `version` changed from "2.0LAUT" to "2.0L AUTO"
- ✓ "L" separated from "AUTO" (Chubb-specific)

---

### Atlas - BMW Model Number Door Fix (Req 7.10)

**Input:**
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
```json
{
  "marca": "BMW",
  "modelo": "3",
  "anio": 2019,
  "transmision": "AUTO",
  "version": "328I 4PUERTAS",
  "hash_comercial": "[SHA-256 of BMW|3|2019|AUTO]"
}
```

**Validation Points:**
- ✓ `modelo` changed from "SERIE 3" to "3"
- ✓ "328I" NOT treated as door count (stays in version)
- ✓ "4PUERTAS" preserved (valid door count)
- ✓ "328PUERTAS" would be REMOVED if present (Atlas-specific)

---

### AXA - A-SPEC Standardization (Req 7.12)

**Input:**
```json
{
  "marca": "ACURA",
  "modelo": "TLX",
  "anio": 2021,
  "transmision": "AUTO",
  "version_original": "A SPEC 2.0L TURBO"
}
```

**Expected Output:**
```json
{
  "marca": "ACURA",
  "modelo": "TLX",
  "anio": 2021,
  "transmision": "AUTO",
  "version": "A-SPEC 2.0L TURBO",
  "hash_comercial": "[SHA-256 of ACURA|TLX|2021|AUTO]"
}
```

**Validation Points:**
- ✓ `version` changed from "A SPEC" to "A-SPEC"
- ✓ Hyphen added for standardization (AXA-specific)
- ✓ Also applies to "TYPE S" → "TYPE-S", "S LINE" → "S-LINE"

---

## Test Execution Procedure

### Step 1: Prepare Test Data

For each insurer workflow, prepare a JSON array with all 10 universal test cases PLUS any insurer-specific test cases:

```json
[
  { /* Test Case 1 */ },
  { /* Test Case 2 */ },
  { /* Test Case 3 */ },
  { /* Test Case 4 */ },
  { /* Test Case 5 */ },
  { /* Test Case 6 */ },
  { /* Test Case 7 */ },
  { /* Test Case 8 */ },
  { /* Test Case 9 */ },
  { /* Test Case 10 */ },
  { /* Insurer-specific test (if applicable) */ }
]
```

### Step 2: Execute Workflow

1. Open workflow in n8n
2. Click "Execute Workflow" button
3. Paste test data JSON array
4. Click "Execute"
5. Wait for execution to complete

### Step 3: Validate Output

For each test case, verify:

1. **Record Status:** Processed or Discarded (as expected)
2. **Field Transformations:** All expected field changes applied
3. **Hash Generation:** `hash_comercial` uses normalized values
4. **Error Logging:** Discarded records have correct error codes
5. **Version Tokens:** `version_tokens_array` deduplicated correctly

### Step 4: Record Results

Use the deployment checklist to record:
- Total test cases: [COUNT]
- Passed: [COUNT]
- Failed: [COUNT]
- Success rate: [PERCENTAGE]%

### Step 5: Investigate Failures

For any failed test cases:
1. Review workflow execution log
2. Check normalization function logic
3. Verify source code matches deployment
4. Document issue in deployment notes
5. Rollback if critical failure

---

## Expected Results Summary

**For All Insurers:**

| Component | Test Cases | Expected Pass Rate |
|-----------|------------|-------------------|
| Brand Consolidation | 2 | 100% |
| Transmission Recovery | 4 | 100% |
| Model Normalization | 1 | 100% |
| Version Cleaning | 2 | 100% |
| Token Deduplication | 1 | 100% |
| **Total Universal** | **10** | **100%** |

**Insurer-Specific:**

| Insurer | Additional Tests | Expected Pass Rate |
|---------|-----------------|-------------------|
| Zurich | 1 (MAZDA prefix) | 100% |
| HDI | 1 (Body type move) | 100% |
| ANA | 2 (MA prefix, CHASIS) | 100% |
| BX | 1 (Brand removal) | 100% |
| El Potosí | 1 (Mercedes cleanup) | 100% |
| GNP | 1 (Token removal) | 100% |
| Chubb | 1 (Liter separation) | 100% |
| Atlas | 1 (BMW doors) | 100% |
| AXA | 1 (A-SPEC format) | 100% |

**Overall Expected:**
- **Total test cases:** 119 (10 universal × 11 insurers + 9 insurer-specific)
- **Expected pass rate:** 100%
- **Acceptable pass rate:** >95% (allowing for minor data variations)

---

**End of Smoke Test Cases Documentation**
