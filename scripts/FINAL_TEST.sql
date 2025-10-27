-- FINAL DEFINITIVE TEST
-- Compare what clean_and_tokenize_version returns in different contexts

\echo '========================================='
\echo 'TEST 1: Direct call'
\echo '========================================='

SELECT clean_and_tokenize_version('I SPORT SUV AUTO 155HP 2.5L 4CIL 5PUERTAS 5OCUP') as tokens;

\echo ''
\echo '========================================='
\echo 'TEST 2: From within a plpgsql function'
\echo '========================================='

DO $$
DECLARE
  result TEXT[];
BEGIN
  result := clean_and_tokenize_version('I SPORT SUV AUTO 155HP 2.5L 4CIL 5PUERTAS 5OCUP');
  RAISE NOTICE 'Tokens: %', result;
  RAISE NOTICE 'Array length: %', array_length(result, 1);
  RAISE NOTICE 'Contains I-SPORT: %', 'I-SPORT' = ANY(result);
END $$;

\echo ''
\echo '========================================='
\echo 'TEST 3: What is ACTUALLY stored in DB'
\echo '========================================='

SELECT
  version,
  version_tokens_array,
  'I-SPORT' = ANY(version_tokens_array) as has_hyphenated_trim
FROM catalogo_homologado
WHERE id = 15413;

\echo ''
\echo 'CONCLUSION:'
\echo 'If TEST 1 and TEST 2 show I-SPORT but TEST 3 shows [I, SPORT], then:'
\echo 'The function works correctly BUT something corrupts the data during INSERT/UPDATE'
