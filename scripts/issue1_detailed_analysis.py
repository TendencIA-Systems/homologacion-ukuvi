#!/usr/bin/env python3
"""
Detailed Analysis of Issue 1: Model Contamination
Focus on SERIE prefix and trailing trim codes
"""

import csv
import json
from collections import defaultdict, Counter

def parse_disponibilidad(disp_json: str):
    """Extract insurer names from disponibilidad JSON"""
    try:
        disp = json.loads(disp_json)
        return list(disp.keys()) if isinstance(disp, dict) else []
    except:
        return []

def main():
    csv_file = '/mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl/data/validation/catalogo_revision.csv'

    serie_by_insurer = defaultdict(int)
    trim_by_insurer = defaultdict(int)
    serie_samples = []
    trim_samples = []
    serie_models = Counter()
    trim_models = Counter()

    print("Analyzing Issue 1: Model Contamination in Detail")
    print("=" * 80)
    print()

    with open(csv_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)

        for record in reader:
            marca = record.get('marca', '').strip().upper()
            modelo = record.get('modelo', '').strip().upper()
            version = record.get('version', '').strip()
            insurers = parse_disponibilidad(record.get('disponibilidad', ''))

            # Check SERIE prefix
            if modelo.startswith('SERIE '):
                for insurer in insurers:
                    serie_by_insurer[insurer.lower()] += 1

                serie_models[f"{marca} {modelo}"] += 1

                if len(serie_samples) < 20:
                    serie_samples.append({
                        'id': record.get('id'),
                        'marca': marca,
                        'modelo': modelo,
                        'anio': record.get('anio'),
                        'version': version[:80],
                        'insurers': ', '.join(insurers)
                    })

            # Check trailing trim codes
            import re
            if re.search(r'\s+[A-Z]{1,2}$', modelo) and marca in ['BMW', 'AUDI', 'MERCEDES BENZ']:
                for insurer in insurers:
                    trim_by_insurer[insurer.lower()] += 1

                trim_models[f"{marca} {modelo}"] += 1

                if len(trim_samples) < 20:
                    trim_samples.append({
                        'id': record.get('id'),
                        'marca': marca,
                        'modelo': modelo,
                        'anio': record.get('anio'),
                        'version': version[:80],
                        'insurers': ', '.join(insurers)
                    })

    # Report SERIE prefix issues
    print("1. SERIE PREFIX CONTAMINATION")
    print("-" * 80)
    print()
    print("By Insurer:")
    for insurer in sorted(serie_by_insurer.keys(), key=lambda x: serie_by_insurer[x], reverse=True):
        count = serie_by_insurer[insurer]
        print(f"  {insurer.upper():15} | {count:5,} records")
    print()

    print("Most Common SERIE Models:")
    for modelo, count in serie_models.most_common(10):
        print(f"  {modelo:30} | {count:4,} records")
    print()

    print("Sample Records (first 10):")
    for i, sample in enumerate(serie_samples[:10], 1):
        print(f"  #{i}:")
        print(f"    {sample['marca']} {sample['modelo']} {sample['anio']}")
        print(f"    Version: {sample['version']}")
        print(f"    From: {sample['insurers']}")
        print()

    # Report trailing trim issues
    print()
    print("2. TRAILING TRIM CODE CONTAMINATION")
    print("-" * 80)
    print()
    print("By Insurer:")
    for insurer in sorted(trim_by_insurer.keys(), key=lambda x: trim_by_insurer[x], reverse=True):
        count = trim_by_insurer[insurer]
        print(f"  {insurer.upper():15} | {count:5,} records")
    print()

    print("Most Common Models with Trailing Trims:")
    for modelo, count in trim_models.most_common(10):
        print(f"  {modelo:30} | {count:4,} records")
    print()

    print("Sample Records (first 10):")
    for i, sample in enumerate(trim_samples[:10], 1):
        print(f"  #{i}:")
        print(f"    {sample['marca']} {sample['modelo']} {sample['anio']}")
        print(f"    Version: {sample['version']}")
        print(f"    From: {sample['insurers']}")
        print()

    # Analysis
    print()
    print("=" * 80)
    print("ANALYSIS & RECOMMENDATIONS")
    print("=" * 80)
    print()
    print(f"Total SERIE prefix issues: {sum(serie_by_insurer.values()):,}")
    print(f"Total trailing trim issues: {sum(trim_by_insurer.values()):,}")
    print()

    # Check which insurers are most affected
    all_insurers = set(list(serie_by_insurer.keys()) + list(trim_by_insurer.keys()))
    print("Insurers needing normalization code review:")
    for insurer in sorted(all_insurers):
        serie_count = serie_by_insurer.get(insurer, 0)
        trim_count = trim_by_insurer.get(insurer, 0)
        if serie_count > 0 or trim_count > 0:
            print(f"  {insurer.upper():15} | SERIE: {serie_count:4,} | Trailing: {trim_count:4,}")

    print()
    print("RECOMMENDATION:")
    print("  The normalization code fixes are either:")
    print("  1. NOT deployed to the insurers listed above, OR")
    print("  2. Not applied to existing/historical data (only new data)")
    print()
    print("  Action needed:")
    print("  - Review normalization code for each affected insurer")
    print("  - Verify fixes are present in code")
    print("  - Re-process affected insurers' data OR")
    print("  - Apply UPDATE queries to clean existing master catalogue")

if __name__ == '__main__':
    main()
