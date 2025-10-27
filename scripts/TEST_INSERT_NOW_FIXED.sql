-- DEFINITIVE TEST: Insert a new record RIGHT NOW and check the tokens
-- Using ONLY columns that exist in the schema

BEGIN;

-- Call procesar_batch_vehiculos with a test ZURICH record
SELECT procesar_batch_vehiculos(
  jsonb_build_array(
    jsonb_build_object(
      'origen_aseguradora', 'ZURICH',
      'id_original', 'TEST_NOW',
      'marca', 'MAZDA',
      'modelo', 'CX-5',
      'anio', 2020,
      'transmision', 'AUTO',
      'version_original', 'I SPORT SUV AUT',
      'version_limpia', 'I SPORT SUV AUTO 155HP',
      'hash_comercial', 'MAZDA|CX-5|2020|AUTO'
    )
  )
) as result;

-- Check what was inserted
SELECT
  'INSERTED RIGHT NOW' as test,
  version,
  version_tokens_array,
  clean_and_tokenize_version(version) as expected,
  version_tokens_array = clean_and_tokenize_version(version) as match,
  'I-SPORT' = ANY(version_tokens_array) as has_hyphen
FROM catalogo_homologado
WHERE hash_comercial = 'MAZDA|CX-5|2020|AUTO'
  AND version = 'I SPORT SUV AUTO 155HP'
ORDER BY fecha_creacion DESC
LIMIT 1;

ROLLBACK;

\echo 'If has_hyphen = TRUE: Bug is in old data, just TRUNCATE and re-run'
\echo 'If has_hyphen = FALSE: Bug is in procesar_batch_vehiculos()'
