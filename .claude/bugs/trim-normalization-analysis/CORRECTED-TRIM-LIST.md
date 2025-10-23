# CORRECTED: Actual Trims vs Transmission Specs

## ✅ ACTUAL TRIMS TO PROTECT (40 unique patterns)

These are **vehicle trim levels** that must be preserved in the version field:

### High Frequency (>100 occurrences)
```
M SPORT: 8,698 total ⚠️ CRITICAL - Most important pattern
I SPORT: 120 total
S SPORT: 108 total
```

### Medium Frequency (20-100 occurrences)
```
TYPE S: 45 total (space-separated variant)
I PREMIUM: 40 total
I TOURING: 34 total
I GRAND TOURING: 26 total ← User specifically requested
C PREMIUM: 24 total
I LUXURY: 24 total
A SPORT: 22 total
L PREMIUM: 20 total
```

### Lower Frequency (<20 occurrences)
```
TYPE-S: 17 total (hyphenated variant)
D PREMIUM: 16 total (Diesel trim)
D SPORT: 14 total (Diesel trim)
R TOURING: 14 total (Honda trim)
D ELEGANCE: 12 total (Diesel trim)
C SPORT: 8 total
E SPORT: 8 total
R SPORT: 8 total
V LUXURY: 7 total
F ELEGANCE: 6 total
L SPORT: 5 total
A LUXURY: 4 total
G ELEGANCE: 4 total
V SPORT: 3 total
V PREMIUM: 3 total
F SPORT: 3 total
N LUXURY: 3 total
A PREMIUM: 3 total
R LUXURY: 2 total
K SPORT: 2 total
K PREMIUM: 2 total
T SPORT: 1 total
E PREMIUM: 1 total
E SELECT: 1 total
TYPE-R: 1 total
K ELEGANCE: 1 total
X SPORT: 1 total
E LUXURY: 1 total
TYPE R: 1 total (space-separated variant)
```

---

## ❌ TRANSMISSION SPECS (DO NOT PROTECT - ADD TO REMOVAL DICTIONARY)

These are **transmission type indicators** used only for inferring AUTO/MANUAL, then removed:

```
STRONIC: 1,316 total (Audi DSG transmission)
S-TRONIC: 316 total (same as above, hyphenated)
XTRONIC: 8 total (Nissan CVT)
Q-TRONIC: 2 total (Infiniti auto transmission)
X-TRONIC: 1 total (same as XTRONIC, hyphenated)
```

### Usage Pattern
1. **Detection**: If version contains STRONIC/S-TRONIC/XTRONIC → infer `transmision = "AUTO"`
2. **Removal**: Remove from version string (add to `irrelevant_comfort_audio` dictionary)
3. **Do NOT protect**: These should be cleaned out, not preserved

---

## Per-Insurer Trim Breakdown

### QUALITAS (Most Common)
```
M SPORT: 1,014
L PREMIUM: 15
TYPE S: 6
C SPORT: 5
TYPE-S: 4
V SPORT: 3
C PREMIUM: 1
```

### ZURICH
```
M SPORT: 1,270 ⚠️ Highest M SPORT count
TYPE S: 10
V LUXURY: 6
A SPORT: 4
A LUXURY: 4
I SPORT: 4
V PREMIUM: 3
```

### HDI
```
M SPORT: 1,484 ⚠️ Highest M SPORT count
S SPORT: 20
I SPORT: 12
TYPE S: 10
I PREMIUM: 6
E SPORT: 3
F ELEGANCE: 3
```

### AXA (Most Diverse - 19 unique trims!)
```
M SPORT: 306
I SPORT: 68
I GRAND TOURING: 26 ⚠️ Only insurer with this pattern
I TOURING: 11
S SPORT: 10
R SPORT: 6
TYPE S: 3
F SPORT: 3
L PREMIUM: 2
R LUXURY: 2
K SPORT: 2
T SPORT: 1
A SPORT: 1
V LUXURY: 1
E PREMIUM: 1
C PREMIUM: 1
E SELECT: 1
TYPE-R: 1
K ELEGANCE: 1
```

### ANA
```
M SPORT: 806
S SPORT: 8
TYPE S: 6
TYPE-S: 4
N LUXURY: 3
```

### ATLAS (Strong Mazda I-series presence)
```
M SPORT: 920
I SPORT: 28
I TOURING: 23
I LUXURY: 16
I PREMIUM: 14
TYPE S: 5
TYPE-S: 3
A PREMIUM: 3
L PREMIUM: 2
K PREMIUM: 2
A SPORT: 2
X SPORT: 1
```

### ELPOTOSI (Diesel trims present)
```
M SPORT: 308
S SPORT: 20
D PREMIUM: 16 ⚠️ Diesel trim
D SPORT: 14 ⚠️ Diesel trim
D ELEGANCE: 12 ⚠️ Diesel trim
I LUXURY: 8
I SPORT: 6
L SPORT: 5
E LUXURY: 1
E SPORT: 1
C PREMIUM: 1
TYPE R: 1
```

### BX
```
M SPORT: 804
S SPORT: 16
TYPE S: 5
G ELEGANCE: 4
F ELEGANCE: 3
C SPORT: 3
L PREMIUM: 1
A SPORT: 1
```

### GNP
```
M SPORT: 828
I PREMIUM: 20
A SPORT: 14
S SPORT: 12
C PREMIUM: 9
E SPORT: 4
I SPORT: 2
```

### CHUBB (Honda R-series present)
```
M SPORT: 958
S SPORT: 22
R TOURING: 14 ⚠️ Honda trim
C PREMIUM: 12
TYPE-S: 6
R SPORT: 2
```

---

## Implementation: Enhanced Trim Protection Function

```javascript
/**
 * CORRECTED: Protects actual vehicle trims (40 patterns)
 * Transmission specs (STRONIC, XTRONIC) are NOT protected - they go to removal dictionary
 */
function protectTrims(version) {
  if (!version) return version;

  // Hyphenated trims (keep existing A-SPEC, S-LINE, etc. + add TYPE-R)
  const PROTECTED_HYPHENATED_TRIMS = [
    'A-SPEC', 'A-SPECH',           // Acura
    'TYPE-S', 'TYPE-R',             // Honda/Acura
    'S-LINE', 'R-LINE',             // Audi/VW (NOT S-TRONIC!)
    'M-SPORT',                       // BMW hyphenated variant
    'E-TRON',                        // Audi electric
    'X-DRIVE',                       // BMW AWD
    // NOTE: S-TRONIC, X-TRONIC, Q-TRONIC are NOT here - they're transmission specs
  ];

  // Space-separated trims - THE COMPLETE LIST
  const PROTECTED_SPACED_TRIMS = [
    // M-series (critical - 8,698 occurrences)
    'M SPORT', 'M LUXURY', 'M PREMIUM',

    // I-series (Mazda - 244 total occurrences)
    'I GRAND TOURING',  // ← User specifically requested (26 occurrences)
    'I TOURING',
    'I SPORT',
    'I LUXURY',
    'I PREMIUM',

    // R-series (Honda - 24 total)
    'R TOURING',
    'R SPORT',
    'R LUXURY',

    // S-series (108 total)
    'S SPORT',
    'S LUXURY',
    'S PREMIUM',
    'S DESIGN',

    // TYPE series (space-separated variants)
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

    // Diesel trims (D-series - 42 total)
    'D PREMIUM', 'D SPORT', 'D ELEGANCE',

    // Other specific trims
    'E SELECT',
  ];

  let protected = version;

  // Protect hyphenated trims
  PROTECTED_HYPHENATED_TRIMS.forEach(trim => {
    const placeholder = trim.replace(/-/g, '_DASH_');
    protected = protected.replace(new RegExp(`\\b${trim}\\b`, 'gi'), placeholder);
  });

  // Protect spaced trims (with multi-space handling)
  PROTECTED_SPACED_TRIMS.forEach(trim => {
    const placeholder = trim.replace(/\s+/g, '_SPACE_');
    const pattern = trim.replace(/\s+/g, '\\s+'); // Handles M SPORT, M  SPORT, etc.
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

---

## Implementation: Transmission Spec Handling

Add these to the removal dictionary (NOT to trim protection):

```javascript
const QUALITAS_NORMALIZATION_DICTIONARY = {
  irrelevant_comfort_audio: [
    // ... existing specs ...

    // Transmission specs (use for inference, then remove)
    "STRONIC",        // Audi DSG (1,316 total occurrences)
    "S-TRONIC",       // Audi DSG hyphenated variant (316)
    "XTRONIC",        // Nissan CVT (8)
    "X-TRONIC",       // Nissan CVT hyphenated (1)
    "Q-TRONIC",       // Infiniti auto (2)

    // ... rest of specs ...
  ],
};
```

### Transmission Inference Logic

Before removing these specs, use them to infer transmission type:

```javascript
function inferTransmission(version, transmisionCode) {
  // If transmission already set from database column, use it
  if (transmisionCode && transmisionCode !== '' && transmisionCode !== '0') {
    return mapTransmissionCode(transmisionCode);
  }

  // Infer from version string
  const versionUpper = version.toUpperCase();

  // These transmission specs indicate AUTO
  if (/\b(STRONIC|S-TRONIC|XTRONIC|X-TRONIC|Q-TRONIC|CVT|TIPTRONIC|DSG|PDK|AUTOMATICO|AUTOMATICA|AUTO|AUT)\b/i.test(versionUpper)) {
    return 'AUTO';
  }

  if (/\b(MANUAL|STD|ESTANDAR)\b/i.test(versionUpper)) {
    return 'MANUAL';
  }

  return null; // Unknown
}
```

---

## Per-Insurer Implementation Summary

| Insurer | Unique Trims | Must Include | Transmission Specs to Remove |
|---------|--------------|--------------|------------------------------|
| **Qualitas** | 7 | M SPORT, L PREMIUM, TYPE S, C SPORT, V SPORT | STRONIC (293), S-TRONIC (144) |
| **Zurich** | 7 | M SPORT, TYPE S, V LUXURY, A SPORT, A LUXURY, I SPORT | Q-TRONIC (2), STRONIC (1) |
| **HDI** | 7 | M SPORT, S SPORT, I SPORT, TYPE S, I PREMIUM, E SPORT, F ELEGANCE | STRONIC (118), S-TRONIC (6) |
| **AXA** | 19 | M SPORT, I SPORT, **I GRAND TOURING**, I TOURING, S SPORT, R SPORT, F SPORT | STRONIC (289), XTRONIC (8), X-TRONIC (1) |
| **ANA** | 5 | M SPORT, S SPORT, TYPE S, N LUXURY | STRONIC (22), S-TRONIC (2) |
| **Atlas** | 12 | M SPORT, I SPORT, I TOURING, I LUXURY, I PREMIUM, TYPE S, A PREMIUM, L PREMIUM, K PREMIUM | STRONIC (33), S-TRONIC (12) |
| **El Potosí** | 11 | M SPORT, S SPORT, **D PREMIUM, D SPORT, D ELEGANCE**, I LUXURY, I SPORT, L SPORT | STRONIC (108), S-TRONIC (3) |
| **BX** | 8 | M SPORT, S SPORT, TYPE S, G ELEGANCE, F ELEGANCE, C SPORT, L PREMIUM | STRONIC (581) ⚠️ Highest count |
| **GNP** | 6 | M SPORT, I PREMIUM, A SPORT, S SPORT, C PREMIUM, E SPORT | STRONIC (20) |
| **Chubb** | 6 | M SPORT, S SPORT, **R TOURING**, C PREMIUM, R SPORT | None found |

---

## Key Corrections from Previous Analysis

### ❌ REMOVED from Trim Protection
- S-TRONIC → Moved to removal dictionary (transmission spec)
- Q-TRONIC → Moved to removal dictionary (transmission spec)
- XTRONIC/X-TRONIC → Moved to removal dictionary (transmission spec)

### ✅ ADDED to Trim Protection
- **I GRAND TOURING** (26 occurrences - AXA only)
- All letter + SPORT/LUXURY/PREMIUM/ELEGANCE combinations found in data
- Diesel trims: D PREMIUM, D SPORT, D ELEGANCE
- Honda R-series: R TOURING, R SPORT, R LUXURY
- Mazda I-series: I GRAND TOURING, I TOURING, I SPORT, I LUXURY, I PREMIUM

---

## Testing Priority

### Critical Path Testing
1. **M SPORT** (8,698 occurrences) - Test with all insurers
2. **I GRAND TOURING** (26 occurrences) - Test with AXA specifically
3. **STRONIC removal** (1,643 total) - Verify transmission inference works first
4. **I-series trims** (244 total) - Test with AXA, Atlas, HDI, El Potosí, GNP

### Sample Test Cases
```javascript
// Trim protection tests
{ input: "M SPORT 2.0L 150HP", expected_contains: "M SPORT" }
{ input: "I GRAND TOURING 2.5L", expected_contains: "I GRAND TOURING" }  // ← NEW
{ input: "I TOURING 2.0L", expected_contains: "I TOURING" }
{ input: "D PREMIUM DIESEL 2.0L", expected_contains: "D PREMIUM" }
{ input: "R TOURING 2.4L", expected_contains: "R TOURING" }

// Transmission spec removal tests
{ input: "ADVANCE STRONIC 2.0L", expected_not_contains: "STRONIC", expected_transmission: "AUTO" }
{ input: "LUXURY S-TRONIC 1.8L", expected_not_contains: "S-TRONIC", expected_transmission: "AUTO" }
{ input: "PREMIUM XTRONIC CVT", expected_not_contains: "XTRONIC", expected_transmission: "AUTO" }
```

---

## Success Metrics (Revised)

- ✅ All 40 trim patterns preserved in version field
- ✅ All transmission specs (STRONIC, XTRONIC, Q-TRONIC) removed after inference
- ✅ Transmission correctly inferred as AUTO when these specs present
- ✅ "I GRAND TOURING" specifically preserved (AXA)
- ✅ D-series diesel trims preserved (El Potosí)
- ✅ R-series Honda trims preserved (Chubb, AXA)
- ✅ M SPORT remains most protected pattern (8,698 occurrences)
