#!/usr/bin/env python3
"""
Analiza el campo MODELO de todas las aseguradoras para identificar
specs que deben ser removidos y movidos al campo VERSION
"""

import csv
import re
from pathlib import Path
from collections import Counter

def extract_specs_from_modelo(modelo):
    """Extrae tokens sospechosos del campo modelo"""
    if not modelo or not isinstance(modelo, str):
        return []

    # Patrones de specs que NO deberían estar en modelo
    specs = []
    modelo_upper = modelo.upper()

    # Body types
    body_types = ['HATCH BACK', 'HATCHBACK', 'SEDAN', 'SUV', 'COUPE', 'CONVERTIBLE',
                  'PICK UP', 'PICKUP', 'VAN', 'WAGON', 'CROSS COUNTRY', 'CROSSOVER']
    for bt in body_types:
        if bt in modelo_upper:
            specs.append(bt)

    # Parenthesis content (e.g., (DERBY), (SERIES 3))
    paren_matches = re.findall(r'\([^)]+\)', modelo)
    specs.extend(paren_matches)

    # Performance trims that should be in version
    perf_trims = ['GTI', 'GTS', 'GT', 'RS', 'R-LINE', 'S-LINE', 'AMG', 'M-SPORT',
                  'TYPE-R', 'TYPE-S', 'A-SPEC', 'NISMO', 'TRD', 'SRT']
    for trim in perf_trims:
        if trim in modelo_upper:
            specs.append(trim)

    # Wheel sizes
    wheel_matches = re.findall(r'RIN\s*\d+|R\d+|LLANTAS?\s*\d+', modelo_upper)
    specs.extend(wheel_matches)

    # CROSS (común en modelos VW)
    if ' CROSS' in modelo_upper or modelo_upper.endswith('CROSS'):
        specs.append('CROSS')

    return specs

def analyze_insurer(csv_path, insurer_name):
    """Analiza specs en campo MODELO de una aseguradora"""
    specs_counter = Counter()
    total_records = 0
    records_with_specs = 0

    with open(csv_path, 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        for row in reader:
            total_records += 1
            modelo = row.get('modelo', '')

            specs = extract_specs_from_modelo(modelo)
            if specs:
                records_with_specs += 1
                for spec in specs:
                    specs_counter[spec] += 1

    return {
        'insurer': insurer_name,
        'total_records': total_records,
        'records_with_specs': records_with_specs,
        'percentage': (records_with_specs / total_records * 100) if total_records > 0 else 0,
        'specs': specs_counter
    }

def main():
    base_path = Path("data/origin")

    print("=" * 100)
    print("ANÁLISIS DE SPECS EN CAMPO MODELO")
    print("=" * 100)
    print()

    insurers = [
        'zurich', 'hdi', 'axa', 'atlas', 'qualitas', 'gnp',
        'mapfre', 'chubb', 'bx', 'elpotosi', 'ana'
    ]

    all_specs = Counter()
    results = []

    for insurer in insurers:
        csv_file = base_path / f"{insurer}-origin.csv"
        if not csv_file.exists():
            print(f"⚠️  {insurer.upper()}: Archivo no encontrado")
            continue

        print(f"🔍 Analizando {insurer.upper()}...")
        result = analyze_insurer(csv_file, insurer)
        results.append(result)

        # Agregar a contador global
        for spec, count in result['specs'].items():
            all_specs[spec] += count

    print()
    print("=" * 100)
    print("RESULTADOS POR ASEGURADORA")
    print("=" * 100)
    print()

    for result in results:
        print(f"📊 {result['insurer'].upper()}:")
        print(f"   Total registros: {result['total_records']:,}")
        print(f"   Registros con specs en MODELO: {result['records_with_specs']:,} ({result['percentage']:.1f}%)")
        if result['specs']:
            print(f"   Top 10 specs encontrados:")
            for spec, count in result['specs'].most_common(10):
                print(f"      • {spec}: {count:,} veces")
        print()

    print("=" * 100)
    print("SPECS GLOBALES A REMOVER DE MODELO (ordenados por frecuencia)")
    print("=" * 100)
    print()

    print("Top 50 specs más comunes:")
    for i, (spec, count) in enumerate(all_specs.most_common(50), 1):
        total_records = sum(r['total_records'] for r in results)
        percentage = (count / total_records) * 100
        print(f"{i:2}. {spec:30} | {count:6,} ocurrencias ({percentage:.2f}%)")

    print()
    print("=" * 100)
    print("LISTA DEFINITIVA PARA CÓDIGO (formato JavaScript array)")
    print("=" * 100)
    print()

    # Generar lista limpia para código
    specs_list = []
    for spec, count in all_specs.most_common(100):
        # Limpiar el spec
        clean_spec = spec.strip().upper()
        clean_spec = clean_spec.replace('(', '').replace(')', '')
        if clean_spec and len(clean_spec) > 1:
            specs_list.append(clean_spec)

    # Remover duplicados manteniendo orden
    seen = set()
    unique_specs = []
    for spec in specs_list:
        if spec not in seen:
            seen.add(spec)
            unique_specs.append(spec)

    print("const MODELO_SPECS_TO_REMOVE = [")
    for spec in unique_specs[:80]:  # Top 80
        print(f'  "{spec}",')
    print("];")

    print()
    print("=" * 100)

if __name__ == "__main__":
    main()
