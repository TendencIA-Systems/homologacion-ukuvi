-- ============================================================
-- SYSTEM MONITORING QUERIES
-- Vehicle Homologation System - Post-Deployment
-- ============================================================
-- Purpose: Daily, weekly, and monthly health checks
-- Usage: Run these queries after deployment (Task 111)
-- Documentation: See POST_DEPLOYMENT_VALIDATION_REPORT.md
-- ============================================================

-- ============================================================
-- SECTION 1: DAILY HEALTH CHECKS
-- ============================================================
-- Run these queries every day to monitor system health
-- Set up alerts if any metric falls below expected thresholds

-- 1.1 Record Count Trends
-- Expected: Total records stable or increasing
-- Alert if: Total drops >10% in 24 hours
SELECT
  CURRENT_DATE AS check_date,
  COUNT(*) AS total_records,
  COUNT(DISTINCT hash_comercial) AS unique_vehicles,
  ROUND(100.0 * SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) / COUNT(*), 2) AS transmission_coverage_pct,
  ROUND(100.0 * COUNT(version_tokens_array) / COUNT(*), 2) AS token_coverage_pct
FROM catalogo_homologado;

-- Expected Output:
-- total_records: ~242,656 (± 5%)
-- transmission_coverage_pct: >95%
-- token_coverage_pct: >98%

-- 1.2 Insurer Coverage Health
-- Expected: All 11 insurers active
-- Alert if: Any insurer last_updated >3 days ago
SELECT
  insurer,
  COUNT(*) AS record_count,
  COUNT(*) FILTER (WHERE (disponibilidad->>insurer)::jsonb->>'activo' = 'true') AS active_records,
  MAX((disponibilidad->>insurer)::jsonb->>'last_updated') AS last_updated,
  CURRENT_DATE - MAX((disponibilidad->>insurer)::jsonb->>'last_updated')::date AS days_since_update
FROM catalogo_homologado,
  LATERAL jsonb_object_keys(disponibilidad) AS insurer
GROUP BY insurer
ORDER BY days_since_update DESC;

-- Expected Output: 11 rows (one per insurer)
-- Alert if: days_since_update >3 for any insurer

-- 1.3 Data Quality Scorecard
-- Expected: All metrics PASS
-- Alert if: Any status = 'FAIL'
SELECT
  'Transmission Coverage' AS metric,
  ROUND(100.0 * SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) / COUNT(*), 2) || '%' AS value,
  CASE WHEN ROUND(100.0 * SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) / COUNT(*), 2) >= 95 THEN 'PASS' ELSE 'FAIL' END AS status
FROM catalogo_homologado

UNION ALL

SELECT
  'Hash Comercial Coverage',
  ROUND(100.0 * COUNT(hash_comercial) / COUNT(*), 2) || '%',
  CASE WHEN COUNT(hash_comercial) = COUNT(*) THEN 'PASS' ELSE 'FAIL' END
FROM catalogo_homologado

UNION ALL

SELECT
  'Version Token Coverage',
  ROUND(100.0 * COUNT(version_tokens_array) / COUNT(*), 2) || '%',
  CASE WHEN ROUND(100.0 * COUNT(version_tokens_array) / COUNT(*), 2) >= 98 THEN 'PASS' ELSE 'FAIL' END
FROM catalogo_homologado

UNION ALL

SELECT
  'Marca Populated',
  ROUND(100.0 * COUNT(marca) / COUNT(*), 2) || '%',
  CASE WHEN COUNT(marca) = COUNT(*) THEN 'PASS' ELSE 'FAIL' END
FROM catalogo_homologado

UNION ALL

SELECT
  'Modelo Populated',
  ROUND(100.0 * COUNT(modelo) / COUNT(*), 2) || '%',
  CASE WHEN COUNT(modelo) = COUNT(*) THEN 'PASS' ELSE 'FAIL' END
FROM catalogo_homologado;

-- Expected: All status = 'PASS'

-- ============================================================
-- SECTION 2: WEEKLY ANALYSIS QUERIES
-- ============================================================
-- Run these queries weekly to track trends and identify issues

-- 2.1 New Vehicles Added (Last 7 Days)
-- Expected: Steady flow of new vehicles from insurer updates
-- Alert if: No new vehicles added in 7 days
SELECT
  marca,
  modelo,
  COUNT(*) AS new_versions,
  STRING_AGG(DISTINCT jsonb_object_keys(disponibilidad), ', ') AS insurers
FROM catalogo_homologado
WHERE fecha_creacion >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY marca, modelo
ORDER BY new_versions DESC
LIMIT 20;

-- Expected: 10-50 new vehicles per week depending on insurer update cycles

-- 2.2 Multi-Insurer Match Quality
-- Expected: Similar token counts across insurer groups
-- Alert if: Low-token records have high insurer counts (suggests poor matching)
SELECT
  jsonb_array_length(jsonb_object_keys(disponibilidad)) AS insurer_count,
  AVG(array_length(version_tokens_array, 1)) AS avg_token_count,
  MIN(array_length(version_tokens_array, 1)) AS min_tokens,
  MAX(array_length(version_tokens_array, 1)) AS max_tokens,
  COUNT(*) AS vehicle_count
FROM catalogo_homologado
WHERE fecha_actualizacion >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY insurer_count
ORDER BY insurer_count;

-- Expected: avg_token_count ≥5 for all groups

-- 2.3 Brand Distribution Changes
-- Expected: Top brands remain stable
-- Alert if: Unknown brands appear in top 20
SELECT
  marca,
  COUNT(*) AS current_count,
  COUNT(*) FILTER (WHERE fecha_creacion >= CURRENT_DATE - INTERVAL '7 days') AS new_this_week,
  ROUND(100.0 * COUNT(*) FILTER (WHERE fecha_creacion >= CURRENT_DATE - INTERVAL '7 days') / COUNT(*), 2) AS growth_pct,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS market_share_pct
FROM catalogo_homologado
GROUP BY marca
ORDER BY current_count DESC
LIMIT 20;

-- Expected: Top brands (NISSAN, CHEVROLET, VW, FORD, TOYOTA)

-- 2.4 Transmission Recovery Success Rate
-- Expected: >95% valid transmission
-- Alert if: Falls below 95%
SELECT
  transmision,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  COUNT(*) FILTER (WHERE fecha_creacion >= CURRENT_DATE - INTERVAL '7 days') AS new_this_week
FROM catalogo_homologado
GROUP BY transmision
ORDER BY count DESC;

-- Expected:
-- AUTO: ~65%, MANUAL: ~31%, NULL: ~4%

-- ============================================================
-- SECTION 3: MONTHLY PERFORMANCE QUERIES
-- ============================================================
-- Run these queries monthly for comprehensive health review

-- 3.1 Data Integrity Checks
-- Expected: 0 duplicates, 0 hash mismatches
-- Alert if: Any violations found

-- Check 1: No duplicate id_canonico
SELECT
  'Duplicate id_canonico' AS issue,
  COUNT(*) AS violation_count
FROM (
  SELECT id_canonico, COUNT(*)
  FROM catalogo_homologado
  GROUP BY id_canonico
  HAVING COUNT(*) > 1
) duplicates

UNION ALL

-- Check 2: hash_comercial matches actual fields
SELECT
  'Hash Comercial Mismatch',
  COUNT(*)
FROM catalogo_homologado
WHERE hash_comercial != ENCODE(SHA256((marca || '|' || modelo || '|' || anio::text || '|' || COALESCE(transmision, ''))::bytea), 'hex')

UNION ALL

-- Check 3: No orphaned records (missing marca/modelo)
SELECT
  'Missing Core Fields',
  COUNT(*)
FROM catalogo_homologado
WHERE marca IS NULL OR modelo IS NULL OR anio IS NULL;

-- Expected: All violation_count = 0

-- 3.2 Year Distribution Analysis
-- Expected: Recent years dominate, old years stable
SELECT
  CASE
    WHEN anio >= 2020 THEN '2020-Present'
    WHEN anio BETWEEN 2015 AND 2019 THEN '2015-2019'
    WHEN anio BETWEEN 2010 AND 2014 THEN '2010-2014'
    WHEN anio BETWEEN 2005 AND 2009 THEN '2005-2009'
    WHEN anio BETWEEN 2000 AND 2004 THEN '2000-2004'
    WHEN anio BETWEEN 1990 AND 1999 THEN '1990-1999'
    ELSE 'Pre-1990'
  END AS year_range,
  COUNT(*) AS records,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  MIN(anio) AS min_year,
  MAX(anio) AS max_year
FROM catalogo_homologado
GROUP BY year_range
ORDER BY min_year DESC;

-- Expected: 2020-Present (~37%), 2015-2019 (~30%)

-- 3.3 Version Token Statistics
-- Expected: Avg tokens ~6, range 1-18
-- Alert if: Avg tokens <5 or >10 (suggests normalization issues)
SELECT
  MIN(array_length(version_tokens_array, 1)) AS min_tokens,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY array_length(version_tokens_array, 1)) AS q1_tokens,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY array_length(version_tokens_array, 1)) AS median_tokens,
  AVG(array_length(version_tokens_array, 1)) AS avg_tokens,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY array_length(version_tokens_array, 1)) AS q3_tokens,
  MAX(array_length(version_tokens_array, 1)) AS max_tokens,
  COUNT(*) FILTER (WHERE array_length(version_tokens_array, 1) IS NULL) AS null_count
FROM catalogo_homologado;

-- Expected: median ~5, avg ~6, max ~18

-- 3.4 Top Models by Insurer Coverage
-- Expected: Popular models (CIVIC, COROLLA, JETTA) have high coverage
SELECT
  marca,
  modelo,
  COUNT(*) AS total_versions,
  AVG(jsonb_array_length(jsonb_object_keys(disponibilidad))) AS avg_insurer_count,
  MAX(jsonb_array_length(jsonb_object_keys(disponibilidad))) AS max_insurer_count,
  STRING_AGG(DISTINCT jsonb_object_keys(disponibilidad), ', ' ORDER BY jsonb_object_keys(disponibilidad)) AS insurers
FROM catalogo_homologado
GROUP BY marca, modelo
ORDER BY total_versions DESC
LIMIT 20;

-- Expected: Popular models have 5-8 insurer coverage

-- ============================================================
-- SECTION 4: A-SPEC vs TECH BUG VERIFICATION
-- ============================================================
-- Verify the critical algorithm fix (Phase 1)
-- Expected: A-SPEC and TECH are separate records, no multi-match

-- 4.1 Check A-SPEC vs TECH Separation
SELECT
  hash_comercial,
  marca,
  modelo,
  anio,
  transmision,
  version,
  jsonb_object_keys(disponibilidad) AS insurer,
  (disponibilidad->>jsonb_object_keys(disponibilidad))::jsonb->>'confidence' AS confidence,
  fecha_actualizacion
FROM catalogo_homologado
WHERE marca = 'ACURA'
  AND modelo = 'TLX'
  AND anio = 2021
  AND (version LIKE '%A-SPEC%' OR version LIKE '%TECH%')
ORDER BY version, insurer;

-- Expected:
-- Separate rows for A-SPEC and TECH versions
-- Each row has only ONE insurer (no multi-match)
-- Zurich assigned to A-SPEC (highest score), not TECH

-- 4.2 Verify No Multi-Match Records
-- Expected: 0 records updated by multiple insurers in same batch
SELECT
  hash_comercial,
  marca,
  modelo,
  anio,
  version,
  jsonb_array_length(jsonb_object_keys(disponibilidad)) AS insurer_count,
  fecha_actualizacion
FROM catalogo_homologado
WHERE fecha_actualizacion >= CURRENT_DATE - INTERVAL '1 day'
  AND jsonb_array_length(jsonb_object_keys(disponibilidad)) > 5  -- Unusually high match count
ORDER BY insurer_count DESC
LIMIT 10;

-- Expected: Most records have 1-3 insurers (gradual accumulation over time)
-- Alert if: Many records with >8 insurers added in single day (suggests multi-match bug)

-- ============================================================
-- SECTION 5: BRAND CONSOLIDATION VERIFICATION
-- ============================================================
-- Verify Phase 2 brand consolidation corrections

-- 5.1 Check for Unconsolidated Variants
-- Expected: 0 rows for known variants (should all be consolidated)
SELECT
  marca,
  COUNT(*) AS record_count,
  STRING_AGG(DISTINCT modelo, ', ') AS sample_models
FROM catalogo_homologado
WHERE marca IN (
  'BMW BW',        -- Should be consolidated to 'BMW'
  'KIA MOTORS',    -- Should be 'KIA'
  'BERCEDES',      -- Should be 'MERCEDES BENZ'
  'MERSEDES',      -- Typo variant
  'MERCEDEZ',      -- Typo variant
  'CHEVROELT',     -- Typo
  'TOYOT'          -- Typo
)
GROUP BY marca;

-- Expected: 0 rows (all variants consolidated)
-- Alert if: Any rows found (consolidation failed)

-- 5.2 Verify Canonical Brand Names
-- Expected: Only canonical names (BMW, KIA, MERCEDES BENZ, etc.)
SELECT
  marca,
  COUNT(*) AS record_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS market_share_pct
FROM catalogo_homologado
WHERE marca IN ('BMW', 'KIA', 'MERCEDES BENZ', 'CHEVROLET', 'TOYOTA')
GROUP BY marca
ORDER BY record_count DESC;

-- Expected: All canonical names present with expected market shares

-- ============================================================
-- SECTION 6: ALERTING QUERIES
-- ============================================================
-- Queries designed for automated monitoring systems
-- Return non-empty result set if alert condition is met

-- 6.1 CRITICAL: Total Record Drop >10%
-- Run daily, alert if returns any rows
WITH baseline AS (
  SELECT 242656 AS expected_count  -- Update this baseline after deployment
),
current_count AS (
  SELECT COUNT(*) AS actual_count FROM catalogo_homologado
)
SELECT
  'CRITICAL: Total record drop >10%' AS alert,
  expected_count,
  actual_count,
  ROUND(100.0 * (expected_count - actual_count) / expected_count, 2) AS drop_pct
FROM baseline, current_count
WHERE actual_count < expected_count * 0.9;  -- Alert if <90% of baseline

-- Expected: 0 rows (no alert)

-- 6.2 CRITICAL: Transmission Coverage <90%
WITH transmission_stats AS (
  SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) AS valid
  FROM catalogo_homologado
)
SELECT
  'CRITICAL: Transmission coverage <90%' AS alert,
  total,
  valid,
  ROUND(100.0 * valid / total, 2) AS coverage_pct
FROM transmission_stats
WHERE ROUND(100.0 * valid / total, 2) < 90;

-- Expected: 0 rows (no alert)

-- 6.3 WARNING: Any Insurer Missing >3 Days
SELECT
  'WARNING: Insurer missing updates >3 days' AS alert,
  insurer,
  MAX((disponibilidad->>insurer)::jsonb->>'last_updated') AS last_updated,
  CURRENT_DATE - MAX((disponibilidad->>insurer)::jsonb->>'last_updated')::date AS days_since
FROM catalogo_homologado,
  LATERAL jsonb_object_keys(disponibilidad) AS insurer
GROUP BY insurer
HAVING CURRENT_DATE - MAX((disponibilidad->>insurer)::jsonb->>'last_updated')::date > 3;

-- Expected: 0 rows (no alert)

-- 6.4 WARNING: Transmission Coverage <95%
WITH transmission_stats AS (
  SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) AS valid
  FROM catalogo_homologado
)
SELECT
  'WARNING: Transmission coverage <95%' AS alert,
  total,
  valid,
  ROUND(100.0 * valid / total, 2) AS coverage_pct
FROM transmission_stats
WHERE ROUND(100.0 * valid / total, 2) < 95;

-- Expected: 0 rows (no alert)

-- ============================================================
-- SECTION 7: EXPORT QUERIES FOR DASHBOARDS
-- ============================================================
-- Queries formatted for external visualization tools

-- 7.1 Daily Metrics (for time-series charts)
-- Export format: CSV with date, metric, value
SELECT
  CURRENT_DATE AS metric_date,
  'Total Records' AS metric_name,
  COUNT(*)::text AS metric_value,
  'count' AS metric_type
FROM catalogo_homologado

UNION ALL

SELECT
  CURRENT_DATE,
  'Transmission Coverage',
  ROUND(100.0 * SUM(CASE WHEN transmision IN ('AUTO', 'MANUAL') THEN 1 ELSE 0 END) / COUNT(*), 2)::text,
  'percentage'
FROM catalogo_homologado

UNION ALL

SELECT
  CURRENT_DATE,
  'Unique Vehicles',
  COUNT(DISTINCT hash_comercial)::text,
  'count'
FROM catalogo_homologado

UNION ALL

SELECT
  CURRENT_DATE,
  'Avg Tokens per Version',
  ROUND(AVG(array_length(version_tokens_array, 1)), 2)::text,
  'average'
FROM catalogo_homologado;

-- 7.2 Insurer Distribution (for pie charts)
SELECT
  insurer AS label,
  COUNT(*) AS value,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM catalogo_homologado,
  LATERAL jsonb_object_keys(disponibilidad) AS insurer
GROUP BY insurer
ORDER BY value DESC;

-- 7.3 Brand Distribution (for bar charts)
SELECT
  marca AS label,
  COUNT(*) AS value,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM catalogo_homologado
GROUP BY marca
ORDER BY value DESC
LIMIT 20;

-- ============================================================
-- END OF MONITORING QUERIES
-- ============================================================
-- Documentation: See POST_DEPLOYMENT_VALIDATION_REPORT.md
-- Maintenance: Update baseline values after major ETL runs
-- Support: Contact data engineering team for query modifications
-- ============================================================
