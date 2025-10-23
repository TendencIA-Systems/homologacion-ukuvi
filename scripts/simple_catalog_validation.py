#!/usr/bin/env python3
"""
Simplified Comprehensive Validation Script for ETL Model Normalization Fixes
Uses only standard library (csv module) - no external dependencies
"""

import csv
import re
import json
from collections import defaultdict, Counter
from pathlib import Path
import sys

# Configuration
BASE_PATH = Path("/mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl")
DATA_PATH = BASE_PATH / "data" / "validation"

CSV_FILES = {
    'zurich': 'catalogo_revision_zurich.csv',
    'zurich_hdi': 'catalogo_revision_zurich_hdi.csv'
}

class SimpleCatalogValidator:
    def __init__(self):
        self.results = {}
        self.data = []
        self.headers = []

    def load_csv(self, filename):
        """Load CSV file using standard library"""
        filepath = DATA_PATH / filename
        print(f"\nLoading {filepath}...")

        try:
            # Try UTF-8 first
            with open(filepath, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                self.headers = reader.fieldnames
                self.data = list(reader)
                print(f"✅ Loaded {len(self.data)} records")
                print(f"Columns: {', '.join(self.headers[:10])}...")
                return True
        except UnicodeDecodeError:
            try:
                # Try latin-1
                with open(filepath, 'r', encoding='latin-1') as f:
                    reader = csv.DictReader(f)
                    self.headers = reader.fieldnames
                    self.data = list(reader)
                    print(f"✅ Loaded {len(self.data)} records (latin-1 encoding)")
                    print(f"Columns: {', '.join(self.headers[:10])}...")
                    return True
            except Exception as e:
                print(f"❌ Error loading {filename}: {e}")
                return False
        except Exception as e:
            print(f"❌ Error loading {filename}: {e}")
            return False

    def get_field(self, row, field, default=''):
        """Safely get field from row"""
        return row.get(field, default) or default

    def validate_issue1_model_contamination(self):
        """Issue 1: Model field contamination"""
        print("\n" + "="*80)
        print("ISSUE 1: MODEL FIELD CONTAMINATION")
        print("="*80)

        patterns = {
            'SERIE_prefix': (r'\bSERIE\s+', 'SERIE prefix (e.g., SERIE 3)'),
            'SDRIVE_suffix': (r'\bSDRIVE\b', 'SDRIVE suffix'),
            'XDRIVE_suffix': (r'\bXDRIVE\b', 'XDRIVE suffix'),
            'single_letter_trim': (r'\s+[IiAaBbEe]$', 'Single letter trim (I, IA, etc.)'),
            'TUR_suffix': (r'\s+TUR\b', 'TUR suffix'),
            'TURBO_suffix': (r'\s+TURBO\b', 'TURBO suffix')
        }

        issues = {name: [] for name in patterns.keys()}

        for row in self.data:
            modelo = self.get_field(row, 'modelo').upper()
            for pattern_name, (pattern, desc) in patterns.items():
                if re.search(pattern, modelo, re.IGNORECASE):
                    issues[pattern_name].append({
                        'marca': self.get_field(row, 'marca'),
                        'modelo': modelo,
                        'anio': self.get_field(row, 'anio'),
                        'version': self.get_field(row, 'version', 'N/A')[:50]
                    })

        total_contaminated = sum(len(v) for v in issues.values())
        total_records = len(self.data)
        contamination_rate = (total_contaminated / total_records * 100) if total_records > 0 else 0

        status = "✅ PASS" if contamination_rate < 1.0 else "❌ FAIL"

        print(f"\n{status}")
        print(f"Contamination Rate: {contamination_rate:.2f}%")
        print(f"Total Contaminated: {total_contaminated:,} / {total_records:,}")
        print("\nBy Pattern:")
        for pattern_name, (_, desc) in patterns.items():
            count = len(issues[pattern_name])
            print(f"  {desc}: {count:,}")
            if count > 0 and count <= 5:
                for item in issues[pattern_name][:3]:
                    print(f"    → {item['marca']} {item['modelo']} {item['anio']}")

        self.results['issue1'] = {
            'status': status,
            'contamination_rate': f"{contamination_rate:.2f}%",
            'total_contaminated': total_contaminated,
            'total_records': total_records,
            'by_pattern': {k: len(v) for k, v in issues.items()},
            'samples': {k: v[:10] for k, v in issues.items() if v}
        }

        return status == "✅ PASS"

    def validate_issue2_bmw_mini(self):
        """Issue 2: BMW/MINI brand separation"""
        print("\n" + "="*80)
        print("ISSUE 2: BMW/MINI BRAND SEPARATION")
        print("="*80)

        bmw_with_mini = []
        mini_brand = []
        mini_with_prefix = []

        for row in self.data:
            marca = self.get_field(row, 'marca').upper()
            modelo = self.get_field(row, 'modelo').upper()

            if marca == 'BMW' and 'MINI' in modelo:
                bmw_with_mini.append({
                    'marca': marca,
                    'modelo': modelo,
                    'anio': self.get_field(row, 'anio')
                })

            if marca == 'MINI':
                mini_brand.append(modelo)
                if re.match(r'^\s*MINI\s+', modelo):
                    mini_with_prefix.append({
                        'marca': marca,
                        'modelo': modelo,
                        'anio': self.get_field(row, 'anio')
                    })

        status = "✅ PASS" if (len(bmw_with_mini) == 0 and len(mini_with_prefix) == 0) else "❌ FAIL"

        mini_variants = Counter(mini_brand).most_common(10)

        print(f"\n{status}")
        print(f"BMW with MINI: {len(bmw_with_mini):,} (Expected: 0)")
        print(f"MINI brand records: {len(mini_brand):,}")
        print(f"MINI with 'MINI ' prefix: {len(mini_with_prefix):,} (Expected: 0)")

        if mini_variants:
            print(f"\nMINI Variants (top 10):")
            for variant, count in mini_variants:
                print(f"  {variant}: {count}")

        if bmw_with_mini:
            print("\nExamples of BMW with MINI:")
            for item in bmw_with_mini[:5]:
                print(f"  → {item['marca']} {item['modelo']} {item['anio']}")

        self.results['issue2'] = {
            'status': status,
            'bmw_with_mini': len(bmw_with_mini),
            'mini_brand_total': len(mini_brand),
            'mini_with_prefix': len(mini_with_prefix),
            'mini_variants': dict(mini_variants),
            'samples_bmw_mini': bmw_with_mini[:10]
        }

        return status == "✅ PASS"

    def validate_issue3_model_completion(self):
        """Issue 3: Incomplete model completion"""
        print("\n" + "="*80)
        print("ISSUE 3: INCOMPLETE MODEL COMPLETION")
        print("="*80)

        bmw_m_single = []
        bmw_x_single = []
        audi_s_single = []
        audi_r_single = []

        for row in self.data:
            marca = self.get_field(row, 'marca').upper()
            modelo = self.get_field(row, 'modelo').strip().upper()
            version = self.get_field(row, 'version', 'N/A')

            if marca == 'BMW':
                if re.match(r'^\s*M\s*$', modelo):
                    bmw_m_single.append({
                        'marca': marca,
                        'modelo': modelo,
                        'version': version[:60],
                        'anio': self.get_field(row, 'anio')
                    })
                elif re.match(r'^\s*X\s*$', modelo):
                    bmw_x_single.append({
                        'marca': marca,
                        'modelo': modelo,
                        'version': version[:60],
                        'anio': self.get_field(row, 'anio')
                    })

            if marca == 'AUDI':
                if re.match(r'^\s*S\s*$', modelo):
                    audi_s_single.append({
                        'marca': marca,
                        'modelo': modelo,
                        'version': version[:60],
                        'anio': self.get_field(row, 'anio')
                    })
                elif re.match(r'^\s*R\s*$', modelo):
                    audi_r_single.append({
                        'marca': marca,
                        'modelo': modelo,
                        'version': version[:60],
                        'anio': self.get_field(row, 'anio')
                    })

        total_single = len(bmw_m_single) + len(bmw_x_single) + len(audi_s_single) + len(audi_r_single)

        if total_single < 5:
            status = "✅ PASS"
        elif total_single < 20:
            status = "⚠️  ACCEPTABLE"
        else:
            status = "❌ FAIL"

        print(f"\n{status}")
        print(f"BMW M (single letter): {len(bmw_m_single):,}")
        print(f"BMW X (single letter): {len(bmw_x_single):,}")
        print(f"AUDI S (single letter): {len(audi_s_single):,}")
        print(f"AUDI R (single letter): {len(audi_r_single):,}")
        print(f"Total Single-Letter: {total_single:,} (Target: <5, Acceptable: <20)")

        if bmw_m_single:
            print("\nExamples of BMW M (single):")
            for item in bmw_m_single[:3]:
                print(f"  → BMW {item['modelo']} {item['anio']} | Version: {item['version']}")

        self.results['issue3'] = {
            'status': status,
            'bmw_m_single': len(bmw_m_single),
            'bmw_x_single': len(bmw_x_single),
            'audi_s_single': len(audi_s_single),
            'audi_r_single': len(audi_r_single),
            'total_single_letter': total_single,
            'samples': {
                'bmw_m': bmw_m_single[:5],
                'bmw_x': bmw_x_single[:5],
                'audi_s': audi_s_single[:5]
            }
        }

        return status in ["✅ PASS", "⚠️  ACCEPTABLE"]

    def check_qa_transmission(self):
        """Check transmission contamination"""
        print("\n" + "="*80)
        print("QA ISSUE: TRANSMISSION CONTAMINATION")
        print("="*80)

        valid_transmissions = {'AUTO', 'MANUAL', 'CVT', 'DSG', 'AUTOMATICA', 'STD', 'AUT', ''}

        invalid = []
        invalid_values = Counter()

        for row in self.data:
            transmision = self.get_field(row, 'transmision').upper().strip()
            if transmision and transmision not in valid_transmissions:
                invalid.append({
                    'marca': self.get_field(row, 'marca'),
                    'modelo': self.get_field(row, 'modelo'),
                    'transmision': transmision
                })
                invalid_values[transmision] += 1

        total = len(self.data)
        invalid_count = len(invalid)
        contamination_rate = (invalid_count / total * 100) if total > 0 else 0

        print(f"\nValid transmissions: {total - invalid_count:,} ({(total-invalid_count)/total*100:.1f}%)")
        print(f"Invalid transmissions: {invalid_count:,} ({contamination_rate:.1f}%)")

        print(f"\nTop 15 Invalid Values:")
        for val, count in invalid_values.most_common(15):
            print(f"  '{val}': {count:,}")

        print("\n⚠️  NOTE: This issue is NOT being fixed in current implementation")

        self.results['qa_transmission'] = {
            'invalid_count': invalid_count,
            'contamination_rate': f"{contamination_rate:.2f}%",
            'top_invalid': dict(invalid_values.most_common(20)),
            'samples': invalid[:10]
        }

    def check_qa_brands(self):
        """Check brand consolidation issues"""
        print("\n" + "="*80)
        print("QA ISSUE: BRAND CONSOLIDATION")
        print("="*80)

        problem_brands = {
            'AUDI II', 'BMW BW', 'MERCEDES BENZ II', 'KIA MOTORS',
            'GREAT WALL MOTORS', 'TESLA MOTORS', 'BERCEDES BENZ',
            'AUTOS', 'MOTOCICLETAS', 'MULTIMARCA', 'LEGALIZADO'
        }

        issues = Counter()

        for row in self.data:
            marca = self.get_field(row, 'marca').upper()
            if marca in problem_brands:
                issues[marca] += 1

        total_issues = sum(issues.values())

        print(f"\nTotal brand consolidation issues: {total_issues:,}")
        print("\nBy Brand:")
        for brand, count in issues.most_common():
            print(f"  {brand}: {count:,}")

        print("\n⚠️  NOTE: This issue is NOT being fixed in current implementation")

        self.results['qa_brands'] = {
            'total_issues': total_issues,
            'by_brand': dict(issues)
        }

    def check_qa_escaping(self):
        """Check character escaping"""
        print("\n" + "="*80)
        print("QA ISSUE: CHARACTER ESCAPING")
        print("="*80)

        backslash_count = 0
        quotes_count = 0
        samples = []

        for row in self.data:
            version = self.get_field(row, 'version')
            if '\\' in version:
                backslash_count += 1
                if len(samples) < 10:
                    samples.append({'version': version, 'type': 'backslash'})
            if '"' in version:
                quotes_count += 1
                if len(samples) < 10:
                    samples.append({'version': version, 'type': 'quotes'})

        print(f"\nBackslashes found: {backslash_count:,}")
        print(f"Quotes found: {quotes_count:,}")
        print(f"Total escaping issues: {backslash_count + quotes_count:,}")

        if samples:
            print("\nExamples:")
            for sample in samples[:5]:
                print(f"  {sample['type']}: {sample['version'][:70]}")

        self.results['qa_escaping'] = {
            'backslash_count': backslash_count,
            'quotes_count': quotes_count,
            'samples': samples[:10]
        }

    def check_client_cases(self):
        """Check client case studies"""
        print("\n" + "="*80)
        print("CLIENT CASE STUDIES")
        print("="*80)

        # Acura ILX 2017
        print("\n1. Acura ILX 2017:")
        acura_ilx = [row for row in self.data
                     if self.get_field(row, 'marca').upper() == 'ACURA'
                     and self.get_field(row, 'modelo').upper() == 'ILX'
                     and self.get_field(row, 'anio') == '2017']

        if acura_ilx:
            print(f"  Found {len(acura_ilx)} records")
            for row in acura_ilx[:5]:
                print(f"    → {self.get_field(row, 'version')[:70]}")
        else:
            print("  ⚠️  No records found")

        # VW Jetta 2012
        print("\n2. VW Jetta 2012:")
        vw_jetta = [row for row in self.data
                    if self.get_field(row, 'marca').upper() in ['VOLKSWAGEN', 'VW']
                    and self.get_field(row, 'modelo').upper() == 'JETTA'
                    and self.get_field(row, 'anio') == '2012']

        if vw_jetta:
            print(f"  Found {len(vw_jetta)} records")
            for row in vw_jetta[:5]:
                trans = self.get_field(row, 'transmision', 'N/A')
                print(f"    → {self.get_field(row, 'version')[:50]} | Trans: {trans}")
        else:
            print("  ⚠️  No records found")

        self.results['client_cases'] = {
            'acura_ilx_2017': len(acura_ilx),
            'vw_jetta_2012': len(vw_jetta)
        }

    def calculate_summary(self):
        """Calculate summary metrics"""
        print("\n" + "="*80)
        print("QUALITY METRICS")
        print("="*80)

        total = len(self.data)

        # Top brands
        brands = Counter(self.get_field(row, 'marca').upper() for row in self.data)

        print(f"\nTotal Records: {total:,}")
        print(f"\nTop 10 Brands:")
        for brand, count in brands.most_common(10):
            print(f"  {brand}: {count:,}")

        # Primary fixes summary
        issue1_pass = self.results.get('issue1', {}).get('status') == '✅ PASS'
        issue2_pass = self.results.get('issue2', {}).get('status') == '✅ PASS'
        issue3_pass = self.results.get('issue3', {}).get('status') in ['✅ PASS', '⚠️  ACCEPTABLE']

        passed = sum([issue1_pass, issue2_pass, issue3_pass])

        self.results['summary'] = {
            'total_records': total,
            'primary_fixes_passed': f"{passed}/3",
            'issue1_pass': issue1_pass,
            'issue2_pass': issue2_pass,
            'issue3_pass': issue3_pass,
            'overall_status': '✅ ALL FIXED' if passed == 3 else '❌ ISSUES FOUND',
            'production_ready': 'YES' if passed == 3 else 'NO'
        }

    def run_validation(self, catalog_type='zurich_hdi'):
        """Run full validation"""
        print("\n" + "="*80)
        print("COMPREHENSIVE CATALOG VALIDATION")
        print(f"Catalog Type: {catalog_type}")
        print("="*80)

        filename = CSV_FILES.get(catalog_type)
        if not filename:
            print(f"❌ Unknown catalog type: {catalog_type}")
            return None

        if not self.load_csv(filename):
            return None

        # Run validations
        print("\n" + "🔍 PRIMARY FIXES VALIDATION")
        self.validate_issue1_model_contamination()
        self.validate_issue2_bmw_mini()
        self.validate_issue3_model_completion()

        print("\n" + "🔍 QA DEPARTMENT FINDINGS")
        self.check_qa_transmission()
        self.check_qa_brands()
        self.check_qa_escaping()

        print("\n" + "🔍 CLIENT CASE STUDIES")
        self.check_client_cases()

        self.calculate_summary()

        # Print final summary
        print("\n" + "="*80)
        print("VALIDATION SUMMARY")
        print("="*80)
        summary = self.results.get('summary', {})
        print(f"\nPrimary Fixes: {summary.get('primary_fixes_passed', 'N/A')}")
        print(f"Overall Status: {summary.get('overall_status', 'N/A')}")
        print(f"Production Ready: {summary.get('production_ready', 'N/A')}")

        return self.results

    def save_results(self, filename):
        """Save results to JSON"""
        output_path = BASE_PATH / 'reports' / filename
        output_path.parent.mkdir(exist_ok=True, parents=True)

        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(self.results, f, indent=2, ensure_ascii=False)

        print(f"\n✅ Results saved to: {output_path}")

def main():
    """Main execution"""
    print("="*80)
    print("ETL MODEL NORMALIZATION FIXES - COMPREHENSIVE VALIDATION")
    print("="*80)

    for catalog_type in ['zurich', 'zurich_hdi']:
        print(f"\n\n{'='*80}")
        print(f"ANALYZING: {catalog_type.upper()}")
        print(f"{'='*80}\n")

        validator = SimpleCatalogValidator()
        results = validator.run_validation(catalog_type)

        if results:
            validator.save_results(f'validation_results_{catalog_type}.json')

    print("\n" + "="*80)
    print("VALIDATION COMPLETE")
    print("="*80)

if __name__ == '__main__':
    main()
