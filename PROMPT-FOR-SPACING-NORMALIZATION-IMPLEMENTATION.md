# Prompt for AI Assistant - Spacing Normalization Implementation

## Context

I need help modifying a vehicle normalization script for an n8n workflow. This file is part of an ETL system that normalizes vehicle data from insurance companies before sending it to a Supabase database for matching via token overlap.

We've identified spacing inconsistencies in version strings (e.g., "M SPORT" vs "MSPORT") that are causing token fragmentation and match failures. I need to add inline spacing normalization code to fix this.

**Important Architecture Notes:**
- This code runs in an **independent n8n workflow** (Code Node)
- **NO imports/requires** are allowed - all code must be inline
- Each insurer has their own separate file and workflow
- The file must remain completely self-contained

## Documentation Reference

Please read these documentation files for complete context:
1. `ANALISIS-SPACING-ISSUES.md` - Problem analysis and patterns identified
2. `SOLUCION-SPACING-NORMALIZATION.md` - Technical solution with code templates
3. `SPACING-NORMALIZATION-SUMMARY.md` - Executive summary

## Task

Modify the normalization file for **[INSURER_NAME]** to add spacing normalization.

**File to modify:** `src/insurers/[insurer]/[insurer]-codigo-de-normalizacion.js`

## Changes Required

### Step 1: Add Spacing Normalization Configuration

Add this complete block **AFTER** the `const crypto = require("crypto");` line and **BEFORE** any existing configuration:

```javascript
// ============================================================================
// SPACING NORMALIZATION CONFIGURATION
// Added: 2025-10-22
// Issue: Spacing inconsistencies causing token overlap failures
// Patterns: M SPORT, X DRIVE, URBAN LINE, SPORT LINE, X LINE, M COMPETITION
// ============================================================================

const SPACING_NORMALIZATION_PATTERNS = [
  // HIGH Priority patterns (125+ occurrences)
  { regex: /\bM\s+SPORT\b/gi, placeholder: "__M_SPORT__", canonical: "M-SPORT" },
  { regex: /\bX\s+DRIVE\b/gi, placeholder: "__X_DRIVE__", canonical: "XDRIVE" },
  { regex: /\bURBAN\s+LINE\b/gi, placeholder: "__URBAN_LINE__", canonical: "URBAN-LINE" },
  { regex: /\bSPORT\s+LINE\b/gi, placeholder: "__SPORT_LINE__", canonical: "SPORT-LINE" },

  // MEDIUM Priority patterns (7-10 occurrences)
  { regex: /\bX\s+LINE\b/gi, placeholder: "__X_LINE__", canonical: "X-LINE" },
  { regex: /\bM\s+COMPETITION\b/gi, placeholder: "__M_COMP__", canonical: "M-COMPETITION" },

  // Additional protected patterns (already standardized in some files)
  { regex: /\bA[\s-]?SPEC\b/gi, placeholder: "__A_SPEC__", canonical: "A-SPEC" },
  { regex: /\bTYPE[\s-]?S\b/gi, placeholder: "__TYPE_S__", canonical: "TYPE-S" },
  { regex: /\bTYPE[\s-]?R\b/gi, placeholder: "__TYPE_R__", canonical: "TYPE-R" },
  { regex: /\bS[\s-]?LINE\b/gi, placeholder: "__S_LINE__", canonical: "S-LINE" },
  { regex: /\bR[\s-]?LINE\b/gi, placeholder: "__R_LINE__", canonical: "R-LINE" },
  { regex: /\bE[\s-]?TRON\b/gi, placeholder: "__E_TRON__", canonical: "E-TRON" },
  { regex: /\bBI[\s-]?TURBO\b/gi, placeholder: "__BI_TURBO__", canonical: "BI-TURBO" },
];

/**
 * Protect spacing-sensitive patterns by replacing with placeholders
 * This prevents them from being affected by token removal
 */
function applySpacingProtection(text) {
  if (!text) return text;
  let result = text;
  SPACING_NORMALIZATION_PATTERNS.forEach(({ regex, placeholder }) => {
    result = result.replace(regex, placeholder);
  });
  return result;
}

/**
 * Restore protected patterns with their canonical normalized forms
 * This ensures consistent spacing across all insurers
 */
function restoreSpacingNormalized(text) {
  if (!text) return text;
  let result = text;
  SPACING_NORMALIZATION_PATTERNS.forEach(({ placeholder, canonical }) => {
    result = result.replace(new RegExp(placeholder, 'g'), canonical);
  });
  return result;
}

// ============================================================================
// END SPACING NORMALIZATION CONFIGURATION
// ============================================================================
```

### Step 2: Modify the cleanVersion() Function

Locate the `cleanVersion()` or similar function that processes the version string. It typically looks like:

```javascript
function cleanVersion(versionOriginal) {
  if (!versionOriginal) return "";

  let cleaned = versionOriginal.toUpperCase().trim();

  // ... existing cleaning code ...

  return cleaned;
}
```

**Modify it to add spacing protection:**

```javascript
function cleanVersion(versionOriginal) {
  if (!versionOriginal) return "";

  let cleaned = versionOriginal.toUpperCase().trim();

  // ===== NUEVO: Protect spacing patterns FIRST =====
  cleaned = applySpacingProtection(cleaned);

  // ... ALL existing cleaning code stays here unchanged ...
  // (remove irrelevant tokens, clean multiple spaces, etc.)

  // ===== NUEVO: Restore with canonical forms LAST =====
  cleaned = restoreSpacingNormalized(cleaned);

  return cleaned;
}
```

**CRITICAL:**
- Add `applySpacingProtection()` call **IMMEDIATELY after** `toUpperCase().trim()`
- Add `restoreSpacingNormalized()` call **AT THE VERY END** before `return`
- DO NOT modify any existing cleaning logic between these calls

### Step 3: Add Test Cases (Optional but Recommended)

Add these test cases at the **very end of the file** (commented out):

```javascript
// ============================================================================
// SPACING NORMALIZATION TEST CASES
// Uncomment and run to validate changes
// ============================================================================
/*
function testSpacingNormalization() {
  const testCases = [
    {
      name: "M SPORT normalization",
      input: "BMW 118I M SPORT AUTOMATICA 3PTAS",
      expectedContains: "M-SPORT",
      expectedNotContains: "M SPORT"
    },
    {
      name: "X DRIVE normalization",
      input: "BMW IX2 X DRIVE 30 EV AUTOMATICA",
      expectedContains: "XDRIVE",
      expectedNotContains: "X DRIVE"
    },
    {
      name: "URBAN LINE normalization",
      input: "BMW 118I URBAN LINE STD 5PTAS",
      expectedContains: "URBAN-LINE",
      expectedNotContains: "URBAN LINE"
    },
    {
      name: "SPORT LINE normalization",
      input: "BMW 118I SPORT LINE AUTOMATICA",
      expectedContains: "SPORT-LINE",
      expectedNotContains: "SPORT LINE"
    },
    {
      name: "No false positive on MINI COOPER S",
      input: "MINI COOPER S CHILI AUTOMATICA",
      expectedContains: "CHILI",
      expectedNotContains: "S-CHILI"
    }
  ];

  let passed = 0;
  let failed = 0;

  console.log("\\n" + "=".repeat(80));
  console.log("SPACING NORMALIZATION TEST RESULTS");
  console.log("=".repeat(80) + "\\n");

  testCases.forEach((test, index) => {
    const output = cleanVersion(test.input);
    let success = true;

    if (!output.includes(test.expectedContains)) {
      console.error(`❌ Test ${index + 1} FAILED: ${test.name}`);
      console.error(`   Missing: "${test.expectedContains}"`);
      console.error(`   Input:   "${test.input}"`);
      console.error(`   Output:  "${output}"`);
      success = false;
    }

    if (output.includes(test.expectedNotContains)) {
      console.error(`❌ Test ${index + 1} FAILED: ${test.name}`);
      console.error(`   Should not contain: "${test.expectedNotContains}"`);
      console.error(`   Input:  "${test.input}"`);
      console.error(`   Output: "${output}"`);
      success = false;
    }

    if (success) {
      console.log(`✅ Test ${index + 1} PASSED: ${test.name}`);
      passed++;
    } else {
      failed++;
    }
  });

  console.log(`\\n${"=".repeat(80)}`);
  console.log(`Results: ${passed} passed, ${failed} failed`);
  console.log("=".repeat(80));

  return failed === 0;
}

// Uncomment to run tests:
// testSpacingNormalization();
*/
```

## Validation Steps

After making the changes:

1. **Read the modified file** and verify:
   - Configuration block is added correctly
   - `cleanVersion()` has both new function calls
   - No syntax errors
   - Existing logic is unchanged

2. **Show me:**
   - The configuration block you added (lines X-Y)
   - The modified `cleanVersion()` function
   - Confirmation that tests were added

3. **Explain:**
   - What the spacing normalization does
   - Why we protect patterns with placeholders
   - What patterns are being normalized

## Expected Behavior

**BEFORE changes:**
- Input: `"BMW 118I M SPORT AUTOMATICA"`
- Tokens: `["BMW", "118I", "M", "SPORT", "AUTOMATICA"]`
- Problem: "M" and "SPORT" are separate tokens

**AFTER changes:**
- Input: `"BMW 118I M SPORT AUTOMATICA"`
- Processing: `"BMW 118I __M_SPORT__ AUTOMATICA"` → clean → `"BMW 118I M-SPORT AUTOMATICA"`
- Tokens: `["BMW", "118I", "M-SPORT", "AUTOMATICA"]`
- Fixed: "M-SPORT" is a single token

## Important Notes

- **DO NOT remove** any existing code
- **DO NOT modify** existing cleaning logic
- **ONLY ADD** the two function calls to `cleanVersion()`
- **PRESERVE** all comments and structure
- The regex patterns use `\b` word boundaries to avoid matching inside words
- The `[\s-]?` pattern matches space OR hyphen OR nothing (handles all variants)

## Files to Reference

If you need examples, check:
- `src/insurers/zurich/zurich-codigo-de-normalizacion.js` - Good example structure
- `src/insurers/ana/ana-codigo-de-normalizacion.js` - Another reference
- `SOLUCION-SPACING-NORMALIZATION.md` - Complete before/after examples

## Questions to Ask Me

Before making changes, please ask:
1. What is the current structure of this file's `cleanVersion()` function?
2. Are there any existing spacing normalization patterns already in the code?
3. Should I preserve any specific formatting or comments?

## Success Criteria

The modification is successful if:
- ✅ File still runs without errors
- ✅ All existing functionality is preserved
- ✅ Test cases pass (when uncommented)
- ✅ Version strings now contain "M-SPORT", "XDRIVE", "URBAN-LINE" instead of spaced variants
- ✅ Code is readable and well-commented

---

## Ready to Start?

Please confirm you understand the task and then:
1. Read the current file: `src/insurers/[insurer]/[insurer]-codigo-de-normalizacion.js`
2. Show me the current `cleanVersion()` function
3. Ask any clarifying questions
4. Make the modifications
5. Validate the changes
