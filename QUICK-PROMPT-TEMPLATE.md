# Quick Prompt Template - Copy & Paste for Each Insurer

Use this shortened version if you want a quick prompt. Just replace `[INSURER]` with the actual insurer name.

---

## Copy This Prompt:

```
I need help adding spacing normalization to a vehicle ETL normalization script.

**Context:**
- File: src/insurers/[INSURER]/[INSURER]-codigo-de-normalizacion.js
- This runs in an independent n8n workflow (NO imports allowed)
- Problem: Spacing issues like "M SPORT" vs "MSPORT" cause token matching failures

**Task:**
Add inline spacing normalization code to fix patterns like:
- "M SPORT" → "M-SPORT"
- "X DRIVE" → "XDRIVE"
- "URBAN LINE" → "URBAN-LINE"
- "SPORT LINE" → "SPORT-LINE"

**Step 1:** Read the documentation first:
- SOLUCION-SPACING-NORMALIZATION.md (section: "Template Completo - Copy/Paste Ready")
- Look for the configuration block and helper functions

**Step 2:** Read the current file:
- src/insurers/[INSURER]/[INSURER]-codigo-de-normalizacion.js
- Show me the current cleanVersion() function

**Step 3:** Make these changes:

1. Add the SPACING_NORMALIZATION_PATTERNS configuration block (see docs)
2. Add applySpacingProtection() function (see docs)
3. Add restoreSpacingNormalized() function (see docs)
4. Modify cleanVersion() to call:
   - applySpacingProtection(cleaned) RIGHT AFTER toUpperCase().trim()
   - restoreSpacingNormalized(cleaned) RIGHT BEFORE return

**CRITICAL:**
- Do NOT use require() or imports
- Do NOT modify existing cleaning logic
- ONLY add the two function calls to cleanVersion()
- ALL code must be inline in the file

**Validation:**
After changes, test with: "BMW 118I M SPORT AUTOMATICA"
Expected output should contain "M-SPORT" not "M SPORT"

Please read the docs, show me the current cleanVersion(), then make the modifications.
```

---

## For Quick Reference - The Code to Add:

**Configuration Block (add after `const crypto = require("crypto");`):**

```javascript
// ============================================================================
// SPACING NORMALIZATION - Added 2025-10-22
// ============================================================================
const SPACING_NORMALIZATION_PATTERNS = [
  { regex: /\bM\s+SPORT\b/gi, placeholder: "__M_SPORT__", canonical: "M-SPORT" },
  { regex: /\bX\s+DRIVE\b/gi, placeholder: "__X_DRIVE__", canonical: "XDRIVE" },
  { regex: /\bURBAN\s+LINE\b/gi, placeholder: "__URBAN_LINE__", canonical: "URBAN-LINE" },
  { regex: /\bSPORT\s+LINE\b/gi, placeholder: "__SPORT_LINE__", canonical: "SPORT-LINE" },
  { regex: /\bX\s+LINE\b/gi, placeholder: "__X_LINE__", canonical: "X-LINE" },
  { regex: /\bM\s+COMPETITION\b/gi, placeholder: "__M_COMP__", canonical: "M-COMPETITION" },
  { regex: /\bA[\s-]?SPEC\b/gi, placeholder: "__A_SPEC__", canonical: "A-SPEC" },
  { regex: /\bTYPE[\s-]?S\b/gi, placeholder: "__TYPE_S__", canonical: "TYPE-S" },
  { regex: /\bTYPE[\s-]?R\b/gi, placeholder: "__TYPE_R__", canonical: "TYPE-R" },
  { regex: /\bS[\s-]?LINE\b/gi, placeholder: "__S_LINE__", canonical: "S-LINE" },
  { regex: /\bR[\s-]?LINE\b/gi, placeholder: "__R_LINE__", canonical: "R-LINE" },
  { regex: /\bE[\s-]?TRON\b/gi, placeholder: "__E_TRON__", canonical: "E-TRON" },
  { regex: /\bBI[\s-]?TURBO\b/gi, placeholder: "__BI_TURBO__", canonical: "BI-TURBO" },
];

function applySpacingProtection(text) {
  if (!text) return text;
  let result = text;
  SPACING_NORMALIZATION_PATTERNS.forEach(({ regex, placeholder }) => {
    result = result.replace(regex, placeholder);
  });
  return result;
}

function restoreSpacingNormalized(text) {
  if (!text) return text;
  let result = text;
  SPACING_NORMALIZATION_PATTERNS.forEach(({ placeholder, canonical }) => {
    result = result.replace(new RegExp(placeholder, 'g'), canonical);
  });
  return result;
}
// ============================================================================
```

**Modifications to cleanVersion():**

```javascript
function cleanVersion(versionOriginal) {
  if (!versionOriginal) return "";
  let cleaned = versionOriginal.toUpperCase().trim();

  // NEW: Protect spacing patterns
  cleaned = applySpacingProtection(cleaned);

  // ... ALL existing code stays here ...

  // NEW: Restore with canonical forms
  cleaned = restoreSpacingNormalized(cleaned);

  return cleaned;
}
```

---

## Insurers to Process (Checklist):

- [ ] ANA
- [ ] ATLAS
- [ ] AXA
- [ ] BX
- [ ] CHUBB
- [ ] EL POTOSÍ
- [ ] GNP
- [ ] HDI
- [ ] MAPFRE
- [ ] QUALITAS
- [ ] ZURICH

**Time estimate:** 1-2 hours per insurer (read + modify + test)
