#!/bin/bash

cd "/mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl"

# Create reports directory
mkdir -p reports

REPORT="reports/validation_report_$(date +%Y%m%d_%H%M%S).txt"

echo "ETL VALIDATION ANALYSIS" > "$REPORT"
echo "======================" >> "$REPORT"
echo "Date: $(date)" >> "$REPORT"
echo "" >> "$REPORT"

# Count total records
TOTAL=$(tail -n +2 data/validation/catalogo_revision.csv | wc -l)
echo "Total Records: $TOTAL" >> "$REPORT"
echo "" >> "$REPORT"

# ISSUE 1: Model Contamination
echo "ISSUE 1: Model Contamination" >> "$REPORT"
echo "============================" >> "$REPORT"

SERIE=$(tail -n +2 data/validation/catalogo_revision.csv | cut -d',' -f4 | grep -iE 'SERIE [0-9]' | wc -l)
echo "SERIE prefix: $SERIE" >> "$REPORT"

DRIVE=$(tail -n +2 data/validation/catalogo_revision.csv | cut -d',' -f4 | grep -iE 'SDRIVE|XDRIVE' | wc -l)
echo "SDRIVE/XDRIVE: $DRIVE" >> "$REPORT"

TRAILING=$(tail -n +2 data/validation/catalogo_revision.csv | cut -d',' -f4 | grep -iE ' I$| IA$' | wc -l)
echo "Trailing I/IA: $TRAILING" >> "$REPORT"

TURBO=$(tail -n +2 data/validation/catalogo_revision.csv | cut -d',' -f4 | grep -iE 'TUR$|TURBO' | wc -l)
echo "TURBO suffix: $TURBO" >> "$REPORT"

CONTAM=$(($SERIE + $DRIVE + $TRAILING + $TURBO))
echo "TOTAL CONTAMINATED: $CONTAM" >> "$REPORT"

if [ $CONTAM -eq 0 ]; then
    echo "Status: PASS (zero)" >> "$REPORT"
elif [ $CONTAM -lt 50 ]; then
    echo "Status: PASS (acceptable)" >> "$REPORT"
else
    echo "Status: FAIL (too many)" >> "$REPORT"
fi
echo "" >> "$REPORT"

# ISSUE 2: BMW/MINI Separation
echo "ISSUE 2: BMW/MINI Separation" >> "$REPORT"
echo "============================" >> "$REPORT"

BMW_MINI=$(tail -n +2 data/validation/catalogo_revision.csv | awk -F',' '$3 == "BMW" && $4 ~ /MINI/' | wc -l)
echo "BMW with MINI: $BMW_MINI" >> "$REPORT"

MINI_BRAND=$(tail -n +2 data/validation/catalogo_revision.csv | awk -F',' '$3 == "MINI"' | wc -l)
echo "MINI brand records: $MINI_BRAND" >> "$REPORT"

if [ $BMW_MINI -eq 0 ] && [ $MINI_BRAND -gt 0 ]; then
    echo "Status: PASS" >> "$REPORT"
else
    echo "Status: FAIL" >> "$REPORT"
fi
echo "" >> "$REPORT"

# ISSUE 3: Incomplete Models
echo "ISSUE 3: Incomplete Models" >> "$REPORT"
echo "============================" >> "$REPORT"

BMW_M=$(tail -n +2 data/validation/catalogo_revision.csv | awk -F',' '$3 == "BMW" && $4 == "M"' | wc -l)
echo "BMW single M: $BMW_M" >> "$REPORT"

BMW_X=$(tail -n +2 data/validation/catalogo_revision.csv | awk -F',' '$3 == "BMW" && $4 == "X"' | wc -l)
echo "BMW single X: $BMW_X" >> "$REPORT"

AUDI_S=$(tail -n +2 data/validation/catalogo_revision.csv | awk -F',' '$3 == "AUDI" && $4 == "S"' | wc -l)
echo "AUDI single S: $AUDI_S" >> "$REPORT"

AUDI_R=$(tail -n +2 data/validation/catalogo_revision.csv | awk -F',' '$3 == "AUDI" && $4 == "R"' | wc -l)
echo "AUDI single R: $AUDI_R" >> "$REPORT"

SINGLES=$(($BMW_M + $BMW_X + $AUDI_S + $AUDI_R))
echo "TOTAL SINGLES: $SINGLES" >> "$REPORT"

if [ $SINGLES -lt 5 ]; then
    echo "Status: PASS" >> "$REPORT"
elif [ $SINGLES -lt 20 ]; then
    echo "Status: CONDITIONAL" >> "$REPORT"
else
    echo "Status: FAIL" >> "$REPORT"
fi
echo "" >> "$REPORT"

# ISSUE 4: MAPFRE IDs
echo "ISSUE 4: MAPFRE IDs" >> "$REPORT"
echo "===================" >> "$REPORT"

MAPFRE=$(tail -n +2 data/validation/catalogo_revision.csv | grep -o '"MAPFRE"' | wc -l)
echo "MAPFRE records found: $MAPFRE" >> "$REPORT"
echo "Status: INFO (presence check only)" >> "$REPORT"
echo "" >> "$REPORT"

# Data Quality
echo "DATA QUALITY CHECKS" >> "$REPORT"
echo "===================" >> "$REPORT"

EMPTY_MARCA=$(tail -n +2 data/validation/catalogo_revision.csv | awk -F',' '$3 == ""' | wc -l)
echo "Empty marca: $EMPTY_MARCA" >> "$REPORT"

EMPTY_MODELO=$(tail -n +2 data/validation/catalogo_revision.csv | awk -F',' '$4 == ""' | wc -l)
echo "Empty modelo: $EMPTY_MODELO" >> "$REPORT"

QUALITY_ISSUES=$(($EMPTY_MARCA + $EMPTY_MODELO))
echo "TOTAL QUALITY ISSUES: $QUALITY_ISSUES" >> "$REPORT"

if [ $QUALITY_ISSUES -eq 0 ]; then
    echo "Status: PASS" >> "$REPORT"
else
    echo "Status: FAIL" >> "$REPORT"
fi
echo "" >> "$REPORT"

# Final Assessment
echo "FINAL ASSESSMENT" >> "$REPORT"
echo "================" >> "$REPORT"

echo "Issue 1 (Contamination): $CONTAM records" >> "$REPORT"
echo "Issue 2 (BMW/MINI): BMW=$BMW_MINI MINI=$MINI_BRAND" >> "$REPORT"
echo "Issue 3 (Singles): $SINGLES records" >> "$REPORT"
echo "Issue 4 (MAPFRE): $MAPFRE records found" >> "$REPORT"
echo "Data Quality: $QUALITY_ISSUES issues" >> "$REPORT"
echo "" >> "$REPORT"

# Overall status
PASS_COUNT=0
if [ $CONTAM -lt 100 ]; then PASS_COUNT=$(($PASS_COUNT + 1)); fi
if [ $BMW_MINI -eq 0 ] && [ $MINI_BRAND -gt 0 ]; then PASS_COUNT=$(($PASS_COUNT + 1)); fi
if [ $SINGLES -lt 20 ]; then PASS_COUNT=$(($PASS_COUNT + 1)); fi
if [ $QUALITY_ISSUES -eq 0 ]; then PASS_COUNT=$(($PASS_COUNT + 1)); fi

echo "Passing checks: $PASS_COUNT/4" >> "$REPORT"

if [ $PASS_COUNT -eq 4 ]; then
    echo "OVERALL: PRODUCTION READY" >> "$REPORT"
elif [ $PASS_COUNT -ge 3 ]; then
    echo "OVERALL: CONDITIONAL" >> "$REPORT"
else
    echo "OVERALL: NOT READY" >> "$REPORT"
fi

# Display report
cat "$REPORT"

echo ""
echo "Report saved to: $REPORT"
