# Per-Insurer Normalization Changes - Detailed Reference

**Document Version:** 1.0
**Date:** 2025-10-17
**Phase:** Phase 4 - Deployment (Task 110)
**Purpose:** Detailed documentation of specific code changes for each insurer

---

## Table of Contents

1. [MAPFRE](#1-mapfre)
2. [Zurich](#2-zurich)
3. [HDI](#3-hdi)
4. [Qualitas](#4-qualitas)
5. [ANA](#5-ana)
6. [BX](#6-bx)
7. [El Potosí](#7-el-potosí)
8. [GNP](#8-gnp)
9. [Chubb](#9-chubb)
10. [Atlas](#10-atlas)
11. [AXA](#11-axa)

---

## 1. MAPFRE

### Workflow Information
- **Workflow Name:** ETL - MAPFRE
- **Source File:** `/src/insurers/mapfre/mapfre-codigo-de-normalizacion.js`
- **Priority:** HIGHEST (worst data quality)
- **Record Count:** ~21,000 records
- **Data Quality Issues:** High transmission contamination, brand variants, duplicate tokens

### Changes Applied

#### 1.1 Brand Consolidation Map (Component 2)
**Added:**
```javascript
const BRAND_CONSOLIDATION_MAP = {
  'BMW BW': 'BMW',
  'BERCEDES': 'MERCEDES BENZ',
  'MERCEDES': 'MERCEDES BENZ',
  'MERCEDESBENZ': 'MERCEDES BENZ',
  'KIA MOTORS': 'KIA',
  'AUTOS': 'INVALID_BRAND',
  'VOLKSWAGEN VW': 'VOLKSWAGEN',
  'VW': 'VOLKSWAGEN',
  'CHEVROLET CHEVY': 'CHEVROLET',
  'CHEVY': 'CHEVROLET',
  'LAND ROVER': 'LAND ROVER',
  'LANDROVER': 'LAND ROVER',
  'ALFA ROMEO': 'ALFA ROMEO',
  'ALFAROMEO': 'ALFA ROMEO'
};

function consolidateBrand(marca) {
  if (!marca) return 'INVALID_BRAND';
  const normalizedMarca = marca.trim().toUpperCase();
  return BRAND_CONSOLIDATION_MAP[normalizedMarca] || normalizedMarca;
}
```

**Applied in processRecord():**
```javascript
// Apply brand consolidation BEFORE hash generation
normalizedRecord.marca = consolidateBrand(record.marca);
if (normalizedRecord.marca === 'INVALID_BRAND') {
  errors.push({
    record: record,
    error: 'INVALID_BRAND',
    details: `Brand "${record.marca}" is invalid`
  });
  return null; // Discard record
}
```

#### 1.2 Transmission Recovery (Component 3)
**Added:**
```javascript
function recoverTransmission(record) {
  const transmisionField = (record.transmision || '').trim().toUpperCase();
  const versionField = (record.version_original || '').trim().toUpperCase();

  // Step 1: Try to extract valid transmission from contaminated field
  const autoPatterns = /\b(AUTO|AUT|AUTOMATIC|TIPTRONIC|DSG|CVT|AUTOMATICA)\b/i;
  const manualPatterns = /\b(MANUAL|MAN|STD|ESTANDAR|STANDARD)\b/i;

  if (autoPatterns.test(transmisionField)) {
    return 'AUTO';
  }
  if (manualPatterns.test(transmisionField)) {
    return 'MANUAL';
  }

  // Step 2: Infer from version_original if step 1 failed
  if (autoPatterns.test(versionField)) {
    return 'AUTO';
  }
  if (manualPatterns.test(versionField)) {
    return 'MANUAL';
  }

  // Unrecoverable
  return null;
}
```

**Applied in processRecord():**
```javascript
// Recover transmission
const recoveredTransmission = recoverTransmission(record);
if (recoveredTransmission === null) {
  errors.push({
    record: record,
    error: 'TRANSMISSION_INFERENCE_FAILED',
    details: 'Could not recover valid transmission value'
  });
  return null; // Discard record
}
normalizedRecord.transmision = recoveredTransmission;
```

#### 1.3 Enhanced Model Normalization (Component 4)
**Modified existing normalizeModelo():**
```javascript
function normalizeModelo(marca, modelo) {
  if (!modelo) return '';

  let normalized = modelo.trim().toUpperCase();

  // NEW: Remove NUEVO/NUEVA/NEW prefix
  normalized = normalized.replace(/^(NUEVO|NUEVA|NEW)\s+/gi, '');

  // NEW: Mazda-specific - Remove "MAZDA" or "MA" prefix
  if (marca === 'MAZDA') {
    normalized = normalized.replace(/^MAZDA\s+/gi, '');
    normalized = normalized.replace(/^MA\s+/gi, '');
  }

  // NEW: Mercedes-specific - Remove "MERCEDES" prefix, replace "KLASSE" with "CLASE"
  if (marca === 'MERCEDES BENZ') {
    normalized = normalized.replace(/^MERCEDES\s+/gi, '');
    normalized = normalized.replace(/\bKLASSE\b/gi, 'CLASE');
  }

  // NEW: BMW-specific - Normalize "SERIE X5" to "X5"
  if (marca === 'BMW') {
    normalized = normalized.replace(/^SERIE\s+/gi, '');
  }

  // EXISTING: Remove body types (keep this logic)
  normalized = normalized.replace(/\b(SEDAN|SUV|PICKUP|VAN|COUPE|HATCHBACK)\b/gi, '');

  // EXISTING: Remove generic prefixes
  normalized = normalized.replace(/^(AUTO|AUTOMOVIL|VEHICULO)\s+/gi, '');

  return normalized.trim();
}
```

#### 1.4 Enhanced Version Cleaning (Component 5)
**Modified existing cleanVersionString():**
```javascript
function cleanVersionString(version) {
  if (!version) return '';

  let cleaned = version.trim().toUpperCase();

  // NEW: Remove escape characters FIRST
  cleaned = cleaned.replace(/\\"/g, '');  // Escaped quotes
  cleaned = cleaned.replace(/\\\\/g, ''); // Backslashes
  cleaned = cleaned.replace(/[""''\"'\u201C\u201D\u2018\u2019]/g, ' '); // All quote types

  // NEW: Separate HP+AUT pattern
  cleaned = cleaned.replace(/(\d+)HPAUT/gi, '$1HP AUT');

  // EXISTING: Remove comfort features (keep this logic)
  cleaned = cleaned.replace(/\b(AA|EE|CD|ABS|BA|AIRBAG)\b/gi, '');

  // NEW: Fix invalid door counts
  cleaned = fixInvalidDoorCounts(cleaned);

  return cleaned.trim();
}

// NEW: Helper function for invalid door counts
function fixInvalidDoorCounts(version) {
  // Remove BMW model numbers: 300PUERTAS, 320PUERTAS, 328PUERTAS, 335PUERTAS
  version = version.replace(/\b(300|320|328|335)PUERTAS\b/gi, '');

  // Fix truck notation: 3500PUERTAS → 4PUERTAS
  version = version.replace(/\b3500PUERTAS\b/gi, '4PUERTAS');

  // Remove invalid door counts: 0PUERTAS, [6-9]PUERTAS, [100+]PUERTAS
  version = version.replace(/\b0PUERTAS\b/gi, '');
  version = version.replace(/\b[6-9]PUERTAS\b/gi, '');
  version = version.replace(/\b\d{3,}PUERTAS\b/gi, '');

  return version;
}
```

#### 1.5 Intelligent Token Deduplication (Component 6)
**Added (if not already present):**
```javascript
function isNumericSpecification(token) {
  // Detect patterns like: 2.0L, 5PUERTAS, 4CIL, 180HP
  return /^\d+(\.\d+)?(L|PUERTAS|CIL|HP|CV|KW)$/i.test(token);
}

function deduplicateTokens(tokens) {
  const seen = new Set();
  const result = [];

  for (const token of tokens) {
    const normalizedToken = token.toUpperCase().trim();

    // Skip empty tokens
    if (!normalizedToken) continue;

    // For numeric specifications, check if we've seen this exact spec type
    if (isNumericSpecification(normalizedToken)) {
      // Allow different spec types: 2.0L and 2PUERTAS are both kept
      // But deduplicate same spec: 2.0L...2.0L → 2.0L (first occurrence wins)
      if (!seen.has(normalizedToken)) {
        seen.add(normalizedToken);
        result.push(token); // Preserve original casing
      }
    } else {
      // For non-numeric tokens, deduplicate normally
      if (!seen.has(normalizedToken)) {
        seen.add(normalizedToken);
        result.push(token);
      }
    }
  }

  return result;
}
```

**Applied in processRecord():**
```javascript
// Apply deduplication AFTER all cleaning steps
const versionTokens = normalizedRecord.version.split(/\s+/);
const deduplicatedTokens = deduplicateTokens(versionTokens);
normalizedRecord.version = deduplicatedTokens.join(' ');
```

### Testing Notes for MAPFRE
- **Focus:** High transmission contamination (GLI, LATITUDE, PEPPER values)
- **Expected Improvement:** Transmission valid % from ~15% to >95%
- **Watch For:** Brand variants like "BMW BW", "BERCEDES"
- **Validation Query:** Check for duplicate tokens in version strings

---

## 2. Zurich

### Workflow Information
- **Workflow Name:** ETL - Zurich
- **Source File:** `/src/insurers/zurich/zurich-codigo-de-normalizacion.js`
- **Priority:** HIGH (whitelisted for creation, critical cross-insurer matching)
- **Record Count:** ~18,000 records
- **Data Quality Issues:** MAZDA prefix contamination, A-SPEC vs TECH matching bug

### Changes Applied

**All 5 components (2-6) applied same as MAPFRE, PLUS:**

#### 2.1 Zurich-Specific Model Normalization (Req 7.3)
**Additional logic in normalizeModelo():**
```javascript
// Zurich-specific: Remove "MAZDA" prefix from Mazda models
if (marca === 'MAZDA') {
  normalized = normalized.replace(/^MAZDA\s+/gi, '');
  // Examples:
  // "MAZDA CX-5" → "CX-5"
  // "MAZDA 3" → "3"
}
```

### Testing Notes for Zurich
- **Focus:** MAZDA prefix removal, A-SPEC standardization
- **Expected Improvement:** Cleaner Mazda models, better cross-insurer matching with A-SPEC trims
- **Watch For:** A-SPEC vs TECH cross-matching (should be fixed by SQL algorithm)
- **Validation Query:** Verify no "MAZDA CX-5" remains (should be "CX-5")

---

## 3. HDI

### Workflow Information
- **Workflow Name:** ETL - HDI
- **Source File:** `/src/insurers/hdi/hdi-codigo-de-normalizacion.js`
- **Priority:** HIGH (whitelisted for creation)
- **Record Count:** ~16,000 records
- **Data Quality Issues:** Body types in modelo field, transmission contamination

### Changes Applied

**All 5 components (2-6) applied same as MAPFRE, PLUS:**

#### 3.1 HDI-Specific Model Normalization (Req 7.7)
**Additional logic in normalizeModelo():**
```javascript
// HDI-specific: Move body types from modelo to version
// This is handled by extracting body type and appending to version
function extractBodyTypeFromModelo(modelo) {
  const bodyTypes = ['SEDAN', 'SUV', 'PICKUP', 'VAN', 'COUPE', 'HATCHBACK'];
  for (const bodyType of bodyTypes) {
    const regex = new RegExp(`\\b${bodyType}\\b`, 'i');
    if (regex.test(modelo)) {
      return bodyType;
    }
  }
  return null;
}

// In processRecord():
const bodyType = extractBodyTypeFromModelo(record.modelo);
if (bodyType) {
  normalizedRecord.version = `${bodyType} ${normalizedRecord.version}`.trim();
  normalizedRecord.modelo = normalizeModelo(record.marca, record.modelo); // Will remove body type
}
```

### Testing Notes for HDI
- **Focus:** Body type migration from modelo to version
- **Expected Improvement:** Cleaner modelo field, richer version strings
- **Watch For:** SEDAN, SUV appearing in modelo (should only be in version)
- **Validation Query:** Check modelo field has no body types

---

## 4. Qualitas

### Workflow Information
- **Workflow Name:** ETL - Qualitas
- **Source File:** `/src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js`
- **Priority:** MEDIUM (reference implementation)
- **Record Count:** ~45,000 records (largest dataset)
- **Data Quality Issues:** Standard issues, but best baseline for patterns

### Changes Applied

**All 5 components (2-6) applied same as MAPFRE.**

**Note:** Qualitas already has `deduplicateTokens()` function (lines 569-609). Enhance rather than replace.

### Testing Notes for Qualitas
- **Focus:** Validate patterns work at scale (45k records)
- **Expected Improvement:** Reference baseline for other insurers
- **Watch For:** Performance with large batch sizes
- **Validation Query:** Compare before/after metrics for all 5 components

---

## 5. ANA

### Workflow Information
- **Workflow Name:** ETL - ANA
- **Source File:** `/src/insurers/ana/ana-codigo-de-normalizacion.js`
- **Priority:** MEDIUM
- **Record Count:** ~14,000 records
- **Data Quality Issues:** MA prefix in Mazda models, CHASIS contamination

### Changes Applied

**All 5 components (2-6) applied same as MAPFRE, PLUS:**

#### 5.1 ANA-Specific Model Normalization (Req 7.4)
**Additional logic in normalizeModelo():**
```javascript
// ANA-specific: Remove "MA" prefix from Mazda models
if (marca === 'MAZDA') {
  normalized = normalized.replace(/^MA\s+/gi, '');
  // Examples:
  // "MA 3" → "3"
  // "MA CX-5" → "CX-5"
}

// ANA-specific: Remove "CHASIS" from all models
normalized = normalized.replace(/\bCHASIS\b/gi, '');
// Examples:
// "F-150 CHASIS" → "F-150"
// "TRANSIT CHASIS CAB" → "TRANSIT CAB"
```

### Testing Notes for ANA
- **Focus:** MA prefix removal, CHASIS cleanup
- **Expected Improvement:** Cleaner Mazda models, better truck model normalization
- **Watch For:** "MA 3" should become "3", "CHASIS" should be removed
- **Validation Query:** Verify no "MA" prefix or "CHASIS" in modelo field

---

## 6. BX

### Workflow Information
- **Workflow Name:** ETL - BX
- **Source File:** `/src/insurers/bx/bx-codigo-de-normalizacion.js`
- **Priority:** MEDIUM
- **Record Count:** ~12,000 records
- **Data Quality Issues:** Brand name in modelo field

### Changes Applied

**All 5 components (2-6) applied same as MAPFRE, PLUS:**

#### 6.1 BX-Specific Model Normalization (Req 7.5)
**Additional logic in normalizeModelo():**
```javascript
// BX-specific: Remove brand name from modelo field
function removeBrandFromModelo(marca, modelo) {
  if (!marca || !modelo) return modelo;

  const marcaNormalized = marca.trim().toUpperCase();
  let modeloNormalized = modelo.trim().toUpperCase();

  // Remove exact brand match at start
  const regex = new RegExp(`^${marcaNormalized}\\s+`, 'i');
  modeloNormalized = modeloNormalized.replace(regex, '');

  return modeloNormalized;
}

// Apply in normalizeModelo():
normalized = removeBrandFromModelo(marca, normalized);
// Examples:
// marca="BMW", modelo="BMW X5" → "X5"
// marca="TOYOTA", modelo="TOYOTA CAMRY" → "CAMRY"
```

### Testing Notes for BX
- **Focus:** Brand name removal from modelo
- **Expected Improvement:** No redundant brand names in modelo field
- **Watch For:** "BMW X5" should become "X5" when marca="BMW"
- **Validation Query:** Check no modelo starts with its marca value

---

## 7. El Potosí

### Workflow Information
- **Workflow Name:** ETL - El Potosí
- **Source File:** `/src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js`
- **Priority:** MEDIUM
- **Record Count:** ~10,000 records
- **Data Quality Issues:** Mercedes prefix variations, generic Mazda models

### Changes Applied

**All 5 components (2-6) applied same as MAPFRE, PLUS:**

#### 7.1 El Potosí-Specific Model Normalization (Req 7.6)
**Additional logic in normalizeModelo():**
```javascript
// ElPotosi-specific: Clean Mercedes prefixes
if (marca === 'MERCEDES BENZ') {
  normalized = normalized.replace(/^MERCEDES\s+/gi, '');
  normalized = normalized.replace(/^BENZ\s+/gi, '');
  normalized = normalized.replace(/^MB\s+/gi, '');
  // Examples:
  // "MERCEDES C CLASE" → "C CLASE"
  // "BENZ E CLASE" → "E CLASE"
}

// ElPotosi-specific: Clean generic Mazda models
if (marca === 'MAZDA') {
  normalized = normalized.replace(/^MAZDA\s+/gi, '');
  normalized = normalized.replace(/^AUTOMOVIL\s+/gi, '');
  // Examples:
  // "MAZDA AUTOMOVIL 3" → "3"
}
```

### Testing Notes for El Potosí
- **Focus:** Mercedes prefix cleanup, generic Mazda model names
- **Expected Improvement:** Consistent Mercedes/Mazda model naming
- **Watch For:** "MERCEDES C CLASE" → "C CLASE", "MAZDA AUTOMOVIL 3" → "3"
- **Validation Query:** Check no "MERCEDES", "BENZ", "MB" prefixes in Mercedes models

---

## 8. GNP

### Workflow Information
- **Workflow Name:** ETL - GNP
- **Source File:** `/src/insurers/gnp/gnp-codigo-de-normalizacion.js`
- **Priority:** MEDIUM
- **Record Count:** ~20,000 records
- **Data Quality Issues:** Marca/modelo tokens in version_original

### Changes Applied

**All 5 components (2-6) applied same as MAPFRE, PLUS:**

#### 8.1 GNP-Specific Version Cleaning (Req 7.8)
**Additional logic in cleanVersionString():**
```javascript
// GNP-specific: Remove marca/modelo tokens from version_original
function removeRedundantTokens(version, marca, modelo) {
  if (!version || !marca || !modelo) return version;

  let cleaned = version;
  const marcaTokens = marca.trim().toUpperCase().split(/\s+/);
  const modeloTokens = modelo.trim().toUpperCase().split(/\s+/);

  // Remove marca tokens
  for (const token of marcaTokens) {
    const regex = new RegExp(`\\b${token}\\b`, 'gi');
    cleaned = cleaned.replace(regex, '');
  }

  // Remove modelo tokens
  for (const token of modeloTokens) {
    const regex = new RegExp(`\\b${token}\\b`, 'gi');
    cleaned = cleaned.replace(regex, '');
  }

  return cleaned.trim();
}

// Apply in processRecord():
normalizedRecord.version = removeRedundantTokens(
  normalizedRecord.version,
  normalizedRecord.marca,
  normalizedRecord.modelo
);
// Examples:
// marca="TOYOTA", modelo="CAMRY", version="TOYOTA CAMRY XLE" → "XLE"
```

### Testing Notes for GNP
- **Focus:** Redundant marca/modelo token removal from version
- **Expected Improvement:** Cleaner version strings without brand/model repetition
- **Watch For:** "TOYOTA CAMRY XLE" should become "XLE" when marca="TOYOTA", modelo="CAMRY"
- **Validation Query:** Check version doesn't contain marca or modelo tokens

---

## 9. Chubb

### Workflow Information
- **Workflow Name:** ETL - Chubb
- **Source File:** `/src/insurers/chubb/chubb-codigo-de-normalizacion.js`
- **Priority:** STANDARD
- **Record Count:** ~15,000 records
- **Data Quality Issues:** Liter separation (2.0LAUT concatenation)

### Changes Applied

**All 5 components (2-6) applied same as MAPFRE, PLUS:**

#### 9.1 Chubb-Specific Version Cleaning (Req 7.9)
**Additional logic in cleanVersionString():**
```javascript
// Chubb-specific: Separate liters from adjacent text
function separateLiterNotation(version) {
  // Pattern: 2.0LAUT → 2.0L AUTO
  version = version.replace(/(\d+\.\d+)LAUT/gi, '$1L AUTO');

  // Pattern: 2.0LMAN → 2.0L MANUAL
  version = version.replace(/(\d+\.\d+)LMAN/gi, '$1L MANUAL');

  // Pattern: 2.0LTURBO → 2.0L TURBO
  version = version.replace(/(\d+\.\d+)L([A-Z]+)/gi, '$1L $2');

  return version;
}

// Apply in cleanVersionString():
cleaned = separateLiterNotation(cleaned);
// Examples:
// "EX 2.0LAUT" → "EX 2.0L AUTO"
// "SPORT 1.8LTURBO" → "SPORT 1.8L TURBO"
```

### Testing Notes for Chubb
- **Focus:** Liter separation from adjacent tokens
- **Expected Improvement:** Properly separated displacement and transmission/features
- **Watch For:** "2.0LAUT" → "2.0L AUTO", "1.8LTURBO" → "1.8L TURBO"
- **Validation Query:** Check no "L" concatenated with adjacent alphabetic characters

---

## 10. Atlas

### Workflow Information
- **Workflow Name:** ETL - Atlas
- **Source File:** `/src/insurers/atlas/atlas-codigo-de-normalizacion.js`
- **Priority:** STANDARD
- **Record Count:** ~13,000 records
- **Data Quality Issues:** BMW model numbers incorrectly parsed as doors

### Changes Applied

**All 5 components (2-6) applied same as MAPFRE, PLUS:**

#### 10.1 Atlas-Specific Version Cleaning (Req 7.10)
**Additional logic in fixInvalidDoorCounts():**
```javascript
// Atlas-specific: Remove BMW model numbers incorrectly parsed as doors
// This is already covered in the base fixInvalidDoorCounts() function:
// 300PUERTAS, 320PUERTAS, 328PUERTAS, 335PUERTAS are removed

// Additional Atlas-specific patterns:
function fixAtlasBMWDoors(version) {
  // Remove other BMW model numbers as doors
  const bmwModelNumbers = ['316', '318', '320', '325', '328', '330', '335', '340',
                           '428', '435', '440', '520', '528', '530', '535', '540',
                           '640', '650', '740', '750', '760'];

  for (const modelNum of bmwModelNumbers) {
    const regex = new RegExp(`\\b${modelNum}PUERTAS\\b`, 'gi');
    version = version.replace(regex, '');
  }

  return version;
}
```

### Testing Notes for Atlas
- **Focus:** BMW model number removal from door counts
- **Expected Improvement:** No invalid BMW model numbers appearing as PUERTAS
- **Watch For:** "328I 4PUERTAS" should NOT become "328PUERTAS"
- **Validation Query:** Check no BMW model numbers followed by "PUERTAS" (320PUERTAS, etc.)

---

## 11. AXA

### Workflow Information
- **Workflow Name:** ETL - AXA
- **Source File:** `/src/insurers/axa/axa-codigo-de-normalizacion.js`
- **Priority:** STANDARD
- **Record Count:** ~17,000 records
- **Data Quality Issues:** A-SPEC vs A SPEC formatting inconsistency

### Changes Applied

**All 5 components (2-6) applied same as MAPFRE, PLUS:**

#### 11.1 AXA-Specific Model Normalization (Req 7.12)
**Additional logic in normalizeModelo() and cleanVersionString():**
```javascript
// AXA-specific: Standardize A-SPEC formatting
function standardizeHyphenatedTrims(text) {
  if (!text) return text;

  // Standardize A-SPEC variants
  text = text.replace(/\bA\s+SPEC\b/gi, 'A-SPEC');
  text = text.replace(/\bASPEC\b/gi, 'A-SPEC');

  // Standardize TYPE-S variants
  text = text.replace(/\bTYPE\s+S\b/gi, 'TYPE-S');
  text = text.replace(/\bTYPES\b/gi, 'TYPE-S');

  // Standardize S-LINE variants
  text = text.replace(/\bS\s+LINE\b/gi, 'S-LINE');
  text = text.replace(/\bSLINE\b/gi, 'S-LINE');

  return text;
}

// Apply to both modelo and version:
normalizedRecord.modelo = standardizeHyphenatedTrims(normalizedRecord.modelo);
normalizedRecord.version = standardizeHyphenatedTrims(normalizedRecord.version);

// Examples:
// "A SPEC" → "A-SPEC"
// "TYPE S" → "TYPE-S"
// "S LINE" → "S-LINE"
```

### Testing Notes for AXA
- **Focus:** Hyphenated trim standardization (A-SPEC, TYPE-S, S-LINE)
- **Expected Improvement:** Consistent trim formatting across all records
- **Watch For:** "A SPEC" → "A-SPEC", "TYPE S" → "TYPE-S"
- **Validation Query:** Check all A-SPEC, TYPE-S, S-LINE use hyphenated format

---

## Quick Reference: Component Matrix

| Insurer | Comp 2 (Brand) | Comp 3 (Trans) | Comp 4 (Model) | Comp 5 (Version) | Comp 6 (Tokens) | Insurer-Specific |
|---------|----------------|----------------|----------------|------------------|-----------------|------------------|
| MAPFRE | ✓ | ✓ | ✓ | ✓ | ✓ | - |
| Zurich | ✓ | ✓ | ✓ + MAZDA prefix | ✓ | ✓ | Req 7.3 |
| HDI | ✓ | ✓ | ✓ + Body type move | ✓ | ✓ | Req 7.7 |
| Qualitas | ✓ | ✓ | ✓ | ✓ | ✓ (enhance) | - |
| ANA | ✓ | ✓ | ✓ + MA/CHASIS | ✓ | ✓ | Req 7.4 |
| BX | ✓ | ✓ | ✓ + Brand removal | ✓ | ✓ | Req 7.5 |
| El Potosí | ✓ | ✓ | ✓ + Mercedes/Mazda | ✓ | ✓ | Req 7.6 |
| GNP | ✓ | ✓ | ✓ | ✓ + Token removal | ✓ | Req 7.8 |
| Chubb | ✓ | ✓ | ✓ | ✓ + Liter separation | ✓ | Req 7.9 |
| Atlas | ✓ | ✓ | ✓ | ✓ + BMW doors | ✓ | Req 7.10 |
| AXA | ✓ | ✓ | ✓ + A-SPEC format | ✓ | ✓ | Req 7.12 |

---

**End of Per-Insurer Changes Documentation**
