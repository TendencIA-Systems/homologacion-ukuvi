-- Dump the ACTUAL function definition from Supabase
-- This shows what is REALLY deployed, not what's in the .sql file

\echo 'ACTUAL DEPLOYED clean_and_tokenize_version() FUNCTION:'
\echo '========================================================'
\echo ''

SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'clean_and_tokenize_version';

\echo ''
\echo '========================================================'
\echo 'Search for: regexp_replace.*I\\s+SPORT'
\echo 'If found: Function has the fix'
\echo 'If NOT found: Function is missing the fix - need to redeploy'
\echo '========================================================'
