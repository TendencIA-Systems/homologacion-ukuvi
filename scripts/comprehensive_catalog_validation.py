#!/usr/bin/env python3
"""
Comprehensive Validation Script for ETL Model Normalization Fixes
Validates the 4 primary issues and checks for QA department findings
"""

import pandas as pd
import re
import json
from collections import defaultdict, Counter
from pathlib import Path
import sys

# Configuration
BASE_PATH = Path("/mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl")
DATA_PATH = BASE_PATH / "data" / "validation"

# CSV files to analyze
CSV_FILES = {
    'zurich': 'catalogo_revision_zurich.csv',
    'zurich_comparacion': 'catalogo_revision_zurich_comparacion_versiones.csv',
    'zurich_hdi': 'catalogo_revision_zurich_hdi.csv',
    'zurich_hdi_comparacion': 'catalogo_revision_zurich_hdi_comparacion_versiones.csv'
}

class CatalogValidator:
    def __init__(self):
        self.results = {
            'primary_fixes': {},
            'qa_issues': {},
            'client_cases': {},
            'quality_metrics': {},
            'regressions': {},
            'summary': {}
        }
        self.df = None
        self.df_comparacion = None

    def load_data(self, filename):
        """Load CSV file with error handling"""
        try:
            filepath = DATA_PATH / filename
            print(f"Loading {filepath}...")

            # Try different encodings
            for encoding in ['utf-8', 'latin-1', 'iso-8859-1']:
                try:
                    df = pd.read_csv(filepath, encoding=encoding, low_memory=False)
                    print(f"  ✓ Loaded {len(df)} records with encoding {encoding}")
                    print(f"  Columns: {list(df.columns)}")
                    return df
                except UnicodeDecodeError:
                    continue

            print(f"  ✗ Failed to load {filename}")
            return None
        except Exception as e:
            print(f"  ✗ Error loading {filename}: {e}")
            return None

    def get_disponibilidad_insurers(self, row):
        """Extract list of insurers from disponibilidad JSON field"""
        if pd.isna(row.get('disponibilidad')):
            return []
        try:
            if isinstance(row['disponibilidad'], str):
                disp = json.loads(row['disponibilidad'])
            else:
                disp = row['disponibilidad']
            return list(disp.keys()) if isinstance(disp, dict) else []
        except:
            return []

    # ========== PRIMARY FIX VALIDATIONS ==========

    def validate_issue1_model_contamination(self):
        """Issue 1: Model field contamination (SERIE, SDRIVE, trim codes, TUR, etc.)"""
        print("\n" + "="*80)
        print("VALIDATING ISSUE 1: Model Field Contamination")
        print("="*80)

        if self.df is None:
            return

        contamination_patterns = {
            'SERIE_prefix': r'\bSERIE\s+',
            'SDRIVE_suffix': r'\bSDRIVE\b',
            'XDRIVE_suffix': r'\bXDRIVE\b',
            'single_letter_trim': r'\s+[IiAaBbEe]$',
            'TUR_suffix': r'\s+TUR\b',
            'TURBO_suffix': r'\s+TURBO\b'
        }

        issues = {}
        samples = {}

        for pattern_name, pattern in contamination_patterns.items():
            # Check in modelo field
            mask = self.df['modelo'].astype(str).str.contains(pattern, case=False, regex=True, na=False)
            count = mask.sum()
            issues[pattern_name] = count

            if count > 0:
                samples[pattern_name] = self.df[mask][['marca', 'modelo', 'anio', 'version']].head(10).to_dict('records')

        total_contaminated = sum(issues.values())
        total_records = len(self.df)
        contamination_rate = (total_contaminated / total_records * 100) if total_records > 0 else 0

        # Pass/Fail criteria
        status = "✅ PASS" if contamination_rate < 1.0 else "❌ FAIL"

        self.results['primary_fixes']['issue1'] = {
            'status': status,
            'contamination_rate': f"{contamination_rate:.2f}%",
            'total_contaminated': total_contaminated,
            'total_records': total_records,
            'by_pattern': issues,
            'samples': samples,
            'criteria': '<1% contamination required',
            'target': '0 records'
        }

        print(f"\nStatus: {status}")
        print(f"Contamination Rate: {contamination_rate:.2f}%")
        print(f"Total Contaminated: {total_contaminated} / {total_records}")
        print("\nBy Pattern:")
        for pattern, count in issues.items():
            print(f"  {pattern}: {count}")

        return status == "✅ PASS"

    def validate_issue2_bmw_mini_separation(self):
        """Issue 2: BMW/MINI brand separation"""
        print("\n" + "="*80)
        print("VALIDATING ISSUE 2: BMW/MINI Brand Separation")
        print("="*80)

        if self.df is None:
            return

        # Check for BMW with MINI in modelo
        bmw_with_mini = self.df[
            (self.df['marca'].str.upper() == 'BMW') &
            (self.df['modelo'].astype(str).str.contains('MINI', case=False, na=False))
        ]

        # Check for MINI brand records
        mini_brand = self.df[self.df['marca'].str.upper() == 'MINI']

        # Check for MINI with "MINI " prefix in modelo
        mini_with_prefix = mini_brand[
            mini_brand['modelo'].astype(str).str.contains(r'^\s*MINI\s+', case=False, regex=True, na=False)
        ]

        bmw_mini_count = len(bmw_with_mini)
        mini_brand_count = len(mini_brand)
        mini_prefix_count = len(mini_with_prefix)

        # Pass/Fail criteria
        status = "✅ PASS" if (bmw_mini_count == 0 and mini_prefix_count == 0) else "❌ FAIL"

        # Get MINI variants
        mini_variants = mini_brand['modelo'].value_counts().head(10).to_dict() if mini_brand_count > 0 else {}

        self.results['primary_fixes']['issue2'] = {
            'status': status,
            'bmw_with_mini': bmw_mini_count,
            'mini_brand_total': mini_brand_count,
            'mini_with_prefix': mini_prefix_count,
            'mini_variants': mini_variants,
            'samples_bmw_mini': bmw_with_mini[['marca', 'modelo', 'anio', 'version']].head(10).to_dict('records') if bmw_mini_count > 0 else [],
            'samples_mini_prefix': mini_with_prefix[['marca', 'modelo', 'anio', 'version']].head(10).to_dict('records') if mini_prefix_count > 0 else [],
            'criteria': '0 BMW with MINI, 0 MINI with prefix',
            'expected': 'MINI brand with clean variants (COOPER, CLUBMAN, etc.)'
        }

        print(f"\nStatus: {status}")
        print(f"BMW with MINI: {bmw_mini_count} (Expected: 0)")
        print(f"MINI brand records: {mini_brand_count}")
        print(f"MINI with 'MINI ' prefix: {mini_prefix_count} (Expected: 0)")
        print(f"\nMINI Variants (top 10):")
        for variant, count in list(mini_variants.items())[:10]:
            print(f"  {variant}: {count}")

        return status == "✅ PASS"

    def validate_issue3_model_completion(self):
        """Issue 3: Incomplete model completion (single letters like M, X, S, R)"""
        print("\n" + "="*80)
        print("VALIDATING ISSUE 3: Incomplete Model Completion")
        print("="*80)

        if self.df is None:
            return

        # BMW M models (single letter)
        bmw_m_single = self.df[
            (self.df['marca'].str.upper() == 'BMW') &
            (self.df['modelo'].astype(str).str.match(r'^\s*M\s*$', case=False, na=False))
        ]

        # BMW X models (single letter)
        bmw_x_single = self.df[
            (self.df['marca'].str.upper() == 'BMW') &
            (self.df['modelo'].astype(str).str.match(r'^\s*X\s*$', case=False, na=False))
        ]

        # AUDI S models (single letter)
        audi_s_single = self.df[
            (self.df['marca'].str.upper() == 'AUDI') &
            (self.df['modelo'].astype(str).str.match(r'^\s*S\s*$', case=False, na=False))
        ]

        # AUDI R models (single letter)
        audi_r_single = self.df[
            (self.df['marca'].str.upper() == 'AUDI') &
            (self.df['modelo'].astype(str).str.match(r'^\s*R\s*$', case=False, na=False))
        ]

        bmw_m_count = len(bmw_m_single)
        bmw_x_count = len(bmw_x_single)
        audi_s_count = len(audi_s_single)
        audi_r_count = len(audi_r_single)
        total_single = bmw_m_count + bmw_x_count + audi_s_count + audi_r_count

        # Pass/Fail criteria: <5 total single-letter models acceptable
        status = "✅ PASS" if total_single < 5 else ("⚠️  ACCEPTABLE" if total_single < 20 else "❌ FAIL")

        self.results['primary_fixes']['issue3'] = {
            'status': status,
            'bmw_m_single': bmw_m_count,
            'bmw_x_single': bmw_x_count,
            'audi_s_single': audi_s_count,
            'audi_r_single': audi_r_count,
            'total_single_letter': total_single,
            'samples_bmw_m': bmw_m_single[['marca', 'modelo', 'anio', 'version']].head(5).to_dict('records') if bmw_m_count > 0 else [],
            'samples_bmw_x': bmw_x_single[['marca', 'modelo', 'anio', 'version']].head(5).to_dict('records') if bmw_x_count > 0 else [],
            'samples_audi_s': audi_s_single[['marca', 'modelo', 'anio', 'version']].head(5).to_dict('records') if audi_s_count > 0 else [],
            'criteria': '<5 single-letter models (acceptable: <20)',
            'target': '95%+ completion'
        }

        print(f"\nStatus: {status}")
        print(f"BMW M (single letter): {bmw_m_count}")
        print(f"BMW X (single letter): {bmw_x_count}")
        print(f"AUDI S (single letter): {audi_s_count}")
        print(f"AUDI R (single letter): {audi_r_count}")
        print(f"Total Single-Letter: {total_single} (Target: <5, Acceptable: <20)")

        return status in ["✅ PASS", "⚠️  ACCEPTABLE"]

    def validate_issue4_mapfre_id_format(self):
        """Issue 4: MAPFRE ID format (must have year suffix)"""
        print("\n" + "="*80)
        print("VALIDATING ISSUE 4: MAPFRE ID Format")
        print("="*80)

        if self.df is None or 'disponibilidad' not in self.df.columns:
            print("⚠️  Cannot validate - disponibilidad field not found")
            return

        # Extract MAPFRE records from disponibilidad
        mapfre_records = []
        for idx, row in self.df.iterrows():
            insurers = self.get_disponibilidad_insurers(row)
            if 'mapfre' in [i.lower() for i in insurers]:
                mapfre_records.append(row)

        if not mapfre_records:
            print("⚠️  No MAPFRE records found in disponibilidad field")
            self.results['primary_fixes']['issue4'] = {
                'status': '⚠️  NO DATA',
                'message': 'No MAPFRE records found'
            }
            return

        mapfre_df = pd.DataFrame(mapfre_records)

        # Check if id_original field exists
        if 'id_original' not in mapfre_df.columns:
            print("⚠️  id_original field not found")
            self.results['primary_fixes']['issue4'] = {
                'status': '⚠️  NO DATA',
                'message': 'id_original field not found'
            }
            return

        # Check for IDs without underscore (missing year)
        without_year = mapfre_df[
            ~mapfre_df['id_original'].astype(str).str.contains('_', na=False)
        ]

        # Check for duplicate IDs
        id_counts = mapfre_df['id_original'].value_counts()
        duplicates = id_counts[id_counts > 1]

        without_year_count = len(without_year)
        duplicate_count = len(duplicates)
        total_mapfre = len(mapfre_df)

        # Pass/Fail criteria
        status = "✅ PASS" if (without_year_count == 0 and duplicate_count == 0) else "❌ FAIL"

        self.results['primary_fixes']['issue4'] = {
            'status': status,
            'total_mapfre_records': total_mapfre,
            'without_year_suffix': without_year_count,
            'duplicate_ids': duplicate_count,
            'samples_without_year': without_year[['marca', 'modelo', 'anio', 'id_original']].head(10).to_dict('records') if without_year_count > 0 else [],
            'duplicate_examples': duplicates.head(10).to_dict() if duplicate_count > 0 else {},
            'criteria': '0 without year, 0 duplicates',
            'expected_format': '{CodModelo}_{AnioFabrica}'
        }

        print(f"\nStatus: {status}")
        print(f"Total MAPFRE records: {total_mapfre}")
        print(f"Without year suffix: {without_year_count} (Expected: 0)")
        print(f"Duplicate IDs: {duplicate_count} (Expected: 0)")

        return status == "✅ PASS"

    # ========== QA ISSUES CHECKS ==========

    def check_qa_transmission_contamination(self):
        """Check for transmission column contamination"""
        print("\n" + "="*80)
        print("CHECKING QA ISSUE: Transmission Column Contamination")
        print("="*80)

        if self.df is None or 'transmision' not in self.df.columns:
            print("⚠️  transmision field not found")
            return

        valid_transmissions = ['AUTO', 'MANUAL', 'CVT', 'DSG', 'AUTOMATICA', 'STD']

        # Count valid vs invalid
        valid = self.df[
            self.df['transmision'].astype(str).str.upper().isin(valid_transmissions) |
            self.df['transmision'].isna()
        ]

        invalid = self.df[
            ~self.df['transmision'].astype(str).str.upper().isin(valid_transmissions) &
            ~self.df['transmision'].isna()
        ]

        valid_count = len(valid)
        invalid_count = len(invalid)
        total = len(self.df)
        contamination_rate = (invalid_count / total * 100) if total > 0 else 0

        # Get examples of invalid values
        invalid_examples = invalid['transmision'].value_counts().head(20).to_dict()

        self.results['qa_issues']['transmission'] = {
            'valid_count': valid_count,
            'invalid_count': invalid_count,
            'contamination_rate': f"{contamination_rate:.2f}%",
            'total_records': total,
            'invalid_examples': invalid_examples,
            'samples': invalid[['marca', 'modelo', 'anio', 'transmision']].head(10).to_dict('records'),
            'note': 'NOT being fixed in current implementation - for future phase'
        }

        print(f"\nValid transmissions: {valid_count} ({(valid_count/total*100):.1f}%)")
        print(f"Invalid transmissions: {invalid_count} ({contamination_rate:.1f}%)")
        print(f"\nTop Invalid Values:")
        for val, count in list(invalid_examples.items())[:10]:
            print(f"  '{val}': {count}")
        print("\n⚠️  NOTE: This issue is NOT being fixed in current implementation")

    def check_qa_brand_consolidation(self):
        """Check for brand consolidation issues"""
        print("\n" + "="*80)
        print("CHECKING QA ISSUE: Brand Consolidation Problems")
        print("="*80)

        if self.df is None:
            return

        problem_brands = {
            'AUDI II': 'AUDI',
            'BMW BW': 'BMW',
            'MERCEDES BENZ II': 'MERCEDES BENZ',
            'KIA MOTORS': 'KIA',
            'GREAT WALL MOTORS': 'GREAT WALL',
            'TESLA MOTORS': 'TESLA',
            'BERCEDES BENZ': 'MERCEDES BENZ'
        }

        invalid_brands = ['AUTOS', 'MOTOCICLETAS', 'MULTIMARCA', 'LEGALIZADO']

        issues = {}
        for problem_brand in problem_brands.keys():
            count = (self.df['marca'].astype(str).str.upper() == problem_brand.upper()).sum()
            if count > 0:
                issues[problem_brand] = count

        for invalid_brand in invalid_brands:
            count = (self.df['marca'].astype(str).str.upper() == invalid_brand.upper()).sum()
            if count > 0:
                issues[invalid_brand] = count

        total_issues = sum(issues.values())

        self.results['qa_issues']['brand_consolidation'] = {
            'total_issues': total_issues,
            'by_brand': issues,
            'note': 'NOT being fixed in current implementation - for future phase'
        }

        print(f"\nTotal brand consolidation issues: {total_issues}")
        print("\nBy Brand:")
        for brand, count in issues.items():
            print(f"  {brand}: {count}")
        print("\n⚠️  NOTE: This issue is NOT being fixed in current implementation")

    def check_qa_character_escaping(self):
        """Check for character escaping issues"""
        print("\n" + "="*80)
        print("CHECKING QA ISSUE: Character Escaping Problems")
        print("="*80)

        if self.df is None or 'version' not in self.df.columns:
            print("⚠️  version field not found")
            return

        # Check for backslashes and quotes
        backslash = self.df[
            self.df['version'].astype(str).str.contains(r'\\', regex=True, na=False)
        ]

        quotes = self.df[
            self.df['version'].astype(str).str.contains(r'"', regex=True, na=False)
        ]

        backslash_count = len(backslash)
        quotes_count = len(quotes)
        total_escaping = len(self.df[
            self.df['version'].astype(str).str.contains(r'[\\"]', regex=True, na=False)
        ])

        self.results['qa_issues']['character_escaping'] = {
            'backslash_count': backslash_count,
            'quotes_count': quotes_count,
            'total_escaping_issues': total_escaping,
            'samples_backslash': backslash[['marca', 'modelo', 'version']].head(10).to_dict('records') if backslash_count > 0 else [],
            'samples_quotes': quotes[['marca', 'modelo', 'version']].head(10).to_dict('records') if quotes_count > 0 else [],
            'note': 'May have been partially addressed in version cleaning'
        }

        print(f"\nBackslashes found: {backslash_count}")
        print(f"Quotes found: {quotes_count}")
        print(f"Total escaping issues: {total_escaping}")
        print("\n⚠️  NOTE: May have been partially addressed in version cleaning")

    # ========== CLIENT CASE STUDIES ==========

    def verify_client_case_acura_ilx(self):
        """Verify Acura ILX 2017 case study"""
        print("\n" + "="*80)
        print("VERIFYING CLIENT CASE: Acura ILX 2017")
        print("="*80)

        if self.df is None:
            return

        # Find Acura ILX 2017
        acura_ilx = self.df[
            (self.df['marca'].str.upper() == 'ACURA') &
            (self.df['modelo'].str.upper() == 'ILX') &
            (self.df['anio'] == 2017)
        ]

        if len(acura_ilx) == 0:
            print("⚠️  No Acura ILX 2017 records found")
            self.results['client_cases']['acura_ilx_2017'] = {
                'status': '⚠️  NO DATA',
                'message': 'No records found'
            }
            return

        print(f"\nFound {len(acura_ilx)} Acura ILX 2017 records")
        print("\nVersions found:")
        for idx, row in acura_ilx.iterrows():
            version = row.get('version', 'N/A')
            insurers = self.get_disponibilidad_insurers(row)
            print(f"  - {version}")
            print(f"    Insurers: {', '.join(insurers)}")

        self.results['client_cases']['acura_ilx_2017'] = {
            'total_records': len(acura_ilx),
            'versions': acura_ilx['version'].tolist() if 'version' in acura_ilx.columns else [],
            'details': acura_ilx[['marca', 'modelo', 'anio', 'version']].to_dict('records'),
            'note': 'Client reported A-SPEC and TECH as different trims - both valid'
        }

    def verify_client_case_vw_jetta(self):
        """Verify VW Jetta 2012 case study"""
        print("\n" + "="*80)
        print("VERIFYING CLIENT CASE: VW Jetta 2012")
        print("="*80)

        if self.df is None:
            return

        # Find VW Jetta 2012
        vw_jetta = self.df[
            (self.df['marca'].str.upper().isin(['VOLKSWAGEN', 'VW'])) &
            (self.df['modelo'].str.upper() == 'JETTA') &
            (self.df['anio'] == 2012)
        ]

        if len(vw_jetta) == 0:
            print("⚠️  No VW Jetta 2012 records found")
            self.results['client_cases']['vw_jetta_2012'] = {
                'status': '⚠️  NO DATA',
                'message': 'No records found'
            }
            return

        print(f"\nFound {len(vw_jetta)} VW Jetta 2012 records")
        print("\nVersions and transmissions:")
        for idx, row in vw_jetta.iterrows():
            version = row.get('version', 'N/A')
            transmision = row.get('transmision', 'N/A')
            insurers = self.get_disponibilidad_insurers(row)
            print(f"  - {version}")
            print(f"    Transmission: {transmision}")
            print(f"    Insurers: {', '.join(insurers)}")

        self.results['client_cases']['vw_jetta_2012'] = {
            'total_records': len(vw_jetta),
            'versions': vw_jetta['version'].tolist() if 'version' in vw_jetta.columns else [],
            'transmissions': vw_jetta['transmision'].tolist() if 'transmision' in vw_jetta.columns else [],
            'details': vw_jetta[['marca', 'modelo', 'anio', 'version', 'transmision']].to_dict('records') if 'transmision' in vw_jetta.columns else [],
            'note': 'Client reported transmission inconsistency between ZURICH and GNP'
        }

    # ========== QUALITY METRICS ==========

    def calculate_quality_metrics(self):
        """Calculate overall quality metrics"""
        print("\n" + "="*80)
        print("CALCULATING QUALITY METRICS")
        print("="*80)

        if self.df is None:
            return

        total_records = len(self.df)

        # Field completeness
        required_fields = ['marca', 'modelo', 'anio']
        completeness = {}
        for field in required_fields:
            if field in self.df.columns:
                non_null = self.df[field].notna().sum()
                completeness[field] = f"{(non_null/total_records*100):.2f}%"

        # By insurer metrics (if disponibilidad exists)
        by_insurer = {}
        if 'disponibilidad' in self.df.columns:
            insurer_counts = Counter()
            for idx, row in self.df.iterrows():
                insurers = self.get_disponibilidad_insurers(row)
                for insurer in insurers:
                    insurer_counts[insurer.upper()] += 1
            by_insurer = dict(insurer_counts)

        # Brand distribution
        top_brands = self.df['marca'].value_counts().head(10).to_dict()

        self.results['quality_metrics'] = {
            'total_records': total_records,
            'field_completeness': completeness,
            'records_by_insurer': by_insurer,
            'top_brands': top_brands
        }

        print(f"\nTotal Records: {total_records:,}")
        print(f"\nField Completeness:")
        for field, pct in completeness.items():
            print(f"  {field}: {pct}")

        if by_insurer:
            print(f"\nRecords by Insurer:")
            for insurer, count in sorted(by_insurer.items()):
                print(f"  {insurer}: {count:,}")

        print(f"\nTop 10 Brands:")
        for brand, count in list(top_brands.items())[:10]:
            print(f"  {brand}: {count:,}")

    # ========== MAIN EXECUTION ==========

    def run_full_validation(self, catalog_type='zurich_hdi'):
        """Run full validation suite"""
        print("\n" + "="*80)
        print("COMPREHENSIVE CATALOG VALIDATION")
        print(f"Catalog Type: {catalog_type}")
        print("="*80)

        # Load data
        filename = CSV_FILES.get(catalog_type)
        if not filename:
            print(f"❌ Unknown catalog type: {catalog_type}")
            return

        self.df = self.load_data(filename)
        if self.df is None:
            print("❌ Failed to load data")
            return

        # Run all validations
        print("\n" + "🔍 PART 1: PRIMARY FIXES VALIDATION " + "="*50)
        pass1 = self.validate_issue1_model_contamination()
        pass2 = self.validate_issue2_bmw_mini_separation()
        pass3 = self.validate_issue3_model_completion()
        pass4 = self.validate_issue4_mapfre_id_format()

        print("\n" + "🔍 PART 2: QA DEPARTMENT FINDINGS " + "="*50)
        self.check_qa_transmission_contamination()
        self.check_qa_brand_consolidation()
        self.check_qa_character_escaping()

        print("\n" + "🔍 PART 3: CLIENT CASE STUDIES " + "="*50)
        self.verify_client_case_acura_ilx()
        self.verify_client_case_vw_jetta()

        print("\n" + "🔍 PART 4: QUALITY METRICS " + "="*50)
        self.calculate_quality_metrics()

        # Generate summary
        primary_fixes_passed = sum([pass1, pass2, pass3, pass4])
        primary_fixes_total = 4

        self.results['summary'] = {
            'catalog_type': catalog_type,
            'primary_fixes_passed': f"{primary_fixes_passed}/{primary_fixes_total}",
            'overall_status': '✅ ALL FIXED' if primary_fixes_passed == 4 else '❌ ISSUES FOUND',
            'production_ready': 'YES' if primary_fixes_passed == 4 else 'NO',
            'recommendations': self.generate_recommendations()
        }

        # Print summary
        print("\n" + "="*80)
        print("VALIDATION SUMMARY")
        print("="*80)
        print(f"\nPrimary Fixes Status: {primary_fixes_passed}/{primary_fixes_total} PASSED")
        print(f"Overall Status: {self.results['summary']['overall_status']}")
        print(f"Production Ready: {self.results['summary']['production_ready']}")

        return self.results

    def generate_recommendations(self):
        """Generate recommendations based on validation results"""
        recommendations = []

        # Check primary fixes
        if self.results['primary_fixes'].get('issue1', {}).get('status') != '✅ PASS':
            recommendations.append("CRITICAL: Fix model field contamination before production")

        if self.results['primary_fixes'].get('issue2', {}).get('status') != '✅ PASS':
            recommendations.append("CRITICAL: Fix BMW/MINI separation before production")

        if self.results['primary_fixes'].get('issue3', {}).get('status') not in ['✅ PASS', '⚠️  ACCEPTABLE']:
            recommendations.append("HIGH: Complete single-letter model parsing")

        if self.results['primary_fixes'].get('issue4', {}).get('status') != '✅ PASS':
            recommendations.append("CRITICAL: Fix MAPFRE ID format before production")

        # Check QA issues
        qa_transmission = self.results['qa_issues'].get('transmission', {})
        if qa_transmission.get('invalid_count', 0) > 1000:
            recommendations.append("FUTURE: Plan transmission normalization project (80%+ contamination)")

        qa_brands = self.results['qa_issues'].get('brand_consolidation', {})
        if qa_brands.get('total_issues', 0) > 100:
            recommendations.append("FUTURE: Plan brand consolidation project")

        if not recommendations:
            recommendations.append("All primary fixes validated successfully - ready for production")

        return recommendations

    def save_results(self, output_file='validation_results.json'):
        """Save results to JSON file"""
        output_path = BASE_PATH / 'reports' / output_file
        output_path.parent.mkdir(exist_ok=True)

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(self.results, f, indent=2, ensure_ascii=False)

        print(f"\n✅ Results saved to: {output_path}")


def main():
    """Main execution"""
    print("\n" + "="*80)
    print("ETL MODEL NORMALIZATION FIXES - COMPREHENSIVE VALIDATION")
    print("="*80)

    # Validate all catalog types
    catalog_types = ['zurich', 'zurich_hdi']

    for catalog_type in catalog_types:
        print(f"\n\n{'='*80}")
        print(f"VALIDATING: {catalog_type.upper()}")
        print(f"{'='*80}")

        validator = CatalogValidator()
        results = validator.run_full_validation(catalog_type=catalog_type)

        if results:
            # Save results
            validator.save_results(f'validation_results_{catalog_type}.json')

    print("\n" + "="*80)
    print("VALIDATION COMPLETE")
    print("="*80)
    print("\nNext steps:")
    print("1. Review validation results in reports/ directory")
    print("2. Check detailed JSON files for specific issues")
    print("3. Generate executive summary report")


if __name__ == '__main__':
    main()
