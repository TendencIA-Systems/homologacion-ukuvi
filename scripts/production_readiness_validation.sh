#!/bin/bash
# Análisis de validación para preparación de producción usando herramientas bash

CSV_FILE="data/validation/catalogo_revision_zurich_hdi_comparacion_versiones.csv"

echo "================================================================================"
echo "ANÁLISIS DE VALIDACIÓN PARA PRODUCCIÓN"
echo "================================================================================"

# Total de registros
TOTAL_LINES=$(wc -l < "$CSV_FILE")
TOTAL_RECORDS=$((TOTAL_LINES - 1))  # Excluir header

echo ""
echo "📊 Total de registros: $TOTAL_RECORDS"

# === 1. ANÁLISIS DE NULLS POR ASEGURADORA ===
echo ""
echo "================================================================================"
echo "1. ANÁLISIS DE VALORES NULL POR ASEGURADORA"
echo "================================================================================"

# Columnas de aseguradoras (índices basados en la estructura del CSV)
# id_vehiculo,marca,modelo,anio,transmision,version_homologada,aseguradora_origen,
# ana_version(8),atlas_version(9),axa_version(10),bx_version(11),chubb_version(12),
# elpotosi_version(13),gnp_version(14),hdi_version(15),mapfre_version(16),qualitas_version(17),zurich_version(18)

declare -A insurers
insurers[8]="ANA"
insurers[9]="ATLAS"
insurers[10]="AXA"
insurers[11]="BX"
insurers[12]="CHUBB"
insurers[13]="ELPOTOSI"
insurers[14]="GNP"
insurers[15]="HDI"
insurers[16]="MAPFRE"
insurers[17]="QUALITAS"
insurers[18]="ZURICH"

for col_idx in "${!insurers[@]}"; do
    insurer="${insurers[$col_idx]}"

    # Contar nulls (valores vacíos o "null")
    nulls=$(awk -F',' -v col="$col_idx" 'NR>1 {
        if ($col == "" || $col == "null") count++
    } END {print count+0}' "$CSV_FILE")

    non_nulls=$((TOTAL_RECORDS - nulls))
    null_pct=$(awk "BEGIN {printf \"%.1f\", ($nulls / $TOTAL_RECORDS) * 100}")

    # Status
    if (( $(echo "$null_pct < 30" | bc -l) )); then
        status="✅"
    elif (( $(echo "$null_pct < 60" | bc -l) )); then
        status="⚠️"
    else
        status="❌"
    fi

    printf "%s %-12s | Nulls: %6d (%5.1f%%) | Válidos: %6d\n" "$status" "$insurer" "$nulls" "$null_pct" "$non_nulls"
done

# === 2. ANÁLISIS DE DISPONIBILIDAD ===
echo ""
echo "================================================================================"
echo "2. ANÁLISIS DE DISPONIBILIDAD POR VEHÍCULO"
echo "================================================================================"

# Promedio de aseguradoras disponibles (columna 19)
avg_availability=$(awk -F',' 'NR>1 {sum+=$19; count++} END {printf "%.2f", sum/count}' "$CSV_FILE")
echo "Promedio de aseguradoras por vehículo: $avg_availability"

# Distribución
echo ""
echo "Distribución de disponibilidad:"
awk -F',' 'NR>1 {count[$19]++} END {
    for (i=0; i<=11; i++) {
        if (count[i] > 0) {
            pct = (count[i] / (NR-1)) * 100
            printf "  %2d aseguradoras: %5d vehículos (%5.1f%%)\n", i, count[i], pct
        }
    }
}' "$CSV_FILE" | sort -n

# === 3. TOP MARCAS ===
echo ""
echo "================================================================================"
echo "3. TOP 20 MARCAS CON MÁS VEHÍCULOS"
echo "================================================================================"

awk -F',' 'NR>1 {count[$2]++} END {
    for (marca in count) {
        print count[marca], marca
    }
}' "$CSV_FILE" | sort -rn | head -20 | while read count marca; do
    pct=$(awk "BEGIN {printf \"%.1f\", ($count / $TOTAL_RECORDS) * 100}")
    printf "  %-15s %6d vehículos (%5.1f%%)\n" "$marca" "$count" "$pct"
done

# === 4. VALIDACIÓN DE VEHÍCULOS ESPECÍFICOS ===
echo ""
echo "================================================================================"
echo "4. VALIDACIÓN DE VEHÍCULOS REPORTADOS POR EL CLIENTE"
echo "================================================================================"

# Honda HR-V 2020 AUTO
echo ""
echo "🚗 HONDA HR-V 2020 AUTO"
awk -F',' '$2=="HONDA" && $3=="HR-V" && $4==2020 && $5=="AUTO" {
    print "   Versión:", $6
    print "   Disponible en", $19, "aseguradoras"
    # Contar nulls
    nulls=0
    for (i=8; i<=18; i++) {
        if ($i == "" || $i == "null") nulls++
    }
    correctas = 11 - nulls
    printf "   ✅ Correctas: %d | ⚪ Nulas: %d\n", correctas, nulls
}' "$CSV_FILE"

# Mazda CX-5 2020 AUTO
echo ""
echo "🚗 MAZDA CX-5 2020 AUTO"
awk -F',' '$2=="MAZDA" && $3=="CX-5" && $4==2020 && $5=="AUTO" {
    print "   Versión:", $6
    print "   Disponible en", $19, "aseguradoras"
    nulls=0
    for (i=8; i<=18; i++) {
        if ($i == "" || $i == "null") nulls++
    }
    correctas = 11 - nulls
    printf "   ✅ Correctas: %d | ⚪ Nulas: %d\n", correctas, nulls
}' "$CSV_FILE"

# Nissan Versa 2020 AUTO
echo ""
echo "🚗 NISSAN VERSA 2020 AUTO"
awk -F',' '$2=="NISSAN" && $3=="VERSA" && $4==2020 && $5=="AUTO" {
    print "   Versión:", $6
    print "   Disponible en", $19, "aseguradoras"
    nulls=0
    for (i=8; i<=18; i++) {
        if ($i == "" || $i == "null") nulls++
    }
    correctas = 11 - nulls
    printf "   ✅ Correctas: %d | ⚪ Nulas: %d\n", correctas, nulls
}' "$CSV_FILE"

# Volkswagen Jetta 2020 AUTO
echo ""
echo "🚗 VOLKSWAGEN JETTA 2020 AUTO"
awk -F',' '$2=="VOLKSWAGEN" && $3=="JETTA" && $4==2020 && $5=="AUTO" {
    print "   Versión:", $6
    print "   Disponible en", $19, "aseguradoras"
    nulls=0
    for (i=8; i<=18; i++) {
        if ($i == "" || $i == "null") nulls++
    }
    correctas = 11 - nulls
    printf "   ✅ Correctas: %d | ⚪ Nulas: %d\n", correctas, nulls
}' "$CSV_FILE"

# === 5. PROBLEMAS DETECTADOS ===
echo ""
echo "================================================================================"
echo "5. RESUMEN DE CALIDAD"
echo "================================================================================"

# Vehículos sin disponibilidad
no_avail=$(awk -F',' 'NR>1 && $19==0 {count++} END {print count+0}' "$CSV_FILE")
if [ "$no_avail" -gt 0 ]; then
    pct=$(awk "BEGIN {printf \"%.1f\", ($no_avail / $TOTAL_RECORDS) * 100}")
    echo "❌ CRÍTICO: $no_avail vehículos ($pct%) no tienen NINGUNA aseguradora disponible"
fi

# Vehículos con poca disponibilidad
low_avail=$(awk -F',' 'NR>1 && $19>0 && $19<3 {count++} END {print count+0}' "$CSV_FILE")
if [ "$low_avail" -gt 0 ]; then
    pct=$(awk "BEGIN {printf \"%.1f\", ($low_avail / $TOTAL_RECORDS) * 100}")
    echo "⚠️  $low_avail vehículos ($pct%) tienen menos de 3 aseguradoras"
fi

# === 6. DECISIÓN FINAL ===
echo ""
echo "================================================================================"
echo "6. DECISIÓN: ¿LISTO PARA PRODUCCIÓN?"
echo "================================================================================"

if [ "$no_avail" -gt 100 ]; then
    echo ""
    echo "🔴 NO LISTO PARA PRODUCCIÓN"
    echo "   Demasiados vehículos sin ninguna aseguradora disponible"
    echo "   Se requiere corrección antes de despliegue"
elif [ "$low_avail" -gt 1000 ]; then
    echo ""
    echo "🟡 LISTO CON RESERVAS"
    echo "   Muchos vehículos con baja disponibilidad"
    echo "   Se recomienda revisar antes de despliegue a producción"
else
    echo ""
    echo "🟢 LISTO PARA PRODUCCIÓN"
    echo "   Calidad de datos aceptable para despliegue"
fi

echo ""
echo "================================================================================"
