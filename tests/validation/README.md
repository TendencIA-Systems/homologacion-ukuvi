# Validation Tests

This directory contains validation tests for the ETL normalization pipeline.

## Brand Consolidation Tests

**File:** `test_brand_consolidation.js`

### Purpose

Validates the `consolidateBrand()` function implementation across all insurer normalization files. This function is critical for ensuring consistent brand names in the master catalog.

### Test Coverage

The test suite validates all 16 entries in the `BRAND_CONSOLIDATION_MAP` plus edge cases:

1. **Suffix Removal (5 tests)**
   - BMW BW → BMW
   - VOLKSWAGEN VW → VOLKSWAGEN
   - CHEVROLET GM → CHEVROLET
   - FORD FR → FORD
   - AUDI II → AUDI

2. **Variant Consolidation (5 tests)**
   - KIA MOTORS → KIA
   - TESLA MOTORS → TESLA
   - MERCEDES BENZ II → MERCEDES BENZ
   - NISSAN II → NISSAN
   - GREAT WALL MOTORS → GREAT WALL

3. **Typo Correction (2 tests)**
   - BERCEDES → MERCEDES BENZ
   - BUIK → BUICK

4. **Invalid Brands (4 tests)**
   - AUTOS → INVALID_BRAND
   - MOTOCICLETAS → INVALID_BRAND
   - MULTIMARCA → INVALID_BRAND
   - LEGALIZADO → INVALID_BRAND

5. **Edge Cases (5 tests)**
   - Pass-through for valid brands not in map
   - Case normalization (lowercase → uppercase)
   - Whitespace trimming
   - Empty/null handling
   - Complete coverage verification

### Running the Tests

```bash
# Run from project root
node tests/validation/test_brand_consolidation.js
```

### Expected Output

```
🧪 Brand Consolidation Validation Tests

======================================================================
✓ Test 1: Suffix removal: BMW BW → BMW
✓ Test 2: Suffix removal: VOLKSWAGEN VW → VOLKSWAGEN
...
✓ Test 22: Complete coverage: All 16 BRAND_CONSOLIDATION_MAP entries work correctly
======================================================================

✓ Brand Consolidation: 22/22 tests passed
⏱  Execution time: <1000ms

✅ All tests passed!
```

### Success Criteria

- ✅ All 22 tests pass (100% pass rate)
- ✅ All 16 brand variants correctly consolidated
- ✅ Invalid brands return 'INVALID_BRAND'
- ✅ Test execution time < 1 second
- ✅ Output format: "✓ Brand Consolidation: 22/22 tests passed"

### Integration

This test validates the centralized `BRAND_CONSOLIDATION_MAP` that is implemented identically across all 11 insurer normalization files:

- AXA
- Chubb
- GNP
- El Potosí
- BX+
- Atlas
- ANA
- Qualitas
- HDI
- Zurich
- Mapfre

### Related Requirements

- **Requirement 3.1:** Suffix removal consolidation
- **Requirement 3.2:** Variant consolidation
- **Requirement 3.3:** Typo correction
- **Requirement 3.4:** Invalid brand handling
- **Requirement 3.5:** Case-insensitive matching
- **Requirement 3.6:** Whitespace normalization

### Maintenance

When adding new brand consolidation rules:

1. Update `BRAND_CONSOLIDATION_MAP` in all insurer normalization files
2. Add corresponding test case(s) to this test file
3. Update the count in "Complete coverage" test description
4. Re-run tests to verify all pass
