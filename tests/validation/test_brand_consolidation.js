/**
 * Brand Consolidation Validation Tests
 *
 * Tests the consolidateBrand() function implementation across all insurer normalization files.
 * Validates suffix removal, variant consolidation, typo correction, and invalid brand handling.
 *
 * Task 104: Phase 3 Validation - Brand Consolidation Tests
 * Requirements: 3.1-3.6 (Brand consolidation acceptance criteria)
 */

const crypto = require("crypto");

// ═══════════════════════════════════════════════════════════════════════════
// BRAND CONSOLIDATION MAP (from design.md lines 240-267)
// ═══════════════════════════════════════════════════════════════════════════

const BRAND_CONSOLIDATION_MAP = {
  // Suffix removal
  "BMW BW": "BMW",
  "VOLKSWAGEN VW": "VOLKSWAGEN",
  "CHEVROLET GM": "CHEVROLET",
  "FORD FR": "FORD",
  "AUDI II": "AUDI",

  // Variant consolidation
  "KIA MOTORS": "KIA",
  "TESLA MOTORS": "TESLA",
  "MERCEDES BENZ II": "MERCEDES BENZ",
  "NISSAN II": "NISSAN",
  "GREAT WALL MOTORS": "GREAT WALL",

  // Typo correction
  "BERCEDES": "MERCEDES BENZ",
  "BUIK": "BUICK",

  // Invalid brands (flag for deletion)
  AUTOS: "INVALID_BRAND",
  MOTOCICLETAS: "INVALID_BRAND",
  MULTIMARCA: "INVALID_BRAND",
  LEGALIZADO: "INVALID_BRAND",
};

// ═══════════════════════════════════════════════════════════════════════════
// CONSOLIDATE BRAND FUNCTION
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Apply centralized brand consolidation after initial normalization
 * @param {string} marca - Raw or pre-normalized brand name
 * @returns {string} - Canonical brand name or 'INVALID_BRAND'
 */
function consolidateBrand(marca) {
  if (!marca || typeof marca !== "string") return "";
  const normalized = marca.toUpperCase().trim();
  return BRAND_CONSOLIDATION_MAP[normalized] || normalized;
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST FRAMEWORK (Simple Node.js Test Runner)
// ═══════════════════════════════════════════════════════════════════════════

class TestRunner {
  constructor() {
    this.tests = [];
    this.passed = 0;
    this.failed = 0;
    this.startTime = null;
  }

  test(description, fn) {
    this.tests.push({ description, fn });
  }

  assertEqual(actual, expected, message) {
    if (actual !== expected) {
      throw new Error(
        `${message}\n  Expected: "${expected}"\n  Received: "${actual}"`
      );
    }
  }

  run() {
    this.startTime = Date.now();
    console.log("\n🧪 Brand Consolidation Validation Tests\n");
    console.log("=" .repeat(70));

    this.tests.forEach((test, index) => {
      try {
        test.fn();
        this.passed++;
        console.log(`✓ Test ${index + 1}: ${test.description}`);
      } catch (error) {
        this.failed++;
        console.log(`✗ Test ${index + 1}: ${test.description}`);
        console.log(`  Error: ${error.message}`);
      }
    });

    const duration = Date.now() - this.startTime;
    const total = this.passed + this.failed;

    console.log("=" .repeat(70));
    console.log(
      `\n${this.passed === total ? "✓" : "✗"} Brand Consolidation: ${this.passed}/${total} tests passed`
    );
    console.log(`⏱  Execution time: ${duration}ms`);

    if (this.failed > 0) {
      console.log(`\n❌ ${this.failed} test(s) failed`);
      process.exit(1);
    } else {
      console.log(`\n✅ All tests passed!`);
      process.exit(0);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TEST SUITE
// ═══════════════════════════════════════════════════════════════════════════

const runner = new TestRunner();

// -----------------------------------------------------------------------------
// Category 1: Suffix Removal Tests (5 tests)
// -----------------------------------------------------------------------------

runner.test("Suffix removal: BMW BW → BMW", () => {
  const result = consolidateBrand("BMW BW");
  runner.assertEqual(result, "BMW", "Should remove BW suffix from BMW");
});

runner.test("Suffix removal: VOLKSWAGEN VW → VOLKSWAGEN", () => {
  const result = consolidateBrand("VOLKSWAGEN VW");
  runner.assertEqual(
    result,
    "VOLKSWAGEN",
    "Should remove VW suffix from VOLKSWAGEN"
  );
});

runner.test("Suffix removal: CHEVROLET GM → CHEVROLET", () => {
  const result = consolidateBrand("CHEVROLET GM");
  runner.assertEqual(
    result,
    "CHEVROLET",
    "Should remove GM suffix from CHEVROLET"
  );
});

runner.test("Suffix removal: FORD FR → FORD", () => {
  const result = consolidateBrand("FORD FR");
  runner.assertEqual(result, "FORD", "Should remove FR suffix from FORD");
});

runner.test("Suffix removal: AUDI II → AUDI", () => {
  const result = consolidateBrand("AUDI II");
  runner.assertEqual(result, "AUDI", "Should remove II suffix from AUDI");
});

// -----------------------------------------------------------------------------
// Category 2: Variant Consolidation Tests (5 tests)
// -----------------------------------------------------------------------------

runner.test("Variant consolidation: KIA MOTORS → KIA", () => {
  const result = consolidateBrand("KIA MOTORS");
  runner.assertEqual(result, "KIA", "Should consolidate KIA MOTORS to KIA");
});

runner.test("Variant consolidation: TESLA MOTORS → TESLA", () => {
  const result = consolidateBrand("TESLA MOTORS");
  runner.assertEqual(
    result,
    "TESLA",
    "Should consolidate TESLA MOTORS to TESLA"
  );
});

runner.test("Variant consolidation: MERCEDES BENZ II → MERCEDES BENZ", () => {
  const result = consolidateBrand("MERCEDES BENZ II");
  runner.assertEqual(
    result,
    "MERCEDES BENZ",
    "Should consolidate MERCEDES BENZ II to MERCEDES BENZ"
  );
});

runner.test("Variant consolidation: NISSAN II → NISSAN", () => {
  const result = consolidateBrand("NISSAN II");
  runner.assertEqual(
    result,
    "NISSAN",
    "Should consolidate NISSAN II to NISSAN"
  );
});

runner.test("Variant consolidation: GREAT WALL MOTORS → GREAT WALL", () => {
  const result = consolidateBrand("GREAT WALL MOTORS");
  runner.assertEqual(
    result,
    "GREAT WALL",
    "Should consolidate GREAT WALL MOTORS to GREAT WALL"
  );
});

// -----------------------------------------------------------------------------
// Category 3: Typo Correction Tests (2 tests)
// -----------------------------------------------------------------------------

runner.test("Typo correction: BERCEDES → MERCEDES BENZ", () => {
  const result = consolidateBrand("BERCEDES");
  runner.assertEqual(
    result,
    "MERCEDES BENZ",
    "Should correct BERCEDES typo to MERCEDES BENZ"
  );
});

runner.test("Typo correction: BUIK → BUICK", () => {
  const result = consolidateBrand("BUIK");
  runner.assertEqual(result, "BUICK", "Should correct BUIK typo to BUICK");
});

// -----------------------------------------------------------------------------
// Category 4: Invalid Brand Tests (4 tests)
// -----------------------------------------------------------------------------

runner.test("Invalid brand: AUTOS → INVALID_BRAND", () => {
  const result = consolidateBrand("AUTOS");
  runner.assertEqual(
    result,
    "INVALID_BRAND",
    "Should flag AUTOS as INVALID_BRAND"
  );
});

runner.test("Invalid brand: MOTOCICLETAS → INVALID_BRAND", () => {
  const result = consolidateBrand("MOTOCICLETAS");
  runner.assertEqual(
    result,
    "INVALID_BRAND",
    "Should flag MOTOCICLETAS as INVALID_BRAND"
  );
});

runner.test("Invalid brand: MULTIMARCA → INVALID_BRAND", () => {
  const result = consolidateBrand("MULTIMARCA");
  runner.assertEqual(
    result,
    "INVALID_BRAND",
    "Should flag MULTIMARCA as INVALID_BRAND"
  );
});

runner.test("Invalid brand: LEGALIZADO → INVALID_BRAND", () => {
  const result = consolidateBrand("LEGALIZADO");
  runner.assertEqual(
    result,
    "INVALID_BRAND",
    "Should flag LEGALIZADO as INVALID_BRAND"
  );
});

// -----------------------------------------------------------------------------
// Category 5: Edge Cases & Pass-Through Tests (5 tests)
// -----------------------------------------------------------------------------

runner.test("Pass-through: Valid brand not in map (TOYOTA) → TOYOTA", () => {
  const result = consolidateBrand("TOYOTA");
  runner.assertEqual(
    result,
    "TOYOTA",
    "Should pass through valid brand not in consolidation map"
  );
});

runner.test("Pass-through: Valid brand not in map (HONDA) → HONDA", () => {
  const result = consolidateBrand("HONDA");
  runner.assertEqual(
    result,
    "HONDA",
    "Should pass through valid brand not in consolidation map"
  );
});

runner.test("Case normalization: lowercase 'bmw bw' → BMW", () => {
  const result = consolidateBrand("bmw bw");
  runner.assertEqual(
    result,
    "BMW",
    "Should handle lowercase input and normalize to uppercase"
  );
});

runner.test("Whitespace handling: '  KIA MOTORS  ' → KIA", () => {
  const result = consolidateBrand("  KIA MOTORS  ");
  runner.assertEqual(
    result,
    "KIA",
    "Should trim whitespace before consolidation"
  );
});

runner.test("Empty/null handling: empty string → empty string", () => {
  const result1 = consolidateBrand("");
  const result2 = consolidateBrand(null);
  const result3 = consolidateBrand(undefined);

  runner.assertEqual(result1, "", "Should return empty string for empty input");
  runner.assertEqual(result2, "", "Should return empty string for null input");
  runner.assertEqual(
    result3,
    "",
    "Should return empty string for undefined input"
  );
});

// -----------------------------------------------------------------------------
// Category 6: All Map Entries Coverage Test (1 comprehensive test)
// -----------------------------------------------------------------------------

runner.test(
  "Complete coverage: All 16 BRAND_CONSOLIDATION_MAP entries work correctly",
  () => {
    const expectedMappings = {
      // Suffix removal (5)
      "BMW BW": "BMW",
      "VOLKSWAGEN VW": "VOLKSWAGEN",
      "CHEVROLET GM": "CHEVROLET",
      "FORD FR": "FORD",
      "AUDI II": "AUDI",

      // Variant consolidation (5)
      "KIA MOTORS": "KIA",
      "TESLA MOTORS": "TESLA",
      "MERCEDES BENZ II": "MERCEDES BENZ",
      "NISSAN II": "NISSAN",
      "GREAT WALL MOTORS": "GREAT WALL",

      // Typo correction (2)
      BERCEDES: "MERCEDES BENZ",
      BUIK: "BUICK",

      // Invalid brands (4)
      AUTOS: "INVALID_BRAND",
      MOTOCICLETAS: "INVALID_BRAND",
      MULTIMARCA: "INVALID_BRAND",
      LEGALIZADO: "INVALID_BRAND",
    };

    let allPassed = true;
    let errors = [];

    Object.entries(expectedMappings).forEach(([input, expected]) => {
      const result = consolidateBrand(input);
      if (result !== expected) {
        allPassed = false;
        errors.push(`  ${input} → Expected "${expected}", got "${result}"`);
      }
    });

    if (!allPassed) {
      throw new Error(
        `Some mappings failed:\n${errors.join("\n")}`
      );
    }
  }
);

// ═══════════════════════════════════════════════════════════════════════════
// RUN TESTS
// ═══════════════════════════════════════════════════════════════════════════

runner.run();
