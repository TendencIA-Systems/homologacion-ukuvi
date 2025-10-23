# CORRECTED Implementation Handoff: Trim Normalization

## Critical Correction

**Transmission specs (STRONIC, S-TRONIC, XTRONIC, Q-TRONIC) are NOT trims.**

These should be:
1. Used to infer transmission = AUTO (if not already set)
2. Added to removal dictionaries
3. **NOT protected** as trims

## Task Overview

Implement trim protection for **40 unique trim patterns** across **11 insurance company ETL scripts**.

**Reference Documents:**
- **Corrected trim list**: `CORRECTED-TRIM-LIST.md` (this directory)
- **Original analysis**: `comprehensive-analysis.md` (background context)

## Critical Findings

### ✅ Actual Trims to Protect (40 patterns)

**Highest Priority:**
- **M SPORT**: 8,698 occurrences (most critical!)
- **I SPORT**: 120 occurrences
- **S SPORT**: 108 occurrences

**Mazda I-Series (244 total):**
- **I GRAND TOURING**: 26 occurrences ← User specifically requested
- **I TOURING**: 34 occurrences
- **I SPORT**: 120 occurrences
- **I LUXURY**: 24 occurrences
- **I PREMIUM**: 40 occurrences

**Honda R-Series (24 total):**
- **R TOURING**: 14 occurrences
- **R SPORT**: 8 occurrences
- **R LUXURY**: 2 occurrences

**Diesel D-Series (42 total):**
- **D PREMIUM**: 16 occurrences
- **D SPORT**: 14 occurrences
- **D ELEGANCE**: 12 occurrences

**Other Letter + Descriptor patterns:** A SPORT, C SPORT, E SPORT, F SPORT, L PREMIUM, V LUXURY, etc. (see CORRECTED-TRIM-LIST.md for complete list)

### ❌ Transmission Specs to REMOVE (NOT protect)

- **STRONIC**: 1,316 occurrences → Add to removal dictionary
- **S-TRONIC**: 316 occurrences → Add to removal dictionary
- **XTRONIC**: 8 occurrences → Add to removal dictionary
- **X-TRONIC**: 1 occurrence → Add to removal dictionary
- **Q-TRONIC**: 2 occurrences → Add to removal dictionary

## Implementation Steps

### Step 1: Enhanced Trim Protection Function

Add this function to each normalization script (customize trim list per insurer):

```javascript
/**
 * Protects actual vehicle trim levels (40 patterns total across all insurers)
 * NOTE: Each insurer has a subset - see CORRECTED-TRIM-LIST.md for specifics
 */
function protectTrims(version) {
  if (!version) return version;

  // Hyphenated trims (existing + TYPE-R)
  const PROTECTED_HYPHENATED_TRIMS = [
    'A-SPEC', 'A-SPECH',           // Acura
    'TYPE-S', 'TYPE-R',             // Honda/Acura
    'S-LINE', 'R-LINE',             // Audi/VW
    'M-SPORT',                       // BMW hyphenated
    'E-TRON',                        // Audi electric
    'X-DRIVE',                       // BMW AWD
    // NOTE: S-TRONIC is NOT here - it's a transmission spec!
  ];

  // Space-separated trims - COMPLETE LIST
  // Only add trims that appear in THIS insurer's data
  const PROTECTED_SPACED_TRIMS = [
    // M-series (8,698 total - present in ALL insurers)
    'M SPORT', 'M LUXURY', 'M PREMIUM',

    // I-series (Mazda - 244 total - AXA, Atlas, HDI, El Potosí, GNP, Zurich)
    'I GRAND TOURING',  // ← User specifically requested (AXA only)
    'I TOURING',
    'I SPORT',
    'I LUXURY',
    'I PREMIUM',

    // R-series (Honda - 24 total - Chubb, AXA, El Potosí)
    'R TOURING',
    'R SPORT',
    'R LUXURY',

    // S-series
    'S SPORT',
    'S LUXURY',
    'S PREMIUM',
    'S DESIGN',

    // TYPE variants (space-separated)
    'TYPE S',
    'TYPE R',

    // Letter + SPORT
    'A SPORT', 'C SPORT', 'E SPORT', 'F SPORT', 'G SPORT',
    'K SPORT', 'L SPORT', 'T SPORT', 'V SPORT', 'X SPORT',

    // Letter + LUXURY
    'A LUXURY', 'E LUXURY', 'N LUXURY', 'V LUXURY',

    // Letter + PREMIUM
    'A PREMIUM', 'C PREMIUM', 'E PREMIUM', 'K PREMIUM', 'L PREMIUM', 'V PREMIUM',

    // Letter + ELEGANCE
    'D ELEGANCE', 'F ELEGANCE', 'G ELEGANCE', 'K ELEGANCE',

    // Diesel trims (El Potosí primarily)
    'D PREMIUM', 'D SPORT', 'D ELEGANCE',

    // Other
    'E SELECT',
  ];

  let protected = version;

  // Protect hyphenated
  PROTECTED_HYPHENATED_TRIMS.forEach(trim => {
    const placeholder = trim.replace(/-/g, '_DASH_');
    protected = protected.replace(new RegExp(`\\b${trim}\\b`, 'gi'), placeholder);
  });

  // Protect spaced (with multi-space handling)
  PROTECTED_SPACED_TRIMS.forEach(trim => {
    const placeholder = trim.replace(/\s+/g, '_SPACE_');
    const pattern = trim.replace(/\s+/g, '\\s+'); // M SPORT, M  SPORT, M   SPORT
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

**IMPORTANT**: Not all insurers have all 40 trims. Reference `CORRECTED-TRIM-LIST.md` per-insurer section to see which trims to include for each insurer.

### Step 2: Add Transmission Specs to Removal Dictionary

Add these to the `irrelevant_comfort_audio` array in EVERY script:

```javascript
const INSURER_NORMALIZATION_DICTIONARY = {
  irrelevant_comfort_audio: [
    // ... existing specs ...

    // Transmission type indicators (use for inference, then remove)
    "STRONIC",        // Audi DSG
    "S-TRONIC",       // Audi DSG hyphenated
    "XTRONIC",        // Nissan CVT
    "X-TRONIC",       // Nissan CVT hyphenated
    "Q-TRONIC",       // Infiniti auto

    // ... rest of existing specs ...
  ],
};
```

### Step 3: Transmission Inference (Before Removal)

Ensure transmission inference happens BEFORE spec removal:

```javascript
function inferTransmission(version, transmisionCode) {
  // If already set from database, use it
  if (transmisionCode && transmisionCode !== '' && transmisionCode !== '0') {
    return mapTransmissionCode(transmisionCode);
  }

  // Infer from version string BEFORE removal
  const versionUpper = version.toUpperCase();

  // AUTO indicators (including transmission specs)
  if (/\b(STRONIC|S-TRONIC|XTRONIC|X-TRONIC|Q-TRONIC|CVT|TIPTRONIC|DSG|PDK|AUTOMATICO|AUTOMATICA|AUTO|AUT)\b/i.test(versionUpper)) {
    return 'AUTO';
  }

  // MANUAL indicators
  if (/\b(MANUAL|STD|ESTANDAR|MECANICA)\b/i.test(versionUpper)) {
    return 'MANUAL';
  }

  return null;
}
```

### Step 4: Correct Processing Order

```javascript
// STAGE 1: Validation
validateRecord(record);

// STAGE 2: Brand/Model Normalization
record.marca = consolidateBrand(record.marca);
record.modelo = cleanBMWModelo(record.marca, record.modelo);
record.modelo = removeSpecsFromModelo(record.modelo);
record.version = stripMarcaFromVersion(record.marca, record.version); // Atlas only

// STAGE 3: Version Pre-processing
record.version = normalizePunctuationVariants(record.version); // GNP only
record.version = fixConcatenations(record.version);            // El Potosí only

// STAGE 4: TRANSMISSION INFERENCE (before removal!)
record.transmision = inferTransmission(record.version, record.transmision_code);

// STAGE 5: TRIM PROTECTION
record.version = protectTrims(record.version);

// STAGE 6: Spec Normalization
record.version = normalizeEngineSpecs(record.version);
record.version = normalizeDoors(record.version);
record.version = normalizeOccupants(record.version);

// STAGE 7: GARBAGE REMOVAL (STRONIC removed here, after inference)
record.version = removeGarbageSpecs(record.version);
record.version = removeBodyTypes(record.version);

// STAGE 8: TRIM RESTORATION
record.version = restoreTrims(record.version);

// STAGE 9: Final Cleanup
record.version = collapseWhitespace(record.version);
record.version = record.version.trim().toUpperCase();

// STAGE 10: Hash Generation
record.hash_comercial = generateHash(...);
record.id_canonico = generateHash(...);
```

## Per-Insurer Quick Reference

| Insurer | Critical Trims | Transmission Specs to Remove | Special Handler |
|---------|----------------|------------------------------|-----------------|
| **Qualitas** | M SPORT, L PREMIUM, TYPE S, C SPORT | STRONIC (293), S-TRONIC (144) | None |
| **Zurich** | M SPORT, TYPE S, V LUXURY, A SPORT, I SPORT | Q-TRONIC (2), STRONIC (1) | None |
| **HDI** | M SPORT, S SPORT, I SPORT, I PREMIUM, E SPORT | STRONIC (118), S-TRONIC (6) | Multi-space |
| **AXA** | M SPORT, **I GRAND TOURING**, I SPORT, I TOURING, S SPORT | STRONIC (289), XTRONIC (8) | GENERICA placeholder |
| **ANA** | M SPORT, S SPORT, TYPE S, N LUXURY | STRONIC (22), S-TRONIC (2) | None |
| **Atlas** | M SPORT, I SPORT, I TOURING, I LUXURY, I PREMIUM | STRONIC (33), S-TRONIC (12) | Strip marca |
| **El Potosí** | M SPORT, **D PREMIUM, D SPORT, D ELEGANCE**, I LUXURY, I SPORT | STRONIC (108), S-TRONIC (3) | Fix concatenations |
| **BX** | M SPORT, S SPORT, TYPE S, G ELEGANCE, F ELEGANCE | STRONIC (581) ⚠️ Highest | None |
| **GNP** | M SPORT, I PREMIUM, A SPORT, S SPORT, C PREMIUM | STRONIC (20) | Normalize punctuation |
| **Chubb** | M SPORT, S SPORT, **R TOURING**, C PREMIUM, R SPORT | None found | None |

## Testing Requirements

### Critical Test Cases

```javascript
// Trim protection
{ input: "M SPORT 2.0L 150HP", expected_contains: "M SPORT" }
{ input: "I GRAND TOURING 2.5L", expected_contains: "I GRAND TOURING" }  // AXA
{ input: "I TOURING 2.0L", expected_contains: "I TOURING" }
{ input: "D PREMIUM DIESEL 2.0L", expected_contains: "D PREMIUM" }       // El Potosí
{ input: "R TOURING 2.4L", expected_contains: "R TOURING" }             // Chubb

// Transmission spec removal + inference
{
  input: "ADVANCE STRONIC 2.0L",
  expected_not_contains: "STRONIC",
  expected_transmission: "AUTO",
  expected_contains: "ADVANCE"
}
{
  input: "LUXURY S-TRONIC 1.8L",
  expected_not_contains: "S-TRONIC",
  expected_transmission: "AUTO"
}
{
  input: "M SPORT XTRONIC 2.0L",  // BX
  expected_contains: "M SPORT",
  expected_not_contains: "XTRONIC",
  expected_transmission: "AUTO"
}
```

## Special Handlers (Same as before)

### Atlas - Strip Marca
```javascript
function stripMarcaFromVersion(marca, version) {
  if (!marca || !version) return version;
  const marcaUpper = marca.toUpperCase().trim();
  const versionUpper = version.toUpperCase();
  if (versionUpper.startsWith(marcaUpper + ' ')) {
    return version.substring(marca.length).trim();
  }
  return version;
}
```

### El Potosí - Fix Concatenations
```javascript
function fixConcatenations(version) {
  if (!version) return version;
  return version
    .replace(/([A-Z])-SPEC(AUT|MAN|STD)/gi, '$1-SPEC $2')
    .replace(/([A-Z])-LINE(AUT|MAN|STD)/gi, '$1-LINE $2')
    .replace(/M-SPORT(AUT|MAN|STD)/gi, 'M-SPORT $1');
}
```

### GNP - Normalize Punctuation
```javascript
function normalizePunctuationVariants(version) {
  if (!version) return version;
  return version
    .replace(/C\/A/g, 'CA')
    .replace(/V\.E\./g, 'VE')
    .replace(/V\/P/g, 'VP')
    .replace(/Q\/C/g, 'QC')
    .replace(/B\/A/g, 'BA');
}
```

### AXA - Handle GENERICA
```javascript
function handlePlaceholders(record) {
  if (record.version_original === 'GENERICA') {
    return null; // Skip record
  }
  return record;
}
```

## Implementation Priority

### Phase 1: High Priority
1. **AXA** - Has I GRAND TOURING (user requested) + highest STRONIC count (289)
2. **HDI** - Has I-series trims + STRONIC (118)
3. **Qualitas** - High M SPORT count + STRONIC (293)
4. **Zurich** - Highest M SPORT single count (1,270)

### Phase 2: Medium Priority
5. **Atlas** - Strong I-series presence + marca stripping
6. **Chubb** - R TOURING pattern
7. **El Potosí** - D-series diesel trims
8. **BX** - Highest STRONIC count (581)

### Phase 3: Lower Priority
9. **GNP** - I PREMIUM present
10. **ANA** - Fewer unique trims

## Success Criteria

- ✅ All 40 trim patterns protected across relevant insurers
- ✅ "I GRAND TOURING" specifically preserved in AXA
- ✅ "R TOURING" preserved in Chubb
- ✅ "D PREMIUM/D SPORT/D ELEGANCE" preserved in El Potosí
- ✅ M SPORT protected in ALL insurers (8,698 total occurrences)
- ✅ STRONIC/XTRONIC removed from version after transmission inference
- ✅ Transmission correctly set to AUTO when transmission specs present
- ✅ Zero data loss

## Common Pitfalls

1. **Don't protect STRONIC/XTRONIC** - They're transmission specs, not trims
2. **Infer transmission BEFORE removing specs** - Otherwise you lose the signal
3. **Only add trims that exist in that insurer's data** - See per-insurer lists
4. **Don't forget multi-space handling** - "M  SPORT" with double space must work
5. **Test transmission inference** - Verify AUTO is set when STRONIC present

## File Locations

```
Scripts to modify:
/src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js
/src/insurers/zurich/zurich-codigo-de-normalizacion.js
/src/insurers/hdi/hdi-codigo-de-normalizacion.js
/src/insurers/axa/axa-codigo-de-normalizacion.js
/src/insurers/ana/ana-codigo-de-normalizacion.js
/src/insurers/atlas/atlas-codigo-de-normalizacion.js
/src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js
/src/insurers/bx/bx-codigo-de-normalizacion.js
/src/insurers/gnp/gnp-codigo-de-normalizacion.js
/src/insurers/chubb/chubb-codigo-de-normalizacion.js

Reference documents:
.claude/bugs/trim-normalization-analysis/CORRECTED-TRIM-LIST.md
.claude/bugs/trim-normalization-analysis/comprehensive-analysis.md

Test data:
/data/origin/{insurer}-origin.csv
```

---

**Ready for implementation. Start with Phase 1, test thoroughly, and report progress.**
