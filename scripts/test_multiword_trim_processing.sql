-- ============================================================================
-- TEST: Diagnóstico de procesamiento de multi-word trims
-- ============================================================================

-- Test 1: Verificar detección de keyword
DO $$
DECLARE
    test_version TEXT := 'I GRAND TOURING HB AUT AA EE';
    has_touring BOOLEAN;
    cleaned TEXT;
BEGIN
    has_touring := test_version ~ '\mTOURING\M';
    RAISE NOTICE 'Test 1 - Detección de keyword';
    RAISE NOTICE '  Input: %', test_version;
    RAISE NOTICE '  has_touring: %', has_touring;

    IF has_touring THEN
        cleaned := regexp_replace(test_version, '\mI\s+GRAND\s+TOURING\M', 'I-GRAND-TOURING', 'gi');
        RAISE NOTICE '  Después de regexp_replace: %', cleaned;
    END IF;
END $$;

-- Test 2: Verificar el proceso completo con clean_and_tokenize_version
SELECT
    'I GRAND TOURING HB AUT' as version_original,
    clean_and_tokenize_version('I GRAND TOURING HB AUT') as tokens;

-- Test 3: Casos reportados por cliente
SELECT
    'MAZDA CX3 2016 I GRAND TOURING' as caso,
    clean_and_tokenize_version('I GRAND TOURING SUV AUT 4CIL') as tokens;

SELECT
    'BMW SERIE 3 2020 M SPORT' as caso,
    clean_and_tokenize_version('M SPORT SEDAN AUT 4CIL') as tokens;

SELECT
    'AUDI A4 2018 S LINE' as caso,
    clean_and_tokenize_version('S LINE SEDAN AUT 4CIL') as tokens;

-- Test 4: Verificar si X-DRIVE funciona (sabemos que sí funciona)
SELECT
    'BMW X-DRIVE (FUNCIONA)' as caso,
    clean_and_tokenize_version('X DRIVE AWD AUT') as tokens;

-- Test 5: Verificar R-LINE (sabemos que sí funciona)
SELECT
    'VW R-LINE (FUNCIONA)' as caso,
    clean_and_tokenize_version('R LINE SPORT AUT') as tokens;

-- Test 6: Verificar versión exacta de ZURICH del catálogo
SELECT
    'ZURICH Mazda 2 2019 (del catálogo)' as caso,
    clean_and_tokenize_version('I GRAND TOURING HB AUT AA EE CD BA VP 106HP ABS 1.5L 4CIL 4P 5OCUP') as tokens;
