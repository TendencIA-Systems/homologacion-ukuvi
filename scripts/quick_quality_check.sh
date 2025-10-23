#!/bin/bash
# Quick Quality Check - Validación rápida de calidad del catálogo
# Uso: ./scripts/quick_quality_check.sh [archivo_csv]

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Archivo por defecto
CSV_FILE="${1:-data/validation/catalogo_revision_zurich_hdi_comparacion_versiones.csv}"

if [ ! -f "$CSV_FILE" ]; then
    echo -e "${RED}❌ Error: No se encontró el archivo $CSV_FILE${NC}"
    exit 1
fi

echo "================================"
echo "  QUICK QUALITY CHECK"
echo "================================"
echo "Archivo: $CSV_FILE"
echo ""

# Total de registros
TOTAL=$(( $(wc -l < "$CSV_FILE") - 1 ))
echo "📊 Total de registros: $TOTAL"
echo ""

# Función para calcular nulls de una columna
check_nulls() {
    local col=$1
    local name=$2
    local nulls=$(awk -F',' -v col="$col" 'NR>1 {if ($col=="" || $col=="null") count++} END {print count+0}' "$CSV_FILE")
    local pct=$(awk "BEGIN {printf \"%.1f\", ($nulls / $TOTAL) * 100}")

    if (( $(echo "$pct < 30" | bc -l) )); then
        echo -e "${GREEN}✅${NC} $name: $pct% nulls"
    elif (( $(echo "$pct < 60" | bc -l) )); then
        echo -e "${YELLOW}⚠️ ${NC} $name: $pct% nulls"
    else
        echo -e "${RED}❌${NC} $name: $pct% nulls"
    fi
}

echo "🔍 Análisis de Nulls por Aseguradora:"
check_nulls 8 "ANA      "
check_nulls 9 "ATLAS    "
check_nulls 10 "AXA      "
check_nulls 11 "BX       "
check_nulls 12 "CHUBB    "
check_nulls 13 "ELPOTOSI "
check_nulls 14 "GNP      "
check_nulls 15 "HDI      "
check_nulls 16 "MAPFRE   "
check_nulls 17 "QUALITAS "
check_nulls 18 "ZURICH   "

echo ""

# Calcular promedio de nulls
AVG_NULLS=$(awk -F',' 'NR>1 {
    for (i=8; i<=18; i++) {
        if ($i=="" || $i=="null") nulls++
    }
    total += 11
}
END {
    printf "%.1f", (nulls/total)*100
}' "$CSV_FILE")

echo -e "📈 Promedio de nulls: ${AVG_NULLS}%"

if (( $(echo "$AVG_NULLS < 40" | bc -l) )); then
    echo -e "   ${GREEN}✅ ACEPTABLE${NC} (< 40%)"
elif (( $(echo "$AVG_NULLS < 60" | bc -l) )); then
    echo -e "   ${YELLOW}⚠️  REVISABLE${NC} (40-60%)"
else
    echo -e "   ${RED}❌ CRÍTICO${NC} (> 60%)"
fi

echo ""
echo "🔍 Disponibilidad de Vehículos:"

# Promedio de aseguradoras por vehículo
AVG_AVAIL=$(awk -F',' 'NR>1 {sum+=$19; count++} END {printf "%.2f", sum/count}' "$CSV_FILE" 2>/dev/null || echo "N/A")
echo "   Promedio: $AVG_AVAIL aseguradoras/vehículo"

# Vehículos sin aseguradoras
NO_AVAIL=$(awk -F',' 'NR>1 && $19==0 {count++} END {print count+0}' "$CSV_FILE" 2>/dev/null || echo "0")
echo "   Sin aseguradoras: $NO_AVAIL vehículos"

# Vehículos con baja disponibilidad (<3)
LOW_AVAIL=$(awk -F',' 'NR>1 && $19>0 && $19<3 {count++} END {print count+0}' "$CSV_FILE" 2>/dev/null || echo "0")
LOW_PCT=$(awk "BEGIN {printf \"%.1f\", ($LOW_AVAIL / $TOTAL) * 100}")
echo "   Con <3 aseguradoras: $LOW_AVAIL vehículos ($LOW_PCT%)"

echo ""
echo "================================"
echo "  RESULTADO"
echo "================================"

# Criterios de decisión
CRITICAL_NULLS=$(awk -F',' 'NR>1 {
    ana=0; atlas=0; axa=0
    if ($8=="" || $8=="null") ana=1
    if ($9=="" || $9=="null") atlas=1
    if ($10=="" || $10=="null") axa=1
} END {
    # Contar aseguradoras con >70% nulls
    # (simplificación - idealmente calcularíamos exacto)
    print 0
}' "$CSV_FILE")

if (( $(echo "$AVG_NULLS > 60" | bc -l) )); then
    echo -e "${RED}🔴 NO LISTO PARA PRODUCCIÓN${NC}"
    echo "   Motivo: Promedio de nulls muy alto ($AVG_NULLS%)"
elif (( $(echo "$AVG_NULLS > 40" | bc -l) )); then
    echo -e "${YELLOW}🟡 LISTO CON RESERVAS${NC}"
    echo "   Motivo: Promedio de nulls elevado ($AVG_NULLS%)"
elif (( $(echo "$LOW_PCT > 25" | bc -l) )); then
    echo -e "${YELLOW}🟡 LISTO CON RESERVAS${NC}"
    echo "   Motivo: Muchos vehículos con baja disponibilidad ($LOW_PCT%)"
else
    echo -e "${GREEN}🟢 LISTO PARA PRODUCCIÓN${NC}"
    echo "   Calidad de datos aceptable"
fi

echo ""
echo "Para análisis detallado, ver: REPORTE-VALIDACION-PRODUCCION.md"
echo "================================"
