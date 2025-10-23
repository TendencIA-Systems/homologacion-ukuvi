#!/usr/bin/env python3
"""
Comprehensive ETL Validation Script
===================================
Validates all fixes applied to the vehicle homologation system.

This script validates:
1. Issue 1: Model Field Contamination
2. Issue 2: BMW/MINI Brand Separation
3. Issue 3: Incomplete Model Completion
4. Issue 4: MAPFRE ID Format
5. QA Department findings
6. Data quality metrics
7. Cross-insurer consistency

Author: ETL Validation Team
Date: 2025-10-18
"""

import pandas as pd
import numpy as np
import json
import re
from collections import defaultdict, Counter
from datetime import datetime

class ETLValidator:
    """Comprehensive ETL validation for vehicle homologation system"""

    def __init__(self, csv_path):
        """Initialize validator with CSV data"""
        print(f"Loading data from {csv_path}...")
        self.df = pd.read_csv(csv_path)
        self.total_records = len(self.df)
        print(f"Loaded {self.total_records:,} records")

        # Initialize results storage
        self.results = {
            'executive_summary': {},
            'issue_1_model_contamination': {},
            'issue_2_bmw_mini_separation': {},
            'issue_3_incomplete_models': {},
            'issue_4_mapfre_ids': {},
            'qa_findings': {},
            'quality_metrics': {},
            'data_regressions': {},
            'recommendations': []
        }

    def run_full_validation(self):
        """Execute complete validation suite"""
        print("\n" + "="*80)
        print("COMPREHENSIVE ETL VALIDATION - STARTING")
        print("="*80)

        # Primary fixes validation
        self.validate_issue_1_model_contamination()
        self.validate_issue_2_bmw_mini_separation()
        self.validate_issue_3_incomplete_models()
        self.validate_issue_4_mapfre_ids()

        # QA findings
        self.check_qa_findings()

        # Quality metrics
        self.calculate_quality_metrics()
        self.analyze_hash_distribution()
        self.check_data_regressions()

        # Generate summary
        self.generate_executive_summary()

        return self.results

    # ========================================================================
    # ISSUE 1: MODEL FIELD CONTAMINATION
    # ========================================================================

    def validate_issue_1_model_contamination(self):
        """
        Validate that modelo fields are clean of trim/variant contamination.

        Expected: <1% of records affected (target: 0 records)

        Patterns to check:
        - SERIE prefixes: "SERIE 3" should be "3"
        - SDRIVE/XDRIVE suffixes: "X3 SDRIVE" should be "X3"
        - Trailing trim codes: "118 I", "120 IA" should be "118", "120"
        - Turbo abbreviations: "M2 TUR", "X2 TURBO" should be "M2", "X2"
        """
        print("\n" + "-"*80)
        print("ISSUE 1: MODEL FIELD CONTAMINATION VALIDATION")
        print("-"*80)

        contamination_patterns = {
            'SERIE_prefix': r'^SERIE\s+',
            'SDRIVE_suffix': r'\s+SDRIVE$',
            'XDRIVE_suffix': r'\s+XDRIVE$',
            'I_suffix': r'\s+I$',
            'IA_suffix': r'\s+IA$',
            'II_suffix': r'\s+II$',
            'TUR_suffix': r'\s+TUR(BO)?$',
            'MINI_prefix_in_model': r'^MINI\s+',
        }

        contaminated = pd.DataFrame()
        pattern_counts = {}

        for pattern_name, pattern_regex in contamination_patterns.items():
            matches = self.df[self.df['modelo'].str.contains(pattern_regex, case=False, na=False, regex=True)]
            pattern_counts[pattern_name] = len(matches)
            contaminated = pd.concat([contaminated, matches])

        # Remove duplicates
        contaminated = contaminated.drop_duplicates(subset=['id'])
        total_contaminated = len(contaminated)
        contamination_rate = (total_contaminated / self.total_records) * 100

        # Get samples
        samples = contaminated.head(20)[['marca', 'modelo', 'anio', 'version']].to_dict('records')

        # Determine pass/fail
        if total_contaminated == 0:
            status = "✅ PASS"
            severity = "NONE"
        elif total_contaminated < 50:
            status = "⚠️ ACCEPTABLE"
            severity = "LOW"
        elif total_contaminated < 100:
            status = "⚠️ CONDITIONAL PASS"
            severity = "MEDIUM"
        else:
            status = "❌ FAIL"
            severity = "HIGH"

        print(f"\nTotal contaminated records: {total_contaminated:,} ({contamination_rate:.2f}%)")
        print(f"Status: {status}")
        print(f"\nPattern breakdown:")
        for pattern, count in pattern_counts.items():
            if count > 0:
                print(f"  - {pattern}: {count:,} records")

        # Store results
        self.results['issue_1_model_contamination'] = {
            'total_contaminated': total_contaminated,
            'contamination_rate': contamination_rate,
            'pattern_counts': pattern_counts,
            'samples': samples,
            'status': status,
            'severity': severity,
            'pass': total_contaminated < 100
        }

    # ========================================================================
    # ISSUE 2: BMW/MINI SEPARATION
    # ========================================================================

    def validate_issue_2_bmw_mini_separation(self):
        """
        Validate BMW/MINI brand separation.

        Expected:
        - 0 records with marca='BMW' AND modelo contains 'MINI'
        - MINI vehicles should have marca='MINI'
        - No "MINI " prefix in modelo for MINI brands
        """
        print("\n" + "-"*80)
        print("ISSUE 2: BMW/MINI BRAND SEPARATION VALIDATION")
        print("-"*80)

        # Check 1: BMW with MINI in modelo
        bmw_with_mini = self.df[
            (self.df['marca'] == 'BMW') &
            (self.df['modelo'].str.contains('MINI', case=False, na=False))
        ]

        # Check 2: Count MINI brand records
        mini_brand = self.df[self.df['marca'] == 'MINI']

        # Check 3: MINI brand with "MINI " prefix in modelo
        mini_with_prefix = mini_brand[
            mini_brand['modelo'].str.contains(r'^MINI\s+', case=False, na=False, regex=True)
        ]

        # Get MINI variants
        mini_variants = mini_brand['modelo'].value_counts().to_dict()

        # Determine status
        bmw_mini_count = len(bmw_with_mini)
        mini_prefix_count = len(mini_with_prefix)

        if bmw_mini_count == 0 and mini_prefix_count == 0 and len(mini_brand) > 0:
            status = "✅ PASS"
            severity = "NONE"
        elif bmw_mini_count == 0 and mini_prefix_count < 10:
            status = "⚠️ ACCEPTABLE"
            severity = "LOW"
        else:
            status = "❌ FAIL"
            severity = "HIGH"

        print(f"\nBMW with MINI in modelo: {bmw_mini_count:,} records")
        print(f"MINI brand records: {len(mini_brand):,} records")
        print(f"MINI with 'MINI ' prefix: {mini_prefix_count:,} records")
        print(f"Status: {status}")

        if len(mini_brand) > 0:
            print(f"\nMINI variants found:")
            for variant, count in sorted(mini_variants.items(), key=lambda x: x[1], reverse=True)[:10]:
                print(f"  - {variant}: {count:,} records")

        # Store results
        self.results['issue_2_bmw_mini_separation'] = {
            'bmw_with_mini_count': bmw_mini_count,
            'mini_brand_count': len(mini_brand),
            'mini_with_prefix_count': mini_prefix_count,
            'mini_variants': mini_variants,
            'bmw_mini_samples': bmw_with_mini.head(10)[['marca', 'modelo', 'anio', 'version']].to_dict('records'),
            'status': status,
            'severity': severity,
            'pass': bmw_mini_count == 0 and mini_prefix_count < 10
        }

    # ========================================================================
    # ISSUE 3: INCOMPLETE MODEL COMPLETION
    # ========================================================================

    def validate_issue_3_incomplete_models(self):
        """
        Validate that single-letter models have been completed.

        Expected:
        - BMW M: 0 single "M" records (acceptable: <5)
        - BMW X: 0 single "X" records (acceptable: <5)
        - AUDI S/R: 0 single "S" or "R" records (acceptable: <5)
        """
        print("\n" + "-"*80)
        print("ISSUE 3: INCOMPLETE MODEL COMPLETION VALIDATION")
        print("-"*80)

        incomplete_models = {
            'BMW_M': self.df[(self.df['marca'] == 'BMW') & (self.df['modelo'] == 'M')],
            'BMW_X': self.df[(self.df['marca'] == 'BMW') & (self.df['modelo'] == 'X')],
            'AUDI_S': self.df[(self.df['marca'] == 'AUDI') & (self.df['modelo'] == 'S')],
            'AUDI_R': self.df[(self.df['marca'] == 'AUDI') & (self.df['modelo'] == 'R')],
        }

        total_incomplete = 0
        pattern_counts = {}
        samples = []

        for pattern, df_subset in incomplete_models.items():
            count = len(df_subset)
            pattern_counts[pattern] = count
            total_incomplete += count

            if count > 0:
                print(f"\n{pattern}: {count:,} records")
                pattern_samples = df_subset.head(5)[['marca', 'modelo', 'anio', 'version']].to_dict('records')
                samples.extend(pattern_samples)

                # Show version examples to see if we can extract
                for sample in pattern_samples[:3]:
                    print(f"  Example: {sample['marca']} {sample['modelo']} {sample['anio']} | version: {sample['version'][:60]}...")

        # Determine status
        if total_incomplete == 0:
            status = "✅ PASS"
            severity = "NONE"
        elif total_incomplete < 5:
            status = "✅ ACCEPTABLE"
            severity = "VERY LOW"
        elif total_incomplete < 20:
            status = "⚠️ CONDITIONAL PASS"
            severity = "LOW"
        else:
            status = "❌ FAIL"
            severity = "MEDIUM"

        print(f"\nTotal incomplete models: {total_incomplete:,} records")
        print(f"Status: {status}")

        # Store results
        self.results['issue_3_incomplete_models'] = {
            'total_incomplete': total_incomplete,
            'pattern_counts': pattern_counts,
            'samples': samples,
            'status': status,
            'severity': severity,
            'pass': total_incomplete < 20
        }

    # ========================================================================
    # ISSUE 4: MAPFRE ID FORMAT
    # ========================================================================

    def validate_issue_4_mapfre_ids(self):
        """
        Validate MAPFRE ID format.

        Expected:
        - All MAPFRE IDs must follow format: {CodModelo}_{Year}
        - 0 records without underscore
        - 100% unique IDs
        """
        print("\n" + "-"*80)
        print("ISSUE 4: MAPFRE ID FORMAT VALIDATION")
        print("-"*80)

        # Parse disponibilidad JSON to get MAPFRE records
        mapfre_records = []

        for idx, row in self.df.iterrows():
            try:
                if pd.notna(row['disponibilidad']):
                    disp = json.loads(row['disponibilidad']) if isinstance(row['disponibilidad'], str) else row['disponibilidad']

                    # Check if MAPFRE is in disponibilidad
                    if isinstance(disp, dict) and 'MAPFRE' in disp:
                        mapfre_info = disp['MAPFRE']
                        if isinstance(mapfre_info, dict) and 'id_original' in mapfre_info:
                            mapfre_records.append({
                                'id': row['id'],
                                'id_original': mapfre_info['id_original'],
                                'marca': row['marca'],
                                'modelo': row['modelo'],
                                'anio': row['anio']
                            })
            except:
                continue

        if len(mapfre_records) == 0:
            print("⚠️ WARNING: No MAPFRE records found in disponibilidad field")
            print("This might indicate the data structure is different than expected.")

            # Try alternative: check if there's an origen_aseguradora field or id_original pattern
            # For now, mark as needs manual review
            status = "⚠️ MANUAL REVIEW NEEDED"
            severity = "UNKNOWN"

            self.results['issue_4_mapfre_ids'] = {
                'mapfre_count': 0,
                'ids_without_year': 0,
                'duplicate_ids': 0,
                'status': status,
                'severity': severity,
                'pass': False,
                'note': "MAPFRE records not found in expected format - manual review required"
            }
            return

        mapfre_df = pd.DataFrame(mapfre_records)

        # Check IDs without year (no underscore)
        ids_without_year = mapfre_df[~mapfre_df['id_original'].str.contains('_', na=False)]

        # Check for duplicate IDs
        id_counts = mapfre_df['id_original'].value_counts()
        duplicate_ids = id_counts[id_counts > 1]

        # Samples
        samples_without_year = ids_without_year.head(10).to_dict('records')
        samples_duplicates = []
        if len(duplicate_ids) > 0:
            for dup_id in duplicate_ids.head(5).index:
                samples_duplicates.append({
                    'id_original': dup_id,
                    'count': int(id_counts[dup_id]),
                    'examples': mapfre_df[mapfre_df['id_original'] == dup_id].head(3).to_dict('records')
                })

        # Determine status
        without_year_count = len(ids_without_year)
        duplicate_count = len(duplicate_ids)

        if without_year_count == 0 and duplicate_count == 0:
            status = "✅ PASS"
            severity = "NONE"
        elif without_year_count < 10 and duplicate_count == 0:
            status = "⚠️ ACCEPTABLE"
            severity = "LOW"
        else:
            status = "❌ FAIL"
            severity = "HIGH"

        print(f"\nMAPFRE records found: {len(mapfre_df):,}")
        print(f"IDs without year suffix: {without_year_count:,}")
        print(f"Duplicate IDs: {duplicate_count:,}")
        print(f"Status: {status}")

        # Store results
        self.results['issue_4_mapfre_ids'] = {
            'mapfre_count': len(mapfre_df),
            'ids_without_year': without_year_count,
            'duplicate_ids': duplicate_count,
            'samples_without_year': samples_without_year,
            'samples_duplicates': samples_duplicates,
            'status': status,
            'severity': severity,
            'pass': without_year_count < 10 and duplicate_count == 0
        }

    # ========================================================================
    # QA DEPARTMENT FINDINGS
    # ========================================================================

    def check_qa_findings(self):
        """
        Check additional QA findings that may not be fixed yet.

        These are NOT part of the current fix but should be monitored:
        1. Transmission column contamination
        2. Brand consolidation issues
        3. Character escaping issues
        """
        print("\n" + "-"*80)
        print("QA DEPARTMENT FINDINGS - ADDITIONAL ISSUES CHECK")
        print("-"*80)

        qa_results = {}

        # 1. Transmission column issues
        valid_transmissions = ['AUTO', 'MANUAL', 'CVT', 'DSG', 'AUTOMATICA', 'MECANICA', 'TIPTRONIC']

        invalid_trans = self.df[
            (self.df['transmision'].notna()) &
            (~self.df['transmision'].isin(valid_transmissions))
        ]

        trans_contamination = len(invalid_trans)
        trans_rate = (trans_contamination / self.total_records) * 100

        print(f"\n1. Transmission Column:")
        print(f"   Valid transmissions: {len(self.df[self.df['transmision'].isin(valid_transmissions)]):,}")
        print(f"   Invalid/contaminated: {trans_contamination:,} ({trans_rate:.1f}%)")

        if trans_contamination > 0:
            print(f"   Sample invalid values:")
            for val in invalid_trans['transmision'].value_counts().head(10).items():
                print(f"     - '{val[0]}': {val[1]:,} records")

        qa_results['transmission_contamination'] = {
            'count': trans_contamination,
            'rate': trans_rate,
            'samples': invalid_trans['transmision'].value_counts().head(20).to_dict()
        }

        # 2. Brand consolidation issues
        problematic_brands = {
            'AUDI II': 'AUDI',
            'BMW BW': 'BMW',
            'MERCEDES BENZ II': 'MERCEDES BENZ',
            'KIA MOTORS': 'KIA',
            'GREAT WALL MOTORS': 'GREAT WALL',
            'TESLA MOTORS': 'TESLA',
            'AUTOS': 'INVALID',
            'MOTOCICLETAS': 'INVALID',
            'MULTIMARCA': 'INVALID',
            'LEGALIZADO': 'INVALID'
        }

        brand_issues = {}
        total_brand_issues = 0

        print(f"\n2. Brand Consolidation Issues:")
        for bad_brand, correct_brand in problematic_brands.items():
            count = len(self.df[self.df['marca'] == bad_brand])
            if count > 0:
                brand_issues[bad_brand] = count
                total_brand_issues += count
                print(f"   - '{bad_brand}' (should be '{correct_brand}'): {count:,} records")

        if total_brand_issues == 0:
            print(f"   ✅ No problematic brand variations found")

        qa_results['brand_consolidation'] = {
            'total_issues': total_brand_issues,
            'issues': brand_issues
        }

        # 3. Character escaping issues
        escape_chars = self.df[
            self.df['version'].str.contains(r'[\\"]', case=False, na=False, regex=True)
        ]

        escape_count = len(escape_chars)
        escape_rate = (escape_count / self.total_records) * 100

        print(f"\n3. Character Escaping Issues:")
        print(f"   Records with escape characters: {escape_count:,} ({escape_rate:.2f}%)")

        if escape_count > 0:
            print(f"   Sample records:")
            for sample in escape_chars.head(5)['version'].values:
                print(f"     - {sample[:80]}...")

        qa_results['character_escaping'] = {
            'count': escape_count,
            'rate': escape_rate,
            'samples': escape_chars.head(10)['version'].tolist()
        }

        self.results['qa_findings'] = qa_results

    # ========================================================================
    # QUALITY METRICS
    # ========================================================================

    def calculate_quality_metrics(self):
        """Calculate comprehensive quality metrics"""
        print("\n" + "-"*80)
        print("QUALITY METRICS CALCULATION")
        print("-"*80)

        # Overall completeness
        required_fields = ['marca', 'modelo', 'anio', 'hash_comercial']

        completeness = {}
        for field in required_fields:
            non_null = self.df[field].notna().sum()
            completeness[field] = (non_null / self.total_records) * 100

        overall_completeness = sum(completeness.values()) / len(completeness)

        print(f"\nField Completeness:")
        for field, pct in completeness.items():
            print(f"  - {field}: {pct:.2f}%")
        print(f"  Overall: {overall_completeness:.2f}%")

        # By-insurer metrics (if we can extract from disponibilidad)
        insurer_metrics = self.calculate_insurer_metrics()

        # Overall quality score
        # Base on: completeness, contamination, separation, etc.
        contamination_penalty = (self.results['issue_1_model_contamination']['contamination_rate'] * 10)
        separation_penalty = (self.results['issue_2_bmw_mini_separation']['bmw_with_mini_count'] / self.total_records) * 100 * 20
        incomplete_penalty = (self.results['issue_3_incomplete_models']['total_incomplete'] / self.total_records) * 100 * 5

        quality_score = max(0, overall_completeness - contamination_penalty - separation_penalty - incomplete_penalty)

        print(f"\n📊 Overall Quality Score: {quality_score:.2f}% / 100%")

        if quality_score >= 95:
            quality_status = "✅ EXCELLENT"
        elif quality_score >= 90:
            quality_status = "✅ GOOD"
        elif quality_score >= 85:
            quality_status = "⚠️ ACCEPTABLE"
        else:
            quality_status = "❌ NEEDS IMPROVEMENT"

        print(f"   Status: {quality_status}")

        self.results['quality_metrics'] = {
            'completeness': completeness,
            'overall_completeness': overall_completeness,
            'quality_score': quality_score,
            'quality_status': quality_status,
            'insurer_metrics': insurer_metrics
        }

    def calculate_insurer_metrics(self):
        """Calculate per-insurer quality metrics from disponibilidad"""
        print(f"\nPer-Insurer Metrics:")

        insurer_counts = defaultdict(int)

        # Parse disponibilidad to count per insurer
        for idx, row in self.df.iterrows():
            try:
                if pd.notna(row['disponibilidad']):
                    disp = json.loads(row['disponibilidad']) if isinstance(row['disponibilidad'], str) else row['disponibilidad']
                    if isinstance(disp, dict):
                        for insurer in disp.keys():
                            insurer_counts[insurer] += 1
            except:
                continue

        # Sort and display
        sorted_insurers = sorted(insurer_counts.items(), key=lambda x: x[1], reverse=True)

        for insurer, count in sorted_insurers:
            pct = (count / self.total_records) * 100
            print(f"  - {insurer}: {count:,} records ({pct:.1f}%)")

        return dict(sorted_insurers)

    # ========================================================================
    # HASH DISTRIBUTION
    # ========================================================================

    def analyze_hash_distribution(self):
        """Analyze hash distribution and collision rates"""
        print("\n" + "-"*80)
        print("HASH DISTRIBUTION ANALYSIS")
        print("-"*80)

        # Count unique hashes
        unique_hashes = self.df['hash_comercial'].nunique()
        hash_collision_rate = (1 - (unique_hashes / self.total_records)) * 100

        # Find hash groups
        hash_counts = self.df['hash_comercial'].value_counts()
        max_records_per_hash = hash_counts.max()
        hashes_with_collisions = len(hash_counts[hash_counts > 1])

        print(f"\nTotal records: {self.total_records:,}")
        print(f"Unique hashes: {unique_hashes:,}")
        print(f"Collision rate: {hash_collision_rate:.2f}%")
        print(f"Max records per hash: {max_records_per_hash:,}")
        print(f"Hashes with collisions: {hashes_with_collisions:,}")

        # Sample high-collision hashes
        print(f"\nTop collision groups:")
        for hash_val, count in hash_counts.head(10).items():
            group = self.df[self.df['hash_comercial'] == hash_val]
            sample = group.iloc[0]
            print(f"  - {count:,} records: {sample['marca']} {sample['modelo']} {sample['anio']} (hash: {hash_val[:16]}...)")

        # Determine status
        if hash_collision_rate < 5:
            status = "✅ EXCELLENT"
        elif hash_collision_rate < 10:
            status = "✅ GOOD"
        elif hash_collision_rate < 20:
            status = "⚠️ ACCEPTABLE"
        else:
            status = "❌ NEEDS IMPROVEMENT"

        self.results['hash_distribution'] = {
            'unique_hashes': unique_hashes,
            'collision_rate': hash_collision_rate,
            'max_per_hash': max_records_per_hash,
            'hashes_with_collisions': hashes_with_collisions,
            'status': status
        }

    # ========================================================================
    # DATA REGRESSIONS
    # ========================================================================

    def check_data_regressions(self):
        """Check for data regressions and new issues"""
        print("\n" + "-"*80)
        print("DATA REGRESSION CHECKS")
        print("-"*80)

        regressions = {}

        # 1. Check for NULL values in critical fields
        print(f"\n1. NULL Value Check:")
        for field in ['marca', 'modelo', 'anio', 'hash_comercial']:
            null_count = self.df[field].isna().sum()
            null_rate = (null_count / self.total_records) * 100
            print(f"   - {field}: {null_count:,} nulls ({null_rate:.2f}%)")
            regressions[f'null_{field}'] = null_count

        # 2. Check for empty strings
        print(f"\n2. Empty String Check:")
        empty_counts = {}
        for field in ['marca', 'modelo', 'version']:
            empty_count = len(self.df[self.df[field] == ''])
            empty_rate = (empty_count / self.total_records) * 100
            print(f"   - {field}: {empty_count:,} empty ({empty_rate:.2f}%)")
            empty_counts[field] = empty_count

        regressions['empty_strings'] = empty_counts

        # 3. Check for double spaces
        print(f"\n3. Double Space Check:")
        double_space_modelo = len(self.df[self.df['modelo'].str.contains('  ', na=False)])
        double_space_version = len(self.df[self.df['version'].str.contains('  ', na=False)])
        print(f"   - modelo: {double_space_modelo:,} records")
        print(f"   - version: {double_space_version:,} records")

        regressions['double_spaces'] = {
            'modelo': double_space_modelo,
            'version': double_space_version
        }

        # 4. Check for leading/trailing spaces
        print(f"\n4. Leading/Trailing Space Check:")
        leading_trailing_modelo = len(self.df[self.df['modelo'].str.strip() != self.df['modelo']])
        leading_trailing_version = len(self.df[self.df['version'].str.strip() != self.df['version']])
        print(f"   - modelo: {leading_trailing_modelo:,} records")
        print(f"   - version: {leading_trailing_version:,} records")

        regressions['leading_trailing_spaces'] = {
            'modelo': leading_trailing_modelo,
            'version': leading_trailing_version
        }

        self.results['data_regressions'] = regressions

    # ========================================================================
    # EXECUTIVE SUMMARY
    # ========================================================================

    def generate_executive_summary(self):
        """Generate executive summary of validation"""
        print("\n" + "="*80)
        print("EXECUTIVE SUMMARY")
        print("="*80)

        # Overall status
        issue_1_pass = self.results['issue_1_model_contamination']['pass']
        issue_2_pass = self.results['issue_2_bmw_mini_separation']['pass']
        issue_3_pass = self.results['issue_3_incomplete_models']['pass']
        issue_4_pass = self.results['issue_4_mapfre_ids']['pass']

        all_pass = issue_1_pass and issue_2_pass and issue_3_pass and issue_4_pass

        if all_pass:
            overall_status = "✅ ALL FIXES VALIDATED - PRODUCTION READY"
            recommendation = "APPROVED FOR PRODUCTION"
        elif issue_1_pass and issue_2_pass and (not issue_3_pass or not issue_4_pass):
            overall_status = "⚠️ MOSTLY FIXED - MINOR ISSUES REMAIN"
            recommendation = "CONDITIONAL APPROVAL - MONITOR EDGE CASES"
        else:
            overall_status = "❌ CRITICAL ISSUES FOUND"
            recommendation = "NOT READY - REQUIRES FIXES"

        print(f"\nOverall Status: {overall_status}")
        print(f"Recommendation: {recommendation}")

        print(f"\n📊 Validation Results:")
        print(f"  Issue 1 (Model Contamination): {self.results['issue_1_model_contamination']['status']}")
        print(f"  Issue 2 (BMW/MINI Separation): {self.results['issue_2_bmw_mini_separation']['status']}")
        print(f"  Issue 3 (Incomplete Models): {self.results['issue_3_incomplete_models']['status']}")
        print(f"  Issue 4 (MAPFRE IDs): {self.results['issue_4_mapfre_ids']['status']}")

        print(f"\n📈 Quality Metrics:")
        print(f"  Overall Quality Score: {self.results['quality_metrics']['quality_score']:.2f}%")
        print(f"  Hash Collision Rate: {self.results['hash_distribution']['collision_rate']:.2f}%")
        print(f"  Data Completeness: {self.results['quality_metrics']['overall_completeness']:.2f}%")

        self.results['executive_summary'] = {
            'overall_status': overall_status,
            'recommendation': recommendation,
            'all_pass': all_pass,
            'timestamp': datetime.now().isoformat()
        }

        # Generate recommendations
        self.generate_recommendations()

    def generate_recommendations(self):
        """Generate actionable recommendations"""
        recommendations = []

        # Based on issue results
        if not self.results['issue_1_model_contamination']['pass']:
            count = self.results['issue_1_model_contamination']['total_contaminated']
            recommendations.append({
                'priority': 'HIGH',
                'category': 'Model Contamination',
                'issue': f'{count:,} records still have contaminated modelo fields',
                'action': 'Review cleanModelField() function implementation and reprocess affected insurers',
                'timeline': '1-2 days'
            })

        if not self.results['issue_2_bmw_mini_separation']['pass']:
            bmw_mini = self.results['issue_2_bmw_mini_separation']['bmw_with_mini_count']
            if bmw_mini > 0:
                recommendations.append({
                    'priority': 'CRITICAL',
                    'category': 'BMW/MINI Separation',
                    'issue': f'{bmw_mini:,} MINI vehicles still under BMW brand',
                    'action': 'Fix BRAND_ALIASES mapping and reprocess data',
                    'timeline': '1 day'
                })

        if not self.results['issue_3_incomplete_models']['pass']:
            incomplete = self.results['issue_3_incomplete_models']['total_incomplete']
            if incomplete > 20:
                recommendations.append({
                    'priority': 'MEDIUM',
                    'category': 'Incomplete Models',
                    'issue': f'{incomplete:,} single-letter models not completed',
                    'action': 'Enhance extractCompleteModel() function to better parse version strings',
                    'timeline': '2-3 days'
                })

        # QA findings
        trans_rate = self.results['qa_findings']['transmission_contamination']['rate']
        if trans_rate > 50:
            recommendations.append({
                'priority': 'HIGH',
                'category': 'Transmission Quality',
                'issue': f'{trans_rate:.1f}% of records have invalid transmission values',
                'action': 'Plan transmission normalization in next phase',
                'timeline': 'Future sprint'
            })

        # Quality score
        quality_score = self.results['quality_metrics']['quality_score']
        if quality_score < 90:
            recommendations.append({
                'priority': 'MEDIUM',
                'category': 'Overall Quality',
                'issue': f'Quality score below 90% (current: {quality_score:.1f}%)',
                'action': 'Address top contamination patterns and improve data completeness',
                'timeline': '3-5 days'
            })

        self.results['recommendations'] = recommendations

        if recommendations:
            print(f"\n🎯 Recommendations:")
            for i, rec in enumerate(recommendations, 1):
                print(f"\n  {i}. [{rec['priority']}] {rec['category']}")
                print(f"     Issue: {rec['issue']}")
                print(f"     Action: {rec['action']}")
                print(f"     Timeline: {rec['timeline']}")

    # ========================================================================
    # REPORT GENERATION
    # ========================================================================

    def save_results(self, output_path):
        """Save validation results to JSON"""
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(self.results, f, indent=2, ensure_ascii=False)
        print(f"\n💾 Results saved to: {output_path}")


def main():
    """Main execution"""
    import sys

    # CSV file path
    csv_path = '/mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl/data/validation/catalogo_revision.csv'
    output_path = '/mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl/reports/validation_results.json'

    # Create validator
    validator = ETLValidator(csv_path)

    # Run validation
    results = validator.run_full_validation()

    # Save results
    validator.save_results(output_path)

    print("\n" + "="*80)
    print("VALIDATION COMPLETE")
    print("="*80)
    print(f"\nRecommendation: {results['executive_summary']['recommendation']}")
    print(f"\nNext steps:")
    print("  1. Review detailed results in: {output_path}")
    print("  2. Address any critical issues found")
    print("  3. Generate client report from results")

    return 0 if results['executive_summary']['all_pass'] else 1


if __name__ == '__main__':
    exit(main())
