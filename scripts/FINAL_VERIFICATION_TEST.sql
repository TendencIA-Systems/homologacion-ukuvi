-- Final verification: Test procesar_batch_vehiculos after dropping trigger

BEGIN;

SELECT procesar_batch_vehiculos(
  jsonb_build_array(
    jsonb_build_object(
      'origen_aseguradora', 'ZURICH',
      'id_original', 'FINAL_TEST',
      'marca', 'MAZDA',
      'modelo', 'CX-5',
      'anio', 2020,
      'transmision', 'AUTO',
      'version_original', 'I SPORT SUV AUT',
      'version_limpia', 'I SPORT SUV AUTO 155HP',
      'hash_comercial', 'MAZDA|CX-5|2020|AUTO'
    )
  )
);

SELECT
  'After dropping trigger' as test,
  version,
  version_tokens_array,
  'I-SPORT' = ANY(version_tokens_array) as has_hyphenated_trim,
  array_length(version_tokens_array, 1) as token_count
FROM catalogo_homologado
WHERE hash_comercial = 'MAZDA|CX-5|2020|AUTO'
  AND version = 'I SPORT SUV AUTO 155HP'
ORDER BY fecha_creacion DESC
LIMIT 1;

ROLLBACK;

\echo ''
\echo 'Expected: has_hyphenated_trim = TRUE'
\echo 'If TRUE: Bug is fixed! TRUNCATE and re-run ETL to regenerate all data'
