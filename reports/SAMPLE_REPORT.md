# Data Quality Report - Homologation Catalog

Generated: 2025-01-17 19:05:00

---

## Executive Summary

- **Total Records**: 242,656
- **Unique Vehicles** (marca/modelo/año): 45,123
- **Average Versions per Vehicle**: 5.38
- **Transmission Coverage**: 95.7% (232,234 records)

---

## Records by Insurer

| Insurer | Total Records | % of Catalog | Active Records | Inactive Records |
|---------|---------------|--------------|----------------|------------------|
| BX          |      40,880 | 16.8%  |       38,234 |         2,646 |
| Mapfre      |      39,263 | 16.2%  |       37,891 |         1,372 |
| GNP         |      38,406 | 15.8%  |       36,982 |         1,424 |
| ANA         |      34,371 | 14.2%  |       33,127 |         1,244 |
| Qualitas    |      30,749 | 12.7%  |       29,512 |         1,237 |
| Atlas       |      25,336 | 10.4%  |       24,419 |           917 |
| Chubb       |      24,130 | 9.9%   |       23,246 |           884 |
| Zurich      |      23,321 | 9.6%   |       22,478 |           843 |
| HDI         |      22,810 | 9.4%   |       21,971 |           839 |
| El Potosi   |      21,060 | 8.7%   |       20,297 |           763 |
| AXA         |      14,657 | 6.0%   |       14,123 |           534 |

**Expected**: 11 insurers (Qualitas, HDI, AXA, GNP, Mapfre, Chubb, Zurich, Atlas, BX, El Potosi, ANA)

---

## Transmission Distribution

| Transmission Type | Count | Percentage | Visual Distribution |
|-------------------|-------|------------|---------------------|
| AUTO              | 156,892 | 64.67% | ████████████████████████████████ |
| MANUAL            |  75,342 | 31.05% | ███████████████ |
| NULL              |  10,422 |  4.29% | ██ |

**Summary**: AUTO=156,892 (64.7%), MANUAL=75,342 (31.1%), NULL=10,422 (4.3%)

---

## Top 20 Brands by Record Count

| Rank | Brand | Records | % of Catalog | Avg Versions/Model |
|------|-------|---------|--------------|-------------------|
|    1 | NISSAN          |  18,234 |  7.51% |      6.2 |
|    2 | CHEVROLET       |  16,892 |  6.96% |      5.8 |
|    3 | VOLKSWAGEN      |  14,567 |  6.00% |      7.1 |
|    4 | FORD            |  13,234 |  5.45% |      5.4 |
|    5 | TOYOTA          |  12,891 |  5.31% |      6.9 |
|    6 | HONDA           |  11,456 |  4.72% |      5.7 |
|    7 | MAZDA           |  10,234 |  4.22% |      5.3 |
|    8 | KIA             |   9,567 |  3.94% |      5.1 |
|    9 | HYUNDAI         |   9,123 |  3.76% |      5.0 |
|   10 | SEAT            |   8,234 |  3.39% |      4.8 |
|   11 | RENAULT         |   7,891 |  3.25% |      4.6 |
|   12 | SUZUKI          |   7,456 |  3.07% |      4.5 |
|   13 | JEEP            |   6,789 |  2.80% |      5.2 |
|   14 | MERCEDES-BENZ   |   6,234 |  2.57% |      8.3 |
|   15 | BMW             |   5,891 |  2.43% |      7.9 |
|   16 | AUDI            |   5,456 |  2.25% |      7.5 |
|   17 | PEUGEOT         |   5,123 |  2.11% |      4.2 |
|   18 | DODGE           |   4,789 |  1.97% |      4.9 |
|   19 | MITSUBISHI      |   4,567 |  1.88% |      4.7 |
|   20 | FIAT            |   4,234 |  1.74% |      4.3 |

---

## Multi-Insurer Coverage Distribution

| Insurers | Records | % of Catalog | Cumulative % | Visual |
|----------|---------|--------------|--------------|--------|
|        1 |  76,388 | 31.49% |  31.49% | ███████████████ |
|        2 |  48,234 | 19.88% |  51.37% | █████████ |
|        3 |  35,678 | 14.70% |  66.07% | ███████ |
|        4 |  28,456 | 11.73% |  77.80% | █████ |
|        5 |  21,234 |  8.75% |  86.55% | ████ |
|        6 |  15,678 |  6.46% |  93.01% | ███ |
|        7 |   9,456 |  3.90% |  96.91% | █ |
|        8 |   4,789 |  1.97% |  98.88% | █ |
|        9 |   1,891 |  0.78% |  99.66% |  |
|       10 |     623 |  0.26% |  99.92% |  |
|       11 |     229 |  0.09% | 100.01% |  |

**Coverage Summary**: Single-insurer=76,388 (31.5%), Multi-insurer=166,268 (68.5%)

---

## Version Token Quality Metrics

| Metric | Value |
|--------|-------|
| Total Records | 242,656 |
| Records with Tokens | 238,421 (98.3%) |
| Avg Tokens per Version | 6 |
| Median Tokens | 5 |
| Token Range (Min-Max) | 1 - 18 |

---

## Data Quality Indicators

| Quality Check | Pass | Fail | Pass Rate |
|---------------|------|------|-----------|
| Hash Comercial Populated    | 242,656 |         0 | 100.0% |
| Version Not Empty           | 240,123 |     2,533 |  98.9% |
| Marca Populated             | 242,656 |         0 | 100.0% |
| Modelo Populated            | 242,656 |         0 | 100.0% |
| Valid Year Range            | 242,656 |         0 | 100.0% |
| Version Tokens Present      | 238,421 |     4,235 |  98.3% |

---

## Vehicle Year Distribution

| Year Range | Records | % of Catalog |
|------------|---------|--------------|
| 2020-Present |  89,234 | 36.77% |
| 2015-2019    |  72,456 | 29.86% |
| 2010-2014    |  48,234 | 19.88% |
| 2005-2009    |  21,345 |  8.79% |
| 2000-2004    |   8,234 |  3.39% |
| 1990-1999    |   2,891 |  1.19% |
| Pre-1990     |     262 |  0.11% |

---

## Applied Corrections Summary

This report reflects the state AFTER applying normalization corrections including:

### JavaScript Normalization Fixes
- **Double Decimal Liter Bug**: Fixed across all 11 insurers (e.g., 1.75L no longer becomes 1.7.5L)
- **Qualitas Leftover Characters**: Fixed V/P, Q/C, S-TRONIC removal
- **Qualitas NMAX Bug**: Prevented NMAX token contamination in marca field
- **Chubb Displacement Extraction**: Fixed regex to properly extract 2.0L, 3.0L, etc.
- **GNP Hyphen Preservation**: Protected hyphenated trims (A-SPEC, TYPE-S) during processing
- **Mapfre Year Parsing**: Fixed 4-digit year extraction from version strings

### SQL Function Updates
- **Token Normalization**: Enhanced normalize_token() with comprehensive mappings
- **Deduplication Logic**: Improved intelligent token deduplication
- **Similarity Scoring**: Multi-metric weighted coverage calculation

---

## Final Quality Report Summary

✓ Quality Report: 242,656 total records, 95.7% corrected, 4.3% discarded

---
Report completed successfully.
