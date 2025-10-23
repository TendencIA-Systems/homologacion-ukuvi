#!/usr/bin/env python3
"""
Analiza el overlap real entre catálogos de aseguradoras
Determina si los nulls son un problema técnico o esperados
"""

import csv
from pathlib import Path

def load_vehicles(csv_path):
    """Carga vehículos únicos (marca|modelo|año) de un CSV"""
    vehicles = set()
    with open(csv_path, 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                # marca, modelo, anio
                vehicle_key = f"{row['marca']}|{row['modelo']}|{row['anio']}"
                vehicles.add(vehicle_key)
            except:
                continue
    return vehicles

def main():
    base_path = Path("data/origin")

    print("=" * 80)
    print("ANÁLISIS DE OVERLAP ENTRE CATÁLOGOS DE ASEGURADORAS")
    print("=" * 80)
    print()

    # Cargar catálogos
    print("📊 Cargando catálogos...")
    zurich = load_vehicles(base_path / "zurich-origin.csv")
    hdi = load_vehicles(base_path / "hdi-origin.csv")
    axa = load_vehicles(base_path / "axa-origin.csv")
    atlas = load_vehicles(base_path / "atlas-origin.csv")
    qualitas = load_vehicles(base_path / "qualitas-origin.csv")
    gnp = load_vehicles(base_path / "gnp-origin.csv")

    print(f"✓ ZURICH: {len(zurich):,} vehículos únicos")
    print(f"✓ HDI: {len(hdi):,} vehículos únicos")
    print(f"✓ AXA: {len(axa):,} vehículos únicos")
    print(f"✓ ATLAS: {len(atlas):,} vehículos únicos")
    print(f"✓ QUALITAS: {len(qualitas):,} vehículos únicos")
    print(f"✓ GNP: {len(gnp):,} vehículos únicos")
    print()

    # Crear catálogo de referencia (Zurich + HDI)
    reference = zurich | hdi
    print(f"📚 Catálogo de referencia (ZURICH + HDI): {len(reference):,} vehículos únicos")
    print()

    # Calcular overlaps
    print("=" * 80)
    print("OVERLAP CON CATÁLOGO DE REFERENCIA (ZURICH + HDI)")
    print("=" * 80)
    print()

    insurers = {
        'AXA': axa,
        'ATLAS': atlas,
        'QUALITAS': qualitas,
        'GNP': gnp
    }

    for name, vehicles in insurers.items():
        overlap = vehicles & reference
        overlap_pct = (len(overlap) / len(vehicles)) * 100 if len(vehicles) > 0 else 0
        unique_to_insurer = len(vehicles - reference)

        print(f"🔍 {name}:")
        print(f"   Total de vehículos: {len(vehicles):,}")
        print(f"   En catálogo de referencia: {len(overlap):,} ({overlap_pct:.1f}%)")
        print(f"   Únicos de {name}: {unique_to_insurer:,} ({100-overlap_pct:.1f}%)")

        if overlap_pct < 50:
            print(f"   ⚠️  BAJO OVERLAP - Los nulls son mayormente ESPERADOS")
        elif overlap_pct < 75:
            print(f"   🟡 OVERLAP MODERADO - Algunos nulls son esperados, otros pueden ser problema")
        else:
            print(f"   ❌ ALTO OVERLAP - Los nulls son mayormente un PROBLEMA del algoritmo")
        print()

    # Análisis cruzado: ¿Cuántos vehículos de AXA están en otras aseguradoras?
    print("=" * 80)
    print("ANÁLISIS CRUZADO: ¿DÓNDE ESTÁN LOS VEHÍCULOS DE AXA?")
    print("=" * 80)
    print()

    axa_in_zurich = len(axa & zurich)
    axa_in_hdi = len(axa & hdi)
    axa_in_atlas = len(axa & atlas)
    axa_in_qualitas = len(axa & qualitas)
    axa_in_gnp = len(axa & gnp)
    axa_nowhere = len(axa - (zurich | hdi | atlas | qualitas | gnp))

    print(f"De los {len(axa):,} vehículos de AXA:")
    print(f"  • {axa_in_zurich:,} ({axa_in_zurich/len(axa)*100:.1f}%) están en ZURICH")
    print(f"  • {axa_in_hdi:,} ({axa_in_hdi/len(axa)*100:.1f}%) están en HDI")
    print(f"  • {axa_in_atlas:,} ({axa_in_atlas/len(axa)*100:.1f}%) están en ATLAS")
    print(f"  • {axa_in_qualitas:,} ({axa_in_qualitas/len(axa)*100:.1f}%) están en QUALITAS")
    print(f"  • {axa_in_gnp:,} ({axa_in_gnp/len(axa)*100:.1f}%) están en GNP")
    print(f"  • {axa_nowhere:,} ({axa_nowhere/len(axa)*100:.1f}%) son ÚNICOS de AXA")
    print()

    # Ejemplos de vehículos únicos de AXA
    print("=" * 80)
    print("MUESTRA: 10 VEHÍCULOS ÚNICOS DE AXA (no en ninguna otra aseguradora)")
    print("=" * 80)
    unique_axa_sample = list(axa - (zurich | hdi | atlas | qualitas | gnp))[:10]
    for vehicle in unique_axa_sample:
        print(f"  • {vehicle}")
    print()

    # Conclusión
    print("=" * 80)
    print("CONCLUSIÓN")
    print("=" * 80)
    print()

    avg_overlap = sum((len(v & reference) / len(v)) * 100 for v in insurers.values()) / len(insurers)

    if avg_overlap < 60:
        print("✅ LOS NULLS SON MAYORMENTE ESPERADOS")
        print("   Los catálogos de aseguradoras son genuinamente diferentes.")
        print("   El sistema está funcionando correctamente.")
        print("   Recomendación: NO hacer cambios al algoritmo.")
    elif avg_overlap < 80:
        print("🟡 LOS NULLS SON PARCIALMENTE UN PROBLEMA")
        print(f"   Hay {avg_overlap:.1f}% de overlap promedio con el catálogo de referencia.")
        print("   Algunos nulls son esperados, pero otros pueden ser mejorados.")
        print("   Recomendación: Revisar umbrales y considerar ajustes menores.")
    else:
        print("❌ LOS NULLS SON MAYORMENTE UN PROBLEMA DEL ALGORITMO")
        print(f"   Hay {avg_overlap:.1f}% de overlap promedio con el catálogo de referencia.")
        print("   La mayoría de los vehículos DEBERÍAN hacer match pero no lo hacen.")
        print("   Recomendación: Ajustar algoritmo de matching urgentemente.")

    print()
    print("=" * 80)

if __name__ == "__main__":
    main()
