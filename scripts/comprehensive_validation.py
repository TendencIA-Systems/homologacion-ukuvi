#!/usr/bin/env python3
"""
Comprehensive Validation Script for Vehicle Homologation Master Catalogue
Validates fixes for 4 primary issues + monitors QA findings + client feedback
"""

import csv
import json
import re
from collections import defaultdict, Counter
from typing import Dict, List, Tuple
import sys

class ValidationReport:
    def __init__(self):
        self.total_records = 0
        self.issues = defaultdict(list)
        self.metrics = defaultdict(int)
        self.insurer_stats = defaultdict(lambda: defaultdict(int))
        self.samples = defaultdict(list)

    def add_issue(self, category: str, record: dict, reason: str):
        """Add an issue with sample record"""
        if len(self.samples[category]) < 20:  # Keep max 20 samples per category
            self.samples[category].append({
                'id': record.get('id', 'N/A'),
                'marca': record.get('marca', 'N/A'),
                'modelo': record.get('modelo', 'N/A'),
                'anio': record.get('anio', 'N/A'),
                'version': record.get('version', 'N/A')[:100],  # Truncate long versions
                'transmision': record.get('transmision', 'N/A'),
                'disponibilidad': record.get('disponibilidad', 'N/A')[:50],
                'reason': reason
            })
        self.metrics[category] += 1

def parse_disponibilidad(disp_json: str) -> List[str]:
    """Extract insurer names from disponibilidad JSON"""
    try:
        disp = json.loads(disp_json)
        return list(disp.keys()) if isinstance(disp, dict) else []
    except:
        return []

def validate_issue_1_model_contamination(record: dict, report: ValidationReport):
    """
    Issue 1: Model Field Contamination
    Check for: SERIE prefix, SDRIVE/XDRIVE suffix, trailing trim codes, turbo abbreviations
    """
    modelo = record.get('modelo', '').strip().upper()
    marca = record.get('marca', '').strip().upper()

    # Check SERIE prefix
    if modelo.startswith('SERIE '):
        report.add_issue('issue1_serie_prefix', record, f'Model has SERIE prefix: {modelo}')

    # Check SDRIVE/XDRIVE suffix (mainly BMW)
    if marca == 'BMW' and (' SDRIVE' in modelo or ' XDRIVE' in modelo):
        report.add_issue('issue1_drive_suffix', record, f'Model has DRIVE suffix: {modelo}')

    # Check trailing trim codes (I, IA, IS, etc.) - single letters after space
    if re.search(r'\s+[A-Z]{1,2}$', modelo) and marca in ['BMW', 'AUDI', 'MERCEDES BENZ']:
        report.add_issue('issue1_trailing_trim', record, f'Model has trailing trim: {modelo}')

    # Check turbo abbreviations (TUR, TURBO at end)
    if modelo.endswith(' TUR') or modelo.endswith(' TURBO'):
        report.add_issue('issue1_turbo_suffix', record, f'Model has turbo suffix: {modelo}')

def validate_issue_2_bmw_mini_separation(record: dict, report: ValidationReport):
    """
    Issue 2: BMW/MINI Brand Separation
    Check for: BMW brand with MINI in modelo, MINI brand properly separated
    """
    marca = record.get('marca', '').strip().upper()
    modelo = record.get('modelo', '').strip().upper()

    # Critical: BMW with MINI in modelo
    if marca == 'BMW' and 'MINI' in modelo:
        report.add_issue('issue2_bmw_with_mini', record, f'BMW brand with MINI in model: {modelo}')

    # Track MINI brand records
    if marca == 'MINI':
        report.metrics['mini_brand_count'] += 1
        # Check if MINI prefix in modelo (should be cleaned)
        if modelo.startswith('MINI '):
            report.add_issue('issue2_mini_prefix', record, f'MINI brand has MINI prefix in model: {modelo}')

        # Track MINI variants
        for variant in ['COOPER', 'CLUBMAN', 'CONVERTIBLE', 'COUNTRYMAN', 'PACEMAN', 'CHILI']:
            if variant in modelo:
                report.metrics[f'mini_variant_{variant.lower()}'] += 1

def validate_issue_3_incomplete_models(record: dict, report: ValidationReport):
    """
    Issue 3: Incomplete Model Completion
    Check for: Single-letter BMW M/X, AUDI S/R models
    """
    marca = record.get('marca', '').strip().upper()
    modelo = record.get('modelo', '').strip().upper()
    version = record.get('version', '').strip().upper()

    # BMW M models - should be M2-M8, not just "M"
    if marca == 'BMW' and modelo == 'M':
        report.add_issue('issue3_bmw_single_m', record, f'BMW single M model, version: {version[:50]}')

    # BMW X models - should be X1-X7, not just "X"
    if marca == 'BMW' and modelo == 'X':
        report.add_issue('issue3_bmw_single_x', record, f'BMW single X model, version: {version[:50]}')

    # AUDI S models - should be S1-S8, not just "S"
    if marca == 'AUDI' and modelo == 'S':
        report.add_issue('issue3_audi_single_s', record, f'AUDI single S model, version: {version[:50]}')

    # AUDI R models - should be R8, not just "R"
    if marca == 'AUDI' and modelo == 'R':
        report.add_issue('issue3_audi_single_r', record, f'AUDI single R model, version: {version[:50]}')

def validate_issue_4_mapfre_id_format(record: dict, report: ValidationReport):
    """
    Issue 4: MAPFRE ID Format
    Check for: IDs must have format {CodModelo}_{Year}, not just code
    """
    disponibilidad = record.get('disponibilidad', '')
    insurers = parse_disponibilidad(disponibilidad)

    if 'mapfre' in [ins.lower() for ins in insurers]:
        report.metrics['mapfre_records'] += 1

        # Try to extract MAPFRE ID from disponibilidad
        try:
            disp = json.loads(disponibilidad)
            if isinstance(disp, dict):
                for insurer, data in disp.items():
                    if insurer.lower() == 'mapfre':
                        if isinstance(data, dict) and 'id_original' in data:
                            id_original = str(data['id_original'])
                            # Check if ID has underscore (format: CODE_YEAR)
                            if '_' not in id_original:
                                report.add_issue('issue4_mapfre_no_year', record,
                                               f'MAPFRE ID without year suffix: {id_original}')
                            else:
                                report.metrics['mapfre_ids_with_year'] += 1
        except:
            pass

def validate_qa_transmission_contamination(record: dict, report: ValidationReport):
    """
    QA Issue: Transmission Column Contamination
    Check for: Invalid transmission values (should be AUTO, MANUAL, CVT, DSG, or null/empty)
    """
    transmision = record.get('transmision', '').strip().upper()

    valid_transmissions = ['AUTO', 'MANUAL', 'CVT', 'DSG', 'AUTOMATICA', 'MECANICA', '']

    if transmision and transmision not in valid_transmissions:
        # Check if it's a trim or other contamination
        if len(transmision) > 15 or ' ' in transmision:
            report.add_issue('qa_transmission_contaminated', record,
                           f'Invalid transmission value: {transmision}')

def validate_qa_brand_consolidation(record: dict, report: ValidationReport):
    """
    QA Issue: Brand Consolidation
    Check for: Duplicate/inconsistent brand names
    """
    marca = record.get('marca', '').strip().upper()

    # Known problematic variations
    brand_issues = {
        'AUDI II': 'Should be AUDI',
        'BMW BW': 'Should be BMW',
        'MERCEDES BENZ II': 'Should be MERCEDES BENZ',
        'KIA MOTORS': 'Should be KIA',
        'GREAT WALL MOTORS': 'Should be GREAT WALL',
        'TESLA MOTORS': 'Should be TESLA',
        'AUTOS': 'Invalid brand',
        'MOTOCICLETAS': 'Invalid brand',
        'MULTIMARCA': 'Invalid brand',
        'LEGALIZADO': 'Invalid brand'
    }

    if marca in brand_issues:
        report.add_issue('qa_brand_consolidation', record,
                       f'{marca}: {brand_issues[marca]}')

    # Track brand distribution
    report.metrics[f'brand_{marca}'] += 1

def validate_qa_character_escaping(record: dict, report: ValidationReport):
    """
    QA Issue: Character Escaping
    Check for: Backslashes, escaped quotes in version field
    """
    version = record.get('version', '')

    # Check for backslashes
    if '\\' in version:
        report.add_issue('qa_backslash_in_version', record,
                       f'Backslash found in version: {version[:100]}')

    # Check for quote characters (", ')
    if '"' in version or "'" in version:
        report.add_issue('qa_quotes_in_version', record,
                       f'Quote characters in version: {version[:100]}')

def validate_data_quality(record: dict, report: ValidationReport):
    """
    General Data Quality Checks
    """
    # Check for NULL/empty in critical fields
    critical_fields = ['marca', 'modelo', 'anio']
    for field in critical_fields:
        value = record.get(field, '').strip()
        if not value:
            report.add_issue('data_quality_missing_critical', record,
                           f'Missing critical field: {field}')

    # Check for double spaces
    modelo = record.get('modelo', '')
    if '  ' in modelo:
        report.add_issue('data_quality_double_spaces', record,
                       f'Double spaces in modelo: {modelo}')

    # Check for leading/trailing spaces (after strip check)
    if record.get('modelo', '') != record.get('modelo', '').strip():
        report.add_issue('data_quality_leading_trailing_spaces', record,
                       'Leading/trailing spaces in modelo')

def analyze_insurer_quality(record: dict, report: ValidationReport):
    """
    Track quality metrics by insurer
    """
    disponibilidad = record.get('disponibilidad', '')
    insurers = parse_disponibilidad(disponibilidad)

    for insurer in insurers:
        insurer_key = insurer.lower()
        report.insurer_stats[insurer_key]['total'] += 1

        # Check completeness for this insurer's record
        has_all_fields = all([
            record.get('marca', '').strip(),
            record.get('modelo', '').strip(),
            record.get('anio', '').strip(),
            record.get('version', '').strip()
        ])

        if has_all_fields:
            report.insurer_stats[insurer_key]['complete'] += 1

def main():
    csv_file = '/mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl/data/validation/catalogo_revision.csv'

    print("=" * 80)
    print("COMPREHENSIVE VALIDATION ANALYSIS")
    print("Vehicle Homologation Master Catalogue")
    print("=" * 80)
    print()

    report = ValidationReport()

    print("Loading data...")
    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)

        for record in reader:
            report.total_records += 1

            # Run all validations
            validate_issue_1_model_contamination(record, report)
            validate_issue_2_bmw_mini_separation(record, report)
            validate_issue_3_incomplete_models(record, report)
            validate_issue_4_mapfre_id_format(record, report)
            validate_qa_transmission_contamination(record, report)
            validate_qa_brand_consolidation(record, report)
            validate_qa_character_escaping(record, report)
            validate_data_quality(record, report)
            analyze_insurer_quality(record, report)

            if report.total_records % 5000 == 0:
                print(f"  Processed {report.total_records:,} records...")

    print(f"\nTotal records processed: {report.total_records:,}")
    print()

    # Print results
    print("=" * 80)
    print("PART 1: PRIMARY FIXES VALIDATION")
    print("=" * 80)
    print()

    # Issue 1: Model Contamination
    print("Issue 1: Model Field Contamination")
    print("-" * 40)
    issue1_total = (
        report.metrics['issue1_serie_prefix'] +
        report.metrics['issue1_drive_suffix'] +
        report.metrics['issue1_trailing_trim'] +
        report.metrics['issue1_turbo_suffix']
    )
    print(f"  SERIE prefix: {report.metrics['issue1_serie_prefix']:,}")
    print(f"  DRIVE suffix: {report.metrics['issue1_drive_suffix']:,}")
    print(f"  Trailing trim: {report.metrics['issue1_trailing_trim']:,}")
    print(f"  Turbo suffix: {report.metrics['issue1_turbo_suffix']:,}")
    print(f"  TOTAL: {issue1_total:,} ({issue1_total/report.total_records*100:.2f}%)")

    if issue1_total < report.total_records * 0.01:  # < 1%
        print(f"  STATUS: ✓ PASS (< 1% contamination)")
    else:
        print(f"  STATUS: ✗ FAIL (>= 1% contamination)")
    print()

    # Issue 2: BMW/MINI Separation
    print("Issue 2: BMW/MINI Brand Separation")
    print("-" * 40)
    print(f"  BMW with MINI in modelo: {report.metrics['issue2_bmw_with_mini']:,}")
    print(f"  MINI brand records: {report.metrics['mini_brand_count']:,}")
    print(f"  MINI with prefix: {report.metrics['issue2_mini_prefix']:,}")
    print(f"  MINI variants:")
    for variant in ['cooper', 'clubman', 'convertible', 'countryman', 'paceman', 'chili']:
        count = report.metrics.get(f'mini_variant_{variant}', 0)
        print(f"    - {variant.upper()}: {count:,}")

    if report.metrics['issue2_bmw_with_mini'] == 0:
        print(f"  STATUS: ✓ PASS (No BMW with MINI)")
    else:
        print(f"  STATUS: ✗ FAIL (Found BMW with MINI)")
    print()

    # Issue 3: Incomplete Models
    print("Issue 3: Incomplete Model Completion")
    print("-" * 40)
    print(f"  BMW single M: {report.metrics['issue3_bmw_single_m']:,}")
    print(f"  BMW single X: {report.metrics['issue3_bmw_single_x']:,}")
    print(f"  AUDI single S: {report.metrics['issue3_audi_single_s']:,}")
    print(f"  AUDI single R: {report.metrics['issue3_audi_single_r']:,}")
    issue3_total = (
        report.metrics['issue3_bmw_single_m'] +
        report.metrics['issue3_bmw_single_x'] +
        report.metrics['issue3_audi_single_s'] +
        report.metrics['issue3_audi_single_r']
    )
    print(f"  TOTAL: {issue3_total:,}")

    if issue3_total <= 5:
        print(f"  STATUS: ✓ PASS (<= 5 single-letter models)")
    elif issue3_total <= 20:
        print(f"  STATUS: ⚠ CONDITIONAL (5-20 single-letter models - review needed)")
    else:
        print(f"  STATUS: ✗ FAIL (> 20 single-letter models)")
    print()

    # Issue 4: MAPFRE ID Format
    print("Issue 4: MAPFRE ID Format")
    print("-" * 40)
    print(f"  MAPFRE records: {report.metrics['mapfre_records']:,}")
    print(f"  IDs with year suffix: {report.metrics['mapfre_ids_with_year']:,}")
    print(f"  IDs WITHOUT year suffix: {report.metrics['issue4_mapfre_no_year']:,}")

    if report.metrics['issue4_mapfre_no_year'] == 0:
        print(f"  STATUS: ✓ PASS (100% IDs with year suffix)")
    elif report.metrics['issue4_mapfre_no_year'] <= 10:
        print(f"  STATUS: ⚠ CONDITIONAL (<= 10 without year)")
    else:
        print(f"  STATUS: ✗ FAIL (> 10 without year)")
    print()

    print("=" * 80)
    print("PART 2: QA DEPARTMENT FINDINGS")
    print("=" * 80)
    print()

    # Transmission Contamination
    print("QA Issue: Transmission Contamination")
    print("-" * 40)
    print(f"  Records with invalid transmission: {report.metrics['qa_transmission_contaminated']:,}")
    print(f"  Percentage: {report.metrics['qa_transmission_contaminated']/report.total_records*100:.2f}%")
    print(f"  NOTE: This was NOT part of current fix - monitoring only")
    print()

    # Brand Consolidation
    print("QA Issue: Brand Consolidation")
    print("-" * 40)
    print(f"  Records needing brand consolidation: {report.metrics['qa_brand_consolidation']:,}")
    print(f"  NOTE: This was NOT part of current fix - monitoring only")
    print()

    # Character Escaping
    print("QA Issue: Character Escaping")
    print("-" * 40)
    print(f"  Backslashes in version: {report.metrics['qa_backslash_in_version']:,}")
    print(f"  Quotes in version: {report.metrics['qa_quotes_in_version']:,}")
    print()

    print("=" * 80)
    print("PART 3: DATA QUALITY METRICS")
    print("=" * 80)
    print()

    # General quality
    print("General Data Quality Issues")
    print("-" * 40)
    print(f"  Missing critical fields: {report.metrics['data_quality_missing_critical']:,}")
    print(f"  Double spaces: {report.metrics['data_quality_double_spaces']:,}")
    print(f"  Leading/trailing spaces: {report.metrics['data_quality_leading_trailing_spaces']:,}")
    print()

    # Insurer quality
    print("Quality by Insurer")
    print("-" * 40)
    for insurer in sorted(report.insurer_stats.keys()):
        stats = report.insurer_stats[insurer]
        total = stats['total']
        complete = stats['complete']
        completeness = (complete / total * 100) if total > 0 else 0
        status = '✓' if completeness >= 94 else '⚠' if completeness >= 90 else '✗'
        print(f"  {insurer.upper():15} | Total: {total:6,} | Complete: {complete:6,} | {completeness:5.1f}% {status}")
    print()

    # Print sample records for critical issues
    print("=" * 80)
    print("SAMPLE RECORDS (Critical Issues Only)")
    print("=" * 80)
    print()

    critical_categories = [
        'issue2_bmw_with_mini',
        'issue1_serie_prefix',
        'issue3_bmw_single_m',
        'issue3_bmw_single_x',
        'issue4_mapfre_no_year'
    ]

    for category in critical_categories:
        if report.samples[category]:
            print(f"\n{category}:")
            print("-" * 80)
            for i, sample in enumerate(report.samples[category][:5], 1):
                print(f"  #{i}:")
                print(f"    ID: {sample['id']}")
                print(f"    Marca: {sample['marca']}, Modelo: {sample['modelo']}, Año: {sample['anio']}")
                print(f"    Version: {sample['version']}")
                print(f"    Reason: {sample['reason']}")
                print()

    # Overall assessment
    print("=" * 80)
    print("OVERALL ASSESSMENT")
    print("=" * 80)
    print()

    # Calculate pass/fail
    passed = []
    failed = []
    conditional = []

    if issue1_total < report.total_records * 0.01:
        passed.append("Issue 1: Model contamination")
    else:
        failed.append("Issue 1: Model contamination")

    if report.metrics['issue2_bmw_with_mini'] == 0:
        passed.append("Issue 2: BMW/MINI separation")
    else:
        failed.append("Issue 2: BMW/MINI separation")

    if issue3_total <= 5:
        passed.append("Issue 3: Model completion")
    elif issue3_total <= 20:
        conditional.append("Issue 3: Model completion (review needed)")
    else:
        failed.append("Issue 3: Model completion")

    if report.metrics['issue4_mapfre_no_year'] == 0:
        passed.append("Issue 4: MAPFRE ID format")
    elif report.metrics['issue4_mapfre_no_year'] <= 10:
        conditional.append("Issue 4: MAPFRE ID format")
    else:
        failed.append("Issue 4: MAPFRE ID format")

    print("PASSED:")
    for item in passed:
        print(f"  ✓ {item}")
    print()

    if conditional:
        print("CONDITIONAL:")
        for item in conditional:
            print(f"  ⚠ {item}")
        print()

    if failed:
        print("FAILED:")
        for item in failed:
            print(f"  ✗ {item}")
        print()

    # Final verdict
    if len(failed) == 0 and len(conditional) <= 1:
        print("FINAL VERDICT: ✓ PRODUCTION READY")
        print("All critical fixes validated successfully.")
    elif len(failed) == 0:
        print("FINAL VERDICT: ⚠ CONDITIONAL APPROVAL")
        print("Primary fixes successful but some items need review.")
    else:
        print("FINAL VERDICT: ✗ NOT READY")
        print("Critical issues found - fixes not fully deployed.")

    print()
    print("=" * 80)

if __name__ == '__main__':
    main()
