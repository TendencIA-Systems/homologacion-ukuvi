#!/usr/bin/env python3
"""
Analiza el campo VERSION de todas las aseguradoras para identificar
tokens de navegación, audio, confort que son irrelevantes
"""

import csv
import re
from pathlib import Path
from collections import Counter

def extract_noise_tokens(version):
    """Extrae tokens irrelevantes (navegación, audio, confort)"""
    if not version or not isinstance(version, str):
        return []

    tokens = []
    version_upper = version.upper()

    # Navegación patterns
    nav_patterns = [
        r'SIS\.?\s*NAV\.?', r'SIS\.?\s*NAVEGACI[OÓ]N', r'SIST\.?\s*NAV\.?',
        r'SISTEMA\s+NAVEGACI[OÓ]N', r'PAQ\.?\s*NAVEG\.?', r'PAQ\.?\s*NAVEGACI[OÓ]N',
        r'NAVEGACI[OÓ]N', r'NAVEG\.?', r'NAV\.?', r'NAVIGATOR',
        r'GPS', r'NAVI', r'RCD', r'RNS'
    ]

    for pattern in nav_patterns:
        matches = re.findall(pattern, version_upper)
        tokens.extend(matches)

    # Audio/Entertainment patterns
    audio_patterns = [
        r'RADIO', r'STEREO', r'ESTEREO', r'EST[EÉ]REO',
        r'SOUND\s*SYSTEM', r'SISTEMA\s+AUDIO', r'AUDIO\s+PREMIUM',
        r'BOSE', r'HARMAN\s*KARDON', r'BEATS', r'JBL', r'ALPINE',
        r'DVD', r'REPRODUCTOR', r'MP3', r'USB', r'AUX', r'BLUETOOTH',
        r'BT', r'PANTALLA', r'TOUCH\s*SCREEN', r'DISPLAY'
    ]

    for pattern in audio_patterns:
        matches = re.findall(pattern, version_upper)
        tokens.extend(matches)

    # Wheel/Tire patterns
    wheel_patterns = [
        r'RIN\s*\d+', r'R\d+(?:\s|$)', r'LLANTAS?\s*\d+',
        r'ALEACI[OÓ]N', r'ALUMINIO', r'RUEDAS?\s*\d+'
    ]

    for pattern in wheel_patterns:
        matches = re.findall(pattern, version_upper)
        tokens.extend(matches)

    # Confort/Luxury features
    comfort_patterns = [
        r'PIEL', r'CUERO', r'LEATHER', r'TELA', r'ALCANTARA', r'GAMUZA',
        r'ASIENTOS\s+ELECTRICOS', r'QUEMACOCOS', r'TECHO\s+SOLAR',
        r'SUNROOF', r'PANORAMIC', r'PANOR[AÁ]MICO',
        r'CLIMATIZADOR', r'CLIMA\s+DUAL', r'BI-ZONA',
        r'CALEFACCI[OÓ]N', r'VENTILACI[OÓ]N'
    ]

    for pattern in comfort_patterns:
        matches = re.findall(pattern, version_upper)
        tokens.extend(matches)

    # Safety (abbreviations only, not descriptive)
    safety_abbrev = [
        r'\bABS\b', r'\bEBD\b', r'\bESP\b', r'\bVSC\b', r'\bTCS\b',
        r'\bBA\b', r'\bCA\b', r'\bCE\b', r'\bQC\b', r'\bVP\b',
        r'\bSM\b', r'\bVT\b', r'\bDIS\b', r'\bTAM\b'
    ]

    for pattern in safety_abbrev:
        matches = re.findall(pattern, version_upper)
        tokens.extend(matches)

    # Other noise
    other_patterns = [
        r'AS\s+DE', r'QCC', r'PAQ\.?', r'PACK', r'PKG', r'PACKAGE',
        r'KIT', r'EQUIP\.?', r'EQUIPAMIENTO'
    ]

    for pattern in other_patterns:
        matches = re.findall(pattern, version_upper)
        tokens.extend(matches)

    return tokens

def analyze_insurer(csv_path, insurer_name):
    """Analiza tokens de ruido en VERSION"""
    noise_counter = Counter()
    total_records = 0
    records_with_noise = 0

    with open(csv_path, 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        for row in reader:
            total_records += 1
            version = row.get('version_original', '')

            tokens = extract_noise_tokens(version)
            if tokens:
                records_with_noise += 1
                for token in tokens:
                    noise_counter[token] += 1

    return {
        'insurer': insurer_name,
        'total_records': total_records,
        'records_with_noise': records_with_noise,
        'percentage': (records_with_noise / total_records * 100) if total_records > 0 else 0,
        'noise': noise_counter
    }

def main():
    base_path = Path("data/origin")

    print("=" * 100)
    print("ANÁLISIS DE TOKENS IRRELEVANTES EN CAMPO VERSION")
    print("=" * 100)
    print()

    insurers = [
        'zurich', 'hdi', 'axa', 'atlas', 'qualitas', 'gnp',
        'mapfre', 'chubb', 'bx', 'elpotosi', 'ana'
    ]

    all_noise = Counter()
    results = []

    for insurer in insurers:
        csv_file = base_path / f"{insurer}-origin.csv"
        if not csv_file.exists():
            print(f"⚠️  {insurer.upper()}: Archivo no encontrado")
            continue

        print(f"🔍 Analizando {insurer.upper()}...")
        result = analyze_insurer(csv_file, insurer)
        results.append(result)

        for token, count in result['noise'].items():
            all_noise[token] += count

    print()
    print("=" * 100)
    print("RESULTADOS POR ASEGURADORA")
    print("=" * 100)
    print()

    for result in results:
        print(f"📊 {result['insurer'].upper()}:")
        print(f"   Total registros: {result['total_records']:,}")
        print(f"   Registros con ruido en VERSION: {result['records_with_noise']:,} ({result['percentage']:.1f}%)")
        if result['noise']:
            print(f"   Top 15 tokens de ruido:")
            for token, count in result['noise'].most_common(15):
                print(f"      • {token}: {count:,} veces")
        print()

    print("=" * 100)
    print("TOKENS GLOBALES DE RUIDO (ordenados por frecuencia)")
    print("=" * 100)
    print()

    print("Top 80 tokens más comunes:")
    for i, (token, count) in enumerate(all_noise.most_common(80), 1):
        total_records = sum(r['total_records'] for r in results)
        percentage = (count / total_records) * 100
        print(f"{i:2}. {token:30} | {count:7,} ocurrencias ({percentage:.2f}%)")

    print()
    print("=" * 100)
    print("LISTA DEFINITIVA PARA DICCIONARIO (formato JavaScript array)")
    print("=" * 100)
    print()

    # Generar lista limpia
    noise_list = []
    for token, count in all_noise.most_common(150):
        clean_token = token.strip().upper()
        # Normalizar variantes
        clean_token = re.sub(r'[\.\/\s]+', ' ', clean_token).strip()
        clean_token = re.sub(r'\s+', ' ', clean_token)

        if clean_token and len(clean_token) > 0:
            noise_list.append(clean_token)

    # Remover duplicados
    seen = set()
    unique_noise = []
    for token in noise_list:
        if token not in seen:
            seen.add(token)
            unique_noise.append(token)

    print("const EXPANDED_NOISE_TOKENS = [")
    print("  // Navegación")
    nav_tokens = [t for t in unique_noise if any(x in t for x in ['NAV', 'GPS', 'RCD', 'RNS'])]
    for token in nav_tokens[:20]:
        print(f'  "{token}",')

    print("\n  // Audio/Entertainment")
    audio_tokens = [t for t in unique_noise if any(x in t for x in ['DVD', 'MP3', 'USB', 'BOSE', 'RADIO', 'AUDIO', 'BLUETOOTH', 'BT'])]
    for token in audio_tokens[:20]:
        print(f'  "{token}",')

    print("\n  // Ruedas/Llantas")
    wheel_tokens = [t for t in unique_noise if 'RIN' in t or 'R' in t[:2] or 'LLANTA' in t]
    for token in wheel_tokens[:15]:
        print(f'  "{token}",')

    print("\n  // Confort/Lujo")
    comfort_tokens = [t for t in unique_noise if any(x in t for x in ['PIEL', 'CUERO', 'TELA', 'CLIMA', 'QUEMACOCOS', 'SUNROOF'])]
    for token in comfort_tokens[:15]:
        print(f'  "{token}",')

    print("\n  // Safety (solo abreviaturas)")
    safety_tokens = [t for t in unique_noise if len(t) <= 4 and any(x in t for x in ['ABS', 'BA', 'CA', 'CE', 'QC', 'VP', 'SM', 'VT', 'DIS', 'TAM', 'EBD', 'ESP', 'VSC', 'TCS'])]
    for token in safety_tokens:
        print(f'  "{token}",')

    print("\n  // Otros")
    other_tokens = [t for t in unique_noise if t not in nav_tokens + audio_tokens + wheel_tokens + comfort_tokens + safety_tokens]
    for token in other_tokens[:20]:
        print(f'  "{token}",')

    print("];")

    print()
    print("=" * 100)

if __name__ == "__main__":
    main()
