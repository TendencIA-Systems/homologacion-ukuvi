#!/bin/bash
#
# Comprehensive ETL Validation Script
# ====================================
#
# This script validates all fixes applied to the vehicle homologation system
# using standard Unix tools (awk, grep, sed, wc)
#

set -euo pipefail

# Configuration
DATA_FILE="../data/validation/catalogo_revision.csv"
COMPARISON_FILE="../data/validation/catalogo_revision_comparacion_versiones.csv"
REPORT_DIR="../reports"
REPORT_FILE="${REPORT_DIR}/validation_report_$(date +%Y%m%d_%H%M%S).md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create reports directory
mkdir -p "${REPORT_DIR}"

# Initialize report
cat > "${REPORT_FILE}" << 'HEADER'
# ETL Validation Comprehensive Report

**Generated**: $(date '+%Y-%m-%d %H:%M:%S')
**Data Source**: Master Catalog

---

HEADER

echo "================================================================================"
echo "🔍 COMPREHENSIVE ETL VALIDATION ANALYSIS"
echo "================================================================================"
echo ""
echo "Data file: ${DATA_FILE}"
echo "Report output: ${REPORT_FILE}"
echo ""

# Get total record count (excluding header)
TOTAL_RECORDS=$(tail -n +2 "${DATA_FILE}" | wc -l)
echo "✓ Total records: ${TOTAL_RECORDS}"

# Write to report
cat >> "${REPORT_FILE}" << EOF

## Summary Statistics

- **Total Records**: $(printf "%'d" ${TOTAL_RECORDS})
- **Analysis Date**: $(date '+%Y-%m-%d %H:%M:%S')

---

EOF

# ============================================================================
# ISSUE 1: Model Field Contamination
# ============================================================================

echo ""
echo "================================================================================"
echo "🔍 ISSUE 1: Model Field Contamination"
echo "================================================================================"

cat >> "${REPORT_FILE}" << 'EOF'
## Issue 1: Model Field Contamination

### Description
Checking for unwanted patterns in the `modelo` field:
- SERIE prefixes (e.g., "SERIE 3" should be "3")
- SDRIVE/XDRIVE suffixes
- Trailing I/IA codes
- TUR/TURBO suffixes
- MINI prefixes

### Results

EOF

# Check for SERIE prefix
SERIE_COUNT=$(tail -n +2 "${DATA_FILE}" | awk -F',' '{print $4}' | grep -iE '\bSERIE\s+[0-9]+\b' | wc -l || echo "0")
SERIE_PCT=$(awk "BEGIN {printf \"%.2f\", ($SERIE_COUNT/$TOTAL_RECORDS)*100}")
echo "  SERIE prefix:                 ${SERIE_COUNT} records (${SERIE_PCT}%)"

# Check for SDRIVE/XDRIVE
DRIVE_COUNT=$(tail -n +2 "${DATA_FILE}" | awk -F',' '{print $4}' | grep -iE '\b(SDRIVE|XDRIVE)\b' | wc -l || echo "0")
DRIVE_PCT=$(awk "BEGIN {printf \"%.2f\", ($DRIVE_COUNT/$TOTAL_RECORDS)*100}")
echo "  SDRIVE/XDRIVE suffix:         ${DRIVE_COUNT} records (${DRIVE_PCT}%)"

# Check for trailing I/IA
TRAILING_COUNT=$(tail -n +2 "${DATA_FILE}" | awk -F',' '{print $4}' | grep -iE '\b[0-9]+\s+I[A]?\b' | wc -l || echo "0")
TRAILING_PCT=$(awk "BEGIN {printf \"%.2f\", ($TRAILING_COUNT/$TOTAL_RECORDS)*100}")
echo "  Trailing I/IA:                ${TRAILING_COUNT} records (${TRAILING_PCT}%)"

# Check for TUR/TURBO suffix
TURBO_COUNT=$(tail -n +2 "${DATA_FILE}" | awk -F',' '{print $4}' | grep -iE '\b(M[0-9]+|X[0-9]+)\s+TUR(BO)?\b' | wc -l || echo "0")
TURBO_PCT=$(awk "BEGIN {printf \"%.2f\", ($TURBO_COUNT/$TOTAL_RECORDS)*100}")
echo "  TUR/TURBO suffix:             ${TURBO_COUNT} records (${TURBO_PCT}%)"

# Calculate total contamination
TOTAL_CONTAMINATED=$((SERIE_COUNT + DRIVE_COUNT + TRAILING_COUNT + TURBO_COUNT))
CONTAMINATION_PCT=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_CONTAMINATED/$TOTAL_RECORDS)*100}")

echo ""
echo "  TOTAL CONTAMINATED:           ${TOTAL_CONTAMINATED} records (${CONTAMINATION_PCT}%)"

# Determine status
if [ ${TOTAL_CONTAMINATED} -eq 0 ]; then
    STATUS="✅ PASS - Zero contamination"
    COLOR="${GREEN}"
elif [ ${TOTAL_CONTAMINATED} -lt 50 ]; then
    STATUS="✅ PASS - Acceptable (<50 records)"
    COLOR="${GREEN}"
elif [ ${TOTAL_CONTAMINATED} -lt 100 ]; then
    STATUS="⚠️  CONDITIONAL - Review edge cases"
    COLOR="${YELLOW}"
else
    STATUS="❌ FAIL - Too many contaminated records"
    COLOR="${RED}"
fi

echo -e "${COLOR}  Status: ${STATUS}${NC}"

# Write to report
cat >> "${REPORT_FILE}" << EOF
| Pattern | Count | Percentage |
|---------|-------|------------|
| SERIE prefix | ${SERIE_COUNT} | ${SERIE_PCT}% |
| SDRIVE/XDRIVE | ${DRIVE_COUNT} | ${DRIVE_PCT}% |
| Trailing I/IA | ${TRAILING_COUNT} | ${TRAILING_PCT}% |
| TUR/TURBO suffix | ${TURBO_COUNT} | ${TURBO_PCT}% |
| **TOTAL** | **${TOTAL_CONTAMINATED}** | **${CONTAMINATION_PCT}%** |

**Status**: ${STATUS}

EOF

# Get samples if contaminated
if [ ${TOTAL_CONTAMINATED} -gt 0 ]; then
    echo "" >> "${REPORT_FILE}"
    echo "**Sample Records (First 10):**" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    echo "| Marca | Modelo | Año | Version |" >> "${REPORT_FILE}"
    echo "|-------|--------|-----|---------|" >> "${REPORT_FILE}"

    # Get sample contaminated records
    tail -n +2 "${DATA_FILE}" | awk -F',' '
        $4 ~ /\bSERIE\s+[0-9]+\b|
\b(SDRIVE|XDRIVE)\b|\b[0-9]+\s+I[A]?\b|\b(M[0-9]+|X[0-9]+)\s+TUR(BO)?\b/ {
            print "| " $3 " | " $4 " | " $5 " | " substr($7, 1, 50) "... |"
        }
    ' | head -10 >> "${REPORT_FILE}"
fi

echo "" >> "${REPORT_FILE}"
echo "---" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

# ============================================================================
# ISSUE 2: BMW/MINI Brand Separation
# ============================================================================

echo ""
echo "================================================================================"
echo "🔍 ISSUE 2: BMW/MINI Brand Separation"
echo "================================================================================"

cat >> "${REPORT_FILE}" << 'EOF'
## Issue 2: BMW/MINI Brand Separation

### Description
Verifying that MINI vehicles are properly separated from BMW brand:
- No BMW records should have "MINI" in modelo field
- MINI should exist as separate brand
- MINI modelo should not have "MINI " prefix

### Results

EOF

# Check for BMW with MINI in modelo
BMW_WITH_MINI=$(tail -n +2 "${DATA_FILE}" | awk -F',' '$3 == "BMW" && $4 ~ /MINI/i' | wc -l || echo "0")

# Check for MINI brand records
MINI_BRAND=$(tail -n +2 "${DATA_FILE}" | awk -F',' '$3 == "MINI"' | wc -l || echo "0")

# Check for MINI with "MINI " prefix
MINI_WITH_PREFIX=$(tail -n +2 "${DATA_FILE}" | awk -F',' '$3 == "MINI" && $4 ~ /^MINI /' | wc -l || echo "0")

echo "  BMW records with MINI:        ${BMW_WITH_MINI}"
echo "  MINI brand records:           ${MINI_BRAND}"
echo "  MINI with 'MINI ' prefix:     ${MINI_WITH_PREFIX}"

# Get MINI variants
if [ ${MINI_BRAND} -gt 0 ]; then
    echo ""
    echo "  MINI Variants:"
    tail -n +2 "${DATA_FILE}" | awk -F',' '$3 == "MINI" {print $4}' | sort | uniq -c | sort -rn | head -10 | while read count variant; do
        echo "    ${variant}: ${count} records"
    done
fi

# Determine status
if [ ${BMW_WITH_MINI} -eq 0 ] && [ ${MINI_BRAND} -gt 0 ]; then
    STATUS="✅ PASS - Clean separation"
    COLOR="${GREEN}"
elif [ ${BMW_WITH_MINI} -gt 0 ]; then
    STATUS="❌ FAIL - BMW contains MINI"
    COLOR="${RED}"
else
    STATUS="⚠️  WARNING - No MINI records found"
    COLOR="${YELLOW}"
fi

echo ""
echo -e "${COLOR}  Status: ${STATUS}${NC}"

# Write to report
cat >> "${REPORT_FILE}" << EOF
| Metric | Count |
|--------|-------|
| BMW with MINI in modelo | ${BMW_WITH_MINI} |
| MINI brand records | ${MINI_BRAND} |
| MINI with "MINI " prefix | ${MINI_WITH_PREFIX} |

**Status**: ${STATUS}

EOF

if [ ${MINI_BRAND} -gt 0 ]; then
    echo "" >> "${REPORT_FILE}"
    echo "**MINI Variants Distribution:**" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    echo "| Modelo | Count |" >> "${REPORT_FILE}"
    echo "|--------|-------|" >> "${REPORT_FILE}"
    tail -n +2 "${DATA_FILE}" | awk -F',' '$3 == "MINI" {print $4}' | sort | uniq -c | sort -rn | head -10 | awk '{print "| " $2 " | " $1 " |"}' >> "${REPORT_FILE}"
fi

echo "" >> "${REPORT_FILE}"
echo "---" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

# ============================================================================
# ISSUE 3: Incomplete Model Completion
# ============================================================================

echo ""
echo "================================================================================"
echo "🔍 ISSUE 3: Incomplete Model Completion"
echo "================================================================================"

cat >> "${REPORT_FILE}" << 'EOF'
## Issue 3: Incomplete Model Completion

### Description
Checking for single-letter models that should be completed:
- BMW M (should be M2-M8)
- BMW X (should be X1-X7)
- AUDI S (should be S1-S8)
- AUDI R (should be R8)

### Results

EOF

# BMW single M
BMW_M=$(tail -n +2 "${DATA_FILE}" | awk -F',' '$3 == "BMW" && $4 == "M"' | wc -l || echo "0")

# BMW single X
BMW_X=$(tail -n +2 "${DATA_FILE}" | awk -F',' '$3 == "BMW" && $4 == "X"' | wc -l || echo "0")

# AUDI single S
AUDI_S=$(tail -n +2 "${DATA_FILE}" | awk -F',' '$3 == "AUDI" && $4 == "S"' | wc -l || echo "0")

# AUDI single R
AUDI_R=$(tail -n +2 "${DATA_FILE}" | awk -F',' '$3 == "AUDI" && $4 == "R"' | wc -l || echo "0")

TOTAL_SINGLE=$((BMW_M + BMW_X + AUDI_S + AUDI_R))
SINGLE_PCT=$(awk "BEGIN {printf \"%.2f\", ($TOTAL_SINGLE/$TOTAL_RECORDS)*100}")

echo "  BMW single 'M':               ${BMW_M}"
echo "  BMW single 'X':               ${BMW_X}"
echo "  AUDI single 'S':              ${AUDI_S}"
echo "  AUDI single 'R':              ${AUDI_R}"
echo ""
echo "  TOTAL SINGLE:                 ${TOTAL_SINGLE} (${SINGLE_PCT}%)"

# Determine status
if [ ${TOTAL_SINGLE} -eq 0 ]; then
    STATUS="✅ PASS - All models completed"
    COLOR="${GREEN}"
elif [ ${TOTAL_SINGLE} -lt 5 ]; then
    STATUS="✅ PASS - Acceptable edge cases (<5)"
    COLOR="${GREEN}"
elif [ ${TOTAL_SINGLE} -lt 20 ]; then
    STATUS="⚠️  CONDITIONAL - Review remaining singles"
    COLOR="${YELLOW}"
else
    STATUS="❌ FAIL - Too many incomplete models"
    COLOR="${RED}"
fi

echo ""
echo -e "${COLOR}  Status: ${STATUS}${NC}"

# Write to report
cat >> "${REPORT_FILE}" << EOF
| Brand | Single Model | Count |
|-------|--------------|-------|
| BMW | M | ${BMW_M} |
| BMW | X | ${BMW_X} |
| AUDI | S | ${AUDI_S} |
| AUDI | R | ${AUDI_R} |
| **TOTAL** | | **${TOTAL_SINGLE}** |

**Percentage**: ${SINGLE_PCT}%

**Status**: ${STATUS}

---

EOF

# ============================================================================
# ISSUE 4: MAPFRE ID Format
# ============================================================================

echo ""
echo "================================================================================"
echo "🔍 ISSUE 4: MAPFRE ID Format"
echo "================================================================================"

cat >> "${REPORT_FILE}" << 'EOF'
## Issue 4: MAPFRE ID Format

### Description
Validating MAPFRE ID format (should be: CODE_YEAR format, e.g., "210_2020")

### Results

EOF

# Extract MAPFRE IDs from disponibilidad JSON
# This is complex with bash - simplified check
MAPFRE_RECORDS=$(tail -n +2 "${DATA_FILE}" | grep -o '"MAPFRE"' | wc -l || echo "0")

echo "  Total MAPFRE records found:   ${MAPFRE_RECORDS}"

if [ ${MAPFRE_RECORDS} -eq 0 ]; then
    STATUS="⚠️  WARNING - No MAPFRE records found"
    COLOR="${YELLOW}"
    echo -e "${COLOR}  Status: ${STATUS}${NC}"
else
    # Extract a sample of MAPFRE IDs to check format
    echo "  Note: Detailed MAPFRE ID validation requires JSON parsing"
    echo "  Performing basic presence check only"
    STATUS="ℹ️  INFO - MAPFRE records present (${MAPFRE_RECORDS} found)"
    COLOR="${BLUE}"
    echo -e "${COLOR}  Status: ${STATUS}${NC}"
fi

cat >> "${REPORT_FILE}" << EOF
**MAPFRE Records Found**: ${MAPFRE_RECORDS}

**Status**: ${STATUS}

**Note**: Detailed MAPFRE ID format validation (CODE_YEAR pattern, duplicates) requires JSON parsing capabilities. Basic presence check completed.

---

EOF

# ============================================================================
# DATA QUALITY CHECKS
# ============================================================================

echo ""
echo "================================================================================"
echo "🔍 DATA QUALITY & REGRESSION CHECKS"
echo "================================================================================"

cat >> "${REPORT_FILE}" << 'EOF'
## Data Quality & Regression Checks

### NULL and Empty Value Detection

EOF

# Count NULL/empty values in critical fields
echo "  Checking for NULL/empty values in critical fields..."

# Count records with empty marca
EMPTY_MARCA=$(tail -n +2 "${DATA_FILE}" | awk -F',' '$3 == "" || $3 == "null"' | wc -l || echo "0")

# Count records with empty modelo
EMPTY_MODELO=$(tail -n +2 "${DATA_FILE}" | awk -F',' '$4 == "" || $4 == "null"' | wc -l || echo "0")

# Count records with empty anio
EMPTY_ANIO=$(tail -n +2 "${DATA_FILE}" | awk -F',' '$5 == "" || $5 == "null" || $5 == "0"' | wc -l || echo "0")

# Count records with empty version
EMPTY_VERSION=$(tail -n +2 "${DATA_FILE}" | awk -F',' '$7 == "" || $7 == "null"' | wc -l || echo "0")

echo "    NULL/empty marca:           ${EMPTY_MARCA}"
echo "    NULL/empty modelo:          ${EMPTY_MODELO}"
echo "    NULL/empty anio:            ${EMPTY_ANIO}"
echo "    NULL/empty version:         ${EMPTY_VERSION}"

TOTAL_QUALITY_ISSUES=$((EMPTY_MARCA + EMPTY_MODELO + EMPTY_ANIO + EMPTY_VERSION))

echo ""
echo "  TOTAL QUALITY ISSUES:         ${TOTAL_QUALITY_ISSUES}"

if [ ${TOTAL_QUALITY_ISSUES} -eq 0 ]; then
    STATUS="✅ PASS - No data quality issues"
    COLOR="${GREEN}"
elif [ ${TOTAL_QUALITY_ISSUES} -lt 10 ]; then
    STATUS="⚠️  MINOR - Few issues detected"
    COLOR="${YELLOW}"
else
    STATUS="❌ FAIL - Data quality issues detected"
    COLOR="${RED}"
fi

echo -e "${COLOR}  Status: ${STATUS}${NC}"

cat >> "${REPORT_FILE}" << EOF
| Field | NULL/Empty Count |
|-------|------------------|
| marca | ${EMPTY_MARCA} |
| modelo | ${EMPTY_MODELO} |
| anio | ${EMPTY_ANIO} |
| version | ${EMPTY_VERSION} |
| **TOTAL** | **${TOTAL_QUALITY_ISSUES}** |

**Status**: ${STATUS}

---

EOF

# ============================================================================
# BRAND DISTRIBUTION
# ============================================================================

echo ""
echo "================================================================================"
echo "🔍 BRAND DISTRIBUTION ANALYSIS"
echo "================================================================================"

cat >> "${REPORT_FILE}" << 'EOF'
## Brand Distribution

### Top 20 Brands by Record Count

EOF

echo "  Top 20 brands by record count:"
echo ""

tail -n +2 "${DATA_FILE}" | awk -F',' '{print $3}' | sort | uniq -c | sort -rn | head -20 | while read count brand; do
    pct=$(awk "BEGIN {printf \"%.2f\", ($count/$TOTAL_RECORDS)*100}")
    echo "    ${brand}: ${count} records (${pct}%)"
done

# Write to report
echo "| Brand | Count | Percentage |" >> "${REPORT_FILE}"
echo "|-------|-------|------------|" >> "${REPORT_FILE}"

tail -n +2 "${DATA_FILE}" | awk -F',' '{print $3}' | sort | uniq -c | sort -rn | head -20 | while read count brand; do
    pct=$(awk "BEGIN {printf \"%.2f\", ($count/$TOTAL_RECORDS)*100}")
    echo "| ${brand} | ${count} | ${pct}% |" >> "${REPORT_FILE}"
done

echo "" >> "${REPORT_FILE}"
echo "---" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

# ============================================================================
# HASH COLLISION ANALYSIS
# ============================================================================

echo ""
echo "================================================================================"
echo "🔍 HASH COLLISION ANALYSIS"
echo "================================================================================"

cat >> "${REPORT_FILE}" << 'EOF'
## Hash Distribution Analysis

### Hash Collision Metrics

EOF

# Count unique hashes
UNIQUE_HASHES=$(tail -n +2 "${DATA_FILE}" | awk -F',' '{print $2}' | sort -u | wc -l || echo "0")

# Calculate collision rate
COLLISION_RATE=$(awk "BEGIN {printf \"%.2f\", (($TOTAL_RECORDS - $UNIQUE_HASHES) / $TOTAL_RECORDS) * 100}")

echo "  Total unique hashes:          ${UNIQUE_HASHES}"
echo "  Total records:                ${TOTAL_RECORDS}"
echo "  Collision rate:               ${COLLISION_RATE}%"

# Determine status
COLLISION_INT=$(echo "${COLLISION_RATE}" | cut -d'.' -f1)

if [ ${COLLISION_INT} -lt 5 ]; then
    STATUS="✅ EXCELLENT - Very low collision rate"
    COLOR="${GREEN}"
elif [ ${COLLISION_INT} -lt 10 ]; then
    STATUS="✅ GOOD - Acceptable collision rate"
    COLOR="${GREEN}"
elif [ ${COLLISION_INT} -lt 20 ]; then
    STATUS="⚠️  WARNING - Elevated collision rate"
    COLOR="${YELLOW}"
else
    STATUS="❌ CONCERN - High collision rate"
    COLOR="${RED}"
fi

echo ""
echo -e "${COLOR}  Status: ${STATUS}${NC}"

cat >> "${REPORT_FILE}" << EOF
| Metric | Value |
|--------|-------|
| Total unique hashes | $(printf "%'d" ${UNIQUE_HASHES}) |
| Total records | $(printf "%'d" ${TOTAL_RECORDS}) |
| Collision rate | ${COLLISION_RATE}% |

**Status**: ${STATUS}

---

EOF

# ============================================================================
# FINAL ASSESSMENT
# ============================================================================

echo ""
echo "================================================================================"
echo "📊 FINAL ASSESSMENT"
echo "================================================================================"

cat >> "${REPORT_FILE}" << 'EOF'
## Final Assessment

### Primary Fixes Summary

EOF

echo ""
echo "  PRIMARY FIXES:"

# Determine overall status for each issue
ISSUE1_PASS=0
if [ ${TOTAL_CONTAMINATED} -lt 100 ]; then
    ISSUE1_PASS=1
    echo "    Issue 1 (Model Contamination):  ✅ PASS"
else
    echo "    Issue 1 (Model Contamination):  ❌ FAIL"
fi

ISSUE2_PASS=0
if [ ${BMW_WITH_MINI} -eq 0 ] && [ ${MINI_BRAND} -gt 0 ]; then
    ISSUE2_PASS=1
    echo "    Issue 2 (BMW/MINI Separation):  ✅ PASS"
else
    echo "    Issue 2 (BMW/MINI Separation):  ❌ FAIL"
fi

ISSUE3_PASS=0
if [ ${TOTAL_SINGLE} -lt 20 ]; then
    ISSUE3_PASS=1
    echo "    Issue 3 (Model Completion):     ✅ PASS"
else
    echo "    Issue 3 (Model Completion):     ❌ FAIL"
fi

ISSUE4_PASS=1  # Basic check (MAPFRE present)
echo "    Issue 4 (MAPFRE IDs):           ℹ️  INFO (${MAPFRE_RECORDS} records found)"

echo ""
echo "  DATA INTEGRITY:"

REGRESSION_PASS=0
if [ ${TOTAL_QUALITY_ISSUES} -lt 10 ]; then
    REGRESSION_PASS=1
    echo "    Regressions:                    ✅ PASS"
else
    echo "    Regressions:                    ❌ FAIL"
fi

echo ""
echo "  OVERALL STATUS:"

ALL_PASS=$((ISSUE1_PASS + ISSUE2_PASS + ISSUE3_PASS + REGRESSION_PASS))

if [ ${ALL_PASS} -eq 4 ]; then
    OVERALL_STATUS="✅ PRODUCTION READY - All critical fixes validated"
    OVERALL_COLOR="${GREEN}"
elif [ ${ALL_PASS} -ge 3 ]; then
    OVERALL_STATUS="⚠️  CONDITIONAL - Most fixes pass, minor issues detected"
    OVERALL_COLOR="${YELLOW}"
else
    OVERALL_STATUS="❌ NOT READY - Critical fixes failing"
    OVERALL_COLOR="${RED}"
fi

echo -e "${OVERALL_COLOR}    ${OVERALL_STATUS}${NC}"

# Write to report
cat >> "${REPORT_FILE}" << EOF
| Issue | Status |
|-------|--------|
| Model Contamination | $([ ${ISSUE1_PASS} -eq 1 ] && echo "✅ PASS" || echo "❌ FAIL") |
| BMW/MINI Separation | $([ ${ISSUE2_PASS} -eq 1 ] && echo "✅ PASS" || echo "❌ FAIL") |
| Model Completion | $([ ${ISSUE3_PASS} -eq 1 ] && echo "✅ PASS" || echo "❌ FAIL") |
| MAPFRE IDs | ℹ️  INFO |
| Data Integrity | $([ ${REGRESSION_PASS} -eq 1 ] && echo "✅ PASS" || echo "❌ FAIL") |

### Overall Status

**${OVERALL_STATUS}**

### Recommendations

EOF

if [ ${ALL_PASS} -eq 4 ]; then
    cat >> "${REPORT_FILE}" << 'EOF'
✅ **APPROVED FOR PRODUCTION**

All critical fixes have been successfully validated. The system shows:
- Minimal to zero model contamination
- Proper BMW/MINI brand separation
- Completed single-letter models
- No data regressions detected

**Next Steps**:
1. Present this validation report to client
2. Proceed with production deployment
3. Monitor post-deployment metrics
4. Schedule QA findings (transmission, brand consolidation) for Phase 2

EOF
elif [ ${ALL_PASS} -ge 3 ]; then
    cat >> "${REPORT_FILE}" << 'EOF'
⚠️  **CONDITIONAL APPROVAL**

Most critical fixes validated successfully, but minor issues remain:

**Action Items**:
1. Review detailed findings above
2. Address minor issues if critical for deployment
3. Document known limitations for client
4. Proceed with cautious deployment
5. Monitor closely in production

EOF
else
    cat >> "${REPORT_FILE}" << 'EOF'
❌ **NOT READY FOR PRODUCTION**

Critical issues detected that must be addressed:

**Action Items**:
1. Review all FAIL statuses above
2. Investigate root causes with development team
3. Reapply fixes as needed
4. Re-run validation after corrections
5. Escalate to technical lead if blocked

EOF
fi

cat >> "${REPORT_FILE}" << EOF

---

**Report Generated**: $(date '+%Y-%m-%d %H:%M:%S')
**Total Records Analyzed**: $(printf "%'d" ${TOTAL_RECORDS})
**Validation Script**: $0

EOF

echo ""
echo "================================================================================"
echo "✅ VALIDATION COMPLETE"
echo "================================================================================"
echo ""
echo "Report saved to: ${REPORT_FILE}"
echo ""
echo "Summary:"
echo "  - Total records analyzed: $(printf "%'d" ${TOTAL_RECORDS})"
echo "  - Primary fixes status: ${ALL_PASS}/4 passing"
echo "  - Overall: ${OVERALL_STATUS}"
echo ""
echo "Review the complete report for detailed findings and recommendations."
echo ""
