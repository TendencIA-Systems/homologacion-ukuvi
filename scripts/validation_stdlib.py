#!/usr/bin/env python3
"""
Comprehensive ETL Validation Script (Standard Library Only)
===========================================================
Validates all fixes applied to the vehicle homologation system.

Uses only Python standard library - no external dependencies required.

Author: ETL Validation Team
Date: 2025-10-18
"""

import csv
import json
import re
from collections import defaultdict, Counter
from datetime import datetime


class ETLValidator:
    """Comprehensive ETL validation for vehicle homologation system"""

    def __init__(self, csv_path):
        """Initialize validator with CSV data"""
        print(f"Loading data from {csv_path}...")

        self.records = []
        self.headers = []

        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            self.headers = reader.fieldnames
            self.records = list(reader)

        self.total_records = len(self.records)
        print(f"Loaded {self.total_records:,} records")
        print(f"Fields: {', '.join(self.headers)}")

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

        pattern_counts = defaultdict(int)
        contaminated_ids = set()
        samples = []

        for record in self.records:
            modelo = record.get('modelo', '')
            if not modelo:
                continue

            for pattern_name, pattern_regex in contamination_patterns.items():
                if re.search(pattern_regex, modelo, re.IGNORECASE):
                    pattern_counts[pattern_name] += 1
                    contaminated_ids.add(record.get('id', ''))

                    if len(samples) < 20:
                        samples.append({
                            'marca': record.get('marca', ''),
                            'modelo': modelo,
                            'anio': record.get('anio', ''),
                            'version': record.get('version', '')[:60]
                        })

        total_contaminated = len(contaminated_ids)
        contamination_rate = (total_contaminated / self.total_records) * 100 if self.total_records > 0 else 0

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
        for pattern, count in sorted(pattern_counts.items(), key=lambda x: x[1], reverse=True):
            if count > 0:
                print(f"  - {pattern}: {count:,} records")

        if samples:
            print(f"\nSample contaminated records:")
            for i, sample in enumerate(samples[:5], 1):
                print(f"  {i}. {sample['marca']} {sample['modelo']} {sample['anio']}")

        # Store results
        self.results['issue_1_model_contamination'] = {
            'total_contaminated': total_contaminated,
            'contamination_rate': contamination_rate,
            'pattern_counts': dict(pattern_counts),
            'samples': samples[:20],
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
        """
        print("\n" + "-"*80)
        print("ISSUE 2: BMW/MINI BRAND SEPARATION VALIDATION")
        print("-"*80)

        bmw_with_mini = []
        mini_brand_records = []
        mini_with_prefix = []
        mini_variants = Counter()

        for record in self.records:
            marca = record.get('marca', '')
            modelo = record.get('modelo', '')

            # Check 1: BMW with MINI in modelo
            if marca == 'BMW' and 'MINI' in modelo.upper():
                bmw_with_mini.append(record)

            # Check 2: Count MINI brand records
            if marca == 'MINI':
                mini_brand_records.append(record)
                mini_variants[modelo] += 1

                # Check 3: MINI brand with "MINI " prefix
                if re.match(r'^MINI\s+', modelo, re.IGNORECASE):
                    mini_with_prefix.append(record)

        # Determine status
        bmw_mini_count = len(bmw_with_mini)
        mini_prefix_count = len(mini_with_prefix)
        mini_brand_count = len(mini_brand_records)

        if bmw_mini_count == 0 and mini_prefix_count == 0 and mini_brand_count > 0:
            status = "✅ PASS"
            severity = "NONE"
        elif bmw_mini_count == 0 and mini_prefix_count < 10:
            status = "⚠️ ACCEPTABLE"
            severity = "LOW"
        else:
            status = "❌ FAIL"
            severity = "HIGH"

        print(f"\nBMW with MINI in modelo: {bmw_mini_count:,} records")
        print(f"MINI brand records: {mini_brand_count:,} records")
        print(f"MINI with 'MINI ' prefix: {mini_prefix_count:,} records")
        print(f"Status: {status}")

        if mini_brand_count > 0:
            print(f"\nMINI variants found:")
            for variant, count in mini_variants.most_common(10):
                print(f"  - {variant}: {count:,} records")

        if bmw_mini_count > 0:
            print(f"\nSample BMW with MINI:")
            for i, rec in enumerate(bmw_with_mini[:5], 1):
                print(f"  {i}. {rec['marca']} {rec['modelo']} {rec['anio']}")

        # Store results
        self.results['issue_2_bmw_mini_separation'] = {
            'bmw_with_mini_count': bmw_mini_count,
            'mini_brand_count': mini_brand_count,
            'mini_with_prefix_count': mini_prefix_count,
            'mini_variants': dict(mini_variants.most_common(20)),
            'bmw_mini_samples': [
                {'marca': r['marca'], 'modelo': r['modelo'], 'anio': r['anio']}
                for r in bmw_with_mini[:10]
            ],
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
        - BMW M: <5 single "M" records
        - BMW X: <5 single "X" records
        - AUDI S/R: <5 single "S" or "R" records
        """
        print("\n" + "-"*80)
        print("ISSUE 3: INCOMPLETE MODEL COMPLETION VALIDATION")
        print("-"*80)

        incomplete_models = {
            'BMW_M': [],
            'BMW_X': [],
            'AUDI_S': [],
            'AUDI_R': [],
        }

        for record in self.records:
            marca = record.get('marca', '')
            modelo = record.get('modelo', '')

            if marca == 'BMW' and modelo == 'M':
                incomplete_models['BMW_M'].append(record)
            elif marca == 'BMW' and modelo == 'X':
                incomplete_models['BMW_X'].append(record)
            elif marca == 'AUDI' and modelo == 'S':
                incomplete_models['AUDI_S'].append(record)
            elif marca == 'AUDI' and modelo == 'R':
                incomplete_models['AUDI_R'].append(record)

        total_incomplete = sum(len(records) for records in incomplete_models.values())
        pattern_counts = {k: len(v) for k, v in incomplete_models.items()}

        samples = []
        for pattern, records in incomplete_models.items():
            if records:
                print(f"\n{pattern}: {len(records):,} records")
                for rec in records[:3]:
                    version = rec.get('version', '')
                    print(f"  Example: {rec['marca']} {rec['modelo']} {rec['anio']} | version: {version[:60]}...")
                    samples.append({
                        'marca': rec['marca'],
                        'modelo': rec['modelo'],
                        'anio': rec['anio'],
                        'version': version[:100]
                    })

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
            'samples': samples[:20],
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
        """
        print("\n" + "-"*80)
        print("ISSUE 4: MAPFRE ID FORMAT VALIDATION")
        print("-"*80)

        mapfre_records = []

        for record in self.records:
            disp_raw = record.get('disponibilidad', '')
            if not disp_raw:
                continue

            try:
                # Try to parse JSON
                if disp_raw.startswith('{'):
                    disp = json.loads(disp_raw)

                    if isinstance(disp, dict) and 'MAPFRE' in disp:
                        mapfre_info = disp['MAPFRE']
                        if isinstance(mapfre_info, dict) and 'id_original' in mapfre_info:
                            mapfre_records.append({
                                'id': record.get('id', ''),
                                'id_original': mapfre_info['id_original'],
                                'marca': record.get('marca', ''),
                                'modelo': record.get('modelo', ''),
                                'anio': record.get('anio', '')
                            })
            except:
                continue

        if len(mapfre_records) == 0:
            print("⚠️ WARNING: No MAPFRE records found in disponibilidad field")
            print("Checking if data structure is different...")

            # Alternative check: look for any pattern
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

        # Check IDs without year (no underscore)
        ids_without_year = [r for r in mapfre_records if '_' not in str(r['id_original'])]

        # Check for duplicate IDs
        id_counter = Counter(r['id_original'] for r in mapfre_records)
        duplicate_ids = {k: v for k, v in id_counter.items() if v > 1}

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

        print(f"\nMAPFRE records found: {len(mapfre_records):,}")
        print(f"IDs without year suffix: {without_year_count:,}")
        print(f"Duplicate IDs: {duplicate_count:,}")
        print(f"Status: {status}")

        if ids_without_year:
            print(f"\nSample IDs without year:")
            for rec in ids_without_year[:5]:
                print(f"  - ID: {rec['id_original']} | {rec['marca']} {rec['modelo']} {rec['anio']}")

        if duplicate_ids:
            print(f"\nSample duplicate IDs:")
            for dup_id, count in list(duplicate_ids.items())[:5]:
                print(f"  - ID: {dup_id} ({count} occurrences)")

        # Store results
        self.results['issue_4_mapfre_ids'] = {
            'mapfre_count': len(mapfre_records),
            'ids_without_year': without_year_count,
            'duplicate_ids': duplicate_count,
            'samples_without_year': ids_without_year[:10],
            'samples_duplicates': list(duplicate_ids.items())[:10],
            'status': status,
            'severity': severity,
            'pass': without_year_count < 10 and duplicate_count == 0
        }

    # ========================================================================
    # QA DEPARTMENT FINDINGS
    # ========================================================================

    def check_qa_findings(self):
        """Check additional QA findings"""
        print("\n" + "-"*80)
        print("QA DEPARTMENT FINDINGS - ADDITIONAL ISSUES CHECK")
        print("-"*80)

        qa_results = {}

        # 1. Transmission column issues
        valid_transmissions = ['AUTO', 'MANUAL', 'CVT', 'DSG', 'AUTOMATICA', 'MECANICA', 'TIPTRONIC']

        invalid_trans_records = []
        trans_values = Counter()

        for record in self.records:
            trans = record.get('transmision', '')
            if trans:
                trans_values[trans] += 1
                if trans not in valid_transmissions:
                    invalid_trans_records.append(record)

        trans_contamination = len(invalid_trans_records)
        trans_rate = (trans_contamination / self.total_records) * 100 if self.total_records > 0 else 0

        print(f"\n1. Transmission Column:")
        print(f"   Total with transmission: {sum(1 for r in self.records if r.get('transmision')):,}")
        print(f"   Invalid/contaminated: {trans_contamination:,} ({trans_rate:.1f}%)")

        if trans_contamination > 0:
            print(f"   Sample invalid values:")
            for val, count in trans_values.most_common(15):
                if val not in valid_transmissions:
                    print(f"     - '{val}': {count:,} records")

        qa_results['transmission_contamination'] = {
            'count': trans_contamination,
            'rate': trans_rate,
            'samples': dict(trans_values.most_common(20))
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
            count = sum(1 for r in self.records if r.get('marca', '') == bad_brand)
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
        escape_pattern = r'[\\"]'
        escape_records = []

        for record in self.records:
            version = record.get('version', '')
            if re.search(escape_pattern, version):
                escape_records.append(record)

        escape_count = len(escape_records)
        escape_rate = (escape_count / self.total_records) * 100 if self.total_records > 0 else 0

        print(f"\n3. Character Escaping Issues:")
        print(f"   Records with escape characters: {escape_count:,} ({escape_rate:.2f}%)")

        if escape_count > 0:
            print(f"   Sample records:")
            for rec in escape_records[:5]:
                version = rec.get('version', '')
                print(f"     - {version[:80]}...")

        qa_results['character_escaping'] = {
            'count': escape_count,
            'rate': escape_rate,
            'samples': [r.get('version', '')[:100] for r in escape_records[:10]]
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

        # Field completeness
        required_fields = ['marca', 'modelo', 'anio', 'hash_comercial']
        completeness = {}

        for field in required_fields:
            non_null = sum(1 for r in self.records if r.get(field))
            completeness[field] = (non_null / self.total_records) * 100 if self.total_records > 0 else 0

        overall_completeness = sum(completeness.values()) / len(completeness) if completeness else 0

        print(f"\nField Completeness:")
        for field, pct in completeness.items():
            print(f"  - {field}: {pct:.2f}%")
        print(f"  Overall: {overall_completeness:.2f}%")

        # Per-insurer metrics
        insurer_counts = defaultdict(int)

        for record in self.records:
            disp_raw = record.get('disponibilidad', '')
            if not disp_raw:
                continue

            try:
                if disp_raw.startswith('{'):
                    disp = json.loads(disp_raw)
                    if isinstance(disp, dict):
                        for insurer in disp.keys():
                            insurer_counts[insurer] += 1
            except:
                continue

        print(f"\nPer-Insurer Metrics:")
        for insurer, count in sorted(insurer_counts.items(), key=lambda x: x[1], reverse=True):
            pct = (count / self.total_records) * 100
            print(f"  - {insurer}: {count:,} records ({pct:.1f}%)")

        # Quality score calculation
        contamination_penalty = (self.results['issue_1_model_contamination']['contamination_rate'] * 10)
        separation_penalty = (self.results['issue_2_bmw_mini_separation']['bmw_with_mini_count'] / self.total_records) * 100 * 20 if self.total_records > 0 else 0
        incomplete_penalty = (self.results['issue_3_incomplete_models']['total_incomplete'] / self.total_records) * 100 * 5 if self.total_records > 0 else 0

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
            'insurer_metrics': dict(insurer_counts)
        }

    # ========================================================================
    # HASH DISTRIBUTION
    # ========================================================================

    def analyze_hash_distribution(self):
        """Analyze hash distribution and collision rates"""
        print("\n" + "-"*80)
        print("HASH DISTRIBUTION ANALYSIS")
        print("-"*80)

        hash_counts = Counter(r.get('hash_comercial', '') for r in self.records if r.get('hash_comercial'))

        unique_hashes = len(hash_counts)
        hash_collision_rate = (1 - (unique_hashes / self.total_records)) * 100 if self.total_records > 0 else 0
        max_records_per_hash = max(hash_counts.values()) if hash_counts else 0
        hashes_with_collisions = sum(1 for count in hash_counts.values() if count > 1)

        print(f"\nTotal records: {self.total_records:,}")
        print(f"Unique hashes: {unique_hashes:,}")
        print(f"Collision rate: {hash_collision_rate:.2f}%")
        print(f"Max records per hash: {max_records_per_hash:,}")
        print(f"Hashes with collisions: {hashes_with_collisions:,}")

        # Sample high-collision hashes
        print(f"\nTop collision groups:")
        for hash_val, count in hash_counts.most_common(10):
            # Find a sample record with this hash
            sample = next((r for r in self.records if r.get('hash_comercial') == hash_val), None)
            if sample:
                print(f"  - {count:,} records: {sample.get('marca', '')} {sample.get('modelo', '')} {sample.get('anio', '')} (hash: {hash_val[:16]}...)")

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
        """Check for data regressions"""
        print("\n" + "-"*80)
        print("DATA REGRESSION CHECKS")
        print("-"*80)

        regressions = {}

        # 1. NULL values in critical fields
        print(f"\n1. NULL Value Check:")
        for field in ['marca', 'modelo', 'anio', 'hash_comercial']:
            null_count = sum(1 for r in self.records if not r.get(field))
            null_rate = (null_count / self.total_records) * 100 if self.total_records > 0 else 0
            print(f"   - {field}: {null_count:,} nulls ({null_rate:.2f}%)")
            regressions[f'null_{field}'] = null_count

        # 2. Empty strings
        print(f"\n2. Empty String Check:")
        empty_counts = {}
        for field in ['marca', 'modelo', 'version']:
            empty_count = sum(1 for r in self.records if r.get(field) == '')
            empty_rate = (empty_count / self.total_records) * 100 if self.total_records > 0 else 0
            print(f"   - {field}: {empty_count:,} empty ({empty_rate:.2f}%)")
            empty_counts[field] = empty_count

        regressions['empty_strings'] = empty_counts

        # 3. Double spaces
        print(f"\n3. Double Space Check:")
        double_space_modelo = sum(1 for r in self.records if '  ' in r.get('modelo', ''))
        double_space_version = sum(1 for r in self.records if '  ' in r.get('version', ''))
        print(f"   - modelo: {double_space_modelo:,} records")
        print(f"   - version: {double_space_version:,} records")

        regressions['double_spaces'] = {
            'modelo': double_space_modelo,
            'version': double_space_version
        }

        # 4. Leading/trailing spaces
        print(f"\n4. Leading/Trailing Space Check:")
        leading_trailing_modelo = sum(1 for r in self.records if r.get('modelo', '').strip() != r.get('modelo', ''))
        leading_trailing_version = sum(1 for r in self.records if r.get('version', '').strip() != r.get('version', ''))
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
        """Generate executive summary"""
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

    def save_results(self, output_path):
        """Save validation results to JSON"""
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(self.results, f, indent=2, ensure_ascii=False)
        print(f"\n💾 Results saved to: {output_path}")


def main():
    """Main execution"""
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
    print(f"  1. Review detailed results in: {output_path}")
    print("  2. Address any critical issues found")
    print("  3. Generate client report from results")

    return 0 if results['executive_summary']['all_pass'] else 1


if __name__ == '__main__':
    exit(main())
