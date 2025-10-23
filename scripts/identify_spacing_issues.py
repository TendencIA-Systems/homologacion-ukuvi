#!/usr/bin/env python3
"""
Spacing Issues Analysis Script
===============================
Identifies spacing inconsistencies in vehicle version strings across 11 insurance
company catalogs that cause token overlap matching failures.

Author: ETL Analysis Team
Date: 2025-10-22
"""

import csv
import re
from collections import defaultdict, Counter
from pathlib import Path


class SpacingAnalyzer:
    """Analyzes spacing patterns in vehicle version strings"""

    def __init__(self, data_origin_path):
        """Initialize analyzer with path to origin data directory"""
        self.data_path = Path(data_origin_path)
        self.insurers = [
            'zurich', 'hdi', 'qualitas', 'axa', 'gnp', 'mapfre',
            'chubb', 'atlas', 'bx', 'elpotosi', 'ana'
        ]

        # Storage for analysis results
        self.all_versions = defaultdict(list)  # insurer -> [versions]
        self.pattern_frequencies = defaultdict(lambda: defaultdict(int))  # pattern -> insurer -> count
        self.variant_groups = defaultdict(set)  # canonical -> {variants}
        self.cross_insurer_inconsistencies = []
        self.vehicles_by_hash = defaultdict(list)  # hash_comercial -> [{insurer, version, ...}]

        print(f"Initialized SpacingAnalyzer for {len(self.insurers)} insurers")

    def load_all_data(self):
        """Load all CSV files from origin directory"""
        print("\n" + "="*80)
        print("LOADING DATA FROM ALL INSURERS")
        print("="*80)

        for insurer in self.insurers:
            csv_file = self.data_path / f"{insurer}-sample.csv"
            if not csv_file.exists():
                print(f"⚠️  {insurer}: File not found - {csv_file}")
                continue

            count = self._load_insurer_csv(insurer, csv_file)
            print(f"✓ {insurer.upper():12s}: {count:6,d} records loaded")

        total = sum(len(versions) for versions in self.all_versions.values())
        print(f"\n📊 Total records loaded: {total:,}")

    def _load_insurer_csv(self, insurer, csv_file):
        """Load single insurer CSV file"""
        count = 0
        try:
            with open(csv_file, 'r', encoding='utf-8-sig') as f:
                reader = csv.reader(f)
                for row in reader:
                    if len(row) < 6:
                        continue

                    # Extract fields (format: aseguradora, id, marca, modelo, anio, version, transmision, activo)
                    marca = row[2].strip().upper() if len(row) > 2 else ""
                    modelo = row[3].strip().upper() if len(row) > 3 else ""
                    anio = row[4].strip() if len(row) > 4 else ""
                    version = row[5].strip().upper() if len(row) > 5 else ""
                    transmision = row[6].strip().upper() if len(row) > 6 else ""

                    if not version or version == "VERSION":  # Skip header
                        continue

                    self.all_versions[insurer].append(version)

                    # Create hash_comercial for cross-insurer comparison
                    hash_key = f"{marca}|{modelo}|{anio}|{transmision}"
                    self.vehicles_by_hash[hash_key].append({
                        'insurer': insurer,
                        'marca': marca,
                        'modelo': modelo,
                        'anio': anio,
                        'version': version,
                        'transmision': transmision
                    })

                    count += 1
        except Exception as e:
            print(f"  ❌ Error reading {csv_file}: {e}")

        return count

    def identify_patterns(self):
        """Identify all spacing pattern categories"""
        print("\n" + "="*80)
        print("IDENTIFYING SPACING PATTERNS")
        print("="*80)

        # Pattern 1: Single letter + space + word (trim prefixes)
        print("\n1️⃣  Analyzing trim prefix patterns (e.g., 'I GRAND', 'S GRAND')...")
        self._find_trim_prefix_patterns()

        # Pattern 2: Fragmented acronyms
        print("\n2️⃣  Analyzing fragmented acronym patterns (e.g., 'T D I', 'F S I')...")
        self._find_fragmented_acronyms()

        # Pattern 3: Number spacing inconsistencies
        print("\n3️⃣  Analyzing number spacing patterns (e.g., '2 0', '1 5 L')...")
        self._find_number_spacing_issues()

        # Pattern 4: Model prefix separations
        print("\n4️⃣  Analyzing model prefix patterns (e.g., 'E TRON', 'BI TURBO')...")
        self._find_model_prefix_patterns()

        print(f"\n✓ Pattern analysis complete")

    def _find_trim_prefix_patterns(self):
        """Find patterns like 'I GRAND', 'S GRAND', 'GT SPORT'"""
        # Single letter followed by space and word
        pattern = re.compile(r'\b([A-Z])\s+([A-Z]{4,})\b')

        for insurer, versions in self.all_versions.items():
            for version in versions:
                matches = pattern.findall(version)
                for letter, word in matches:
                    spaced = f"{letter} {word}"
                    compressed = f"{letter}{word}"
                    hyphenated = f"{letter}-{word}"

                    # Count occurrence
                    self.pattern_frequencies[f"TRIM_PREFIX:{spaced}"][insurer] += 1

                    # Group variants
                    canonical = hyphenated
                    self.variant_groups[canonical].add(spaced)
                    self.variant_groups[canonical].add(compressed)
                    self.variant_groups[canonical].add(hyphenated)

    def _find_fragmented_acronyms(self):
        """Find patterns like 'T D I', 'F S I', 'T S I'"""
        # 2-4 single letters separated by spaces
        pattern = re.compile(r'\b([A-Z])\s+([A-Z])\s*([A-Z])?\s*([A-Z])?\b')

        known_acronyms = ['TDI', 'FSI', 'TSI', 'GTI', 'GTS', 'AMG', 'SRT']

        for insurer, versions in self.all_versions.items():
            for version in versions:
                matches = pattern.findall(version)
                for match in matches:
                    letters = [l for l in match if l]
                    if len(letters) >= 2:
                        spaced = ' '.join(letters)
                        compressed = ''.join(letters)

                        # Only track if it looks like a known acronym
                        if compressed in known_acronyms or len(letters) >= 3:
                            self.pattern_frequencies[f"ACRONYM:{spaced}"][insurer] += 1
                            self.variant_groups[compressed].add(spaced)
                            self.variant_groups[compressed].add(compressed)

    def _find_number_spacing_issues(self):
        """Find patterns like '2 0', '1 5 L', '2 . 0 L'"""
        # Numbers with spaces or periods
        patterns = [
            (re.compile(r'\b(\d)\s+(\d)\b'), 'NUMBER_SPACED'),  # "2 0"
            (re.compile(r'\b(\d)\s*\.\s*(\d)\s+L\b'), 'DISPLACEMENT_SPACED'),  # "2 . 0 L"
            (re.compile(r'\b(\d+)\s+(\d+)\s*L\b'), 'DISPLACEMENT_SEPARATED'),  # "1 5 L"
        ]

        for regex, pattern_type in patterns:
            for insurer, versions in self.all_versions.items():
                for version in versions:
                    matches = regex.findall(version)
                    for match in matches:
                        if len(match) == 2:
                            spaced = f"{match[0]} {match[1]}"
                            compressed = f"{match[0]}{match[1]}"

                            self.pattern_frequencies[f"{pattern_type}:{spaced}"][insurer] += 1
                            self.variant_groups[compressed].add(spaced)
                            self.variant_groups[compressed].add(compressed)

    def _find_model_prefix_patterns(self):
        """Find patterns like 'E TRON', 'BI TURBO', 'X LINE'"""
        known_prefixes = [
            ('E', 'TRON'),
            ('BI', 'TURBO'),
            ('TWIN', 'TURBO'),
            ('X', 'LINE'),
            ('M', 'SPORT'),
            ('TYPE', 'S'),
            ('TYPE', 'R'),
            ('A', 'SPEC'),
        ]

        for prefix, suffix in known_prefixes:
            pattern_spaced = f"{prefix} {suffix}"
            pattern_compressed = f"{prefix}{suffix}"
            pattern_hyphenated = f"{prefix}-{suffix}"

            for insurer, versions in self.all_versions.items():
                for version in versions:
                    if pattern_spaced in version:
                        self.pattern_frequencies[f"MODEL_PREFIX:{pattern_spaced}"][insurer] += 1
                        self.variant_groups[pattern_hyphenated].add(pattern_spaced)
                        self.variant_groups[pattern_hyphenated].add(pattern_compressed)
                        self.variant_groups[pattern_hyphenated].add(pattern_hyphenated)

    def find_cross_insurer_inconsistencies(self):
        """Identify vehicles with spacing variations across insurers"""
        print("\n" + "="*80)
        print("FINDING CROSS-INSURER INCONSISTENCIES")
        print("="*80)

        inconsistency_count = 0

        for hash_key, vehicles in self.vehicles_by_hash.items():
            if len(vehicles) < 2:
                continue  # Need at least 2 insurers for comparison

            # Group by insurer to get unique versions per insurer
            insurer_versions = defaultdict(set)
            for v in vehicles:
                insurer_versions[v['insurer']].add(v['version'])

            if len(insurer_versions) < 2:
                continue  # Need multiple insurers

            # Check for spacing differences
            all_versions = set()
            for versions in insurer_versions.values():
                all_versions.update(versions)

            # Look for spacing variants in the same vehicle
            has_spacing_issue = False
            for canonical, variants in self.variant_groups.items():
                matching_versions = all_versions & variants
                if len(matching_versions) >= 2:
                    has_spacing_issue = True
                    break

            if has_spacing_issue:
                inconsistency_count += 1
                self.cross_insurer_inconsistencies.append({
                    'hash': hash_key,
                    'marca': vehicles[0]['marca'],
                    'modelo': vehicles[0]['modelo'],
                    'anio': vehicles[0]['anio'],
                    'insurers': list(insurer_versions.keys()),
                    'versions': {k: list(v) for k, v in insurer_versions.items()}
                })

        print(f"✓ Found {inconsistency_count:,} vehicles with cross-insurer spacing inconsistencies")

    def calculate_overlap_scores(self, version_a, version_b):
        """Calculate token overlap between two versions (simulating tokenize_version)"""
        # Simplified tokenization (mimics SQL function behavior)
        def tokenize(version):
            # Lowercase, split on whitespace/punctuation, deduplicate
            tokens = re.findall(r'[A-Z0-9]+', version.upper())
            return set(tokens)

        tokens_a = tokenize(version_a)
        tokens_b = tokenize(version_b)

        if not tokens_a or not tokens_b:
            return 0.0

        intersection = len(tokens_a & tokens_b)
        max_len = max(len(tokens_a), len(tokens_b))

        return intersection / max_len if max_len > 0 else 0.0

    def generate_report(self):
        """Generate comprehensive analysis report"""
        print("\n" + "="*80)
        print("GENERATING ANALYSIS REPORT")
        print("="*80)

        # Count patterns
        total_patterns = len(self.pattern_frequencies)
        total_variants = len(self.variant_groups)

        # Calculate affected vehicles (rough estimate)
        total_occurrences = sum(
            sum(counts.values())
            for counts in self.pattern_frequencies.values()
        )

        print(f"📊 Patterns identified: {total_patterns}")
        print(f"📊 Variant groups: {total_variants}")
        print(f"📊 Total occurrences: {total_occurrences:,}")
        print(f"📊 Cross-insurer issues: {len(self.cross_insurer_inconsistencies):,}")

        return {
            'total_patterns': total_patterns,
            'total_variants': total_variants,
            'total_occurrences': total_occurrences,
            'cross_insurer_issues': len(self.cross_insurer_inconsistencies),
            'pattern_frequencies': dict(self.pattern_frequencies),
            'variant_groups': {k: list(v) for k, v in self.variant_groups.items()},
            'inconsistencies_sample': self.cross_insurer_inconsistencies[:20]
        }


def main():
    """Main execution function"""
    print("="*80)
    print("SPACING ISSUES IDENTIFICATION SCRIPT")
    print("="*80)

    # Initialize analyzer
    data_path = Path(__file__).parent.parent / "data" / "origin"
    analyzer = SpacingAnalyzer(data_path)

    # Run analysis
    analyzer.load_all_data()
    analyzer.identify_patterns()
    analyzer.find_cross_insurer_inconsistencies()

    # Generate report
    results = analyzer.generate_report()

    # Print top patterns
    print("\n" + "="*80)
    print("TOP 20 MOST FREQUENT PATTERNS")
    print("="*80)

    pattern_totals = {
        pattern: sum(counts.values())
        for pattern, counts in results['pattern_frequencies'].items()
    }

    for i, (pattern, count) in enumerate(sorted(pattern_totals.items(), key=lambda x: -x[1])[:20], 1):
        category, example = pattern.split(':', 1)
        print(f"{i:2d}. {category:20s} | {example:30s} | {count:6,d} occurrences")

    print("\n✅ Analysis complete!")
    print(f"💾 Results stored in memory for report generation")

    return analyzer, results


if __name__ == "__main__":
    analyzer, results = main()
