# ETL Validation Comprehensive Report

**Generated**: $(date '+%Y-%m-%d %H:%M:%S')
**Data Source**: Master Catalog

---


## Summary Statistics

- **Total Records**: 29662
- **Analysis Date**: 2025-10-18 18:30:06

---

## Issue 1: Model Field Contamination

### Description
Checking for unwanted patterns in the `modelo` field:
- SERIE prefixes (e.g., "SERIE 3" should be "3")
- SDRIVE/XDRIVE suffixes
- Trailing I/IA codes
- TUR/TURBO suffixes
- MINI prefixes

### Results

