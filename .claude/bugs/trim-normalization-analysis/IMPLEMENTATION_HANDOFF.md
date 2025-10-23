# Implementation Handoff: Trim Normalization & Spec Cleanup

## Task Overview

You will be implementing systematic improvements to **11 insurance company ETL normalization scripts** to enhance vehicle trim pattern preservation and garbage spec removal. This work is based on comprehensive analysis of **385,000+ vehicle records** across all insurers.

## Context Documents

**Primary Reference**: `/mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl/.claude/bugs/trim-normalization-analysis/comprehensive-analysis.md`

This document contains:
- Complete per-insurer findings with specific examples from real data
- 37 unique trim patterns identified (10 protected, 27 need addition)
- Missing garbage specs per insurer
- Processing order validation and recommendations
- Cross-insurer spec variation mappings

**Related Files**:
- Origin data: `/data/origin/{insurer}-origin.csv`
- Normalization scripts: `/src/insurers/{insurer}/{insurer}-codigo-de-normalizacion.js`
- SQL functions: `/src/supabase/funciones-homologacion-v2.8.1-trims-expanded.sql`

## Critical Findings Summary

### 🚨 Highest Priority Issues

1. **M SPORT** (2,636 occurrences) - Space-separated variant NOT protected in ANY script
2. **Mapfre** - Complete data extraction failure, version field empty
3. **Atlas** - Marca contaminating version field ("ACURA ILX PREMIUM" instead of "PREMIUM")
4. **S-TRONIC** (316 occurrences) - Audi transmission trim unprotected
5. **X-DRIVE** (70 occurrences) - BMW all-wheel drive trim unprotected

### Key Stats
- **27 trim patterns** need to be added across all scripts
- **~30 garbage specs** missing from removal dictionaries
- **4 special handlers** needed (Atlas marca stripping, El Potosí concatenations, GNP punctuation, AXA placeholders)
- **1 data extraction fix** required (Mapfre)

## Implementation Approach

### Principles

1. **Each insurer script is independent** - No shared functions (n8n limitation)
2. **Preserve existing logic** - Add to, don't replace
3. **Test incrementally** - One insurer at a time
4. **Maintain processing order** - Follow documented sequence
5. **Use exact patterns** - Reference comprehensive-analysis.md for specifics

### Standard Implementation Pattern

For each of the 11 normalization scripts, you will:

#### Step 1: Add Enhanced Trim Protection

Add/expand the trim protection function to handle BOTH hyphenated and space-separated patterns:

```javascript
function protectTrims(version) {
  if (!version) return version;

  // HYPHENATED TRIMS (existing + additions)
  const PROTECTED_HYPHENATED_TRIMS = [
    'A-SPEC', 'A-SPECH',           // Acura (including typo)
    'TYPE-S', 'TYPE-R',             // Honda/Acura
    'S-LINE', 'R-LINE',             // Audi/VW
    'M-SPORT',                       // BMW (hyphenated)
    'E-TRON', 'E-TURBO',            // Audi electric/turbo
    'S-TRONIC', 'Q-TRONIC',         // Audi/Infiniti transmissions ← ADD
    'X-DRIVE',                       // BMW AWD ← ADD
    'A-SEMI',                        // Semi-automatic ← ADD
  ];

  // SPACE-SEPARATED TRIMS (NEW - critical addition)
  const PROTECTED_SPACED_TRIMS = [
    'M SPORT',                       // ← CRITICAL - 2,636 total occurrences
    'TYPE S',                        // Honda (space variant)
    'I TOURING', 'I SPORT', 'I LUXURY', 'I PREMIUM',  // Mazda I-series ← ADD
    'R TOURING', 'R SPORT',          // Honda R-series ← ADD
    'S SPORT', 'E SPORT', 'A SPORT', 'T SPORT', 'X SPORT',  // Sport variants ← ADD
    'L PREMIUM', 'N LUXURY', 'V LUXURY', 'A LUXURY',  // Luxury trims ← ADD
    'D PREMIUM', 'D SPORT', 'D ELEGANCE',  // Diesel trims ← ADD
    'E PREMIUM', 'C PREMIUM', 'E SELECT',  // Premium variants ← ADD
    'S DESIGN',                      // Seat/Audi ← ADD
  ];

  let protected = version;

  // Protect hyphenated (exact match)
  PROTECTED_HYPHENATED_TRIMS.forEach(trim => {
    const placeholder = trim.replace(/-/g, '_DASH_');
    protected = protected.replace(new RegExp(`\\b${trim}\\b`, 'gi'), placeholder);
  });

  // Protect spaced (multi-space handling)
  PROTECTED_SPACED_TRIMS.forEach(trim => {
    const placeholder = trim.replace(/\s+/g, '_SPACE_');
    const pattern = trim.replace(/\s+/g, '\\s+'); // Match M SPORT, M  SPORT, M   SPORT
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

**IMPORTANT**: Not all insurers have all trim patterns. Reference the comprehensive-analysis.md document for EACH insurer's specific trim list. Only add trims that appear in that insurer's data.

#### Step 2: Expand Removal Dictionaries

Add missing garbage specs to the `irrelevant_comfort_audio` array. Each insurer has specific gaps - reference comprehensive-analysis.md section for that insurer.

**Universal additions** (add to ALL scripts if not present):
```javascript
"USB",           // Missing from most
"BT",            // Missing from most
"BLUETOOTH",     // Full word variant
```

**Per-Insurer specific** (see comprehensive-analysis.md for complete list):
- Zurich: `"USB", "BT"`
- HDI: `"VP", "QC", "BT", "BLUETOOTH", "CP"`
- AXA: `"BT", "NAVEG", "PIEL", "AC"`
- ANA: `"USB", "PTAS"`
- El Potosí: `"SQ", "CB", "CQ", "CE", "CA", "B/A", "TON", "PIEL"`
- BX: `"BT", "LUJO", "V/P", "CP"`
- GNP: `"C/A", "V.E.", "VE", "AC", "BT"`
- Chubb: `"CB", "CQ", "CA", "CE", "PIEL", "SM", "IMO"`

#### Step 3: Implement Special Handlers (Only for specific insurers)

**Atlas Only** - Strip marca from version:
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
// Call BEFORE any other version processing
```

**El Potosí Only** - Fix concatenations:
```javascript
function fixConcatenations(version) {
  if (!version) return version;
  return version
    .replace(/([A-Z])-SPEC(AUT|MAN|STD)/gi, '$1-SPEC $2')
    .replace(/([A-Z])-LINE(AUT|MAN|STD)/gi, '$1-LINE $2')
    .replace(/M-SPORT(AUT|MAN|STD)/gi, 'M-SPORT $1');
}
// Call BEFORE trim protection
```

**GNP Only** - Normalize punctuation:
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
// Call BEFORE spec removal
```

**AXA Only** - Handle GENERICA placeholder:
```javascript
function handlePlaceholders(record) {
  if (record.version_original === 'GENERICA') {
    return null; // Skip record
  }
  return record;
}
// Call at validation stage
```

#### Step 4: Validate Processing Order

Ensure the processing follows this sequence:

```javascript
// STAGE 1: VALIDATION & INITIAL CLEANUP
validateRecord(record);
handlePlaceholders(record);           // AXA only

// STAGE 2: BRAND/MODEL NORMALIZATION
record.marca = consolidateBrand(record.marca);
record.modelo = cleanBMWModelo(record.marca, record.modelo);
record.modelo = removeSpecsFromModelo(record.modelo);
record.version = stripMarcaFromVersion(record.marca, record.version); // Atlas only

// STAGE 3: VERSION PRE-PROCESSING
record.version = normalizePunctuationVariants(record.version); // GNP only
record.version = fixConcatenations(record.version);            // El Potosí only

// STAGE 4: TRIM PROTECTION
record.version = protectHyphenatedTrims(record.version);
record.version = protectSpacedTrims(record.version);

// STAGE 5: TRANSMISSION MAPPING
record.transmision = mapTransmission(record.version, record.transmision_code);

// STAGE 6: SPEC NORMALIZATION
record.version = normalizeEngineSpecs(record.version);
record.version = normalizeDoors(record.version);
record.version = normalizeOccupants(record.version);

// STAGE 7: GARBAGE REMOVAL
record.version = removeGarbageSpecs(record.version);
record.version = removeBodyTypes(record.version);

// STAGE 8: TRIM RESTORATION
record.version = restoreProtectedTrims(record.version);

// STAGE 9: FINAL CLEANUP
record.version = collapseWhitespace(record.version);
record.version = record.version.trim().toUpperCase();

// STAGE 10: HASH GENERATION
record.hash_comercial = generateHash(...);
record.id_canonico = generateHash(...);
```

## Implementation Order

### Phase 1: High Priority (Implement First)
1. **Qualitas** - 39,715 records, 13 trim patterns, missing CAM TRAS/SPORTSHIFT
2. **Zurich** - 38,984 records, 7 trim patterns, missing USB/BT
3. **HDI** - 38,186 records, 10 trim patterns, multi-space issues, missing VP/QC/BT
4. **ANA** - 36,432 records, 8 trim patterns, missing X-DRIVE critical for BMW

### Phase 2: Medium Priority
5. **Atlas** - 31,229 records, requires marca stripping handler
6. **El Potosí** - 23,040 records, concatenation fixes, largest dictionary
7. **Chubb** - 31,256 records, 7 trim patterns, large dictionary additions
8. **GNP** - 55,486 records (LARGEST), punctuation handler

### Phase 3: Lower Priority
9. **AXA** - 14,424 records (SMALLEST), GENERICA handler
10. **BX** - 39,292 records, fewer changes needed

### Phase 4: Blocked (Fix First)
11. **Mapfre** - 37,346 records, **DATA EXTRACTION BROKEN** - fix query before normalization

## Per-Insurer Quick Reference

Use this table to quickly find what each insurer needs:

| Insurer | Trims to Add | Dictionary Additions | Special Handler | Priority |
|---------|--------------|----------------------|-----------------|----------|
| Qualitas | M SPORT, L PREMIUM, TYPE S, S-TRONIC | CAM TRAS, SPORTSHIFT | None | HIGH |
| Zurich | M SPORT, TYPE S, A SPORT, A LUXURY | USB, BT | None | HIGH |
| HDI | M SPORT, S SPORT, E SPORT, I SPORT | VP, QC, BT, BLUETOOTH, CP | Multi-space regex | HIGH |
| ANA | M SPORT, X-DRIVE, TYPE S, S SPORT, N LUXURY | USB, PTAS | None | HIGH |
| Atlas | M SPORT, I TOURING, I SPORT, I LUXURY, I PREMIUM, S-TRONIC, TYPE S, A-SPECH | None | Strip marca | HIGH |
| El Potosí | M SPORT, D PREMIUM, D SPORT, D ELEGANCE, S SPORT, I LUXURY, I SPORT, X-DRIVE | SQ, CB, CQ, CE, CA, B/A, TON, PIEL | Fix concatenations | HIGH |
| Chubb | M SPORT, R TOURING, S SPORT, R SPORT | CB, CQ, CA, CE, PIEL, SM, IMO | None | HIGH |
| GNP | M SPORT, I PREMIUM, S SPORT, A SPORT | C/A, V.E., VE, AC, BT | Normalize punctuation | MEDIUM |
| AXA | M SPORT, S-DESIGN, T SPORT, L PREMIUM, V LUXURY, E PREMIUM, C PREMIUM, E SELECT | BT, NAVEG, PIEL, AC | Handle GENERICA | MEDIUM |
| BX | M SPORT, S SPORT, TYPE S, L PREMIUM | BT, LUJO, V/P, CP | None | MEDIUM |
| Mapfre | TBD | TBD | Fix extraction query | CRITICAL |

## Testing Requirements

### Unit Tests (Per Script)

After modifying each script, test with these sample inputs:

```javascript
testCases = [
  // Trim protection
  { input: "M SPORT 2.0L 150HP", expected_contains: "M SPORT" },
  { input: "M  SPORT 2.0L", expected_contains: "M SPORT" },  // Multi-space
  { input: "I TOURING 2.5L", expected_contains: "I TOURING" },
  { input: "A-SPEC 1.5L", expected_contains: "A-SPEC" },

  // Garbage removal
  { input: "PREMIUM AA EE CD 4P", expected_not_contains: ["AA", "EE", "CD"] },
  { input: "SPORT USB BT GPS", expected_not_contains: ["USB", "BT", "GPS"] },

  // Special handlers
  { input: "ACURA ILX PREMIUM", insurer: "Atlas", expected_not_starts_with: "ACURA" },
  { input: "A-SPECAUT 1.5L", insurer: "ElPotosi", expected_contains: "A-SPEC AUT" },
  { input: "ADVANCE C/A V.E.", insurer: "GNP", expected_not_contains: ["C/A", "V.E."] },
];
```

### Integration Tests

1. Run modified script against 100-record sample from that insurer's origin CSV
2. Verify:
   - All records process successfully (no errors)
   - Protected trims appear in final version
   - Garbage specs removed
   - Hash generation works
3. Compare token counts before/after (should be similar or improved)

### Validation Queries

After implementation, run these checks:

```sql
-- Check trim preservation
SELECT version, version_tokens_array
FROM catalogo_homologado
WHERE origen_aseguradora = 'QUALITAS'
  AND version LIKE '%M SPORT%'
LIMIT 20;

-- Check garbage spec removal
SELECT version, version_tokens_array
FROM catalogo_homologado
WHERE origen_aseguradora = 'ZURICH'
  AND (version LIKE '%AA%' OR version LIKE '%EE%' OR version LIKE '%CD%')
LIMIT 20;

-- Verify no data loss
SELECT origen_aseguradora, COUNT(*)
FROM catalogo_homologado
GROUP BY origen_aseguradora
ORDER BY origen_aseguradora;
```

## Common Pitfalls to Avoid

1. **Don't protect all trims in all scripts** - Each insurer has different trims in their data. Reference comprehensive-analysis.md for each insurer's specific list.

2. **Don't forget multi-space handling** - "M SPORT" can appear as "M  SPORT" or "M   SPORT" in some insurers' data. Use `\s+` in regex patterns.

3. **Don't skip processing order** - Order matters! Trim protection MUST happen BEFORE garbage removal, or protected trims will be corrupted.

4. **Don't add functions that aren't called** - If you add a helper function, make sure it's actually invoked in the main processing logic.

5. **Don't break existing logic** - These scripts are production-critical. Add to existing patterns, don't replace wholesale.

6. **Don't forget to restore trims** - After protection and processing, trims MUST be restored (placeholders replaced with original characters).

7. **Don't assume dictionaries are complete** - Even after this work, new garbage specs may emerge. Design for extensibility.

## Success Criteria

### Quantitative
- ✅ All 11 scripts modified (10 + Mapfre after extraction fix)
- ✅ 27 new trim patterns protected across scripts
- ✅ ~30 garbage specs added to dictionaries
- ✅ 4 special handlers implemented
- ✅ Zero data loss (all records process)
- ✅ Processing time increase <5%

### Qualitative
- ✅ "M SPORT" appears in final version field, not corrupted to "M" + "SPORT" tokens
- ✅ Garbage specs (AA, EE, CD, USB, BT, etc.) removed from version
- ✅ Version field clean and ready for tokenization
- ✅ No marca contamination in Atlas version field
- ✅ No concatenated trims in El Potosí (A-SPECAUT)
- ✅ Token overlap scores improved for same-vehicle matches

## File Locations

### Normalization Scripts (to modify)
```
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
/src/insurers/mapfre/mapfre-codigo-de-normalizacion.js
```

### Reference Data (for testing)
```
/data/origin/qualitas-origin.csv
/data/origin/zurich-origin.csv
/data/origin/hdi-origin.csv
... (all 11 insurers)
```

### Analysis Document (your guide)
```
/mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl/.claude/bugs/trim-normalization-analysis/comprehensive-analysis.md
```

## Questions & Clarifications

If you encounter ambiguity:

1. **Consult comprehensive-analysis.md first** - It has specific examples from real data for each insurer
2. **Check existing code patterns** - Follow the conventions already in the script
3. **Test with sample data** - Use origin CSV to validate assumptions
4. **Document your decisions** - Add comments explaining non-obvious choices

## Final Notes

- **This is production-critical code** - Test thoroughly before deployment
- **Each script is independent** - Can't share functions due to n8n architecture
- **Prioritize M SPORT** - This single pattern affects 2,636 records across all insurers
- **Don't rush** - Better to implement correctly than quickly
- **Document changes** - Add comments explaining new logic for future maintainers

## Implementation Checklist

For each insurer, verify:

- [ ] Trim protection function added/expanded with insurer-specific patterns
- [ ] Space-separated trims handled (especially M SPORT)
- [ ] Multi-space handling for trims with spacing variations
- [ ] Removal dictionary expanded with insurer-specific garbage specs
- [ ] Special handler implemented (if required for that insurer)
- [ ] Processing order validated and corrected if needed
- [ ] Unit tests pass with sample data
- [ ] Integration test with 100-record sample succeeds
- [ ] No data loss (record count unchanged)
- [ ] Protected trims appear in output
- [ ] Garbage specs removed from output
- [ ] Code commented and documented

Good luck! Reference the comprehensive-analysis.md document frequently - it's your single source of truth.
