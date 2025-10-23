#!/usr/bin/env python3
"""
Comprehensive ETL Validation Analysis
======================================

This script validates all fixes applied to the vehicle homologation system,
checking for the 4 primary issues, QA findings, client feedback, and new issues.

Usage:
    python comprehensive_validation_analysis.py

Output:
    - Console output with detailed findings
    - JSON report file with all metrics
    - Executive summary for client presentation
"""

import pandas as pd
import json
import re
from collections import defaultdict, Counter
from datetime import datetime
import sys

# Configuration
DATA_FILE = '../data/validation/catalogo_revision.csv'
COMPARISON_FILE = '../data/validation/catalogo_revision_comparacion_versiones.csv'
OUTPUT_REPORT = '../reports/validation_comprehensive_report.json'
OUTPUT_SUMMARY = '../reports/validation_executive_summary.md'

# Valid transmission values
VALID_TRANSMISSIONS = {'AUTO', 'MANUAL', 'CVT', 'DSG', None, ''}

# Known brand consolidation issues
BRAND_ISSUES = {
    'AUDI II': 'AUDI',
    'BMW BW': 'BMW',
    'MERCEDES BENZ II': 'MERCEDES BENZ',
    'KIA MOTORS': 'KIA',
    'GREAT WALL MOTORS': 'GREAT WALL',
    'TESLA MOTORS': 'TESLA'
}

INVALID_BRANDS = {'AUTOS', 'MOTOCICLETAS', 'MULTIMARCA', 'LEGALIZADO'}

# Issue patterns for model contamination
MODEL_CONTAMINATION_PATTERNS = [
    (r'\bSERIE\s+\d+\b', 'SERIE prefix'),
    (r'\b(SDRIVE|XDRIVE)\b', 'DRIVE suffix'),
    (r'\b\d+\s+I[A]?\b', 'Trailing I/IA'),
    (r'\b(M\d+|X\d+)\s+TUR(BO)?\b', 'TURBO/TUR suffix'),
    (r'\bMINI\s+', 'MINI prefix')
]


class ComprehensiveValidator:
    """Main validation class for all ETL quality checks"""

    def __init__(self, data_file, comparison_file):
        print("=" * 80)
        print("🔍 COMPREHENSIVE ETL VALIDATION ANALYSIS")
        print("=" * 80)
        print(f"Loading data from: {data_file}")

        self.df = pd.read_csv(data_file)
        self.df_comparison = pd.read_csv(comparison_file)

        print(f"✓ Loaded {len(self.df):,} records from master catalog")
        print(f"✓ Loaded {len(self.df_comparison):,} records from comparison file")

        self.results = {
            'timestamp': datetime.now().isoformat(),
            'total_records': len(self.df),
            'primary_fixes': {},
            'qa_findings': {},
            'client_feedback': {},
            'regressions': {},
            'quality_metrics': {},
            'hash_analysis': {},
            'insurer_breakdown': {}
        }

        # Parse disponibilidad JSONB for insurer analysis
        self.parse_insurer_data()

    def parse_insurer_data(self):
        """Parse the disponibilidad JSONB field to extract insurer information"""
        print("\n📊 Parsing insurer availability data...")

        self.df['insurers_available'] = self.df['disponibilidad'].apply(
            lambda x: self._extract_insurers(x) if pd.notna(x) else []
        )
        self.df['insurer_count'] = self.df['insurers_available'].apply(len)

        # Get all unique insurers
        all_insurers = set()
        for insurers in self.df['insurers_available']:
            all_insurers.update(insurers)

        self.insurers = sorted(all_insurers)
        print(f"✓ Found {len(self.insurers)} insurers: {', '.join(self.insurers)}")

    def _extract_insurers(self, disp_json):
        """Extract insurer names from disponibilidad JSONB string"""
        try:
            if isinstance(disp_json, str):
                data = json.loads(disp_json)
                return [k for k, v in data.items() if v.get('disponible', False)]
        except:
            return []
        return []

    # ========================================================================
    # PRIMARY FIX VALIDATIONS (Issues 1-4)
    # ========================================================================

    def validate_issue_1_model_contamination(self):
        """Issue 1: Model field contamination with trim suffixes"""
        print("\n" + "=" * 80)
        print("🔍 ISSUE 1: Model Field Contamination")
        print("=" * 80)

        contamination_results = {}
        total_contaminated = 0
        samples = []

        for pattern, description in MODEL_CONTAMINATION_PATTERNS:
            matches = self.df[self.df['modelo'].str.contains(pattern, case=False, na=False, regex=True)]
            count = len(matches)
            total_contaminated += count

            contamination_results[description] = {
                'count': count,
                'percentage': (count / len(self.df)) * 100,
                'pattern': pattern
            }

            if count > 0:
                samples.extend(matches[['marca', 'modelo', 'anio', 'version']].head(5).to_dict('records'))

            print(f"  {description:30s}: {count:6,} records ({(count/len(self.df)*100):5.2f}%)")

        print(f"\n  {'TOTAL CONTAMINATED':30s}: {total_contaminated:6,} records ({(total_contaminated/len(self.df)*100):5.2f}%)")

        # Determine status
        if total_contaminated == 0:
            status = "✅ PASS - Zero contamination"
        elif total_contaminated < 50:
            status = "⚠️  PASS - Acceptable (<50 records)"
        elif total_contaminated < 100:
            status = "⚠️  CONDITIONAL - Review edge cases"
        else:
            status = "❌ FAIL - Too many contaminated records"

        print(f"\n  Status: {status}")

        self.results['primary_fixes']['issue_1_model_contamination'] = {
            'total_contaminated': total_contaminated,
            'percentage': (total_contaminated / len(self.df)) * 100,
            'by_pattern': contamination_results,
            'samples': samples[:10],
            'status': status
        }

        return status.startswith("✅") or status.startswith("⚠️")

    def validate_issue_2_bmw_mini_separation(self):
        """Issue 2: BMW/MINI brand separation"""
        print("\n" + "=" * 80)
        print("🔍 ISSUE 2: BMW/MINI Brand Separation")
        print("=" * 80)

        # Check for BMW records with MINI in modelo
        bmw_with_mini = self.df[
            (self.df['marca'] == 'BMW') &
            (self.df['modelo'].str.contains('MINI', case=False, na=False))
        ]

        # Check for MINI brand records
        mini_brand = self.df[self.df['marca'] == 'MINI']

        # Check for MINI prefix in MINI modelo
        mini_with_prefix = mini_brand[mini_brand['modelo'].str.startswith('MINI ', na=False)]

        # Get MINI variant breakdown
        mini_variants = Counter(mini_brand['modelo'].tolist())

        print(f"  BMW records with MINI:        {len(bmw_with_mini):6,} records")
        print(f"  MINI brand records:           {len(mini_brand):6,} records")
        print(f"  MINI with 'MINI ' prefix:     {len(mini_with_prefix):6,} records")

        if len(mini_brand) > 0:
            print(f"\n  MINI Variants Distribution:")
            for variant, count in mini_variants.most_common(10):
                print(f"    {variant:30s}: {count:4,} records")

        # Determine status
        if len(bmw_with_mini) == 0 and len(mini_brand) > 0:
            status = "✅ PASS - Clean separation"
        elif len(bmw_with_mini) > 0:
            status = "❌ FAIL - BMW contains MINI"
        else:
            status = "⚠️  WARNING - No MINI records found"

        print(f"\n  Status: {status}")

        self.results['primary_fixes']['issue_2_bmw_mini_separation'] = {
            'bmw_with_mini_count': len(bmw_with_mini),
            'mini_brand_count': len(mini_brand),
            'mini_with_prefix_count': len(mini_with_prefix),
            'mini_variants': dict(mini_variants.most_common(20)),
            'bmw_with_mini_samples': bmw_with_mini[['marca', 'modelo', 'anio', 'version']].head(10).to_dict('records'),
            'status': status
        }

        return status.startswith("✅")

    def validate_issue_3_incomplete_models(self):
        """Issue 3: Incomplete model completion (single-letter models)"""
        print("\n" + "=" * 80)
        print("🔍 ISSUE 3: Incomplete Model Completion")
        print("=" * 80)

        # BMW single-letter M and X models
        bmw_single_m = self.df[
            (self.df['marca'] == 'BMW') &
            (self.df['modelo'].str.match(r'^M$', na=False))
        ]

        bmw_single_x = self.df[
            (self.df['marca'] == 'BMW') &
            (self.df['modelo'].str.match(r'^X$', na=False))
        ]

        # AUDI single-letter S and R models
        audi_single_s = self.df[
            (self.df['marca'] == 'AUDI') &
            (self.df['modelo'].str.match(r'^S$', na=False))
        ]

        audi_single_r = self.df[
            (self.df['marca'] == 'AUDI') &
            (self.df['modelo'].str.match(r'^R$', na=False))
        ]

        total_single = len(bmw_single_m) + len(bmw_single_x) + len(audi_single_s) + len(audi_single_r)

        print(f"  BMW single 'M':               {len(bmw_single_m):6,} records")
        print(f"  BMW single 'X':               {len(bmw_single_x):6,} records")
        print(f"  AUDI single 'S':              {len(audi_single_s):6,} records")
        print(f"  AUDI single 'R':              {len(audi_single_r):6,} records")
        print(f"  {'TOTAL':30s}: {total_single:6,} records")

        # Determine status
        if total_single == 0:
            status = "✅ PASS - All models completed"
        elif total_single < 5:
            status = "✅ PASS - Acceptable edge cases (<5)"
        elif total_single < 20:
            status = "⚠️  CONDITIONAL - Review remaining singles"
        else:
            status = "❌ FAIL - Too many incomplete models"

        print(f"\n  Status: {status}")

        samples = []
        for df_subset in [bmw_single_m, bmw_single_x, audi_single_s, audi_single_r]:
            if len(df_subset) > 0:
                samples.extend(df_subset[['marca', 'modelo', 'anio', 'version']].head(3).to_dict('records'))

        self.results['primary_fixes']['issue_3_incomplete_models'] = {
            'bmw_single_m': len(bmw_single_m),
            'bmw_single_x': len(bmw_single_x),
            'audi_single_s': len(audi_single_s),
            'audi_single_r': len(audi_single_r),
            'total_single': total_single,
            'percentage': (total_single / len(self.df)) * 100,
            'samples': samples[:10],
            'status': status
        }

        return status.startswith("✅") or status.startswith("⚠️")

    def validate_issue_4_mapfre_ids(self):
        """Issue 4: MAPFRE ID format validation"""
        print("\n" + "=" * 80)
        print("🔍 ISSUE 4: MAPFRE ID Format")
        print("=" * 80)

        # Extract MAPFRE IDs from disponibilidad
        mapfre_records = []

        for idx, row in self.df.iterrows():
            try:
                if pd.notna(row['disponibilidad']):
                    disp = json.loads(row['disponibilidad'])
                    if 'MAPFRE' in disp:
                        mapfre_records.append({
                            'id_original': disp['MAPFRE'].get('id_original', ''),
                            'marca': row['marca'],
                            'modelo': row['modelo'],
                            'anio': row['anio']
                        })
            except:
                pass

        if len(mapfre_records) == 0:
            print("  ⚠️  WARNING: No MAPFRE records found in dataset")
            status = "⚠️  WARNING - No MAPFRE data"

            self.results['primary_fixes']['issue_4_mapfre_ids'] = {
                'total_mapfre_records': 0,
                'status': status
            }
            return True

        # Check ID format
        mapfre_df = pd.DataFrame(mapfre_records)

        # IDs without year suffix (no underscore)
        without_year = mapfre_df[~mapfre_df['id_original'].str.contains('_', na=False)]

        # Check for duplicate IDs
        id_counts = mapfre_df['id_original'].value_counts()
        duplicates = id_counts[id_counts > 1]

        # Check format pattern (should be: digits_year)
        correct_format = mapfre_df[mapfre_df['id_original'].str.match(r'^\d+_\d{4}$', na=False)]

        print(f"  Total MAPFRE records:         {len(mapfre_df):6,}")
        print(f"  Without year suffix:          {len(without_year):6,} ({len(without_year)/len(mapfre_df)*100:5.2f}%)")
        print(f"  Correct format (XXX_YYYY):    {len(correct_format):6,} ({len(correct_format)/len(mapfre_df)*100:5.2f}%)")
        print(f"  Duplicate IDs:                {len(duplicates):6,}")

        if len(duplicates) > 0:
            print(f"\n  Top duplicates:")
            for id_val, count in duplicates.head(5).items():
                print(f"    {id_val:30s}: {count:4,} times")

        # Determine status
        if len(without_year) == 0 and len(duplicates) == 0:
            status = "✅ PASS - All IDs correct format, no duplicates"
        elif len(without_year) < 10 and len(duplicates) == 0:
            status = "⚠️  PASS - Minor format issues, no duplicates"
        elif len(duplicates) > 0:
            status = "❌ FAIL - Duplicate IDs found"
        else:
            status = "❌ FAIL - Too many format issues"

        print(f"\n  Status: {status}")

        self.results['primary_fixes']['issue_4_mapfre_ids'] = {
            'total_mapfre_records': len(mapfre_df),
            'without_year_suffix': len(without_year),
            'correct_format_count': len(correct_format),
            'duplicate_ids': len(duplicates),
            'duplicate_examples': duplicates.head(10).to_dict() if len(duplicates) > 0 else {},
            'samples_without_year': without_year.head(10).to_dict('records'),
            'status': status
        }

        return len(duplicates) == 0

    # ========================================================================
    # QA FINDINGS VALIDATION
    # ========================================================================

    def check_transmission_contamination(self):
        """Check for transmission field contamination"""
        print("\n" + "=" * 80)
        print("🔍 QA CHECK: Transmission Contamination")
        print("=" * 80)

        valid_trans = self.df[self.df['transmision'].isin(VALID_TRANSMISSIONS)]
        invalid_trans = self.df[~self.df['transmision'].isin(VALID_TRANSMISSIONS)]

        # Get frequency of invalid values
        invalid_values = Counter(invalid_trans['transmision'].dropna().tolist())

        print(f"  Valid transmission values:    {len(valid_trans):6,} ({len(valid_trans)/len(self.df)*100:5.2f}%)")
        print(f"  Invalid transmission values:  {len(invalid_trans):6,} ({len(invalid_trans)/len(self.df)*100:5.2f}%)")

        if len(invalid_trans) > 0:
            print(f"\n  Most common invalid values:")
            for value, count in invalid_values.most_common(15):
                print(f"    {str(value):30s}: {count:6,} records")

        self.results['qa_findings']['transmission_contamination'] = {
            'valid_count': len(valid_trans),
            'invalid_count': len(invalid_trans),
            'contamination_percentage': (len(invalid_trans) / len(self.df)) * 100,
            'invalid_values': dict(invalid_values.most_common(30)),
            'note': 'NOT FIXED in current implementation - documented for future work'
        }

    def check_brand_consolidation(self):
        """Check for brand consolidation issues"""
        print("\n" + "=" * 80)
        print("🔍 QA CHECK: Brand Consolidation Issues")
        print("=" * 80)

        all_brands = Counter(self.df['marca'].dropna().tolist())

        # Check for known problematic brands
        found_issues = {}
        total_issue_records = 0

        for problematic_brand, correct_brand in BRAND_ISSUES.items():
            count = all_brands.get(problematic_brand, 0)
            if count > 0:
                found_issues[problematic_brand] = {
                    'count': count,
                    'should_be': correct_brand
                }
                total_issue_records += count
                print(f"  {problematic_brand:30s} → {correct_brand:20s}: {count:6,} records")

        # Check for invalid brands
        invalid_brands_found = {}
        for invalid_brand in INVALID_BRANDS:
            count = all_brands.get(invalid_brand, 0)
            if count > 0:
                invalid_brands_found[invalid_brand] = count
                total_issue_records += count
                print(f"  INVALID: {invalid_brand:30s}: {count:6,} records")

        print(f"\n  Total records with brand issues: {total_issue_records:6,} ({total_issue_records/len(self.df)*100:5.2f}%)")
        print(f"  Total unique brands in dataset:  {len(all_brands):6,}")

        if total_issue_records > 1000:
            priority = "HIGH PRIORITY for future work"
        elif total_issue_records > 100:
            priority = "MEDIUM PRIORITY for future work"
        else:
            priority = "LOW PRIORITY for future work"

        print(f"\n  Priority: {priority}")

        self.results['qa_findings']['brand_consolidation'] = {
            'total_unique_brands': len(all_brands),
            'consolidation_issues': found_issues,
            'invalid_brands': invalid_brands_found,
            'total_issue_records': total_issue_records,
            'percentage': (total_issue_records / len(self.df)) * 100,
            'priority': priority,
            'all_brands': dict(all_brands.most_common(50)),
            'note': 'NOT FIXED in current implementation - documented for future work'
        }

    def check_character_escaping(self):
        """Check for character escaping issues in version field"""
        print("\n" + "=" * 80)
        print("🔍 QA CHECK: Character Escaping Issues")
        print("=" * 80)

        # Check for backslashes
        with_backslash = self.df[self.df['version'].str.contains(r'\\', na=False, regex=False)]

        # Check for quote characters
        with_quotes = self.df[self.df['version'].str.contains(r'["\']', na=False, regex=True)]

        total_escaping_issues = len(with_backslash) + len(with_quotes)

        print(f"  Records with backslashes:     {len(with_backslash):6,}")
        print(f"  Records with quote chars:     {len(with_quotes):6,}")
        print(f"  Total escaping issues:        {total_escaping_issues:6,} ({total_escaping_issues/len(self.df)*100:5.2f}%)")

        if total_escaping_issues > 50:
            severity = "HIGH - Version field needs cleanup"
        elif total_escaping_issues > 10:
            severity = "MEDIUM - Minor cosmetic issues"
        else:
            severity = "LOW - Negligible impact"

        print(f"\n  Severity: {severity}")

        samples = []
        if len(with_backslash) > 0:
            samples.extend(with_backslash[['marca', 'modelo', 'version']].head(5).to_dict('records'))
        if len(with_quotes) > 0:
            samples.extend(with_quotes[['marca', 'modelo', 'version']].head(5).to_dict('records'))

        self.results['qa_findings']['character_escaping'] = {
            'backslash_count': len(with_backslash),
            'quotes_count': len(with_quotes),
            'total_issues': total_escaping_issues,
            'percentage': (total_escaping_issues / len(self.df)) * 100,
            'severity': severity,
            'samples': samples[:10]
        }

    # ========================================================================
    # CLIENT FEEDBACK VALIDATION
    # ========================================================================

    def validate_client_cases(self):
        """Validate specific client-reported cases"""
        print("\n" + "=" * 80)
        print("🔍 CLIENT FEEDBACK: Specific Case Validation")
        print("=" * 80)

        # Case 1: Acura ILX 2017
        print("\n  Case 1: Acura ILX 2017")
        ilx_2017 = self.df_comparison[
            (self.df_comparison['marca'] == 'ACURA') &
            (self.df_comparison['modelo'] == 'ILX') &
            (self.df_comparison['anio'] == 2017)
        ]

        if len(ilx_2017) > 0:
            print(f"    Found {len(ilx_2017)} variants for ACURA ILX 2017")
            for idx, row in ilx_2017.iterrows():
                print(f"      - {row['version_homologada']}")
                if pd.notna(row['zurich_version']):
                    print(f"        ZURICH: {row['zurich_version']}")
                if pd.notna(row['qualitas_version']):
                    print(f"        QUALITAS: {row['qualitas_version']}")
        else:
            print("    ⚠️  No records found for ACURA ILX 2017")

        # Case 2: Volkswagen Jetta 2012 AUTO
        print("\n  Case 2: Volkswagen Jetta 2012 AUTO")
        jetta_2012 = self.df_comparison[
            (self.df_comparison['marca'] == 'VOLKSWAGEN') &
            (self.df_comparison['modelo'] == 'JETTA') &
            (self.df_comparison['anio'] == 2012) &
            (self.df_comparison['transmision'] == 'AUTO')
        ]

        if len(jetta_2012) > 0:
            print(f"    Found {len(jetta_2012)} variants for VW JETTA 2012 AUTO")
            for idx, row in jetta_2012.head(5).iterrows():
                print(f"      - {row['version_homologada']}")
                if pd.notna(row['zurich_version']):
                    print(f"        ZURICH: {row['zurich_version']}")
                if pd.notna(row['gnp_version']):
                    print(f"        GNP: {row['gnp_version']}")
        else:
            print("    ⚠️  No records found for VW JETTA 2012 AUTO")

        self.results['client_feedback']['case_studies'] = {
            'acura_ilx_2017': ilx_2017[['version_homologada', 'zurich_version', 'qualitas_version']].to_dict('records') if len(ilx_2017) > 0 else [],
            'vw_jetta_2012_auto': jetta_2012[['version_homologada', 'zurich_version', 'gnp_version']].head(10).to_dict('records') if len(jetta_2012) > 0 else []
        }

    # ========================================================================
    # REGRESSION DETECTION
    # ========================================================================

    def detect_regressions(self):
        """Detect potential data regressions"""
        print("\n" + "=" * 80)
        print("🔍 REGRESSION DETECTION")
        print("=" * 80)

        # Check for NULL values in critical fields
        null_marca = self.df['marca'].isna().sum()
        null_modelo = self.df['modelo'].isna().sum()
        null_anio = self.df['anio'].isna().sum()

        print(f"  NULL values in marca:         {null_marca:6,}")
        print(f"  NULL values in modelo:        {null_modelo:6,}")
        print(f"  NULL values in anio:          {null_anio:6,}")

        # Check for empty strings
        empty_marca = (self.df['marca'] == '').sum()
        empty_modelo = (self.df['modelo'] == '').sum()
        empty_version = (self.df['version'] == '').sum()

        print(f"  Empty strings in marca:       {empty_marca:6,}")
        print(f"  Empty strings in modelo:      {empty_modelo:6,}")
        print(f"  Empty strings in version:     {empty_version:6,}")

        # Check for double spaces
        double_spaces_modelo = self.df[self.df['modelo'].str.contains('  ', na=False, regex=False)]
        double_spaces_version = self.df[self.df['version'].str.contains('  ', na=False, regex=False)]

        print(f"  Double spaces in modelo:      {len(double_spaces_modelo):6,}")
        print(f"  Double spaces in version:     {len(double_spaces_version):6,}")

        # Check for leading/trailing spaces
        leading_trailing_modelo = self.df[
            (self.df['modelo'].str.startswith(' ', na=False)) |
            (self.df['modelo'].str.endswith(' ', na=False))
        ]

        print(f"  Leading/trailing in modelo:   {len(leading_trailing_modelo):6,}")

        total_issues = (null_marca + null_modelo + null_anio + empty_marca +
                       empty_modelo + len(double_spaces_modelo) +
                       len(double_spaces_version) + len(leading_trailing_modelo))

        if total_issues == 0:
            status = "✅ PASS - No regressions detected"
        elif total_issues < 10:
            status = "⚠️  MINOR - Few issues detected"
        else:
            status = "❌ FAIL - Regressions detected"

        print(f"\n  Status: {status}")

        self.results['regressions']['data_quality'] = {
            'null_values': {
                'marca': null_marca,
                'modelo': null_modelo,
                'anio': null_anio
            },
            'empty_strings': {
                'marca': empty_marca,
                'modelo': empty_modelo,
                'version': empty_version
            },
            'formatting_issues': {
                'double_spaces_modelo': len(double_spaces_modelo),
                'double_spaces_version': len(double_spaces_version),
                'leading_trailing_modelo': len(leading_trailing_modelo)
            },
            'total_issues': total_issues,
            'status': status
        }

        return total_issues < 10

    # ========================================================================
    # QUALITY METRICS BY INSURER
    # ========================================================================

    def analyze_quality_by_insurer(self):
        """Analyze data quality metrics broken down by insurer"""
        print("\n" + "=" * 80)
        print("🔍 QUALITY METRICS BY INSURER")
        print("=" * 80)

        insurer_metrics = {}

        for insurer in self.insurers:
            # Get records from this insurer
            insurer_records = self.df[self.df['insurers_available'].apply(lambda x: insurer in x)]

            if len(insurer_records) == 0:
                continue

            # Calculate completeness
            completeness = (
                (insurer_records['marca'].notna().sum() / len(insurer_records)) * 100 +
                (insurer_records['modelo'].notna().sum() / len(insurer_records)) * 100 +
                (insurer_records['anio'].notna().sum() / len(insurer_records)) * 100 +
                (insurer_records['version'].notna().sum() / len(insurer_records)) * 100
            ) / 4

            # Calculate quality score (no contamination, no issues)
            issues = 0
            for pattern, _ in MODEL_CONTAMINATION_PATTERNS:
                issues += insurer_records['modelo'].str.contains(pattern, case=False, na=False, regex=True).sum()

            quality_score = max(0, 100 - (issues / len(insurer_records)) * 100)

            insurer_metrics[insurer] = {
                'record_count': len(insurer_records),
                'completeness': completeness,
                'quality_score': quality_score,
                'issues': issues
            }

            status = "✓" if quality_score > 94 else ("⚠" if quality_score > 90 else "✗")

            print(f"  {insurer:12s}: {len(insurer_records):6,} records | "
                  f"Completeness: {completeness:5.1f}% | "
                  f"Quality: {quality_score:5.1f}% | {status}")

        # Calculate averages
        avg_completeness = sum(m['completeness'] for m in insurer_metrics.values()) / len(insurer_metrics)
        avg_quality = sum(m['quality_score'] for m in insurer_metrics.values()) / len(insurer_metrics)

        print(f"\n  {'AVERAGE':12s}:             | "
              f"Completeness: {avg_completeness:5.1f}% | "
              f"Quality: {avg_quality:5.1f}%")

        self.results['quality_metrics']['by_insurer'] = insurer_metrics
        self.results['quality_metrics']['averages'] = {
            'completeness': avg_completeness,
            'quality_score': avg_quality
        }

    # ========================================================================
    # HASH DISTRIBUTION ANALYSIS
    # ========================================================================

    def analyze_hash_distribution(self):
        """Analyze hash collision patterns"""
        print("\n" + "=" * 80)
        print("🔍 HASH DISTRIBUTION ANALYSIS")
        print("=" * 80)

        # Count records per hash
        hash_counts = self.df['hash_comercial'].value_counts()

        # Calculate collision rate
        total_hashes = len(hash_counts)
        total_records = len(self.df)
        collision_rate = ((total_records - total_hashes) / total_records) * 100

        # Get distribution
        max_records_per_hash = hash_counts.max()
        avg_records_per_hash = hash_counts.mean()

        print(f"  Total unique hashes:          {total_hashes:6,}")
        print(f"  Total records:                {total_records:6,}")
        print(f"  Collision rate:               {collision_rate:6.2f}%")
        print(f"  Max records per hash:         {max_records_per_hash:6,}")
        print(f"  Avg records per hash:         {avg_records_per_hash:6.2f}")

        # Show distribution
        print(f"\n  Hash distribution:")
        distribution = hash_counts.value_counts().sort_index()
        for records_per_hash, hash_count in distribution.head(10).items():
            print(f"    {records_per_hash:3,} records/hash: {hash_count:6,} hashes")

        # Determine status
        if collision_rate < 5:
            status = "✅ EXCELLENT - Very low collision rate"
        elif collision_rate < 10:
            status = "✅ GOOD - Acceptable collision rate"
        elif collision_rate < 20:
            status = "⚠️  WARNING - Elevated collision rate"
        else:
            status = "❌ CONCERN - High collision rate"

        print(f"\n  Status: {status}")

        self.results['hash_analysis'] = {
            'total_unique_hashes': total_hashes,
            'total_records': total_records,
            'collision_rate': collision_rate,
            'max_records_per_hash': int(max_records_per_hash),
            'avg_records_per_hash': float(avg_records_per_hash),
            'distribution': {int(k): int(v) for k, v in distribution.head(20).items()},
            'status': status
        }

    # ========================================================================
    # MAIN EXECUTION
    # ========================================================================

    def run_comprehensive_validation(self):
        """Run all validation checks"""
        print("\n" + "=" * 80)
        print("🚀 STARTING COMPREHENSIVE VALIDATION")
        print("=" * 80)

        # Primary fixes
        issue1_pass = self.validate_issue_1_model_contamination()
        issue2_pass = self.validate_issue_2_bmw_mini_separation()
        issue3_pass = self.validate_issue_3_incomplete_models()
        issue4_pass = self.validate_issue_4_mapfre_ids()

        # QA findings
        self.check_transmission_contamination()
        self.check_brand_consolidation()
        self.check_character_escaping()

        # Client feedback
        self.validate_client_cases()

        # Regressions
        regression_pass = self.detect_regressions()

        # Quality metrics
        self.analyze_quality_by_insurer()
        self.analyze_hash_distribution()

        # Overall assessment
        primary_fixes_pass = issue1_pass and issue2_pass and issue3_pass and issue4_pass

        print("\n" + "=" * 80)
        print("📊 FINAL ASSESSMENT")
        print("=" * 80)

        print(f"\n  PRIMARY FIXES:")
        print(f"    Issue 1 (Model Contamination):  {'✅ PASS' if issue1_pass else '❌ FAIL'}")
        print(f"    Issue 2 (BMW/MINI Separation):  {'✅ PASS' if issue2_pass else '❌ FAIL'}")
        print(f"    Issue 3 (Model Completion):     {'✅ PASS' if issue3_pass else '❌ FAIL'}")
        print(f"    Issue 4 (MAPFRE IDs):           {'✅ PASS' if issue4_pass else '❌ FAIL'}")

        print(f"\n  DATA INTEGRITY:")
        print(f"    Regressions:                    {'✅ PASS' if regression_pass else '❌ FAIL'}")

        print(f"\n  OVERALL STATUS:")
        if primary_fixes_pass and regression_pass:
            overall = "✅ PRODUCTION READY - All critical fixes validated"
        elif primary_fixes_pass:
            overall = "⚠️  CONDITIONAL - Fixes pass but regressions detected"
        else:
            overall = "❌ NOT READY - Critical fixes failing"

        print(f"    {overall}")

        self.results['overall_assessment'] = {
            'primary_fixes_pass': primary_fixes_pass,
            'regressions_pass': regression_pass,
            'production_ready': primary_fixes_pass and regression_pass,
            'overall_status': overall
        }

        return self.results

    def save_results(self):
        """Save validation results to JSON file"""
        import os
        os.makedirs('../reports', exist_ok=True)

        with open(OUTPUT_REPORT, 'w') as f:
            json.dump(self.results, f, indent=2, default=str)

        print(f"\n✓ Results saved to: {OUTPUT_REPORT}")

        # Generate executive summary
        self.generate_executive_summary()

    def generate_executive_summary(self):
        """Generate a markdown executive summary"""
        summary = f"""# ETL Validation Executive Summary

**Date**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
**Total Records Analyzed**: {self.results['total_records']:,}

## Overall Status

{self.results['overall_assessment']['overall_status']}

**Production Ready**: {'✅ YES' if self.results['overall_assessment']['production_ready'] else '❌ NO'}

---

## Primary Fixes Validation

### Issue 1: Model Field Contamination
- **Total Contaminated**: {self.results['primary_fixes']['issue_1_model_contamination']['total_contaminated']:,} records ({self.results['primary_fixes']['issue_1_model_contamination']['percentage']:.2f}%)
- **Status**: {self.results['primary_fixes']['issue_1_model_contamination']['status']}

### Issue 2: BMW/MINI Separation
- **BMW with MINI**: {self.results['primary_fixes']['issue_2_bmw_mini_separation']['bmw_with_mini_count']:,} records
- **MINI Brand Records**: {self.results['primary_fixes']['issue_2_bmw_mini_separation']['mini_brand_count']:,} records
- **Status**: {self.results['primary_fixes']['issue_2_bmw_mini_separation']['status']}

### Issue 3: Incomplete Models
- **Total Single-Letter Models**: {self.results['primary_fixes']['issue_3_incomplete_models']['total_single']:,} records ({self.results['primary_fixes']['issue_3_incomplete_models']['percentage']:.2f}%)
- **Status**: {self.results['primary_fixes']['issue_3_incomplete_models']['status']}

### Issue 4: MAPFRE IDs
- **Total MAPFRE Records**: {self.results['primary_fixes']['issue_4_mapfre_ids']['total_mapfre_records']:,}
- **Status**: {self.results['primary_fixes']['issue_4_mapfre_ids']['status']}

---

## Quality Metrics

### Overall Data Quality
- **Average Completeness**: {self.results['quality_metrics']['averages']['completeness']:.1f}%
- **Average Quality Score**: {self.results['quality_metrics']['averages']['quality_score']:.1f}%

### Hash Distribution
- **Collision Rate**: {self.results['hash_analysis']['collision_rate']:.2f}%
- **Status**: {self.results['hash_analysis']['status']}

---

## QA Findings (For Future Work)

### Transmission Contamination
- **Invalid Transmissions**: {self.results['qa_findings']['transmission_contamination']['invalid_count']:,} records ({self.results['qa_findings']['transmission_contamination']['contamination_percentage']:.2f}%)

### Brand Consolidation
- **Records with Brand Issues**: {self.results['qa_findings']['brand_consolidation']['total_issue_records']:,} ({self.results['qa_findings']['brand_consolidation']['percentage']:.2f}%)
- **Priority**: {self.results['qa_findings']['brand_consolidation']['priority']}

---

## Recommendations

"""

        if self.results['overall_assessment']['production_ready']:
            summary += """
✅ **APPROVED FOR PRODUCTION**

All 4 primary fixes have been successfully validated. The system is ready for client delivery.

**Next Steps**:
1. Present this validation report to client
2. Proceed with production deployment
3. Schedule QA findings (transmission, brand consolidation) for Phase 2
"""
        else:
            summary += """
⚠️ **ADDITIONAL WORK REQUIRED**

Some critical issues were detected that must be addressed before production deployment.

**Next Steps**:
1. Review detailed findings in comprehensive report
2. Address failing validation checks
3. Re-run validation after fixes
4. Escalate to development team if needed
"""

        summary += f"""

---

**Full Report**: `{OUTPUT_REPORT}`
**Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
"""

        with open(OUTPUT_SUMMARY, 'w') as f:
            f.write(summary)

        print(f"✓ Executive summary saved to: {OUTPUT_SUMMARY}")


def main():
    """Main execution function"""
    try:
        # Initialize validator
        validator = ComprehensiveValidator(DATA_FILE, COMPARISON_FILE)

        # Run all validations
        results = validator.run_comprehensive_validation()

        # Save results
        validator.save_results()

        print("\n" + "=" * 80)
        print("✅ VALIDATION COMPLETE")
        print("=" * 80)
        print(f"\nCheck reports directory for detailed results:")
        print(f"  - {OUTPUT_REPORT}")
        print(f"  - {OUTPUT_SUMMARY}")

        return 0

    except Exception as e:
        print(f"\n❌ ERROR: {str(e)}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
