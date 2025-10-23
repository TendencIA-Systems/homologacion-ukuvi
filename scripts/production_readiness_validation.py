#!/usr/bin/env python3
"""
Análisis de validación para preparación de producción
Valida la calidad del catálogo homologado contra los requisitos del cliente
"""

import pandas as pd
import numpy as np
from pathlib import Path
import json

def analyze_catalog_quality(csv_path):
    """Analiza la calidad del catálogo de validación"""

    print("=" * 80)
    print("ANÁLISIS DE VALIDACIÓN PARA PRODUCCIÓN")
    print("=" * 80)

    # Cargar datos
    print("\n📊 Cargando datos de validación...")
    df = pd.read_csv(csv_path)

    print(f"✓ Total de registros: {len(df):,}")
    print(f"✓ Columnas: {len(df.columns)}")

    # Definir columnas de aseguradoras
    insurer_cols = [
        'ana_version', 'atlas_version', 'axa_version', 'bx_version',
        'chubb_version', 'elpotosi_version', 'gnp_version', 'hdi_version',
        'mapfre_version', 'qualitas_version', 'zurich_version'
    ]

    # === 1. ANÁLISIS DE NULLS ===
    print("\n" + "=" * 80)
    print("1. ANÁLISIS DE VALORES NULL POR ASEGURADORA")
    print("=" * 80)

    null_analysis = {}
    for col in insurer_cols:
        total = len(df)
        nulls = df[col].isna().sum() + (df[col] == 'null').sum()
        null_pct = (nulls / total) * 100
        non_nulls = total - nulls

        insurer_name = col.replace('_version', '').upper()
        null_analysis[insurer_name] = {
            'total': total,
            'nulls': int(nulls),
            'non_nulls': int(non_nulls),
            'null_percentage': round(null_pct, 2)
        }

        status = "✅" if null_pct < 30 else "⚠️" if null_pct < 60 else "❌"
        print(f"{status} {insurer_name:12} | Nulls: {nulls:6,} ({null_pct:5.1f}%) | Válidos: {non_nulls:6,}")

    # === 2. ANÁLISIS DE DISPONIBILIDAD ===
    print("\n" + "=" * 80)
    print("2. ANÁLISIS DE DISPONIBILIDAD POR VEHÍCULO")
    print("=" * 80)

    avg_availability = df['total_aseguradoras_disponibles'].mean()
    median_availability = df['total_aseguradoras_disponibles'].median()

    print(f"Promedio de aseguradoras por vehículo: {avg_availability:.2f}")
    print(f"Mediana de aseguradoras por vehículo: {median_availability:.0f}")

    # Distribución de disponibilidad
    print("\nDistribución de disponibilidad:")
    avail_counts = df['total_aseguradoras_disponibles'].value_counts().sort_index()
    for count, freq in avail_counts.items():
        pct = (freq / len(df)) * 100
        bar = "█" * int(pct / 2)
        print(f"  {count:2} aseguradoras: {freq:5,} vehículos ({pct:5.1f}%) {bar}")

    # === 3. ANÁLISIS POR MARCA ===
    print("\n" + "=" * 80)
    print("3. TOP 20 MARCAS CON MÁS VEHÍCULOS")
    print("=" * 80)

    top_brands = df['marca'].value_counts().head(20)
    for marca, count in top_brands.items():
        pct = (count / len(df)) * 100
        print(f"  {marca:15} {count:6,} vehículos ({pct:5.1f}%)")

    # === 4. ANÁLISIS DE VEHÍCULOS ESPECÍFICOS DEL CLIENTE ===
    print("\n" + "=" * 80)
    print("4. VALIDACIÓN DE VEHÍCULOS REPORTADOS POR EL CLIENTE")
    print("=" * 80)

    # Los 4 vehículos específicos del reporte del cliente
    test_vehicles = [
        {'marca': 'HONDA', 'modelo': 'HR-V', 'anio': 2020, 'transmision': 'AUTO'},
        {'marca': 'MAZDA', 'modelo': 'CX-5', 'anio': 2020, 'transmision': 'AUTO'},
        {'marca': 'NISSAN', 'modelo': 'VERSA', 'anio': 2020, 'transmision': 'AUTO'},
        {'marca': 'VOLKSWAGEN', 'modelo': 'JETTA', 'anio': 2020, 'transmision': 'AUTO'},
    ]

    for vehicle in test_vehicles:
        print(f"\n🚗 {vehicle['marca']} {vehicle['modelo']} {vehicle['anio']} {vehicle['transmision']}")

        mask = (
            (df['marca'] == vehicle['marca']) &
            (df['modelo'] == vehicle['modelo']) &
            (df['anio'] == vehicle['anio']) &
            (df['transmision'] == vehicle['transmision'])
        )

        matches = df[mask]

        if len(matches) == 0:
            print("   ❌ NO ENCONTRADO EN CATÁLOGO")
            continue

        print(f"   Versiones encontradas: {len(matches)}")

        for idx, row in matches.iterrows():
            print(f"   • {row['version_homologada']}")
            print(f"     Disponible en {row['total_aseguradoras_disponibles']} aseguradoras:")

            # Contar correctas, incorrectas, nulas
            correctas = 0
            incorrectas = 0
            nulas = 0

            for col in insurer_cols:
                val = row[col]
                if pd.isna(val) or val == 'null':
                    nulas += 1
                elif isinstance(val, str) and len(val.strip()) > 0:
                    correctas += 1
                else:
                    incorrectas += 1

            print(f"     ✅ Correctas: {correctas} | ❌ Incorrectas: {incorrectas} | ⚪ Nulas: {nulas}")

    # === 5. PROBLEMAS DETECTADOS ===
    print("\n" + "=" * 80)
    print("5. PROBLEMAS DETECTADOS")
    print("=" * 80)

    problems = []

    # 5.1 Aseguradoras con alto porcentaje de nulls
    for insurer, data in null_analysis.items():
        if data['null_percentage'] > 60:
            problems.append(f"❌ CRÍTICO: {insurer} tiene {data['null_percentage']:.1f}% de valores null")
        elif data['null_percentage'] > 30:
            problems.append(f"⚠️  ADVERTENCIA: {insurer} tiene {data['null_percentage']:.1f}% de valores null")

    # 5.2 Vehículos con poca disponibilidad
    low_availability = df[df['total_aseguradoras_disponibles'] < 3]
    if len(low_availability) > 0:
        pct = (len(low_availability) / len(df)) * 100
        problems.append(f"⚠️  {len(low_availability):,} vehículos ({pct:.1f}%) tienen menos de 3 aseguradoras")

    # 5.3 Vehículos sin ninguna aseguradora
    no_availability = df[df['total_aseguradoras_disponibles'] == 0]
    if len(no_availability) > 0:
        pct = (len(no_availability) / len(df)) * 100
        problems.append(f"❌ CRÍTICO: {len(no_availability):,} vehículos ({pct:.1f}%) no tienen NINGUNA aseguradora disponible")

    if problems:
        for problem in problems:
            print(problem)
    else:
        print("✅ No se detectaron problemas críticos")

    # === 6. RECOMENDACIONES ===
    print("\n" + "=" * 80)
    print("6. RECOMENDACIONES PARA PRODUCCIÓN")
    print("=" * 80)

    recommendations = []

    # Calcular promedio de nulls
    avg_null_pct = np.mean([data['null_percentage'] for data in null_analysis.values()])

    if avg_null_pct > 40:
        recommendations.append("❌ NO LISTO: Promedio de nulls ({:.1f}%) es demasiado alto".format(avg_null_pct))
        recommendations.append("   → Revisar y corregir código de normalización de todas las aseguradoras")
    elif avg_null_pct > 25:
        recommendations.append("⚠️  REVISAR: Promedio de nulls ({:.1f}%) es elevado".format(avg_null_pct))
        recommendations.append("   → Priorizar corrección de aseguradoras con más nulls")
    else:
        recommendations.append("✅ ACEPTABLE: Promedio de nulls ({:.1f}%) está dentro del rango aceptable".format(avg_null_pct))

    if len(no_availability) > 0:
        recommendations.append("❌ CRÍTICO: Existen vehículos sin ninguna aseguradora")
        recommendations.append("   → Investigar por qué estos vehículos no matchean con ninguna aseguradora")

    if avg_availability < 4:
        recommendations.append("⚠️  Disponibilidad promedio baja ({:.1f} aseguradoras por vehículo)".format(avg_availability))
        recommendations.append("   → Revisar algoritmo de matching y umbrales de similitud")
    else:
        recommendations.append("✅ Disponibilidad promedio aceptable ({:.1f} aseguradoras por vehículo)".format(avg_availability))

    for rec in recommendations:
        print(rec)

    # === 7. DECISIÓN FINAL ===
    print("\n" + "=" * 80)
    print("7. DECISIÓN: ¿LISTO PARA PRODUCCIÓN?")
    print("=" * 80)

    critical_issues = sum(1 for p in problems if p.startswith("❌"))
    warnings = sum(1 for p in problems if p.startswith("⚠️"))

    if critical_issues > 0:
        print("\n🔴 NO LISTO PARA PRODUCCIÓN")
        print(f"   Problemas críticos detectados: {critical_issues}")
        print("   Se requiere corrección antes de despliegue")
    elif warnings > 2:
        print("\n🟡 LISTO CON RESERVAS")
        print(f"   Advertencias detectadas: {warnings}")
        print("   Se recomienda revisar antes de despliegue a producción")
    else:
        print("\n🟢 LISTO PARA PRODUCCIÓN")
        print("   Calidad de datos aceptable para despliegue")

    print("\n" + "=" * 80)

    return {
        'total_records': len(df),
        'null_analysis': null_analysis,
        'avg_availability': avg_availability,
        'problems': problems,
        'recommendations': recommendations,
        'critical_issues': critical_issues,
        'warnings': warnings
    }

if __name__ == "__main__":
    csv_path = Path("data/validation/catalogo_revision_zurich_hdi_comparacion_versiones.csv")

    if not csv_path.exists():
        print(f"❌ Error: No se encontró el archivo {csv_path}")
        exit(1)

    results = analyze_catalog_quality(csv_path)

    # Guardar resultados en JSON
    output_path = Path("reports/production_readiness_analysis.json")
    output_path.parent.mkdir(exist_ok=True)

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    print(f"\n📄 Resultados guardados en: {output_path}")
