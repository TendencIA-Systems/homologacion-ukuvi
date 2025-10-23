-- ============================================================================
-- DATA QUALITY REPORT GENERATOR
-- ============================================================================
-- Purpose: Generate comprehensive quality metrics for catalogo_homologado
-- Output: Markdown-formatted report showing post-correction state
-- Usage: Run in Supabase SQL Editor or via psql
-- ============================================================================

\echo '# Data Quality Report - Homologation Catalog'
\echo ''
\echo 'Generated: ' || TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS')
\echo ''
\echo '---'
\echo ''

-- ============================================================================
-- SECTION 1: EXECUTIVE SUMMARY
-- ============================================================================

\echo '## Executive Summary'
\echo ''

WITH summary_stats AS (
    SELECT
        COUNT(*) AS total_records,
        COUNT(DISTINCT CONCAT(marca, '|', modelo, '|', anio)) AS unique_vehicles,
        ROUND(COUNT(*)::NUMERIC / NULLIF(COUNT(DISTINCT CONCAT(marca, '|', modelo, '|', anio)), 0), 2) AS avg_versions_per_vehicle,
        COUNT(*) FILTER (WHERE transmision IS NOT NULL) AS records_with_transmission,
        COUNT(*) FILTER (WHERE transmision IS NULL) AS records_without_transmission,
        ROUND(100.0 * COUNT(*) FILTER (WHERE transmision IS NOT NULL) / COUNT(*), 1) AS transmission_coverage_pct
    FROM catalogo_homologado
)
SELECT
    FORMAT('- **Total Records**: %s', TO_CHAR(total_records, 'FM999,999,999')) AS metric,
    FORMAT('- **Unique Vehicles** (marca/modelo/año): %s', TO_CHAR(unique_vehicles, 'FM999,999,999')) AS metric2,
    FORMAT('- **Average Versions per Vehicle**: %s', avg_versions_per_vehicle) AS metric3,
    FORMAT('- **Transmission Coverage**: %s%% (%s records)', transmission_coverage_pct, TO_CHAR(records_with_transmission, 'FM999,999,999')) AS metric4
FROM summary_stats;

\echo ''
\echo '---'
\echo ''

-- ============================================================================
-- SECTION 2: RECORDS BY INSURER
-- ============================================================================

\echo '## Records by Insurer'
\echo ''
\echo '| Insurer | Total Records | % of Catalog | Active Records | Inactive Records |'
\echo '|---------|---------------|--------------|----------------|------------------|'

WITH insurer_stats AS (
    SELECT
        insurer_key,
        COUNT(*) AS total_records,
        COUNT(*) FILTER (WHERE (disponibilidad->>insurer_key)::JSONB->>'activo' = 'true') AS active_records,
        COUNT(*) FILTER (WHERE (disponibilidad->>insurer_key)::JSONB->>'activo' = 'false') AS inactive_records,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 1) AS pct_of_catalog
    FROM catalogo_homologado,
    LATERAL jsonb_object_keys(disponibilidad) AS insurer_key
    GROUP BY insurer_key
    ORDER BY total_records DESC
)
SELECT
    FORMAT('| %s | %s | %s%% | %s | %s |',
        RPAD(insurer_key, 11),
        LPAD(TO_CHAR(total_records, 'FM999,999'), 13),
        LPAD(pct_of_catalog::TEXT, 4),
        LPAD(TO_CHAR(active_records, 'FM999,999'), 14),
        LPAD(TO_CHAR(inactive_records, 'FM999,999'), 16)
    )
FROM insurer_stats;

\echo ''
\echo '**Expected**: 11 insurers (Qualitas, HDI, AXA, GNP, Mapfre, Chubb, Zurich, Atlas, BX, El Potosi, ANA)'
\echo ''
\echo '---'
\echo ''

-- ============================================================================
-- SECTION 3: TRANSMISSION DISTRIBUTION
-- ============================================================================

\echo '## Transmission Distribution'
\echo ''
\echo '| Transmission Type | Count | Percentage | Visual Distribution |'
\echo '|-------------------|-------|------------|---------------------|'

WITH transmission_stats AS (
    SELECT
        COALESCE(transmision, 'NULL') AS trans_type,
        COUNT(*) AS record_count,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS percentage
    FROM catalogo_homologado
    GROUP BY COALESCE(transmision, 'NULL')
    ORDER BY record_count DESC
),
total_count AS (
    SELECT SUM(record_count) AS total FROM transmission_stats
)
SELECT
    FORMAT('| %s | %s | %s%% | %s |',
        RPAD(trans_type, 17),
        LPAD(TO_CHAR(record_count, 'FM999,999'), 9),
        LPAD(percentage::TEXT, 6),
        REPEAT('█', LEAST(FLOOR(percentage / 2)::INT, 50))
    )
FROM transmission_stats, total_count
ORDER BY record_count DESC;

\echo ''

WITH transmission_summary AS (
    SELECT
        COUNT(*) FILTER (WHERE transmision = 'AUTO') AS auto_count,
        COUNT(*) FILTER (WHERE transmision = 'MANUAL') AS manual_count,
        COUNT(*) FILTER (WHERE transmision IS NULL) AS null_count,
        COUNT(*) AS total
    FROM catalogo_homologado
)
SELECT
    FORMAT('**Summary**: AUTO=%s (%s%%), MANUAL=%s (%s%%), NULL=%s (%s%%)',
        TO_CHAR(auto_count, 'FM999,999'),
        ROUND(100.0 * auto_count / total, 1),
        TO_CHAR(manual_count, 'FM999,999'),
        ROUND(100.0 * manual_count / total, 1),
        TO_CHAR(null_count, 'FM999,999'),
        ROUND(100.0 * null_count / total, 1)
    )
FROM transmission_summary;

\echo ''
\echo '---'
\echo ''

-- ============================================================================
-- SECTION 4: TOP 20 BRANDS BY COUNT
-- ============================================================================

\echo '## Top 20 Brands by Record Count'
\echo ''
\echo '| Rank | Brand | Records | % of Catalog | Avg Versions/Model |'
\echo '|------|-------|---------|--------------|-------------------|'

WITH brand_stats AS (
    SELECT
        marca,
        COUNT(*) AS record_count,
        COUNT(DISTINCT modelo) AS distinct_models,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS pct_of_catalog,
        ROUND(COUNT(*)::NUMERIC / NULLIF(COUNT(DISTINCT modelo), 0), 1) AS avg_versions_per_model,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rank
    FROM catalogo_homologado
    GROUP BY marca
    ORDER BY record_count DESC
    LIMIT 20
)
SELECT
    FORMAT('| %s | %s | %s | %s%% | %s |',
        LPAD(rank::TEXT, 4),
        RPAD(marca, 15),
        LPAD(TO_CHAR(record_count, 'FM999,999'), 9),
        LPAD(pct_of_catalog::TEXT, 6),
        LPAD(avg_versions_per_model::TEXT, 8)
    )
FROM brand_stats;

\echo ''
\echo '---'
\echo ''

-- ============================================================================
-- SECTION 5: MULTI-INSURER COVERAGE
-- ============================================================================

\echo '## Multi-Insurer Coverage Distribution'
\echo ''
\echo '| Insurers | Records | % of Catalog | Cumulative % | Visual |'
\echo '|----------|---------|--------------|--------------|--------|'

WITH coverage_stats AS (
    SELECT
        jsonb_object_keys_count AS insurer_count,
        COUNT(*) AS record_count,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS pct_of_catalog,
        SUM(ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2)) OVER (ORDER BY jsonb_object_keys_count) AS cumulative_pct
    FROM (
        SELECT jsonb_object_keys(disponibilidad) AS insurer_key, *
        FROM catalogo_homologado
    ) sub,
    LATERAL (SELECT COUNT(*) AS jsonb_object_keys_count FROM jsonb_object_keys(disponibilidad)) counts
    GROUP BY jsonb_object_keys_count
    ORDER BY jsonb_object_keys_count
)
SELECT
    FORMAT('| %s | %s | %s%% | %s%% | %s |',
        LPAD(insurer_count::TEXT, 8),
        LPAD(TO_CHAR(record_count, 'FM999,999'), 9),
        LPAD(pct_of_catalog::TEXT, 6),
        LPAD(cumulative_pct::TEXT, 6),
        REPEAT('█', LEAST(FLOOR(pct_of_catalog / 2)::INT, 30))
    )
FROM coverage_stats;

\echo ''

WITH coverage_summary AS (
    SELECT
        COUNT(*) FILTER (WHERE insurer_count = 1) AS single_insurer,
        COUNT(*) FILTER (WHERE insurer_count >= 2) AS multi_insurer,
        COUNT(*) AS total
    FROM (
        SELECT
            (SELECT COUNT(*) FROM jsonb_object_keys(disponibilidad)) AS insurer_count
        FROM catalogo_homologado
    ) counts
)
SELECT
    FORMAT('**Coverage Summary**: Single-insurer=%s (%s%%), Multi-insurer=%s (%s%%)',
        TO_CHAR(single_insurer, 'FM999,999'),
        ROUND(100.0 * single_insurer / total, 1),
        TO_CHAR(multi_insurer, 'FM999,999'),
        ROUND(100.0 * multi_insurer / total, 1)
    )
FROM coverage_summary;

\echo ''
\echo '---'
\echo ''

-- ============================================================================
-- SECTION 6: VERSION TOKEN ANALYSIS
-- ============================================================================

\echo '## Version Token Quality Metrics'
\echo ''
\echo '| Metric | Value |'
\echo '|--------|-------|'

WITH token_stats AS (
    SELECT
        COUNT(*) AS total_records,
        COUNT(*) FILTER (WHERE version_tokens_array IS NOT NULL AND array_length(version_tokens_array, 1) > 0) AS records_with_tokens,
        ROUND(AVG(array_length(version_tokens_array, 1))) AS avg_tokens_per_version,
        MIN(array_length(version_tokens_array, 1)) AS min_tokens,
        MAX(array_length(version_tokens_array, 1)) AS max_tokens,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY array_length(version_tokens_array, 1)) AS median_tokens
    FROM catalogo_homologado
)
SELECT
    FORMAT('| %s | %s |', 'Total Records', TO_CHAR(total_records, 'FM999,999')) AS line
FROM token_stats
UNION ALL
SELECT FORMAT('| %s | %s (%s%%) |', 'Records with Tokens', TO_CHAR(records_with_tokens, 'FM999,999'), ROUND(100.0 * records_with_tokens / total_records, 1))
FROM token_stats
UNION ALL
SELECT FORMAT('| %s | %s |', 'Avg Tokens per Version', avg_tokens_per_version)
FROM token_stats
UNION ALL
SELECT FORMAT('| %s | %s |', 'Median Tokens', median_tokens)
FROM token_stats
UNION ALL
SELECT FORMAT('| %s | %s - %s |', 'Token Range (Min-Max)', min_tokens, max_tokens)
FROM token_stats;

\echo ''
\echo '---'
\echo ''

-- ============================================================================
-- SECTION 7: DATA QUALITY INDICATORS
-- ============================================================================

\echo '## Data Quality Indicators'
\echo ''
\echo '| Quality Check | Pass | Fail | Pass Rate |'
\echo '|---------------|------|------|-----------|'

WITH quality_checks AS (
    SELECT
        'Hash Comercial Populated' AS check_name,
        COUNT(*) FILTER (WHERE hash_comercial IS NOT NULL AND hash_comercial != '') AS pass_count,
        COUNT(*) FILTER (WHERE hash_comercial IS NULL OR hash_comercial = '') AS fail_count,
        COUNT(*) AS total
    FROM catalogo_homologado
    UNION ALL
    SELECT
        'Version Not Empty',
        COUNT(*) FILTER (WHERE version IS NOT NULL AND version != ''),
        COUNT(*) FILTER (WHERE version IS NULL OR version = ''),
        COUNT(*)
    FROM catalogo_homologado
    UNION ALL
    SELECT
        'Marca Populated',
        COUNT(*) FILTER (WHERE marca IS NOT NULL AND marca != ''),
        COUNT(*) FILTER (WHERE marca IS NULL OR marca = ''),
        COUNT(*)
    FROM catalogo_homologado
    UNION ALL
    SELECT
        'Modelo Populated',
        COUNT(*) FILTER (WHERE modelo IS NOT NULL AND modelo != ''),
        COUNT(*) FILTER (WHERE modelo IS NULL OR modelo = ''),
        COUNT(*)
    FROM catalogo_homologado
    UNION ALL
    SELECT
        'Valid Year Range',
        COUNT(*) FILTER (WHERE anio BETWEEN 1980 AND EXTRACT(YEAR FROM NOW()) + 2),
        COUNT(*) FILTER (WHERE anio < 1980 OR anio > EXTRACT(YEAR FROM NOW()) + 2),
        COUNT(*)
    FROM catalogo_homologado
    UNION ALL
    SELECT
        'Version Tokens Present',
        COUNT(*) FILTER (WHERE version_tokens_array IS NOT NULL AND array_length(version_tokens_array, 1) > 0),
        COUNT(*) FILTER (WHERE version_tokens_array IS NULL OR array_length(version_tokens_array, 1) = 0),
        COUNT(*)
    FROM catalogo_homologado
)
SELECT
    FORMAT('| %s | %s | %s | %s%% |',
        RPAD(check_name, 27),
        LPAD(TO_CHAR(pass_count, 'FM999,999'), 9),
        LPAD(TO_CHAR(fail_count, 'FM999,999'), 9),
        LPAD(ROUND(100.0 * pass_count / NULLIF(total, 0), 1)::TEXT, 5)
    )
FROM quality_checks;

\echo ''
\echo '---'
\echo ''

-- ============================================================================
-- SECTION 8: YEAR DISTRIBUTION
-- ============================================================================

\echo '## Vehicle Year Distribution'
\echo ''
\echo '| Year Range | Records | % of Catalog |'
\echo '|------------|---------|--------------|'

WITH year_ranges AS (
    SELECT
        CASE
            WHEN anio >= 2020 THEN '2020-Present'
            WHEN anio >= 2015 THEN '2015-2019'
            WHEN anio >= 2010 THEN '2010-2014'
            WHEN anio >= 2005 THEN '2005-2009'
            WHEN anio >= 2000 THEN '2000-2004'
            WHEN anio >= 1990 THEN '1990-1999'
            ELSE 'Pre-1990'
        END AS year_range,
        COUNT(*) AS record_count,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER(), 2) AS pct_of_catalog
    FROM catalogo_homologado
    GROUP BY year_range
    ORDER BY
        CASE year_range
            WHEN '2020-Present' THEN 1
            WHEN '2015-2019' THEN 2
            WHEN '2010-2014' THEN 3
            WHEN '2005-2009' THEN 4
            WHEN '2000-2004' THEN 5
            WHEN '1990-1999' THEN 6
            ELSE 7
        END
)
SELECT
    FORMAT('| %s | %s | %s%% |',
        RPAD(year_range, 12),
        LPAD(TO_CHAR(record_count, 'FM999,999'), 9),
        LPAD(pct_of_catalog::TEXT, 6)
    )
FROM year_ranges;

\echo ''
\echo '---'
\echo ''

-- ============================================================================
-- SECTION 9: CORRECTION IMPACT SUMMARY
-- ============================================================================

\echo '## Applied Corrections Summary'
\echo ''
\echo 'This report reflects the state AFTER applying normalization corrections including:'
\echo ''
\echo '### JavaScript Normalization Fixes'
\echo '- **Double Decimal Liter Bug**: Fixed across all 11 insurers (e.g., 1.75L no longer becomes 1.7.5L)'
\echo '- **Qualitas Leftover Characters**: Fixed V/P, Q/C, S-TRONIC removal'
\echo '- **Qualitas NMAX Bug**: Prevented NMAX token contamination in marca field'
\echo '- **Chubb Displacement Extraction**: Fixed regex to properly extract 2.0L, 3.0L, etc.'
\echo '- **GNP Hyphen Preservation**: Protected hyphenated trims (A-SPEC, TYPE-S) during processing'
\echo '- **Mapfre Year Parsing**: Fixed 4-digit year extraction from version strings'
\echo ''
\echo '### SQL Function Updates'
\echo '- **Token Normalization**: Enhanced normalize_token() with comprehensive mappings'
\echo '- **Deduplication Logic**: Improved intelligent token deduplication'
\echo '- **Similarity Scoring**: Multi-metric weighted coverage calculation'
\echo ''
\echo '---'
\echo ''

-- ============================================================================
-- SECTION 10: FINAL SUMMARY OUTPUT
-- ============================================================================

\echo '## Final Quality Report Summary'
\echo ''

WITH final_summary AS (
    SELECT
        COUNT(*) AS total_records,
        COUNT(*) FILTER (WHERE transmision IS NOT NULL) AS records_with_transmission,
        COUNT(*) FILTER (WHERE transmision IS NULL) AS records_discarded,
        ROUND(100.0 * COUNT(*) FILTER (WHERE transmision IS NOT NULL) / COUNT(*), 1) AS correction_pct,
        ROUND(100.0 * COUNT(*) FILTER (WHERE transmision IS NULL) / COUNT(*), 1) AS discard_pct
    FROM catalogo_homologado
)
SELECT
    FORMAT('✓ Quality Report: %s total records, %s%% corrected, %s%% discarded',
        TO_CHAR(total_records, 'FM999,999'),
        correction_pct,
        discard_pct
    ) AS summary_output
FROM final_summary;

\echo ''
\echo '---'
\echo 'Report completed successfully.'
\echo ''
