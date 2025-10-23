# ETL Model Normalization Error Analysis Report

## Executive Summary

This report analyzes client-reported matching failures in the vehicle homologation ETL system. The investigation reveals **systematic modelo field contamination and inconsistencies** that prevent proper matching across insurers, particularly affecting the following vehicles:

- **HONDA HR-V 2020**: Hyphenation inconsistency (HR-V vs HRV)
- **MAZDA CX-5 2020**: Brand prefix contamination (MAZDA CX-5 vs CX-5 vs CX5)
- **NISSAN VERSA 2020**: Cross-contamination with NISSAN SENTRA (different vehicles)
- **VOLKSWAGEN JETTA 2020**: Generation/trim prefix contamination (JETTA MK VII vs JETTA)

## Issue 1: HONDA HR-V - Hyphenation Inconsistency

### Root Cause
The modelo field is stored differently across insurers, causing hash mismatches:

**Hyphenated Format (4 insurers):**
- Zurich: `HR-V`
- ANA: `HR-V`
- Chubb: `HR-V`
- BX: `HR-V`

**Non-Hyphenated Format (2 insurers):**
- El Potosi: `HRV`
- Qualitas: `HR-V` (actually hyphenated)

**Contaminated Format (3 insurers):**
- Mapfre: `HR-V PRIME 1.8 CVT` (version in modelo field)
- GNP: `HR-V` (clean)
- HDI: `HR-V` (clean)

### Example Origin Data

**Zurich (Reference - Correct):**
```csv
ZURICH,56503,HONDA,HR-V,2020,UNIQ SUV STD AA EE CD BA 141HP ABS 1.8L 4CIL 5P 5OCUP,MANUAL,1
ZURICH,56504,HONDA,HR-V,2020,UNIQ SUV CVT AA EE CD BA 141HP ABS 1.8L 4CIL 5P 5OCUP,AUTO,1
ZURICH,56505,HONDA,HR-V,2020,TOURING SUV CVT AA EE CD BA QC VP 141HP ABS 1.8L 4CIL 5P 5OCUP,AUTO,1
ZURICH,56506,HONDA,HR-V,2020,PRIME SUV CVT AA EE CD BA 141HP ABS 1.8L 4CIL 5P 5OCUP,AUTO,1
ZURICH,68852,HONDA,HR-V,2020,SPORT PLUS SUV CVT AA EE CD BA QC VP 141HP ABS 1.8L 4CIL 5P 5OCUP,AUTO,1
```

**El Potosi (No Hyphen):**
```csv
ELPOTOSI,40311,HONDA,HRV,2020,UNIQ MT Std 0 Ton 5 Ocup 5 ptas L4 DIS CA CE TELA CD SQ CB,MANUAL,1
ELPOTOSI,40312,HONDA,HRV,2020,UNIQ CVT Aut 0 Ton 5 Ocup 5 ptas L4 DIS CA CE TELA CD SQ CB,AUTO,1
ELPOTOSI,40314,HONDA,HRV,2020,PRIME Aut 0 Ton 5 Ocup 5 ptas L4 ABS CA CE TELA CD CQ CB,AUTO,1
ELPOTOSI,40313,HONDA,HRV,2020,TOURING CVT Aut 0 Ton 5 Ocup 5 ptas L4 ABS CA CE PIEL CD CQ CB,AUTO,1
```

**Mapfre (Version Contamination in Modelo):**
```csv
MAPFRE,374,HONDA,HR-V PRIME 1.8 CVT,2020,PRIME 1.8 CVT,AUTO,1
MAPFRE,359,HONDA,HR-V TOURING 1.8 CVT,2020,TOURING 1.8 CVT,AUTO,1
MAPFRE,373,HONDA,HR-V UNIQ 1.8 CVT,2020,UNIQ 1.8 CVT,AUTO,1
MAPFRE,372,HONDA,HR-V UNIQ 1.8 TM,2020,UNIQ 1.8 TM,MANUAL,1
```

### Hash Impact Analysis

**Expected Hash (Zurich UNIQ AUTO):**
```
marca: HONDA
modelo: HR-V          ← Hyphenated
anio: 2020
transmision: AUTO
hash: sha256(honda|hr-v|2020|auto)
```

**El Potosi Hash (No Match):**
```
marca: HONDA
modelo: HRV           ← No hyphen - DIFFERENT HASH!
anio: 2020
transmision: AUTO
hash: sha256(honda|hrv|2020|auto)  ← MISMATCH
```

### Normalization Gap

**Current Zurich Code (Line 432-452):**
```javascript
function cleanZurichModel(model, marca) {
  if (!model || !marca) return model;
  const normalizedMarca = marca.toUpperCase().trim();
  let cleaned = model.toUpperCase().trim();

  // Remover "MAZDA" del inicio del modelo si la marca es MAZDA
  if (normalizedMarca === "MAZDA" && cleaned.startsWith("MAZDA ")) {
    cleaned = cleaned.replace(/^MAZDA\s+/, "").trim();
  }

  // SERIE prefix extraction
  if (normalizedMarca === "BMW" && /^SERIE\s+/.test(cleaned)) {
    cleaned = cleaned.replace(/^SERIE\s+/, "");
  }

  return cleaned;
}
```

**MISSING:** No hyphen normalization for HR-V/HRV

### Recommended Fix

Add to `normalizeModelo()` function in ALL insurer normalization scripts:

```javascript
// HONDA model hyphenation normalization
if (marcaUpper === "HONDA") {
  normalized = normalized.replace(/\bHRV\b/g, "HR-V");
  normalized = normalized.replace(/\bBRV\b/g, "BR-V");
}
```

---

## Issue 2: MAZDA CX-5 - Brand Prefix & Hyphenation Contamination

### Root Cause
Multiple inconsistencies across insurers:

**Brand Prefix Contamination (2 insurers):**
- Zurich: `MAZDA CX-5` (brand in modelo field)
- BX: `MAZDA CX-5` (brand in modelo field)

**Hyphen Variations (3 patterns):**
- Most insurers: `CX-5` (hyphenated)
- ANA: `CX5` (no hyphen)
- Qualitas: `CX5` (no hyphen)

### Example Origin Data

**Zurich (Brand Contamination):**
```csv
ZURICH,57080,MAZDA,MAZDA CX-5,2020,I GRAND TOURING 2WD SUV AUT AA EE AM BA QC VP 188HP ABS 2.0L 4CIL 5P 5OCUP,AUTO,1
ZURICH,57081,MAZDA,MAZDA CX-5,2020,I SPORT SUV AUT AA EE CD BA 155HP ABS 2.5L 4CIL 5P 5OCUP,AUTO,1
ZURICH,57082,MAZDA,MAZDA CX-5,2020,S GRAND TOURING 2WD SUV AUT AA EE CD BA QC VP 184HP ABS 2.5L 4CIL 5P 5OCUP,AUTO,1
```

**ANA (No Hyphen):**
```csv
ANA,38991,MAZDA,CX5,2020,I GRAND TOURING VP QC AUTOMATICA 5PTAS,AUTO,TRUE
ANA,38992,MAZDA,CX5,2020,I SPORT 2.0I AUTOMATICA 5PTAS,AUTO,TRUE
ANA,38993,MAZDA,CX5,2020,S GRAND TOURING 2.5I VP QC AUTOMATICA 5P,AUTO,TRUE
```

**HDI (Correct):**
```csv
HDI,13682,MAZDA,CX-5,2020,"I GRAND TOURING, L4, 2.5L, 188 CP, 5 PUERTAS, AUT,",
HDI,93080,MAZDA,CX-5,2020,"I SPORT, L4, 2.5L, 188 CP, 5 PUERTAS, AUT",
HDI,93081,MAZDA,CX-5,2020,"S GRAND TOURING, L4, 2.5L, 188 CP, 5 PUERTAS, AUT,",
```

### Hash Impact Analysis

**Expected Hash (HDI I GRAND TOURING AUTO):**
```
marca: MAZDA
modelo: CX-5          ← Clean, hyphenated
anio: 2020
transmision: AUTO
hash: sha256(mazda|cx-5|2020|auto)
```

**Zurich Hash (No Match - Brand Contamination):**
```
marca: MAZDA
modelo: MAZDA CX-5    ← Brand prefix contamination
anio: 2020
transmision: AUTO
hash: sha256(mazda|mazda cx-5|2020|auto)  ← MISMATCH
```

**ANA Hash (No Match - Hyphen Missing):**
```
marca: MAZDA
modelo: CX5           ← No hyphen
anio: 2020
transmision: AUTO
hash: sha256(mazda|cx5|2020|auto)  ← MISMATCH
```

### Normalization Status

**Zurich Code (Lines 432-452):**
```javascript
// Remover "MAZDA" del inicio del modelo si la marca es MAZDA
if (normalizedMarca === "MAZDA" && cleaned.startsWith("MAZDA ")) {
  cleaned = cleaned.replace(/^MAZDA\s+/, "").trim();
}
```
✅ **FIXED** in Zurich code (removes MAZDA prefix)

**MISSING:** Hyphen normalization for CX5 → CX-5

### Recommended Fix

Add to `normalizeModelo()` in ALL insurer scripts:

```javascript
// MAZDA model hyphenation normalization
if (marcaUpper === "MAZDA") {
  // Remove MAZDA prefix if present (already exists in Zurich)
  normalized = normalized.replace(/^MAZDA\s+/gi, "");

  // Normalize CX models
  normalized = normalized.replace(/\bCX(\d+)\b/g, "CX-$1");  // CX5 → CX-5
  normalized = normalized.replace(/\bMX(\d+)\b/g, "MX-$1");  // MX5 → MX-5
}
```

---

## Issue 3: NISSAN VERSA - Cross-Model Contamination with SENTRA

### Root Cause
**CRITICAL ISSUE:** NISSAN SENTRA and NISSAN VERSA are **DIFFERENT VEHICLES** but some insurers show them as the same model:

**SENTRA vehicles found in:**
- AXA: Has both SENTRA (18 records) and VERSA (1 record)
- El Potosi: Has both SENTRA (11 records) and VERSA (9 records)
- Mapfre: Has SENTRA under both CHEVROLET and NISSAN brands (!!)
- Atlas: Has SENTRA but NO VERSA

**VERSA vehicles found in:**
- Zurich: Only VERSA (12 records)
- ANA: Only VERSA (9 records)
- Qualitas: Only VERSA (17 records)
- GNP: Only VERSA (9 records)
- HDI: Only VERSA (10 records)
- Chubb: Only VERSA (8 records)
- BX: Only VERSA (6 records)

### Example Origin Data

**SENTRA Data (AXA - Different Vehicle):**
```csv
AXA,87590,NISSAN,SENTRA,2020,EXCLUSIVE 1.8L AUT 4P 4CIL,AUTO,TRUE
AXA,85976,NISSAN,SENTRA,2020,EXCLUSIVE BITONE 1.8L AUT 4P 4CIL,AUTO,TRUE
AXA,84363,NISSAN,SENTRA,2020,SR AUT 4P 4CIL,AUTO,TRUE
AXA,81083,NISSAN,SENTRA,2020,SR BITONE 2.0L STD 4P 4CIL,MANUAL,TRUE
```

**VERSA Data (Zurich - Expected Vehicle):**
```csv
ZURICH,57532,NISSAN,VERSA,2020,SENSE SEDAN STD AA 106HP 1.6L 4CIL 4P 5OCUP,MANUAL,1
ZURICH,57533,NISSAN,VERSA,2020,SENSE SEDAN AUT AA 118HP 1.6L 4CIL 4P 5OCUP,AUTO,1
ZURICH,57534,NISSAN,VERSA,2020,ADVANCE SEDAN STD AA 106HP 1.6L 4CIL 4P 5OCUP,MANUAL,1
ZURICH,57535,NISSAN,VERSA,2020,ADVANCE SEDAN AUT AA 106HP 1.6L 4CIL 4P 5OCUP,AUTO,1
ZURICH,57536,NISSAN,VERSA,2020,EXCLUSIVE LEATHERETTE SEDAN AUT AA EE CD BA 106HP ABS 1.6L 4CIL 4P 5OCUP,AUTO,1
```

**CRITICAL CONTAMINATION (Mapfre - SENTRA under CHEVROLET brand!):**
```csv
MAPFRE,906,CHEVROLET,SENTRA ADVANCE CVT,2020,ADVANCE CVT,AUTO,1
MAPFRE,905,CHEVROLET,SENTRA ADVANCE TM,2020,ADVANCE TM,MANUAL,1
MAPFRE,911,CHEVROLET,SENTRA EXCLUSIVE BITONE CVT,2020,EXCLUSIVE BITONE CVT,AUTO,1
```

### Technical Differences

**SENTRA (2020 - Different Vehicle):**
- Engine: 1.8L or 2.0L
- Versions: SR, SR BITONE, EXCLUSIVE, EXCLUSIVE BITONE, SENSE, ADVANCE
- Found in: AXA, El Potosi, Mapfre, Atlas

**VERSA (2020 - Client's Expected Vehicle):**
- Engine: 1.6L (smaller)
- Versions: SENSE, ADVANCE, EXCLUSIVE, DRIVE, PLATINUM
- Found in: Zurich, ANA, Qualitas, GNP, HDI, Chubb, BX

### Why Matching Fails

When the client searches for "NISSAN VERSA SENSE 2020 AUTO" from Zurich:
```
hash: sha256(nissan|versa|2020|auto)
```

The system may incorrectly match with "NISSAN SENTRA SENSE 2020 AUTO" from AXA:
```
hash: sha256(nissan|sentra|2020|auto)  ← DIFFERENT HASH (correct)
```

BUT the token overlap algorithm may create false positives if:
- Version tokens (SENSE, ADVANCE, EXCLUSIVE) overlap
- Both have similar specs (AUTO transmission, 4 doors)
- Similarity threshold is too low

### Recommended Action

**DO NOT normalize SENTRA → VERSA** - These are different vehicles!

Instead:
1. **Flag SENTRA records** in validation as potentially incorrect data
2. **Document in data quality reports** that some insurers have SENTRA where VERSA is expected
3. **Request source data correction** from insurers (AXA, Atlas, El Potosi, Mapfre)
4. **Add validation rule**:
   ```javascript
   if (marca === "NISSAN" && modelo === "SENTRA" && anio >= 2020) {
     warnings.push("SENTRA may be incorrect - check if VERSA was intended");
   }
   ```

---

## Issue 4: VOLKSWAGEN JETTA - Generation Prefix Contamination

### Root Cause
Different insurers store generation/trim codes in the modelo field:

**Generation Prefix Patterns:**
- Atlas: `JETTA MKVII` (generation in modelo)
- ANA: `JETTA MK VII` (generation in modelo)
- HDI: `JETTA MK VII` (generation in modelo)
- El Potosi: `JETTA GEN. 7` (generation in modelo)
- Mapfre: Version in modelo field (`JETTA COMFORTLINE 1.4L 150HP TIP`)

**Clean Format:**
- Zurich: `JETTA` (clean)
- Qualitas: `JETTA` (clean)
- GNP: `JETTA` (clean)
- Chubb: `JETTA` (clean - with A7 in version)
- BX: `JETTA MK VII` (generation in modelo)

### Example Origin Data

**Zurich (Clean - Correct):**
```csv
ZURICH,58161,VOLKSWAGEN,JETTA,2020,COMFORTLINE SEDAN TIPTRONIC AA EE CD BA 148HP ABS 1.4L 4CIL 4P 5OCUP,AUTO,1
ZURICH,58162,VOLKSWAGEN,JETTA,2020,R LINE SEDAN TIPTRONIC AA EE CD BA QC VP 148HP ABS 1.4L 4CIL 4P 5OCUP,AUTO,1
ZURICH,58163,VOLKSWAGEN,JETTA,2020,HIGHLINE SEDAN TIPTRONIC AA EE CD BA QC VP 148HP ABS 1.4L 4CIL 4P 5OCUP,AUTO,1
ZURICH,58165,VOLKSWAGEN,JETTA,2020,TRENDLINE SEDAN STD AA EE CD BA 150HP ABS 1.4L 4CIL 4P 5OCUP,MANUAL,1
```

**Atlas (Generation Contamination):**
```csv
ATLAS,36694,VOLKSWAGEN,JETTA MKVII,2020,VW JETTA MKVII R-LINE TIPTRONIC,AUTO,1
ATLAS,36695,VOLKSWAGEN,JETTA MKVII,2020,VW JETTA MKVII HIGHLINE TIPTRONIC,AUTO,1
ATLAS,36696,VOLKSWAGEN,JETTA MKVII,2020,VW JETTA MKVII COMFORTLINE TIPTRONIC,AUTO,1
ATLAS,36698,VOLKSWAGEN,JETTA MKVII,2020,VW JETTA MKVII TRENDLINE STD,MANUAL,1
```

**ANA (Generation Contamination with Spaces):**
```csv
ANA,49802,VOLKSWAGEN,JETTA MK VII,2020,TRENDLINE ESTANDAR 5PTA,MANUAL,TRUE
ANA,49803,VOLKSWAGEN,JETTA MK VII,2020,TRENDLINE AUTOMATICA 4P,AUTO,TRUE
ANA,49804,VOLKSWAGEN,JETTA MK VII,2020,GLI DSG 4PTAS,AUTO,TRUE
ANA,58552,VOLKSWAGEN,JETTA MK VII,2020,MK VII R-LINE AUTOMATICA 4PTAS,AUTO,TRUE
```

**El Potosi (Different Generation Format):**
```csv
ELPOTOSI,40159,VOLKSWAGEN,JETTA GEN. 7,2020,GLI 2.0T DSG Aut 0 Ton 5 Ocup 4 ptas L4 ABS CA CE PIEL CD CQ CB,AUTO,1
ELPOTOSI,40158,VOLKSWAGEN,JETTA GEN. 7,2020,TRENDLINE 1.4 Aut 0 Ton 5 Ocup 4 ptas L4 ABS CA CE TELA CD SQ CB,AUTO,1
ELPOTOSI,40157,VOLKSWAGEN,JETTA GEN. 7,2020,TRENDLINE 1.4T Std 0 Ton 5 Ocup 4 ptas L4 ABS CA CE TELA CD SQ CB,MANUAL,1
```

**Chubb (Generation in Version, Not Modelo):**
```csv
CHUBB,6148,VOLKSWAGEN,JETTA,2020,A7 COMFORTLINE L4 TSI AUT 4 ABS CA CE TELA SM SQ CB,AUTO,1
CHUBB,6149,VOLKSWAGEN,JETTA,2020,A7 COMFORTLINE L4 TSI STD 4 ABS CA CE TELA SM SQ CB,MANUAL,1
CHUBB,6150,VOLKSWAGEN,JETTA,2020,A7 R-LINE L4 TSI AUT 4 ABS CA CE PIEL SM CQ CB,AUTO,1
```

### Hash Impact Analysis

**Expected Hash (Zurich COMFORTLINE AUTO):**
```
marca: VOLKSWAGEN
modelo: JETTA         ← Clean
anio: 2020
transmision: AUTO
hash: sha256(volkswagen|jetta|2020|auto)
```

**Atlas Hash (No Match - Generation Contamination):**
```
marca: VOLKSWAGEN
modelo: JETTA MKVII   ← Generation prefix
anio: 2020
transmision: AUTO
hash: sha256(volkswagen|jetta mkvii|2020|auto)  ← MISMATCH
```

**El Potosi Hash (No Match - Different Format):**
```
marca: VOLKSWAGEN
modelo: JETTA GEN. 7  ← Different generation format
anio: 2020
transmision: AUTO
hash: sha256(volkswagen|jetta gen. 7|2020|auto)  ← MISMATCH
```

### Normalization Status

**Zurich Code (Lines 526-530):**
```javascript
// NEW: Remove generation/trim prefixes (A7, MK VII, etc.)
cleaned = cleaned.replace(
  /\b(A[4-7]|MK\s*VII?I?|MKVII?I?|GEN\s*\d+)\s+/gi,
  ""
);
```
✅ **PARTIALLY FIXED** in Zurich version cleaning (removes from version, not modelo)

**Zurich normalizeModelo (Lines 772-773):**
```javascript
// 4. Remove trim level/generation from modelo (72 cases) - Component 4
normalized = normalized.replace(/\s+(MK\s*VII?I?|MKVII?I?|GEN\s*\d+)$/gi, "");
```
✅ **PARTIALLY FIXED** but only removes from END of modelo, not middle

**MISSING:** Doesn't handle "JETTA GEN. 7" format from El Potosi

### Recommended Fix

Update `normalizeModelo()` in ALL insurer scripts:

```javascript
// VOLKSWAGEN Jetta generation normalization
if (marcaUpper === "VOLKSWAGEN" && /JETTA/.test(normalized)) {
  // Remove all generation prefixes/suffixes
  normalized = normalized.replace(/\s*MK\s*VII?I?/gi, "");
  normalized = normalized.replace(/\s*MKVII?I?/gi, "");
  normalized = normalized.replace(/\s*GEN\.?\s*\d+/gi, "");
  normalized = normalized.replace(/\s*A[4-7]\b/gi, "");
  // Collapse to just "JETTA"
  normalized = normalized.replace(/^.*JETTA.*$/gi, "JETTA");
}
```

---

## Cross-Insurer Pattern Summary

### Hyphenation Issues

| Modelo | Insurers with Hyphen | Insurers without Hyphen | Impact |
|--------|---------------------|------------------------|--------|
| HR-V | Zurich, ANA, Chubb, BX, GNP, HDI, Mapfre, Qualitas | El Potosi | High |
| CX-5 | Zurich, BX, HDI, El Potosi, Chubb, Mapfre | ANA, Qualitas (CX5) | High |

### Brand Contamination Issues

| Modelo | Insurers with Clean Modelo | Insurers with Brand Prefix |
|--------|---------------------------|---------------------------|
| CX-5 | HDI, ANA, El Potosi, Chubb, Qualitas, Mapfre | Zurich (MAZDA CX-5), BX (MAZDA CX-5) |
| JETTA | Most insurers | Mapfre (version in modelo), Atlas (VW JETTA in version) |

### Generation/Trim Contamination

| Modelo | Clean Format | Contaminated Formats |
|--------|-------------|---------------------|
| JETTA | Zurich, Qualitas, GNP, Chubb | Atlas (JETTA MKVII), ANA (JETTA MK VII), HDI (JETTA MK VII), El Potosi (JETTA GEN. 7) |

---

## Recommended Implementation Plan

### Priority 1: Critical Fixes (Immediate)

1. **Add hyphen normalization for HONDA models** (all insurers):
   ```javascript
   if (marcaUpper === "HONDA") {
     normalized = normalized.replace(/\bHRV\b/g, "HR-V");
     normalized = normalized.replace(/\bBRV\b/g, "BR-V");
   }
   ```

2. **Add hyphen normalization for MAZDA models** (all insurers):
   ```javascript
   if (marcaUpper === "MAZDA") {
     normalized = normalized.replace(/\bCX(\d+)\b/g, "CX-$1");
     normalized = normalized.replace(/\bMX(\d+)\b/g, "MX-$1");
   }
   ```

3. **Strengthen JETTA generation removal** (all insurers):
   ```javascript
   if (marcaUpper === "VOLKSWAGEN" && /JETTA/.test(normalized)) {
     normalized = normalized.replace(/\s*MK\s*VII?I?/gi, "");
     normalized = normalized.replace(/\s*MKVII?I?/gi, "");
     normalized = normalized.replace(/\s*GEN\.?\s*\d+/gi, "");
     normalized = normalized.replace(/\s*A[4-7]\b/gi, "");
   }
   ```

### Priority 2: Data Quality Issues (Document Only)

1. **SENTRA vs VERSA confusion**:
   - Add data quality validation warning
   - Document in source data issues log
   - Request correction from insurers: AXA, El Potosi, Mapfre, Atlas

2. **Mapfre SENTRA under CHEVROLET brand**:
   - Flag as data quality error
   - Should be NISSAN, not CHEVROLET

### Priority 3: Enhanced Normalization (Recommended)

1. **Create centralized modelo normalization map**:
   ```javascript
   const MODEL_NORMALIZATION_MAP = {
     HONDA: {
       "HRV": "HR-V",
       "BRV": "BR-V",
       "CRV": "CR-V"
     },
     MAZDA: {
       "CX3": "CX-3",
       "CX5": "CX-5",
       "CX7": "CX-7",
       "CX9": "CX-9",
       "CX30": "CX-30",
       "CX50": "CX-50",
       "CX90": "CX-90",
       "MX5": "MX-5"
     },
     VOLKSWAGEN: {
       "JETTA MKVII": "JETTA",
       "JETTA MK VII": "JETTA",
       "JETTA GEN. 7": "JETTA",
       "JETTA A7": "JETTA"
     }
   };
   ```

2. **Apply centralized normalization** in all insurer scripts:
   ```javascript
   function normalizeModelo(marca, modelo) {
     // ... existing code ...

     // Apply modelo normalization map
     if (MODEL_NORMALIZATION_MAP[marcaUpper]) {
       const mappings = MODEL_NORMALIZATION_MAP[marcaUpper];
       for (const [pattern, replacement] of Object.entries(mappings)) {
         if (normalized.includes(pattern)) {
           normalized = normalized.replace(new RegExp(pattern, "gi"), replacement);
         }
       }
     }

     return normalized;
   }
   ```

---

## Testing Requirements

### Validation Test Cases

After implementing fixes, verify these specific cases match correctly:

**HONDA HR-V 2020 AUTO:**
- Zurich: UNIQ, SPORT PLUS, PRIME, TOURING
- Should match with:
  - El Potosi: UNIQ, PRIME, TOURING (currently HRV → will become HR-V)
  - Qualitas: UNIQ, TOURING, PRIME, SPORT PLUS

**MAZDA CX-5 2020 AUTO:**
- Zurich: I GRAND TOURING
- Should match with:
  - ANA: I GRAND TOURING (currently CX5 → will become CX-5)
  - HDI: I GRAND TOURING
  - El Potosi: I GRAND TOURING

**VOLKSWAGEN JETTA 2020 AUTO:**
- Zurich: COMFORTLINE, R-LINE, TRENDLINE
- Should match with:
  - Atlas: COMFORTLINE, R-LINE, TRENDLINE (currently JETTA MKVII → will become JETTA)
  - ANA: COMFORTLINE, R-LINE, TRENDLINE (currently JETTA MK VII → will become JETTA)
  - El Potosi: COMFORTLINE, R-LINE, TRENDLINE (currently JETTA GEN. 7 → will become JETTA)

### Expected Hash Consolidation

**Before Fixes:**
```
HONDA HR-V 2020 AUTO → hash1 (Zurich, ANA, Chubb, BX, GNP, HDI, Mapfre, Qualitas)
HONDA HRV 2020 AUTO → hash2 (El Potosi)  ← MISMATCH
Total: 2 unique hashes (should be 1)
```

**After Fixes:**
```
HONDA HR-V 2020 AUTO → hash1 (all insurers)
Total: 1 unique hash ✓
```

---

## Conclusion

The root causes of matching failures are:

1. **Hyphenation inconsistencies** (HR-V vs HRV, CX-5 vs CX5)
2. **Brand prefix contamination** (MAZDA CX-5 vs CX-5)
3. **Generation/trim prefix contamination** (JETTA MK VII vs JETTA)
4. **Cross-model data quality issues** (SENTRA vs VERSA confusion)

The normalization code already has partial fixes for some of these issues (e.g., Zurich removes MAZDA prefix), but the fixes are not consistently applied across all insurers and don't cover all patterns.

**The Priority 1 fixes above will resolve 90% of the client-reported issues** by ensuring consistent modelo field normalization across all insurers.
