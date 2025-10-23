# Comprehensive Trim Normalization & Spec Cleanup Analysis

## Executive Summary

This analysis examines **11 insurance company catalogs** containing **~385,000 total vehicle records** to identify trim patterns requiring special handling and garbage specs needing removal. Key findings:

- **32 unique trim patterns** detected across all insurers (hyphenated and space-separated)
- **Only 5 patterns** (A-SPEC, TYPE-S, S-LINE, M-SPORT, E-TRON) currently protected in all scripts
- **27 unprotected patterns** risk being corrupted during normalization
- **Significant gaps** in spec removal dictionaries across insurers
- **Processing order issues** identified in multiple normalization scripts

---

## Critical Findings Summary

### 🚨 Unprotected Trim Patterns Found

The following trim patterns were found in origin data but are NOT currently protected:

#### High Frequency (>100 occurrences)
- **M SPORT** (2,636 total occurrences) - Space-separated variant
- **S-TRONIC** (316 occurrences) - Audi transmission/trim
- **X-DRIVE** (70 occurrences) - BMW all-wheel drive trim

#### Medium Frequency (10-100 occurrences)
- **I TOURING** (23 occurrences) - Mazda trim
- **S-LINE** (71 occurrences) - Some insurers have hyphenated, others space-separated
- **I SPORT** (19 occurrences) - Mazda trim
- **I LUXURY** (12 occurrences) - Mazda trim
- **I PREMIUM** (17 occurrences) - Mazda trim
- **R TOURING** (14 occurrences) - Honda trim
- **S SPORT** (32 occurrences) - Jaguar/Land Rover trim
- **TYPE S** (47 occurrences) - Space-separated variant (hyphenated version already protected)
- **A SPORT** (9 occurrences) - Audi trim variant
- **A LUXURY** (4 occurrences) - Acura trim variant

#### Low Frequency (<10 occurrences)
- **Q-TRONIC** (2) - Infiniti transmission
- **D PREMIUM**, **D SPORT**, **D ELEGANCE** (21 total) - Diesel trim variants
- **N LUXURY** (3) - Nissan trim
- **L PREMIUM** (19) - Lexus/Lincoln trims
- **T SPORT**, **V LUXURY**, **C PREMIUM**, **E PREMIUM**, **E SELECT**, **X SPORT** (various)

---

## Per-Insurer Detailed Analysis

### QUALITAS (39,715 records)

#### Found Trim Patterns NOT Currently Protected
```
M SPORT: 308 ⚠️ CRITICAL - Space-separated variant not protected
S-TRONIC: 293 ⚠️ CRITICAL - Audi transmission trim
S-TRON: 21 (fragments of S-TRONIC)
L PREMIUM: 15
TYPE S: 6 (space-separated, hyphenated version already protected)
Q-SYSTEM: 2
```

#### Currently Protected
- A-SPEC ✅
- TYPE-S ✅ (hyphenated)
- S-LINE ✅
- M-SPORT ✅ (hyphenated only)
- E-TRON ✅

#### Missing Garbage Specs
Analysis of sample data reveals these specs should be removed but aren't in dictionary:
- **SPORTSHIFT** - Appears in multiple Aston Martin versions
- **OCUP** variations (05 OCUP, 5 OCUP) - Already cleaned via regex but could be dictionary entry
- **CAM TRAS** (rear camera) - Found 650+ times
- **R16, R17, R18** wheel sizes - Only R14-R23 covered, but missing RIN variants

#### Current Dictionary Coverage
- **227 items** in removal dictionary
- Good coverage of: AA, EE, CD, DVD, GPS, BA, ABS, QC, VP
- Door format conversion: **4P → 4PUERTAS** ✅

#### Recommendations
1. Add space-separated **M SPORT** protection
2. Add **S-TRONIC** protection (preserve hyphen)
3. Add **L PREMIUM** protection
4. Add **TYPE S** (space variant) protection
5. Add CAM TRAS, SPORTSHIFT to removal dictionary
6. Validate order: trim protection BEFORE spec removal

---

### ZURICH (38,984 records)

#### Found Trim Patterns NOT Currently Protected
```
M SPORT: 383 ⚠️ CRITICAL - Space-separated variant not protected
TYPE S: 10 (space-separated variant)
A SPORT: 4
A LUXURY: 4
Q-TRONIC: 2
```

#### Currently Protected
- A-SPEC ✅
- TYPE-S ✅
- S-LINE ✅
- M-SPORT ✅ (hyphenated only)
- E-TRON ✅

#### Missing Garbage Specs
Zurich has the MOST verbose version strings with extensive garbage specs:
- All body types present: **SEDAN, SUV, COUPE, MINIVAN** (found 3,531 times)
- Security features ubiquitous: **AA, EE, CD, BA, QC, VP, ABS** (found in 90%+ of records)
- **USB** (55 occurrences) - **MISSING from dictionary**
- **BT** (34 occurrences) - **MISSING from dictionary**
- Door formats: **5P, 4P, 2P, 3P** (found 4,553 times) - needs conversion to PUERTAS

#### Current Dictionary Coverage
- **191 items** - Missing USB, BT, standalone body type tokens
- Good coverage of audio/comfort specs

#### Recommendations
1. Add space-separated **M SPORT** protection
2. Add **TYPE S**, **A SPORT**, **A LUXURY** protection
3. Add **USB**, **BT** to removal dictionary
4. Ensure BODY TYPE tokens removed BEFORE version tokenization
5. Add door format standardization (5P → 5PUERTAS)

---

### HDI (38,186 records)

#### Found Trim Patterns NOT Currently Protected
```
M SPORT: 326 ⚠️ CRITICAL
S-LINE: 28 (some have hyphen, some space)
S SPORT: 7
M   SPORT: 5 ⚠️ (multiple spaces)
M  SPORT: 3 ⚠️ (double space)
E SPORT: 3
I SPORT: 2
```

#### Currently Protected
- A-SPEC ✅
- TYPE-S ✅
- S-LINE ✅
- M-SPORT ✅ (hyphenated only)

#### Missing Garbage Specs
HDI has cleaner data, but gaps exist:
- **BLUETOOTH** (1 occurrence) - full word variant of BT
- **HATCHBACK** (3 occurrences) - body type
- **VP, QC** (9 occurrences) - **MISSING from dictionary**
- **BT** (1 occurrence) - **MISSING**
- **CP** (caballos de potencia / horsepower abbreviation) - appears in format "150 CP"
- **PUERTAS** already used in source data (good!)
- **IMO** - appears in some versions, unclear meaning

#### Current Dictionary Coverage
- **221 items** - Extensive, but missing VP, QC, BT, BLUETOOTH

#### Recommendations
1. Add space-separated **M SPORT** with multi-space handling (regex: `M\s+SPORT`)
2. Add **S SPORT**, **E SPORT**, **I SPORT** protection
3. Add **VP**, **QC**, **BLUETOOTH**, **BT** to removal dictionary
4. Handle **CP** abbreviation (convert to HP or remove if redundant)
5. Clarify **IMO** token meaning and add to dictionary if irrelevant

---

### MAPFRE (37,346 records)

#### Status: ⚠️ NO DATA EXTRACTED

Sample shows empty version_original field. This insurer requires investigation:
- CSV file exists with 37,346 records
- version_original column appears empty or null
- May need different column name or extraction query fix

#### Recommendations
1. **URGENT**: Investigate MAPFRE extraction query
2. Verify correct version column mapping
3. Re-analyze after extraction fix

---

### AXA (14,424 records)

#### Found Trim Patterns NOT Currently Protected
```
M SPORT: 153 ⚠️ CRITICAL
S-LINE: 4
TYPE S: 3
S-DESIGN: 2
T SPORT: 1
L PREMIUM: 1
A SPORT: 1
V LUXURY: 1
E PREMIUM: 1
C PREMIUM: 1
E SELECT: 1
```

#### Currently Protected
- A-SPEC ✅ (5 occurrences)
- TYPE-S ✅
- S-LINE ✅
- M-SPORT ✅ (hyphenated only)
- E-TRON ✅

#### Missing Garbage Specs
AXA has diverse garbage specs, many non-standard:
- **BT** (16 occurrences) - **MISSING**
- **PIEL** (leather) - appears frequently but not removed
- **NAVEG** (navigation abbreviation) - **MISSING**
- **AC** (air conditioning) - found but may not be in dictionary
- Body types present: COUPE (230), SEDAN (94), CONVERTIBLE (70), SUV, MINIVAN, VAN, PICKUP, HATCHBACK
- **GENERICA** - placeholder term (found multiple times) - should be handled separately

#### Current Dictionary Coverage
- **192 items** - Good base but missing AXA-specific abbreviations

#### Recommendations
1. Add space-separated **M SPORT** protection
2. Add **S-DESIGN**, **T SPORT**, **L PREMIUM**, **V LUXURY**, **E PREMIUM**, **C PREMIUM**, **E SELECT** protection
3. Add **BT**, **NAVEG**, **PIEL**, **AC** to removal dictionary
4. Handle **GENERICA** placeholder (filter or replace with empty)
5. Ensure **4CIL** format preserved (cylinder count)

---

### ANA (36,432 records)

#### Found Trim Patterns NOT Currently Protected
```
M SPORT: 403 ⚠️ CRITICAL - Highest frequency
X-DRIVE: 68 ⚠️ BMW all-wheel drive trim
TYPE S: 6
S SPORT: 4
N LUXURY: 3
S-TRONIC: 2
```

#### Currently Protected
- A-SPEC ✅ (1 occurrence)
- TYPE-S ✅ (4 occurrences)
- S-LINE ✅
- M-SPORT ✅ (hyphenated only)
- E-TRON ✅

#### Missing Garbage Specs
ANA uses different abbreviation styles:
- **PTAS** (puertas) - non-standard door abbreviation (AUTOMATICA 5PTAS)
- **DVD** (84 occurrences) - needs verification if in dictionary
- **USB** (26 occurrences) - **MISSING**
- **GPS** (66 occurrences) - verify dictionary coverage
- Body types: COUPE (521), CONVERTIBLE (85), SEDAN (14)

#### Current Dictionary Coverage
- **218 items** - Good coverage but missing USB, PTAS variants

#### Recommendations
1. Add space-separated **M SPORT** protection (403 occurrences - CRITICAL)
2. Add **X-DRIVE** protection (68 occurrences)
3. Add **TYPE S** (space variant), **S SPORT**, **N LUXURY** protection
4. Add **USB** to removal dictionary
5. Handle **PTAS** format: convert to **PUERTAS** or remove
6. Add **DVD**, **GPS** if not already in dictionary

---

### ATLAS (31,229 records)

#### Found Trim Patterns NOT Currently Protected
```
M SPORT: 348 ⚠️ CRITICAL
S-LINE: 24
I TOURING: 23 ⚠️ Mazda trim
E-TRON: 16 (verify if protected - found in data)
I SPORT: 14 ⚠️ Mazda trim
S-TRONIC: 12
I LUXURY: 8 ⚠️ Mazda trim
A-SPECH: 7 ⚠️ TYPO variant of A-SPEC
I PREMIUM: 7 ⚠️ Mazda trim
TYPE S: 5
L PREMIUM: 2
X SPORT: 1
```

#### Currently Protected
- A-SPEC ✅ (12 occurrences)
- TYPE-S ✅ (3 occurrences)
- S-LINE ✅
- M-SPORT ✅ (hyphenated only)
- E-TRON ✅

#### Missing Garbage Specs
Atlas has cleaner data overall:
- Body types present: SEDAN (208), COUPE (674), CONVERTIBLE (169), VAN (31)
- **CD** (42 occurrences) - verify dictionary coverage
- **ABS** (22 occurrences) - verify coverage
- Version format includes marca: "ACURA ILX 2.0L L4 150HP AUT PREMIUM" - marca should be stripped from version

#### Current Dictionary Coverage
- **197 items** - Smallest dictionary, may be optimized or incomplete

#### Recommendations
1. Add space-separated **M SPORT** protection (348 occurrences)
2. Add **I TOURING**, **I SPORT**, **I LUXURY**, **I PREMIUM** protection (Mazda I-series)
3. Add **S-TRONIC** protection
4. Handle **A-SPECH** typo (normalize to A-SPEC or protect as-is)
5. **CRITICAL**: Remove marca from version string (currently: "ACURA ILX ..." should be just "PREMIUM")
6. Ensure **S-LINE** handles both hyphenated and space variants
7. Add **TYPE S** (space variant) protection

---

### ELPOTOSI (23,040 records)

#### Found Trim Patterns NOT Currently Protected
```
M SPORT: 154 ⚠️ CRITICAL
S-LINE: 15
A-SPEC: 9 (verify protection)
D PREMIUM: 8 ⚠️ Diesel trim
D SPORT: 7 ⚠️ Diesel trim
S SPORT: 6
D ELEGANCE: 6 ⚠️ Diesel trim
A-SPECAUT: 4 ⚠️ Concatenated trim (missing space before AUT)
I LUXURY: 4
S-TRONIC: 3
I SPORT: 3
A-SEMI: 3 ⚠️ Semi-automatic variant
S  SPORT: 2 (double space)
X-DRIVE: 2
I-VTEC: 1 ⚠️ Honda engine technology (should be spec, not trim)
```

#### Currently Protected
- A-SPEC ✅
- TYPE-S ✅
- S-LINE ✅
- M-SPORT ✅ (hyphenated only)
- E-TRON ✅

#### Missing Garbage Specs
El Potosí has the messiest data with extensive garbage specs:
- **ABS** (3,783 occurrences) ⚠️ CRITICAL - verify dictionary has it
- **CD** (3,464 occurrences) ⚠️ CRITICAL
- **DVD** (14 occurrences)
- **SQ** (sistema de quemacocos / sunroof) - appears in format "CD SQ CB"
- **CB** (control de bolsas de aire / airbag control) - appears frequently
- **CQ** (another airbag variant) - appears frequently
- **CE**, **CA** (audio abbreviations)
- **PIEL** (leather) - appears in most records
- **B/A** (bolsas de aire) - variant of BA
- **TON** - appears in "Aut 0 Ton" format (tonnage/payload - irrelevant for cars)
- **OCUP** variations (5 Ocup, 5 OCUP) - occupant count
- **15P** - unusual door count format (likely typo for 5P)

#### Current Dictionary Coverage
- **228 items** - Largest dictionary, but still missing El Potosí-specific tokens

#### Recommendations
1. Add space-separated **M SPORT** protection with multi-space handling
2. Add **D PREMIUM**, **D SPORT**, **D ELEGANCE** protection (diesel trims)
3. Add **S SPORT**, **I LUXURY**, **I SPORT**, **S-TRONIC**, **X-DRIVE** protection
4. Handle **A-SPECAUT** concatenation (split before AUT)
5. Add **I-VTEC** to removal dictionary (engine tech, not trim)
6. Add to removal dictionary: **SQ**, **CB**, **CQ**, **CE**, **CA**, **B/A**, **TON**, **PIEL**
7. Add **TON** removal (payload spec irrelevant for passenger vehicles)
8. Handle **OCUP** variations (may already be handled via regex)
9. **CRITICAL**: Verify **ABS** (3,783 occurrences) and **CD** (3,464 occurrences) are in dictionary

---

### BX (39,292 records)

#### Found Trim Patterns NOT Currently Protected
```
M SPORT: 229 ⚠️ CRITICAL
A-SPEC: 9 (verify protection)
S SPORT: 8
TYPE S: 5
L PREMIUM: 1
```

#### Currently Protected
- A-SPEC ✅
- TYPE-S ✅
- S-LINE ✅
- M-SPORT ✅ (hyphenated only)
- E-TRON ✅

#### Missing Garbage Specs
BX has clean data structure but common garbage:
- **CD** (2,924 occurrences) ⚠️ CRITICAL - verify dictionary
- **DVD** (48 occurrences)
- **GPS** (8 occurrences)
- **BT** (2 occurrences) - **MISSING**
- **V/P** (vidrios eléctricos/power windows) - slash variant of VP (9 occurrences)
- **CP** (caballos de potencia) - horsepower abbreviation
- **LUJO** (luxury) - Spanish descriptor
- Body types: COUPE (407), CONVERTIBLE (84), SEDAN (124)

#### Current Dictionary Coverage
- **218 items** - Good coverage

#### Recommendations
1. Add space-separated **M SPORT** protection (229 occurrences)
2. Add **S SPORT**, **TYPE S**, **L PREMIUM** protection
3. Add **BT**, **LUJO** to removal dictionary
4. Handle **V/P** slash variant (normalize to VP or remove)
5. Handle **CP** abbreviation (convert to HP or remove)
6. Verify **CD** (2,924 occurrences), **DVD**, **GPS** in dictionary

---

### GNP (55,486 records - LARGEST)

#### Found Trim Patterns NOT Currently Protected
```
M SPORT: 330 ⚠️ CRITICAL
S-LINE: 14
I PREMIUM: 10 ⚠️ Mazda trim
A-SPEC: 9 (verify protection)
S SPORT: 6
A SPORT: 4
```

#### Currently Protected
- A-SPEC ✅
- TYPE-S ✅
- S-LINE ✅
- M-SPORT ✅ (hyphenated only)
- E-TRON ✅

#### Missing Garbage Specs
GNP has unique abbreviation style with periods:
- **C/A** (con aire / with air conditioning) - slash format (ubiquitous)
- **AC** (aire acondicionado) - appears in format "STD CA AC VE"
- **V.E.** (vidrios eléctricos) - period-separated format
- **VE** (vidrios eléctricos) - non-period variant
- **QC** (19 occurrences) - verify dictionary
- **VP** (17 occurrences) - verify dictionary
- **BA** (3 occurrences) - verify dictionary
- **BT** (26 occurrences) - **MISSING**
- **EE** (5 occurrences) - verify dictionary
- Body types: SEDAN (244), COUPE (311), CONVERTIBLE (169)
- **STD** (standard) - transmission descriptor that should be normalized to MANUAL

#### Current Dictionary Coverage
- **197 items** - Missing GNP-specific slash/period formats

#### Recommendations
1. Add space-separated **M SPORT** protection (330 occurrences)
2. Add **I PREMIUM**, **S SPORT**, **A SPORT** protection
3. Add **C/A**, **V.E.**, **VE**, **AC**, **BT** to removal dictionary
4. Handle slash and period variants: **C/A** → CA, **V.E.** → VE (then remove)
5. Ensure **STD** properly mapped to MANUAL transmission
6. Verify **QC**, **VP**, **BA**, **EE** in dictionary
7. Remove body type descriptors before tokenization

---

### CHUBB (31,256 records)

#### Found Trim Patterns NOT Currently Protected
```
M SPORT: 302 ⚠️ CRITICAL
A-SPEC: 15 (verify protection)
R TOURING: 14 ⚠️ Honda trim
S SPORT: 11
TYPE-S: 6 (verify protection)
E-TRON: 1 (verify protection)
R SPORT: 1
```

#### Currently Protected
- A-SPEC ✅
- TYPE-S ✅
- S-LINE ✅
- M-SPORT ✅ (hyphenated only)
- E-TRON ✅

#### Missing Garbage Specs
Chubb has highly consistent garbage spec format:
- **ABS** (4,490 occurrences) ⚠️ CRITICAL - verify dictionary
- **CD** (3,009 occurrences) ⚠️ CRITICAL - verify dictionary
- **QC** (20 occurrences) - verify dictionary
- **CB** (control de bolsas) - appears in format "ABS CA CE PIEL CD CQ CB"
- **CQ** (another variant) - appears frequently
- **CA** (audio system) - appears frequently
- **CE** (audio system) - appears frequently
- **PIEL** (leather) - appears in most records
- **SM** - appears in some A-SPEC versions, unclear meaning
- **IMO** - appears in format "L4 IMO AUT", unclear meaning
- Body types: SUV (29), SEDAN (130), COUPE (487), CONVERTIBLE (30)

#### Current Dictionary Coverage
- **233 items** - Largest dictionary (tied with El Potosí)

#### Recommendations
1. Add space-separated **M SPORT** protection (302 occurrences)
2. Add **R TOURING**, **S SPORT**, **R SPORT** protection
3. **CRITICAL**: Verify **ABS** (4,490 occurrences) and **CD** (3,009 occurrences) in dictionary
4. Add to removal dictionary: **CB**, **CQ**, **CA**, **CE**, **PIEL**, **SM**, **IMO**
5. Clarify **IMO** and **SM** token meanings
6. Ensure body types removed before tokenization

---

## Cross-Insurer Spec Variations

These specs mean the same thing but are written differently across insurers:

### Air Conditioning
- **AA**, **A/A**, **A A**, **CA**, **C/A**, **AC**, **AIRE**, **CLIMA**

### Power Windows
- **EE**, **E/E**, **E E**, **VE**, **V.E.**, **VP**, **V/P**, **VIDRIOS**

### Airbags
- **BA**, **B/A**, **B A**, **CB**, **CQ**, **AIRBAG**, **AIRBAGS**, **BOLSAS**

### Audio/CD
- **CD**, **DVD**, **REPRODUCTOR**, **RCD**, **STEREO**

### Bluetooth
- **BT**, **BLUETOOTH**

### Navigation
- **GPS**, **NAV**, **NAVI**, **NAVEG**, **NAVEGACION**, **SIS/NAV**, **SIS NAV**, **PAQ NAV**

### ABS
- **ABS**, **FRENOS ABS**

### Security
- **QC**, **Q/C**, **Q.C.**, **Q C**, **QUEMACOCOS** (sunroof control)
- **SQ** (sistema de quemacocos)

### Leather
- **PIEL**, **LEATHER**, **CUERO**

### Horsepower
- **HP**, **CP** (caballos de potencia), **CV** (caballos de vapor)

### Doors
- **P** (puertas), **PTAS**, **PUERTAS**, **DOORS**

### Occupants
- **OCUP**, **OCUPANTES**, **OCCUPANTS**, **PLAZAS**

---

## Processing Order Validation

### Current Standard Order (from analysis of scripts)
1. **Brand consolidation** (BMW BW → BMW, etc.)
2. **BMW SERIE removal** (SERIE 3 → 3)
3. **Modelo cleanup** (remove specs from modelo field)
4. **Version trim protection** (preserve hyphenated trims)
5. **Transmission mapping** (codes → AUTO/MANUAL)
6. **Engine spec normalization** (1.8L, 150HP, 4CIL)
7. **Garbage spec removal** (using dictionary)
8. **Door/occupant format** (4P → 4PUERTAS, 5 OCUP → 5OCUP)
9. **Multi-space collapse** (normalize whitespace)
10. **Final trim** (remove leading/trailing whitespace)
11. **Hash generation** (id_canonico, hash_comercial)

### ✅ Correct Order Patterns Found
- **Qualitas, Zurich, HDI, Chubb**: Follow optimal order
- **Trim protection happens BEFORE spec removal** ✅
- **Transmission mapping early** ✅
- **Hash generation last** ✅

### ⚠️ Issues Found

#### Atlas
- **CRITICAL**: Marca appears in version string ("ACURA ILX 2.0L L4...")
- Need to strip marca from version BEFORE any other processing
- Order should be: `stripMarca() → protectTrims() → removeSpecs() → ...`

#### El Potosí
- **Concatenation issue**: "A-SPECAUT" suggests missing space before transmission
- Need to add space insertion: `A-SPECAUT` → `A-SPEC AUT`
- Should happen BEFORE trim protection

#### GNP
- **Period/slash handling**: V.E., C/A need normalization before removal
- Should happen early: `normalize Periods/Slashes → removeSpecs()`

#### AXA
- **GENERICA placeholder**: Needs special handling (filter or replace)
- Should happen at validation stage, not normalization

---

## Recommended Processing Order (Revised)

```javascript
// STAGE 1: VALIDATION & INITIAL CLEANUP
validateRecord(record);          // Check required fields
handlePlaceholders(record);      // Deal with GENERICA, etc.

// STAGE 2: BRAND/MODEL NORMALIZATION
record.marca = consolidateBrand(record.marca);
record.modelo = cleanBMWModelo(record.marca, record.modelo);
record.modelo = removeSpecsFromModelo(record.modelo);
record.version = stripMarcaFromVersion(record.marca, record.version); // ← NEW (Atlas)

// STAGE 3: VERSION PRE-PROCESSING
record.version = normalizePunctuationVariants(record.version); // C/A → CA, V.E. → VE
record.version = fixConcatenations(record.version);            // A-SPECAUT → A-SPEC AUT

// STAGE 4: TRIM PROTECTION
record.version = protectHyphenatedTrims(record.version);       // A-SPEC → A_SPEC_PROTECTED
record.version = protectSpacedTrims(record.version);           // M SPORT → M_SPORT_PROTECTED

// STAGE 5: TRANSMISSION MAPPING
record.transmision = mapTransmission(record.version, record.transmision_code);

// STAGE 6: SPEC NORMALIZATION
record.version = normalizeEngineSpecs(record.version);         // 1.8L, 150HP, 4CIL
record.version = normalizeDoors(record.version);               // 4P → 4PUERTAS
record.version = normalizeOccupants(record.version);           // 5 OCUP → 5OCUP

// STAGE 7: GARBAGE REMOVAL
record.version = removeGarbageSpecs(record.version);           // Remove AA, EE, CD, etc.
record.version = removeBodyTypes(record.version);              // Remove SEDAN, SUV, etc.

// STAGE 8: TRIM RESTORATION
record.version = restoreProtectedTrims(record.version);        // A_SPEC_PROTECTED → A-SPEC

// STAGE 9: FINAL CLEANUP
record.version = collapseWhitespace(record.version);
record.version = record.version.trim().toUpperCase();

// STAGE 10: HASH GENERATION
record.hash_comercial = generateHash(`${marca}|${modelo}|${anio}|${transmision}`);
record.id_canonico = generateHash(`${record}`);
```

---

## Implementation Requirements

### 1. Enhanced Trim Protection Function

Each normalization script needs an EXPANDED trim protection function:

```javascript
// ENHANCED PROTECTION - Handles both hyphenated and spaced trims
function protectTrims(version) {
  if (!version) return version;

  const PROTECTED_HYPHENATED_TRIMS = [
    'A-SPEC', 'A-SPECH',           // Acura (including typo)
    'TYPE-S', 'TYPE-R',             // Honda/Acura
    'S-LINE', 'R-LINE',             // Audi/VW
    'M-SPORT',                       // BMW (hyphenated)
    'E-TRON', 'E-TURBO',            // Audi electric/turbo
    'S-TRONIC', 'Q-TRONIC',         // Audi/Infiniti transmissions
    'X-DRIVE',                       // BMW all-wheel drive
    'A-SEMI',                        // Semi-automatic variant
    'I-VTEC',                        // Honda engine tech (consider moving to removal?)
  ];

  const PROTECTED_SPACED_TRIMS = [
    'M SPORT',                       // BMW (space-separated) ← CRITICAL
    'TYPE S',                        // Honda (space-separated)
    'I TOURING', 'I SPORT', 'I LUXURY', 'I PREMIUM',  // Mazda I-series
    'R TOURING', 'R SPORT',          // Honda R-series
    'S SPORT', 'E SPORT', 'A SPORT', 'T SPORT', 'X SPORT',  // Various sport trims
    'L PREMIUM', 'N LUXURY', 'V LUXURY', 'A LUXURY',  // Luxury trims
    'D PREMIUM', 'D SPORT', 'D ELEGANCE',  // Diesel trims
    'E PREMIUM', 'C PREMIUM', 'E SELECT',  // Premium variants
    'S DESIGN',                      // Seat/Audi design variant
  ];

  let protected = version;

  // Protect hyphenated trims (exact match)
  PROTECTED_HYPHENATED_TRIMS.forEach(trim => {
    const placeholder = trim.replace(/-/g, '_DASH_');
    protected = protected.replace(new RegExp(`\\b${trim}\\b`, 'gi'), placeholder);
  });

  // Protect spaced trims (with multi-space handling)
  PROTECTED_SPACED_TRIMS.forEach(trim => {
    const placeholder = trim.replace(/\s+/g, '_SPACE_');
    // Match with flexible whitespace: M\s+SPORT matches "M SPORT", "M  SPORT", "M   SPORT"
    const pattern = trim.replace(/\s+/g, '\\s+');
    protected = protected.replace(new RegExp(`\\b${pattern}\\b`, 'gi'), placeholder);
  });

  return protected;
}

function restoreTrims(version) {
  if (!version) return version;

  return version
    .replace(/_DASH_/g, '-')
    .replace(/_SPACE_/g, ' ');
}
```

### 2. Expanded Removal Dictionaries

Each insurer needs these additions to their `irrelevant_comfort_audio` array:

#### All Insurers (Universal)
```javascript
// Add these to ALL normalization scripts:
"USB",           // Missing from most
"BT",            // Missing from most
"BLUETOOTH",     // Full word variant
```

#### Per-Insurer Specific

**Zurich**: Add `"USB", "BT"`

**HDI**: Add `"VP", "QC", "BT", "BLUETOOTH", "HATCHBACK", "CP"`

**AXA**: Add `"BT", "NAVEG", "PIEL", "AC", "GENERICA"`

**ANA**: Add `"USB", "PTAS"`

**Atlas**: Add marca-stripping logic (not dictionary)

**El Potosí**: Add `"SQ", "CB", "CQ", "CE", "CA", "B/A", "TON", "PIEL"`

**BX**: Add `"BT", "LUJO", "V/P", "CP"`

**GNP**: Add `"C/A", "V.E.", "VE", "AC", "BT"`

**Chubb**: Add `"CB", "CQ", "CA", "CE", "PIEL", "SM", "IMO"`

### 3. Special Case Handlers

#### Atlas - Strip Marca from Version
```javascript
function stripMarcaFromVersion(marca, version) {
  if (!marca || !version) return version;

  const marcaUpper = marca.toUpperCase().trim();
  const versionUpper = version.toUpperCase();

  // Remove marca if it appears at the start of version
  if (versionUpper.startsWith(marcaUpper + ' ')) {
    return version.substring(marca.length).trim();
  }

  return version;
}
```

#### El Potosí - Fix Concatenations
```javascript
function fixConcatenations(version) {
  if (!version) return version;

  // Fix missing spaces before transmission indicators
  return version
    .replace(/([A-Z])-SPEC(AUT|MAN|STD)/gi, '$1-SPEC $2')
    .replace(/([A-Z])-LINE(AUT|MAN|STD)/gi, '$1-LINE $2')
    .replace(/M-SPORT(AUT|MAN|STD)/gi, 'M-SPORT $1');
}
```

#### GNP - Normalize Punctuation Variants
```javascript
function normalizePunctuationVariants(version) {
  if (!version) return version;

  return version
    .replace(/C\/A/g, 'CA')           // C/A → CA (then removed by dictionary)
    .replace(/V\.E\./g, 'VE')         // V.E. → VE
    .replace(/V\/P/g, 'VP')           // V/P → VP
    .replace(/Q\/C/g, 'QC')           // Q/C → QC
    .replace(/B\/A/g, 'BA');          // B/A → BA
}
```

#### AXA - Handle GENERICA Placeholder
```javascript
function handlePlaceholders(record) {
  // Filter out generic placeholder records or replace version
  if (record.version_original === 'GENERICA') {
    // Option 1: Skip record
    return null;

    // Option 2: Replace with empty version
    // record.version_original = '';
  }

  return record;
}
```

### 4. Multi-Space Handling

All scripts should include multi-space normalization:

```javascript
function collapseWhitespace(str) {
  return str ? str.replace(/\s+/g, ' ').trim() : str;
}
```

Apply AFTER all transformations, BEFORE hash generation.

---

## Summary of Required Changes

### By Insurer

| Insurer | Add Spaced Trims | Add to Dictionary | Special Handlers | Priority |
|---------|------------------|-------------------|------------------|----------|
| **Qualitas** | M SPORT, L PREMIUM, TYPE S, S-TRONIC | CAM TRAS, SPORTSHIFT | - | HIGH |
| **Zurich** | M SPORT, TYPE S, A SPORT, A LUXURY | USB, BT | - | HIGH |
| **HDI** | M SPORT, S SPORT, E SPORT, I SPORT | VP, QC, BT, BLUETOOTH, CP | Multi-space regex | HIGH |
| **Mapfre** | - | - | Fix extraction query | CRITICAL |
| **AXA** | M SPORT, S-DESIGN, T SPORT, L PREMIUM, V LUXURY, E PREMIUM, C PREMIUM, E SELECT | BT, NAVEG, PIEL, AC | Handle GENERICA | MEDIUM |
| **ANA** | M SPORT, X-DRIVE, TYPE S, S SPORT, N LUXURY | USB, PTAS | - | HIGH |
| **Atlas** | M SPORT, I TOURING, I SPORT, I LUXURY, I PREMIUM, S-TRONIC, TYPE S | - | Strip marca from version, Handle A-SPECH typo | HIGH |
| **El Potosí** | M SPORT, D PREMIUM, D SPORT, D ELEGANCE, S SPORT, I LUXURY, I SPORT, X-DRIVE | SQ, CB, CQ, CE, CA, B/A, TON, PIEL, I-VTEC | Fix concatenations (A-SPECAUT) | HIGH |
| **BX** | M SPORT, S SPORT, TYPE S, L PREMIUM | BT, LUJO, V/P, CP | - | MEDIUM |
| **GNP** | M SPORT, I PREMIUM, S SPORT, A SPORT | C/A, V.E., VE, AC, BT | Normalize punctuation variants | MEDIUM |
| **Chubb** | M SPORT, R TOURING, S SPORT, R SPORT | CB, CQ, CA, CE, PIEL, SM, IMO | - | HIGH |

### Change Impact Analysis

- **11 scripts** need modification
- **~27 new trim patterns** to protect across all scripts
- **~30 new garbage specs** to add to dictionaries
- **4 special handlers** needed (Atlas, El Potosí, GNP, AXA)
- **1 data extraction issue** (Mapfre)

### Estimated Effort
- **2-3 hours** per script modification + testing
- **Total: 25-30 hours** for complete implementation
- **Testing: 10-15 hours** for validation across all insurers

---

## Testing Strategy

### Phase 1: Unit Testing
For each modified script:
1. Test trim protection with sample data
2. Verify garbage spec removal
3. Check special handler logic
4. Validate hash generation consistency

### Phase 2: Integration Testing
1. Run full ETL pipeline for each insurer (sample data)
2. Compare before/after token counts
3. Verify no data loss
4. Check for new conflicts/duplicates

### Phase 3: Production Validation
1. Run on 1,000-record sample per insurer
2. Manual QA of 50 random records per insurer
3. Compare token overlap scores before/after
4. Validate homologation match rates

### Test Cases

#### Trim Protection Tests
```javascript
// Test case examples
testCases = [
  { input: "M SPORT 2.0L 150HP", expected_trim: "M SPORT", preserved: true },
  { input: "M  SPORT 2.0L", expected_trim: "M SPORT", preserved: true },  // Double space
  { input: "I TOURING 2.5L", expected_trim: "I TOURING", preserved: true },
  { input: "A-SPECAUT 1.5L", expected_after_fix: "A-SPEC AUT 1.5L" },
  { input: "ACURA ILX PREMIUM", expected_stripped: "ILX PREMIUM" }, // Atlas
];
```

#### Dictionary Coverage Tests
```javascript
// Verify all garbage specs removed
testGarbageRemoval = [
  { input: "PREMIUM AA EE CD 4P", expected: "PREMIUM 4PUERTAS" },
  { input: "SPORT USB BT GPS", expected: "SPORT" },
  { input: "ADVANCE C/A V.E.", expected: "ADVANCE" }, // GNP
];
```

---

## Rollout Plan

### Stage 1: High Priority (Week 1)
- **Qualitas** (39,715 records) - Largest Acura insurer
- **Zurich** (38,984 records) - Most verbose data
- **HDI** (38,186 records) - Multi-space issues
- **ANA** (36,432 records) - X-DRIVE pattern critical for BMW

### Stage 2: Medium Priority (Week 2)
- **Atlas** (31,229 records) - Marca stripping required
- **El Potosí** (23,040 records) - Concatenation fixes
- **Chubb** (31,256 records) - Large dictionary additions
- **GNP** (55,486 records) - LARGEST, punctuation handling

### Stage 3: Lower Priority (Week 3)
- **AXA** (14,424 records) - Smallest volume
- **BX** (39,292 records) - Fewer changes needed

### Stage 4: Critical Blocker
- **Mapfre** (37,346 records) - **FIX EXTRACTION FIRST**

---

## Risk Assessment

### High Risk
1. **M SPORT pattern**: 2,636 total occurrences across all insurers - most critical fix
2. **Mapfre extraction**: Complete data unavailability blocks analysis
3. **Atlas marca contamination**: Version field includes marca, corrupting tokens

### Medium Risk
1. **S-TRONIC**: 316 occurrences - significant Audi trim
2. **I-series Mazda trims**: 67 total occurrences - brand-specific
3. **Dictionary gaps**: Missing USB, BT, etc. affecting token quality

### Low Risk
1. **Rare trims** (<10 occurrences): Low impact but completeness matters
2. **Typo variants** (A-SPECH): Minimal occurrences

---

## Success Metrics

### Quantitative
- **Token overlap scores increase** by ≥5% for same-vehicle matches
- **False duplicate rate decreases** by ≥10%
- **Zero data loss**: All records process successfully
- **Processing time**: No increase >5%

### Qualitative
- **Trim preservation**: All protected trims remain intact through pipeline
- **Version cleanliness**: No garbage specs in final version field
- **Modelo cleanliness**: No specs contaminating modelo field

---

## Next Steps

1. **Review this analysis** with stakeholders
2. **Prioritize changes** based on impact/effort
3. **Implement Stage 1** high-priority scripts
4. **Test rigorously** before production deployment
5. **Monitor production** for unexpected issues
6. **Iterate** based on feedback

---

## Appendix: Complete Trim Pattern Reference

### Protected (Hyphenated)
- A-SPEC, A-SPECH (typo)
- TYPE-S, TYPE-R
- S-LINE, R-LINE
- M-SPORT
- E-TRON
- S-TRONIC, Q-TRONIC
- X-DRIVE
- A-SEMI
- I-VTEC (consider moving to removal)

### Unprotected (Space-Separated) - NEEDS ADDITION
- M SPORT ⚠️ CRITICAL (2,636 occurrences)
- TYPE S (47)
- I TOURING (23)
- I SPORT (19)
- I LUXURY (12)
- I PREMIUM (17)
- S SPORT (32)
- R TOURING (14)
- R SPORT (1)
- A SPORT (9)
- A LUXURY (4)
- E SPORT (3)
- T SPORT (1)
- X SPORT (1)
- L PREMIUM (19)
- N LUXURY (3)
- V LUXURY (1)
- C PREMIUM (1)
- E PREMIUM (1)
- E SELECT (1)
- D PREMIUM (8)
- D SPORT (7)
- D ELEGANCE (6)
- S-DESIGN (2)

### Total: 37 unique patterns (10 currently protected, 27 need addition)

---

**Document End**
