# Additional Model Normalization Fixes

## Issue Discovered

After initial implementation, additional contamination patterns were found:

### 1. Single Letter Suffixes in Modelo
**Examples**:
- `SILVERADO C 1500` → should be `SILVERADO 1500`
- `SILVERADO C 2500` → should be `SILVERADO 2500`

**Impact**: 650+ records with "C" suffix, 723+ with "M", 615+ with "S", etc.

### 2. Trim/Config Codes in Modelo
**Examples**:
- `SILVERADO 1500 CAB REG` → should be `SILVERADO 1500`
- `SILVERADO 1500 CAB.REG.` → should be `SILVERADO 1500`
- `RAM 2500 CREW CAB` → should be `RAM 2500`
- `RAM 2500 QUAD CAB` → should be `RAM 2500`

### 3. Additional Trim Indicators
**Patterns to remove**:
- `CAB REG`, `CAB.REG.`, `CAB.REGULAR`
- `DR`, `WT` (trim codes)

---

## Enhanced normalizeModelo() Function

Add the following to the existing `normalizeModelo()` function:

```javascript
function normalizeModelo(marca, modelo) {
  if (!modelo || typeof modelo !== "string") return "";

  let normalized = modelo.toUpperCase().trim();
  const marcaUpper = (marca || "").toUpperCase().trim();

  // Remove generic prefixes (PICK UP, CAMIONETA, VAN, TRUCK)
  normalized = normalized.replace(/^PICK\s*UP\s+/gi, "");
  normalized = normalized.replace(/^PICK-UP\s+/gi, "");
  normalized = normalized.replace(/^CAMIONETA\s+/gi, "");
  normalized = normalized.replace(/^VAN\s+/gi, "");
  normalized = normalized.replace(/^TRUCK\s+/gi, "");

  // Remove brand name if repeated in model field
  if (marcaUpper) {
    const brandPattern = new RegExp(`^${marcaUpper.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s+`, 'gi');
    normalized = normalized.replace(brandPattern, "");
  }

  // ========== NEW: Remove single letter suffixes (trim codes) ==========
  // Remove patterns like "C 1500", "M 350", "S 90" but preserve "TYPE-S", "A-SPEC", etc.
  // Must have a number following to be considered a trim code
  normalized = normalized.replace(/\s+([A-Z])\s+(\d)/g, " $2");

  // ========== NEW: Remove cab type and configuration codes ==========
  normalized = normalized.replace(/\s+CAB\.?\s*REG\.?(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+CAB\.?\s*REGULAR(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+CREW\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+QUAD\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+MEGA\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+SUPER\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+KING\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+DOBLE\s+CABINA(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+SENCILLA\s+CABINA(?:\s+|$)/gi, " ");

  // ========== NEW: Remove standalone trim codes at end ==========
  normalized = normalized.replace(/\s+(DR|WT|SL|SLE|SLT)$/gi, "");

  // Remove trim level suffixes from model field (keep existing)
  normalized = normalized.replace(/\s+(CREW|QUAD|MEGA|SUPER|KING)\s+CAB$/gi, "");
  normalized = normalized.replace(/\s+(DOBLE|SENCILLA)\s+CABINA$/gi, "");

  // Clean up multiple spaces and trim
  normalized = normalized.replace(/\s+/g, " ").trim();

  return normalized;
}
```

---

## Expected Results After Enhancement

### Before Enhancement
```
SILVERADO C 1500     → hash based on "SILVERADO C 1500"
SILVERADO 1500       → hash based on "SILVERADO 1500"
Result: Different hashes, no grouping ❌
```

### After Enhancement
```
SILVERADO C 1500     → normalized to "SILVERADO 1500" → same hash
SILVERADO 1500       → normalized to "SILVERADO 1500" → same hash
Result: Same hash, grouped together ✅
```

### Additional Examples
```
Before                          →  After
──────────────────────────────────────────────────────────
SILVERADO C 2500                →  SILVERADO 2500
SILVERADO 1500 CAB REG          →  SILVERADO 1500
SILVERADO 1500 CAB.REG.         →  SILVERADO 1500
SILVERADO 2500 CAB.REGULAR      →  SILVERADO 2500
SILVERADO 3500 DR               →  SILVERADO 3500
SILVERADO 3500 WT               →  SILVERADO 3500
RAM 2500 CREW CAB               →  RAM 2500
RAM 2500 QUAD CAB               →  RAM 2500
RAM MEGA CAB                    →  RAM
```

---

## Implementation Priority

**HIGH PRIORITY** - Should be applied immediately after the initial fix:

1. The "C" pattern affects 650+ records
2. CAB variations affect hundreds more
3. These patterns prevent proper grouping just like "PICK UP"

---

## Testing

```javascript
// Test cases
console.assert(normalizeModelo("CHEVROLET", "SILVERADO C 1500") === "SILVERADO 1500");
console.assert(normalizeModelo("CHEVROLET", "SILVERADO 1500 CAB REG") === "SILVERADO 1500");
console.assert(normalizeModelo("DODGE", "RAM 2500 CREW CAB") === "RAM 2500");
console.assert(normalizeModelo("CHEVROLET", "SILVERADO 3500 WT") === "SILVERADO 3500");
```

---

## Action Required

Apply this enhanced version to all 11 insurer files to replace the current `normalizeModelo()` function.
