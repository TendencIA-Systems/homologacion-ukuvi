#!/usr/bin/env python3
"""
Refined contamination analysis to distinguish legitimate model names from actual contamination
"""

import csv
import re
from pathlib import Path
from collections import Counter

BASE_PATH = Path("/mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl")
DATA_PATH = BASE_PATH / "data" / "validation"

# Legitimate models that end with single letters (whitelisted)
LEGITIMATE_SINGLE_LETTER_MODELS = {
    'CLASE A', 'CLASE B', 'CLASE C', 'CLASE E', 'CLASE G', 'CLASE S',
    'SERIE A', 'SERIE B', 'SERIE C', 'SERIE E', 'SERIE G', 'SERIE S',
    'TYPE S', 'TYPE R',
    'CLASE A AMG', 'CLASE B AMG', 'CLASE C AMG', 'CLASE E AMG', 'CLASE S AMG'
}

def analyze_contamination(filename):
    """Detailed contamination analysis"""
    filepath = DATA_PATH / filename
    print(f"\n{'='*80}")
    print(f"DETAILED CONTAMINATION ANALYSIS: {filename}")
    print(f"{'='*80}\n")

    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        data = list(reader)

    print(f"Total records: {len(data):,}\n")

    # Categorize contamination
    categories = {
        'legitimate_clase': [],  # CLASE A, B, E, etc.
        'bmw_single_letter_trim': [],  # 118 I, 120 IA, etc.
        'serie_prefix': [],  # SERIE 3, SERIE X5
        'drive_suffix': [],  # X3 SDRIVE, X5 XDRIVE
        'turbo_in_model': [],  # M2 TUR, X2 TURBO
        'other_single_letter': []  # Other patterns
    }

    for row in data:
        marca = row.get('marca', '').upper()
        modelo = row.get('modelo', '').strip().upper()
        version = row.get('version', 'N/A')[:80]

        # Check for CLASE/SERIE with single letter (legitimate)
        if re.match(r'^CLASE\s+[A-Z]$', modelo) or re.match(r'^SERIE\s+[A-Z]$', modelo):
            categories['legitimate_clase'].append({
                'marca': marca,
                'modelo': modelo,
                'anio': row.get('anio', ''),
                'version': version
            })
            continue

        # Check for SERIE prefix (actual contamination)
        if re.search(r'\bSERIE\s+\d', modelo):
            categories['serie_prefix'].append({
                'marca': marca,
                'modelo': modelo,
                'anio': row.get('anio', ''),
                'version': version
            })
            continue

        # Check for SDRIVE/XDRIVE (actual contamination)
        if re.search(r'\b(SDRIVE|XDRIVE)\b', modelo):
            categories['drive_suffix'].append({
                'marca': marca,
                'modelo': modelo,
                'anio': row.get('anio', ''),
                'version': version
            })
            continue

        # Check for TURBO in modelo (potential contamination)
        if re.search(r'\bTURBO?\b', modelo):
            categories['turbo_in_model'].append({
                'marca': marca,
                'modelo': modelo,
                'anio': row.get('anio', ''),
                'version': version
            })
            continue

        # Check for BMW single-letter trims (118 I, 120 IA)
        if marca == 'BMW' and re.search(r'\d+\s+I[A]?$', modelo):
            categories['bmw_single_letter_trim'].append({
                'marca': marca,
                'modelo': modelo,
                'anio': row.get('anio', ''),
                'version': version
            })
            continue

        # Check for other single-letter patterns
        if re.search(r'\s+[A-Z]$', modelo):
            # Only flag if not whitelisted
            modelo_clean = modelo.strip()
            if modelo_clean not in LEGITIMATE_SINGLE_LETTER_MODELS:
                categories['other_single_letter'].append({
                    'marca': marca,
                    'modelo': modelo,
                    'anio': row.get('anio', ''),
                    'version': version
                })

    # Print results
    print("CONTAMINATION BREAKDOWN:\n")

    total_legitimate = len(categories['legitimate_clase'])
    total_contamination = sum(len(v) for k, v in categories.items() if k != 'legitimate_clase')

    print(f"✅ LEGITIMATE (CLASE/SERIE + letter): {total_legitimate:,}")
    print(f"❌ ACTUAL CONTAMINATION: {total_contamination:,}\n")

    print("-" * 80)

    for category, items in categories.items():
        if category == 'legitimate_clase':
            continue

        count = len(items)
        if count > 0:
            print(f"\n{category.upper().replace('_', ' ')}: {count:,}")
            print("Examples:")
            for item in items[:5]:
                print(f"  → {item['marca']} {item['modelo']} {item['anio']}")
                print(f"     Version: {item['version']}")

    # Summary
    print("\n" + "="*80)
    print("SUMMARY")
    print("="*80)
    print(f"Total Legitimate: {total_legitimate:,}")
    print(f"Total Contamination: {total_contamination:,}")
    print(f"Contamination Rate: {(total_contamination / len(data) * 100):.2f}%")

    if total_contamination == 0:
        print("\n✅ PASS - No contamination found")
    elif total_contamination < len(data) * 0.01:
        print(f"\n✅ PASS - Contamination < 1% ({(total_contamination / len(data) * 100):.2f}%)")
    else:
        print(f"\n❌ FAIL - Contamination ≥ 1% ({(total_contamination / len(data) * 100):.2f}%)")

    return {
        'total_records': len(data),
        'legitimate': total_legitimate,
        'contamination': total_contamination,
        'contamination_rate': f"{(total_contamination / len(data) * 100):.2f}%",
        'by_category': {k: len(v) for k, v in categories.items()},
        'details': categories
    }

def main():
    """Main execution"""
    print("="*80)
    print("REFINED CONTAMINATION ANALYSIS")
    print("="*80)

    files = [
        'catalogo_revision_zurich.csv',
        'catalogo_revision_zurich_hdi.csv'
    ]

    for filename in files:
        result = analyze_contamination(filename)
        print("\n")

if __name__ == '__main__':
    main()
