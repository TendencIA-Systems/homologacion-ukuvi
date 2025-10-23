#!/usr/bin/env python3
"""
Spacing Normalization Validation Script
========================================
Tests the impact of spacing normalization fixes on token overlap scores.

This script:
1. Loads sample vehicle data
2. Simulates current tokenization (with spacing issues)
3. Simulates normalized tokenization (after fixes)
4. Calculates overlap scores for both
5. Reports improvement metrics

Author: ETL Validation Team
Date: 2025-10-22
"""

import re
from collections import defaultdict
from pathlib import Path


class TokenOverlapCalculator:
    """Calculates token overlap scores with and without spacing normalization"""

    def __init__(self):
        # Spacing normalization patterns to apply
        self.normalization_patterns = [
            (r'\bM\s+SPORT\b', 'M-SPORT'),
            (r'\bX\s+DRIVE\b', 'XDRIVE'),
            (r'\bURBAN\s+LINE\b', 'URBAN-LINE'),
            (r'\bSPORT\s+LINE\b', 'SPORT-LINE'),
            (r'\bX\s+LINE\b', 'X-LINE'),
            (r'\bM\s+COMPETITION\b', 'M-COMPETITION'),
        ]

        self.test_cases = []
        self.results = {
            'total_tests': 0,
            'improved': 0,
            'no_change': 0,
            'degraded': 0,
            'avg_improvement': 0.0
        }

    def tokenize_version(self, version, apply_normalization=False):
        """
        Tokenize version string similar to SQL function.

        Args:
            version (str): Version string to tokenize
            apply_normalization (bool): If True, apply spacing fixes first

        Returns:
            set: Set of tokens
        """
        if not version:
            return set()

        text = version.upper().strip()

        # Apply spacing normalization if requested
        if apply_normalization:
            for pattern, replacement in self.normalization_patterns:
                text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)

        # Extract alphanumeric tokens
        tokens = re.findall(r'[A-Z0-9]+', text)

        # Deduplicate and return as set
        return set(tokens)

    def calculate_overlap(self, version_a, version_b, normalized=False):
        """
        Calculate token overlap score between two versions.

        Args:
            version_a (str): First version
            version_b (str): Second version
            normalized (bool): Apply normalization before tokenizing

        Returns:
            float: Overlap score (0.0 to 1.0)
        """
        tokens_a = self.tokenize_version(version_a, apply_normalization=normalized)
        tokens_b = self.tokenize_version(version_b, apply_normalization=normalized)

        if not tokens_a or not tokens_b:
            return 0.0

        intersection = len(tokens_a & tokens_b)
        max_len = max(len(tokens_a), len(tokens_b))

        return intersection / max_len if max_len > 0 else 0.0

    def add_test_case(self, name, version_a, version_b, description=""):
        """Add a test case for comparison"""
        self.test_cases.append({
            'name': name,
            'version_a': version_a,
            'version_b': version_b,
            'description': description
        })

    def run_tests(self):
        """Execute all test cases and calculate improvements"""
        print("\n" + "="*80)
        print("SPACING NORMALIZATION VALIDATION")
        print("="*80)

        improvements = []

        for i, test in enumerate(self.test_cases, 1):
            print(f"\n{i}. {test['name']}")
            print(f"   {test['description']}")
            print(f"   Version A: {test['version_a']}")
            print(f"   Version B: {test['version_b']}")

            # Calculate current overlap
            current_overlap = self.calculate_overlap(
                test['version_a'],
                test['version_b'],
                normalized=False
            )

            # Calculate normalized overlap
            normalized_overlap = self.calculate_overlap(
                test['version_a'],
                test['version_b'],
                normalized=True
            )

            # Calculate improvement
            delta = normalized_overlap - current_overlap
            pct_improvement = (delta / current_overlap * 100) if current_overlap > 0 else 0

            # Store results
            test['current_overlap'] = current_overlap
            test['normalized_overlap'] = normalized_overlap
            test['delta'] = delta
            test['pct_improvement'] = pct_improvement

            improvements.append(delta)

            # Classify result
            if delta > 0.01:
                self.results['improved'] += 1
                status = "✅ IMPROVED"
            elif delta < -0.01:
                self.results['degraded'] += 1
                status = "❌ DEGRADED"
            else:
                self.results['no_change'] += 1
                status = "➖ NO CHANGE"

            print(f"   Current overlap:    {current_overlap:.2%}")
            print(f"   Normalized overlap: {normalized_overlap:.2%}")
            print(f"   Delta:              {delta:+.2%} ({pct_improvement:+.1f}%)")
            print(f"   Status:             {status}")

            # Show tokens for debugging
            tokens_a_current = self.tokenize_version(test['version_a'], False)
            tokens_a_norm = self.tokenize_version(test['version_a'], True)
            tokens_b_current = self.tokenize_version(test['version_b'], False)
            tokens_b_norm = self.tokenize_version(test['version_b'], True)

            if tokens_a_current != tokens_a_norm:
                print(f"   Tokens A (current):     {sorted(tokens_a_current)}")
                print(f"   Tokens A (normalized):  {sorted(tokens_a_norm)}")

            if tokens_b_current != tokens_b_norm:
                print(f"   Tokens B (current):     {sorted(tokens_b_current)}")
                print(f"   Tokens B (normalized):  {sorted(tokens_b_norm)}")

        # Calculate summary statistics
        self.results['total_tests'] = len(self.test_cases)
        self.results['avg_improvement'] = sum(improvements) / len(improvements) if improvements else 0.0

        # Print summary
        self.print_summary()

        return self.results

    def print_summary(self):
        """Print summary of validation results"""
        print("\n" + "="*80)
        print("VALIDATION SUMMARY")
        print("="*80)

        print(f"\nTotal test cases:     {self.results['total_tests']}")
        print(f"Improved:             {self.results['improved']} ✅")
        print(f"No change:            {self.results['no_change']} ➖")
        print(f"Degraded:             {self.results['degraded']} ❌")
        print(f"Average improvement:  {self.results['avg_improvement']:+.2%}")

        # Assessment
        print("\n" + "-"*80)
        if self.results['improved'] >= self.results['total_tests'] * 0.8:
            print("✅ EXCELLENT: >80% of cases improved")
        elif self.results['improved'] >= self.results['total_tests'] * 0.5:
            print("✓ GOOD: >50% of cases improved")
        elif self.results['improved'] >= self.results['total_tests'] * 0.3:
            print("⚠ ACCEPTABLE: >30% of cases improved, review degraded cases")
        else:
            print("❌ POOR: <30% improvement, normalization may need adjustment")

        if self.results['degraded'] > 0:
            print(f"⚠️  WARNING: {self.results['degraded']} cases degraded - review implementation")

    def export_results(self, output_file):
        """Export results to CSV for further analysis"""
        import csv

        with open(output_file, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=[
                'name', 'description', 'version_a', 'version_b',
                'current_overlap', 'normalized_overlap', 'delta', 'pct_improvement'
            ])
            writer.writeheader()

            for test in self.test_cases:
                writer.writerow({
                    'name': test['name'],
                    'description': test['description'],
                    'version_a': test['version_a'],
                    'version_b': test['version_b'],
                    'current_overlap': f"{test['current_overlap']:.4f}",
                    'normalized_overlap': f"{test['normalized_overlap']:.4f}",
                    'delta': f"{test['delta']:+.4f}",
                    'pct_improvement': f"{test['pct_improvement']:+.2f}"
                })

        print(f"\n💾 Results exported to: {output_file}")


def main():
    """Main test execution"""
    calculator = TokenOverlapCalculator()

    # ========================================================================
    # TEST CASES - Based on real patterns found in analysis
    # ========================================================================

    # Test 1: M SPORT spacing
    calculator.add_test_case(
        name="BMW M SPORT spacing",
        version_a="118I M SPORT AUTOMATICA 3PTAS",
        version_b="118I MSPORT AUTOMATICA 3PTAS",
        description="Same vehicle, different spacing on M SPORT"
    )

    # Test 2: X DRIVE spacing
    calculator.add_test_case(
        name="BMW X DRIVE spacing",
        version_a="IX2 X DRIVE 30 EV AUTOMATICA",
        version_b="IX2 XDRIVE 30 EV AUTOMATICA",
        description="Same vehicle, different spacing on X DRIVE"
    )

    # Test 3: URBAN LINE spacing
    calculator.add_test_case(
        name="BMW URBAN LINE spacing",
        version_a="118I URBAN LINE STD 5PTAS",
        version_b="118I URBANLINE STD 5PTAS",
        description="Same vehicle, different spacing on URBAN LINE"
    )

    # Test 4: SPORT LINE spacing
    calculator.add_test_case(
        name="BMW SPORT LINE spacing",
        version_a="118I SPORT LINE AUTOMATICA",
        version_b="118I SPORTLINE AUTOMATICA",
        description="Same vehicle, different spacing on SPORT LINE"
    )

    # Test 5: Multiple patterns
    calculator.add_test_case(
        name="Multiple spacing issues",
        version_a="X3 M SPORT X DRIVE 30D AUTOMATICA",
        version_b="X3 MSPORT XDRIVE 30D AUTOMATICA",
        description="Multiple spacing differences in same version"
    )

    # Test 6: Real case from analysis
    calculator.add_test_case(
        name="BMW iX3 M SPORT (real case)",
        version_a="M SPORT INSPIRING EV 80KWH AUTOMATICA 5PTAS",
        version_b="MSPORT INSPIRING EV 80KWH AUTOMATICA 5PTAS",
        description="Real case from ANA data"
    )

    # Test 7: Ensure no false positive on MINI
    calculator.add_test_case(
        name="MINI COOPER S - No false positive",
        version_a="COOPER S CHILI AUTOMATICA",
        version_b="COOPER S CHILI AUTOMATICA",
        description="Should have perfect match, 'S' is model not trim"
    )

    # Test 8: X LINE spacing
    calculator.add_test_case(
        name="BMW X LINE spacing",
        version_a="X1 X LINE SDRIVE18I AUTOMATICA",
        version_b="X1 XLINE SDRIVE18I AUTOMATICA",
        description="X LINE trim spacing"
    )

    # Test 9: M Competition spacing
    calculator.add_test_case(
        name="BMW M Competition spacing",
        version_a="M4 M COMPETITION 510HP",
        version_b="M4 MCOMPETITION 510HP",
        description="M Competition spacing"
    )

    # Test 10: Cross-insurer real example
    calculator.add_test_case(
        name="Cross-insurer BMW 118i",
        version_a="I URBAN LINE 2.0L",  # HDI style
        version_b="118I URBAN LINE ESTANDAR 5PTAS",  # ANA style
        description="Different insurers, same vehicle"
    )

    # Run all tests
    results = calculator.run_tests()

    # Export results
    output_file = Path(__file__).parent.parent / "reports" / "spacing_normalization_test_results.csv"
    output_file.parent.mkdir(exist_ok=True)
    calculator.export_results(output_file)

    # Return exit code based on results
    if results['degraded'] > 0:
        print("\n⚠️  WARNING: Some tests degraded. Review implementation before deploying.")
        return 1
    elif results['improved'] < results['total_tests'] * 0.5:
        print("\n⚠️  WARNING: Less than 50% improvement. Review normalization patterns.")
        return 1
    else:
        print("\n✅ SUCCESS: Normalization validation passed!")
        return 0


if __name__ == "__main__":
    exit(main())
