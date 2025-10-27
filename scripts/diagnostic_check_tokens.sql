-- ============================================================================
-- DIAGNOSTIC: Check actual tokens stored in catalogo_homologado
-- ============================================================================
-- This will show us if version_tokens_array has hyphens or spaces
-- ============================================================================

\echo '============================================================================'
\echo 'DIAGNOSTIC: MAZDA CX-5 2020 I SPORT tokens'
\echo '============================================================================'
\echo ''

SELECT
  id,
  marca,
  modelo,
  anio,
  transmision,
  version,
  version_tokens_array,
  array_length(version_tokens_array, 1) as token_count,
  jsonb_object_keys(disponibilidad) as insurers
FROM catalogo_homologado
WHERE marca = 'MAZDA'
  AND modelo = 'CX-5'
  AND anio = 2020
  AND transmision = 'AUTO'
  AND version ILIKE '%I SPORT%'
ORDER BY id
LIMIT 10;

\echo ''
\echo '============================================================================'
\echo 'TEST: Does is_single_spec_match work with these tokens?'
\echo '============================================================================'
\echo ''

-- Simulate GNP matching with ZURICH
WITH gnp_tokens AS (
  SELECT clean_and_tokenize_version('I SPORT AUTO') as tokens
),
zurich_record AS (
  SELECT
    id,
    version,
    version_tokens_array
  FROM catalogo_homologado
  WHERE marca = 'MAZDA'
    AND modelo = 'CX-5'
    AND anio = 2020
    AND version ILIKE '%I SPORT%'
    AND disponibilidad ? 'ZURICH'
  LIMIT 1
)
SELECT
  'GNP tokens' as source,
  gnp_tokens.tokens as tokens
FROM gnp_tokens
UNION ALL
SELECT
  'ZURICH tokens' as source,
  zurich_record.version_tokens_array as tokens
FROM zurich_record;

\echo ''
\echo 'Match result:'
\echo ''

WITH gnp_tokens AS (
  SELECT clean_and_tokenize_version('I SPORT AUTO') as tokens
),
zurich_record AS (
  SELECT version_tokens_array
  FROM catalogo_homologado
  WHERE marca = 'MAZDA'
    AND modelo = 'CX-5'
    AND anio = 2020
    AND version ILIKE '%I SPORT%'
    AND disponibilidad ? 'ZURICH'
  LIMIT 1
)
SELECT
  is_single_spec_match(gnp_tokens.tokens, zurich_record.version_tokens_array) as should_match,
  extract_primary_trim(gnp_tokens.tokens) as gnp_trim,
  extract_primary_trim(zurich_record.version_tokens_array) as zurich_trim
FROM gnp_tokens, zurich_record;

\echo ''
\echo '============================================================================'
