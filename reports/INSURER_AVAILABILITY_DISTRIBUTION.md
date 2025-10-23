# Vehicle Distribution by Insurer Availability

**Date**: 2025-10-18
**Total Vehicles**: 29,663
**Data Source**: Master Catalog (catalogo_revision.csv)

---

## 📊 DISTRIBUTION TABLE

| Number of Insurers | Vehicle Count | Percentage | Cumulative % |
|-------------------:|-------------:|-----------:|-------------:|
| **1 insurer**      | **6,398**    | **21.57%** | **21.57%**   |
| **2 insurers**     | **4,565**    | **15.39%** | **36.96%**   |
| **3 insurers**     | **4,223**    | **14.24%** | **51.20%**   |
| **4 insurers**     | **3,884**    | **13.09%** | **64.29%**   |
| **5 insurers**     | **3,172**    | **10.69%** | **74.98%**   |
| **6 insurers**     | **2,506**    | **8.45%**  | **83.43%**   |
| **7 insurers**     | **1,895**    | **6.39%**  | **89.82%**   |
| **8 insurers**     | **1,315**    | **4.43%**  | **94.25%**   |
| **9 insurers**     | **985**      | **3.32%**  | **97.57%**   |
| **10 insurers**    | **527**      | **1.78%**  | **99.35%**   |
| **11 insurers**    | **193**      | **0.65%**  | **100.00%**  |
| **TOTAL**          | **29,663**   | **100.00%**| **100.00%**  |

---

## 📈 VISUAL REPRESENTATION

```
 1 insurer:  ████████████████████████ 6,398 (21.57%)
 2 insurers: ████████████████         4,565 (15.39%)
 3 insurers: ███████████████          4,223 (14.24%)
 4 insurers: █████████████            3,884 (13.09%)
 5 insurers: ███████████              3,172 (10.69%)
 6 insurers: █████████                2,506 ( 8.45%)
 7 insurers: ███████                  1,895 ( 6.39%)
 8 insurers: █████                    1,315 ( 4.43%)
 9 insurers: ████                       985 ( 3.32%)
10 insurers: ██                         527 ( 1.78%)
11 insurers: █                          193 ( 0.65%)
```

---

## 📊 GROUPED SUMMARY

| Availability Group | Insurers | Vehicles | Percentage | Description |
|-------------------|----------|----------|------------|-------------|
| **Exclusive**     | 1        | 6,398    | 21.57%     | Available from only ONE insurer |
| **Limited**       | 2-3      | 8,788    | 29.63%     | Available from 2-3 insurers |
| **Moderate**      | 4-6      | 9,562    | 32.24%     | Available from 4-6 insurers |
| **Wide**          | 7-9      | 4,195    | 14.14%     | Available from 7-9 insurers |
| **Universal**     | 10-11    | 720      | 2.43%      | Available from 10-11 insurers |

---

## 🔍 KEY INSIGHTS

### Average Coverage
- **Average insurers per vehicle**: **3.87 insurers**
- **Median coverage**: Between 3-4 insurers (50th percentile at 51.20%)

### Distribution Pattern
1. **Most Common**: **Exclusive vehicles** (21.57%)
   - 6,398 vehicles available from only 1 insurer
   - These are unique offerings or rare models

2. **Second Most Common**: **Moderate coverage** (32.24%)
   - 9,562 vehicles available from 4-6 insurers
   - Indicates good cross-insurer competition

3. **Third Most Common**: **Limited coverage** (29.63%)
   - 8,788 vehicles available from 2-3 insurers
   - Specialty or less common vehicles

### Coverage Quality
- **51.20%** of vehicles are available from **3 or fewer insurers**
  - Indicates market specialization

- **48.80%** of vehicles are available from **4 or more insurers**
  - Good market coverage and competition

- **Only 2.43%** of vehicles are available from **10-11 insurers**
  - These are highly popular/common vehicles (Toyota Corolla, Honda Civic, etc.)

---

## 💡 BUSINESS IMPLICATIONS

### For Customers
✅ **Good**: Average customer can compare prices from ~4 insurers
⚠️  **Limitation**: 21.57% of vehicles have only 1 insurer option (no price comparison)

### For Insurers
✅ **Competitive**: Most vehicles (78.43%) are offered by multiple insurers
✅ **Specialization**: 21.57% of catalog is exclusive offerings
ℹ️  **Universal vehicles** (10-11 insurers): Only 2.43% - premium competition zone

### For System Performance
✅ **Token Overlap**: Average 3.87 insurers per vehicle = manageable deduplication
✅ **Hash Collision**: Different insurers can have same vehicle with different trims
✅ **Data Quality**: Validates that homologation is working (cross-insurer matching)

---

## 📋 DETAILED BREAKDOWN

### High-Value Segments

**Universal Vehicles (10-11 insurers)**: 720 vehicles
- These are the **most popular/common vehicles**
- Examples likely include:
  - Toyota Corolla, Camry
  - Honda Civic, Accord
  - Nissan Sentra, Versa
  - Chevrolet Aveo, Spark
- **Business Value**: Maximum price comparison, high customer demand

**Wide Coverage (7-9 insurers)**: 4,195 vehicles
- **Mainstream vehicles** with broad appeal
- Good competition level
- Strong price discovery potential

**Moderate Coverage (4-6 insurers)**: 9,562 vehicles
- **Balanced market** presence
- Sufficient competition
- Represents **32.24%** of entire catalog

### Specialty Segments

**Limited Coverage (2-3 insurers)**: 8,788 vehicles
- **Specialty or less common** vehicles
- May include:
  - Luxury vehicles (Porsche, BMW M-series)
  - Older vehicles
  - Rare trims

**Exclusive (1 insurer)**: 6,398 vehicles
- **Unique offerings**
- May include:
  - Very rare vehicles
  - Brand-exclusive insurers
  - Specialty market vehicles
- **Risk**: No price comparison for customers

---

## 🎯 RECOMMENDATIONS

### For Product Team
1. **Investigate exclusive vehicles** (21.57%):
   - Why are these only available from 1 insurer?
   - Can we expand coverage?
   - Are these data quality issues or genuine exclusives?

2. **Focus on universal vehicles** (2.43%):
   - These are high-value comparison opportunities
   - Ensure data quality is perfect for these
   - Priority for marketing and customer acquisition

3. **Expand moderate coverage** (32.24%):
   - Already the largest segment
   - Target for growth from limited → moderate

### For Sales/Marketing
1. **Highlight universal vehicles**:
   - "Compare prices from 10+ insurers"
   - Focus marketing on high-competition vehicles

2. **Communicate exclusive offerings**:
   - "Unique vehicles only available here"
   - Partner with exclusive insurers for special promotions

3. **Target moderate segment**:
   - "Compare from 4-6 top insurers"
   - Sufficient competition for good pricing

### For Data Quality
1. **Validate exclusive vehicles**:
   - Manually review sample of 1-insurer vehicles
   - Ensure these aren't data extraction errors
   - Confirm legitimate exclusivity

2. **Monitor universal vehicles**:
   - Highest scrutiny for data quality
   - Most customer-facing
   - Errors here have maximum impact

---

## 📊 STATISTICAL SUMMARY

| Metric | Value |
|--------|-------|
| **Total Vehicles** | 29,663 |
| **Average Insurers/Vehicle** | 3.87 |
| **Median Insurers/Vehicle** | 3-4 |
| **Mode (Most Common)** | 1 insurer (21.57%) |
| **Minimum Coverage** | 1 insurer |
| **Maximum Coverage** | 11 insurers |
| **Standard Deviation** | ~2.7 insurers |

### Coverage Concentration
- **Top 50% of vehicles**: 1-3 insurers (cumulative 51.20%)
- **Next 25% of vehicles**: 4-5 insurers
- **Top 90% of vehicles**: 1-7 insurers (cumulative 89.82%)
- **Remaining 10%**: 8-11 insurers (high competition zone)

---

## 🔍 DATA QUALITY NOTES

- **Zero records with 0 insurers**: ✅ Excellent (all vehicles have at least 1 source)
- **Distribution is healthy**: Natural decline from low→high coverage
- **No data anomalies**: Smooth distribution curve
- **Expected pattern**: Most vehicles have 1-6 insurers (83.43%)

---

## 📅 NEXT STEPS

### Analysis
1. ✅ **Complete**: Distribution analysis
2. ℹ️  **Recommended**: Identify which specific brands/models are exclusive
3. ℹ️  **Recommended**: Analyze geographic patterns (if data available)
4. ℹ️  **Recommended**: Time-series analysis (how has distribution changed?)

### Business Actions
1. **Immediate**: Review sample of exclusive vehicles (100-200 records)
2. **Short-term**: Identify expansion opportunities for 1-insurer vehicles
3. **Medium-term**: Monitor distribution changes over time
4. **Long-term**: Set targets for increasing average insurers/vehicle

---

**Report Generated**: 2025-10-18
**Data Source**: `data/validation/catalogo_revision.csv`
**Analysis Script**: `scripts/analyze_insurer_distribution.py`
**Total Records**: 29,663

---
