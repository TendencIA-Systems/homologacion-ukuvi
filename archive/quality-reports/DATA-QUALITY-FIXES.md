# Data Quality Fixes - Implementation Plan

## Overview
This document contains all fixes identified during the data quality analysis of the homologation catalog. The fixes address normalization issues and improve trim-level matching accuracy.

---

## PART 1: NORMALIZATION CODE FIXES

### Issue 1: Remove "0 TON" from El Potosi and Chubb

**Problem**: El Potosi and Chubb are sending "0 TON" and "0TON" to the database (1,731 affected records).

**Files to modify**:
1. `src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js`
2. `src/insurers/chubb/chubb-codigo-de-normalizacion.js`

**Changes**:

#### File 1: `src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js`

**Location**: Find the `normalizeTonCapacity` function (around line 545-550)

**Current code**:
```javascript
function normalizeTonCapacity(value = "") {
  if (!value || typeof value !== "string") return "";
  return value.replace(/\b(\d+(?:\.\d+)?)\s*TON\b/gi, (_, ton) => `${ton}TON`);
}
```

**Replace with**:
```javascript
function normalizeTonCapacity(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b0+(?:\.\d+)?\s*TON(?:ELADAS)?\b/gi, " ")
    .replace(/\bTONELADAS?\b/gi, "TON")
    .replace(/\b(\d+(?:\.\d+)?)\s*TON\b/gi, (_, ton) => `${ton}TON`);
}
```

#### File 2: `src/insurers/chubb/chubb-codigo-de-normalizacion.js`

**Location**: Find the `normalizeTonCapacity` function (around line 244-249)

**Current code**:
```javascript
function normalizeTonCapacity(value = "") {
  if (!value || typeof value !== "string") return "";
  return value.replace(/\b(\d+(?:\.\d+)?)\s*TON\b/gi, (_, ton) => `${ton}TON`);
}
```

**Replace with**:
```javascript
function normalizeTonCapacity(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b0+(?:\.\d+)?\s*TON(?:ELADAS)?\b/gi, " ")
    .replace(/\bTONELADAS?\b/gi, "TON")
    .replace(/\b(\d+(?:\.\d+)?)\s*TON\b/gi, (_, ton) => `${ton}TON`);
}
```

**Impact**: Removes "0 TON", "0.5 TON", "00 TON", etc. from El Potosi and Chubb records.

---

### Issue 2: Add "IMO" to Chubb Dictionary

**Problem**: Chubb records contain "IMO" token (unknown abbreviation) that should be removed.

**File to modify**: `src/insurers/chubb/chubb-codigo-de-normalizacion.js`

**Location**: Find the `irrelevant_comfort_audio` array in the dictionary (around lines 10-80)

**Current code** (partial):
```javascript
const CHUBB_NORMALIZATION_DICTIONARY = {
  irrelevant_comfort_audio: [
    "AA",
    "EE",
    "CD",
    // ... more tokens ...
    "TELA",
    "ASIENTO GIRATORIO",
    // indicadores de transmisión
```

**Add this line** after "ASIENTO GIRATORIO" (before the transmission indicators comment):
```javascript
    "IMO",
```

**Impact**: Removes "IMO" from Chubb records.

---

### Issue 3: Add Wheel Sizes to Qualitas Dictionary

**Problem**: Qualitas records still contain "R16", "R18", etc. (wheel/rim sizes).

**File to modify**: `src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js`

**Location**: Find the `irrelevant_comfort_audio` array (around lines 13-80)

**Current code** (partial):
```javascript
const QUALITAS_NORMALIZATION_DICTIONARY = {
  irrelevant_comfort_audio: [
    "AA",
    "EE",
    "CD",
    // ... more tokens ...
    "CAM TRAS",
    "TBO",
    "STD",
```

**Add these lines** after "CAM TRAS" (before transmission tokens like "STD"):
```javascript
    // Wheel/rim sizes
    "R14",
    "R15",
    "R16",
    "R17",
    "R18",
    "R19",
    "R20",
    "R21",
    "R22",
    "R23",
```

**Impact**: Removes wheel size tokens from Qualitas records.

---

## PART 2: SUPABASE SQL FUNCTION FIXES

### Issue 4: Expand Trim Token List and Elevate to Critical

**Problem**: Current trim tokens have weight 2.0 (high_impact), allowing technical specs to override trim differences. Also, the trim list is incomplete.

**File to modify**: `src/supabase/funcion-multiples-estrategias.sql`

**Location**: Find the `calculate_weighted_coverage` function, specifically the token weight definitions (around lines 487-505)

**Current code**:
```sql
    -- Token weights (now simpler)
    critical_tokens TEXT[] := ARRAY[
        -- Drivetrain conflicts are critical
        'AWD', '4WD', '2WD', 'FWD', 'RWD',
        -- Door count is critical (affects vehicle type)
        '2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS', '7PUERTAS',
        -- Fuel type conflicts
        'DIESEL', 'GASOLINA', 'HIBRIDO', 'ELECTRICO', 'HYBRID', 'ELECTRIC', 'GAS'
    ];

    high_impact_tokens TEXT[] := ARRAY[
        -- Engine specs are important but not critical
        '4CIL', '6CIL', '8CIL', '10CIL', '12CIL', '3CIL',
        'TURBO', 'BITURBO', 'TWIN', 'SUPERCHARGED',
        -- Trim levels
        'PREMIUM', 'LUXURY', 'SPORT', 'LIMITED', 'ELITE'
    ];
```

**Replace with**:
```sql
    -- Token weights (now simpler)
    critical_tokens TEXT[] := ARRAY[
        -- Drivetrain conflicts are critical
        'AWD', '4WD', '2WD', 'FWD', 'RWD',
        -- Door count is critical (affects vehicle type)
        '2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS', '7PUERTAS',
        -- Fuel type conflicts
        'DIESEL', 'GASOLINA', 'HIBRIDO', 'ELECTRICO', 'HYBRID', 'ELECTRIC', 'GAS',
        -- Trim levels are critical (prevent PREMIUM from matching TECH, etc.)
        'PREMIUM', 'LUXURY', 'SPORT', 'LIMITED', 'ELITE', 'EXCLUSIVE',
        'TECH', 'TECHNOLOGY', 'A-SPEC', 'TYPE-S', 'TYPE-R', 'S-LINE',
        'ADVANCE', 'TOURING', 'EX-L', 'LX', 'EX', 'SX', 'SEL', 'SE',
        'BASE', 'COMFORT', 'ELEGANCE', 'TITANIUM', 'PLATINIUM', 'PLATINUM',
        'GT', 'GTI', 'GTS', 'RS', 'AMG', 'M', 'R-LINE', 'R-DESIGN',
        'LARAMIE', 'DENALI', 'REBEL', 'RAPTOR', 'TRD', 'RUBICON',
        'NISMO', 'STI', 'WRX', 'TYPE-F', 'F-SPORT', 'FSPORT',
        'HIGHLINE', 'COMFORTLINE', 'TRENDLINE', 'SPORTLINE',
        'COSMOPOLITAN', 'COSMOPOLITA', 'ESPECIAL', 'SPECIAL', 'EDITION',
        'ANNIVERSARY', 'ANIVERSARIO', 'SIGNATURE', 'RESERVE',
        'PRESTIGE', 'PROGRESSIVE', 'ESSENTIAL', 'EXCELLENCE'
    ];

    high_impact_tokens TEXT[] := ARRAY[
        -- Engine specs are important but not critical
        '4CIL', '6CIL', '8CIL', '10CIL', '12CIL', '3CIL',
        'TURBO', 'BITURBO', 'TWIN', 'SUPERCHARGED'
    ];
```

**Impact**:
- Trim tokens now have weight 5.0 (critical) instead of 2.0 (high_impact)
- Expanded trim list from 5 tokens to 60+ tokens covering all major manufacturers
- Prevents matching PREMIUM with TECH, LUXURY with SPORT, etc.

---

## VERIFICATION STEPS

After applying all fixes:

### 1. Re-run Normalization Workflows in n8n

Execute all 11 insurer workflows to regenerate normalized data with the fixes.

### 2. Re-run Supabase Homologation

The SQL function will automatically use the new critical trim tokens on next batch processing.

### 3. Validation Queries

Run these queries in Supabase to verify improvements:

```sql
-- Check for remaining 0 TON issues
SELECT COUNT(*)
FROM catalogo_homologado
WHERE version LIKE '%0 TON%' OR version LIKE '%0TON%';
-- Expected: 0 (down from 1,731)

-- Check for remaining wheel size tokens in normalized versions
SELECT COUNT(*)
FROM catalogo_homologado
WHERE version ~ '\bR1[4-9]\b|\bR2[0-3]\b';
-- Expected: Significant reduction

-- Check for IMO token in Chubb records
SELECT COUNT(*)
FROM catalogo_homologado
WHERE disponibilidad ? 'CHUBB'
  AND version LIKE '%IMO%';
-- Expected: 0
```

### 4. Spot Check Trim Matching

```sql
-- Find any records where PREMIUM and TECH are matched together
SELECT
    id_vehiculo,
    marca,
    modelo,
    anio,
    version,
    disponibilidad
FROM catalogo_homologado
WHERE version LIKE '%PREMIUM%'
  AND EXISTS (
      SELECT 1
      FROM jsonb_each_text(disponibilidad) d
      WHERE d.value::jsonb->>'version_original' LIKE '%TECH%'
        AND d.value::jsonb->>'version_original' NOT LIKE '%PREMIUM%'
  )
LIMIT 10;
-- Expected: Significant reduction or zero results
```

---

## SUMMARY OF CHANGES

### Normalization Code Changes (3 files):
1. ✅ **elpotosi-codigo-de-normalizacion.js** - Add 0 TON removal to `normalizeTonCapacity`
2. ✅ **chubb-codigo-de-normalizacion.js** - Add 0 TON removal to `normalizeTonCapacity` + Add "IMO" to dictionary
3. ✅ **qualitas-codigo-de-normalizacion-n8n.js** - Add wheel sizes (R14-R23) to dictionary

### SQL Function Changes (1 file):
4. ✅ **funcion-multiples-estrategias.sql** - Move trim tokens to `critical_tokens` array and expand list from 5 to 60+ trims

### Expected Impact:
- **~1,731 records** will have "0 TON" removed
- **~6,289 records** (63% of sampled data) will have cleaner normalized versions
- **~71 trim confusion cases** (0.7% of sampled data) will be prevented from matching
- **No changes to minimal version matching behavior** (intentionally preserved)
- **No changes to threshold values** (intentionally preserved)
- **No changes to core matching algorithm** (only token weights adjusted)

---

## NOTES

1. **Minimal Version Matching**: Intentionally NOT modified. Records like "A-SPEC" from MAPFRE will continue to match both "A-SPEC 4PUERTAS" and "A-SPEC 5PUERTAS" as designed.

2. **Threshold Values**: Intentionally NOT modified. Current values (75% same-insurer, 70% cross-insurer) are working well.

3. **Core Algorithm**: Intentionally NOT modified. Only token categorization (critical vs high_impact) is changed.

4. **Backward Compatibility**: All changes are additive (adding tokens to dictionaries) or weight adjustments. No breaking changes to existing matches.

5. **Testing**: Recommend running on a test subset first, then comparing before/after metrics to validate improvements.

---

## READY TO PROCEED?

Please review this plan and let me know:
1. ✅ Do you approve these changes?
2. ✅ Should I proceed with applying them?
3. ❓ Any modifications to the trim list? (I can add/remove specific trims)
4. ❓ Any other concerns or questions?

Once you confirm, I will apply all changes to the specified files.
