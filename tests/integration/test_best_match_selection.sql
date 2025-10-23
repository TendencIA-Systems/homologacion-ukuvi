-- ============================================================================
-- INTEGRATION TEST: Best-Match Selection Algorithm
-- ============================================================================
-- Test Case: A-SPEC vs TECH scenario
--
-- Purpose: Verify that procesar_batch_vehiculos correctly selects and updates
--          ONLY the best matching record (highest score) when multiple candidates
--          exist, preventing incorrect trim-level matches like A-SPEC being
--          matched with TECH.
--
-- Test Scenario:
--   - Incoming: Zurich A-SPEC 201HP 2.0L 4CIL 4PUERTAS 5OCUP
--   - Existing Catalog:
--     * Record 1 (TECH): TECH 4P L4 2.4L AUTO 5OCUP (expected score ~0.45)
--     * Record 2 (A-SPEC): A-SPEC 200HP 2.0L 4CIL 4PUERTAS 5OCUP (expected score ~0.95)
--
-- Expected Result:
--   - ONLY Record 2 (A-SPEC) should be updated with Zurich availability
--   - Record 1 (TECH) should remain unchanged
--   - No new records should be created
--
-- Requirements Coverage:
--   - 1.0: Best-Match Selection Algorithm
--   - 1.5: Update only best match, not all qualifying matches
-- ============================================================================

-- ============================================================================
-- TEST SETUP
-- ============================================================================

DO $$
DECLARE
    test_hash_comercial TEXT;
    test_record_1_id BIGINT;
    test_record_2_id BIGINT;
    incoming_batch JSONB;
    result RECORD;
    record_1_disponibilidad JSONB;
    record_2_disponibilidad JSONB;
    test_passed BOOLEAN := TRUE;
    error_messages TEXT := '';
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Starting Best-Match Selection Test';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 1: Clean Test Environment
    -- ========================================================================
    RAISE NOTICE '[SETUP] Cleaning test environment...';

    -- Delete any existing test data for ACURA TLX 2021
    DELETE FROM catalogo_homologado
    WHERE marca = 'ACURA'
      AND modelo = 'TLX'
      AND anio = 2021;

    RAISE NOTICE '[SETUP] Test environment cleaned';
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 2: Generate Test Hash
    -- ========================================================================
    -- hash_comercial = SHA-256 of "marca|modelo|anio|transmision"
    test_hash_comercial := encode(
        digest('ACURA|TLX|2021|AUTO', 'sha256'),
        'hex'
    );

    RAISE NOTICE '[SETUP] Test hash_comercial: %', test_hash_comercial;
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 3: Insert Mock Catalog Records
    -- ========================================================================
    RAISE NOTICE '[SETUP] Inserting mock catalog records...';

    -- Record 1: TECH version (lower similarity to incoming A-SPEC)
    -- This version has different specs that should produce a lower score (~0.45)
    INSERT INTO catalogo_homologado (
        hash_comercial,
        marca,
        modelo,
        anio,
        transmision,
        version,
        version_tokens_array,
        disponibilidad
    ) VALUES (
        test_hash_comercial,
        'ACURA',
        'TLX',
        2021,
        'AUTO',
        'TECH 4P L4 2.4L AUTO 5OCUP',
        clean_and_tokenize_version('TECH 4P L4 2.4L AUTO 5OCUP'),
        jsonb_build_object(
            'HDI', jsonb_build_object(
                'origen', true,
                'disponible', true,
                'aseguradora', 'HDI',
                'id_original', 'HDI-TEST-001',
                'version_original', 'TECH 4P L4 2.4L AUTO 5OCUP',
                'confianza_score', 0.95,
                'metodo_match', 'tier1_exact_version',
                'tier', 1,
                'fecha_actualizacion', NOW()
            )
        )
    ) RETURNING id INTO test_record_1_id;

    RAISE NOTICE '[SETUP] Inserted Record 1 (TECH) - ID: %', test_record_1_id;
    RAISE NOTICE '[SETUP]   Version: TECH 4P L4 2.4L AUTO 5OCUP';

    -- Record 2: A-SPEC version (high similarity to incoming A-SPEC)
    -- This version should match closely with incoming data (score ~0.95)
    INSERT INTO catalogo_homologado (
        hash_comercial,
        marca,
        modelo,
        anio,
        transmision,
        version,
        version_tokens_array,
        disponibilidad
    ) VALUES (
        test_hash_comercial,
        'ACURA',
        'TLX',
        2021,
        'AUTO',
        'A-SPEC 200HP 2.0L 4CIL 4PUERTAS 5OCUP',
        clean_and_tokenize_version('A-SPEC 200HP 2.0L 4CIL 4PUERTAS 5OCUP'),
        jsonb_build_object(
            'QUALITAS', jsonb_build_object(
                'origen', true,
                'disponible', true,
                'aseguradora', 'QUALITAS',
                'id_original', 'QUALITAS-TEST-002',
                'version_original', 'A-SPEC 200HP 2.0L 4CIL 4PUERTAS 5OCUP',
                'confianza_score', 0.98,
                'metodo_match', 'tier1_exact_version',
                'tier', 1,
                'fecha_actualizacion', NOW()
            )
        )
    ) RETURNING id INTO test_record_2_id;

    RAISE NOTICE '[SETUP] Inserted Record 2 (A-SPEC) - ID: %', test_record_2_id;
    RAISE NOTICE '[SETUP]   Version: A-SPEC 200HP 2.0L 4CIL 4PUERTAS 5OCUP';
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 4: Prepare Incoming Batch (Zurich Data)
    -- ========================================================================
    RAISE NOTICE '[TEST] Preparing incoming Zurich batch...';

    -- Incoming Zurich record with A-SPEC 201HP (very similar to Record 2)
    incoming_batch := jsonb_build_array(
        jsonb_build_object(
            'hash_comercial', test_hash_comercial,
            'marca', 'ACURA',
            'modelo', 'TLX',
            'anio', 2021,
            'transmision', 'AUTO',
            'version_limpia', 'A-SPEC 201HP 2.0L 4CIL 4PUERTAS 5OCUP',
            'origen_aseguradora', 'ZURICH',
            'id_original', 'ZURICH-TEST-003',
            'version_original', 'A-SPEC 201HP 2.0L 4CIL 4PUERTAS 5OCUP'
        )
    );

    RAISE NOTICE '[TEST] Incoming version: A-SPEC 201HP 2.0L 4CIL 4PUERTAS 5OCUP';
    RAISE NOTICE '[TEST] Expected behavior:';
    RAISE NOTICE '[TEST]   - Should match Record 2 (A-SPEC) with high score (~0.95)';
    RAISE NOTICE '[TEST]   - Should match Record 1 (TECH) with low score (~0.45)';
    RAISE NOTICE '[TEST]   - Should UPDATE ONLY Record 2 (highest score)';
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 5: Execute procesar_batch_vehiculos
    -- ========================================================================
    RAISE NOTICE '[EXECUTE] Calling procesar_batch_vehiculos...';

    SELECT * INTO result
    FROM procesar_batch_vehiculos(incoming_batch);

    RAISE NOTICE '[EXECUTE] Processing complete';
    RAISE NOTICE '[EXECUTE] Results:';
    RAISE NOTICE '[EXECUTE]   - Insertados: %', result.insertados;
    RAISE NOTICE '[EXECUTE]   - Actualizados: %', result.actualizados;
    RAISE NOTICE '[EXECUTE]   - Skipped: %', result.skipped;
    RAISE NOTICE '[EXECUTE]   - Multi-matches: %', result.multi_matches;
    RAISE NOTICE '[EXECUTE]   - Tier1: %, Tier2: %, Tier3: %',
        result.tier1_matches, result.tier2_matches, result.tier3_matches;
    RAISE NOTICE '[EXECUTE]   - Processing time: % ms', result.processing_time_ms;
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 6: Retrieve Updated Records
    -- ========================================================================
    RAISE NOTICE '[VERIFY] Retrieving updated records...';

    SELECT disponibilidad INTO record_1_disponibilidad
    FROM catalogo_homologado
    WHERE id = test_record_1_id;

    SELECT disponibilidad INTO record_2_disponibilidad
    FROM catalogo_homologado
    WHERE id = test_record_2_id;

    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 7: ASSERTIONS
    -- ========================================================================
    RAISE NOTICE '[VERIFY] Running assertions...';
    RAISE NOTICE '';

    -- -----------------------------------------------------------------------
    -- Assertion 1: Exactly 1 record should be updated
    -- -----------------------------------------------------------------------
    RAISE NOTICE '[ASSERTION 1] Verify exactly 1 update occurred';
    IF result.actualizados != 1 THEN
        test_passed := FALSE;
        error_messages := error_messages || E'\n  FAILED: Expected 1 update, got ' || result.actualizados;
        RAISE NOTICE '  FAILED: Expected 1 update, got %', result.actualizados;
    ELSE
        RAISE NOTICE '  PASSED: Exactly 1 record updated';
    END IF;
    RAISE NOTICE '';

    -- -----------------------------------------------------------------------
    -- Assertion 2: No new records should be created
    -- -----------------------------------------------------------------------
    RAISE NOTICE '[ASSERTION 2] Verify no new records created';
    IF result.insertados != 0 THEN
        test_passed := FALSE;
        error_messages := error_messages || E'\n  FAILED: Expected 0 inserts, got ' || result.insertados;
        RAISE NOTICE '  FAILED: Expected 0 inserts, got %', result.insertados;
    ELSE
        RAISE NOTICE '  PASSED: No new records created';
    END IF;
    RAISE NOTICE '';

    -- -----------------------------------------------------------------------
    -- Assertion 3: Record 1 (TECH) should NOT have Zurich entry
    -- -----------------------------------------------------------------------
    RAISE NOTICE '[ASSERTION 3] Verify Record 1 (TECH) unchanged';
    RAISE NOTICE '  Record 1 disponibilidad keys: %',
        (SELECT array_agg(key) FROM jsonb_object_keys(record_1_disponibilidad) AS key);

    IF record_1_disponibilidad ? 'ZURICH' THEN
        test_passed := FALSE;
        error_messages := error_messages || E'\n  FAILED: Record 1 (TECH) incorrectly has ZURICH entry';
        RAISE NOTICE '  FAILED: Record 1 (TECH) should NOT have ZURICH entry';
        RAISE NOTICE '    Found: %', record_1_disponibilidad->'ZURICH';
    ELSE
        RAISE NOTICE '  PASSED: Record 1 (TECH) has no ZURICH entry';
    END IF;

    IF NOT (record_1_disponibilidad ? 'HDI') THEN
        test_passed := FALSE;
        error_messages := error_messages || E'\n  FAILED: Record 1 (TECH) lost original HDI entry';
        RAISE NOTICE '  FAILED: Record 1 (TECH) should still have HDI entry';
    ELSE
        RAISE NOTICE '  PASSED: Record 1 (TECH) still has original HDI entry';
    END IF;
    RAISE NOTICE '';

    -- -----------------------------------------------------------------------
    -- Assertion 4: Record 2 (A-SPEC) SHOULD have Zurich entry
    -- -----------------------------------------------------------------------
    RAISE NOTICE '[ASSERTION 4] Verify Record 2 (A-SPEC) updated with Zurich';
    RAISE NOTICE '  Record 2 disponibilidad keys: %',
        (SELECT array_agg(key) FROM jsonb_object_keys(record_2_disponibilidad) AS key);

    IF NOT (record_2_disponibilidad ? 'ZURICH') THEN
        test_passed := FALSE;
        error_messages := error_messages || E'\n  FAILED: Record 2 (A-SPEC) missing ZURICH entry';
        RAISE NOTICE '  FAILED: Record 2 (A-SPEC) should have ZURICH entry';
    ELSE
        RAISE NOTICE '  PASSED: Record 2 (A-SPEC) has ZURICH entry';
        RAISE NOTICE '    Zurich data: %', record_2_disponibilidad->'ZURICH';

        -- Verify Zurich entry structure
        IF (record_2_disponibilidad->'ZURICH'->>'aseguradora') != 'ZURICH' THEN
            test_passed := FALSE;
            error_messages := error_messages || E'\n  FAILED: ZURICH entry has incorrect aseguradora';
            RAISE NOTICE '  FAILED: ZURICH entry has incorrect aseguradora';
        END IF;

        IF (record_2_disponibilidad->'ZURICH'->>'id_original') != 'ZURICH-TEST-003' THEN
            test_passed := FALSE;
            error_messages := error_messages || E'\n  FAILED: ZURICH entry has incorrect id_original';
            RAISE NOTICE '  FAILED: ZURICH entry has incorrect id_original';
        END IF;
    END IF;

    IF NOT (record_2_disponibilidad ? 'QUALITAS') THEN
        test_passed := FALSE;
        error_messages := error_messages || E'\n  FAILED: Record 2 (A-SPEC) lost original QUALITAS entry';
        RAISE NOTICE '  FAILED: Record 2 (A-SPEC) should still have QUALITAS entry';
    ELSE
        RAISE NOTICE '  PASSED: Record 2 (A-SPEC) still has original QUALITAS entry';
    END IF;
    RAISE NOTICE '';

    -- -----------------------------------------------------------------------
    -- Assertion 5: Verify multi-match was detected
    -- -----------------------------------------------------------------------
    RAISE NOTICE '[ASSERTION 5] Verify multi-match detection';
    IF result.multi_matches != 1 THEN
        test_passed := FALSE;
        error_messages := error_messages || E'\n  WARNING: Expected multi_match_count = 1, got ' || result.multi_matches;
        RAISE NOTICE '  WARNING: Expected multi_match_count = 1, got %', result.multi_matches;
    ELSE
        RAISE NOTICE '  PASSED: Multi-match correctly detected';
    END IF;
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 8: TEST CLEANUP
    -- ========================================================================
    RAISE NOTICE '[CLEANUP] Removing test data...';

    DELETE FROM catalogo_homologado
    WHERE id IN (test_record_1_id, test_record_2_id);

    RAISE NOTICE '[CLEANUP] Test data removed';
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 9: FINAL RESULT
    -- ========================================================================
    RAISE NOTICE '========================================';
    IF test_passed THEN
        RAISE NOTICE 'TEST RESULT: PASSED';
        RAISE NOTICE '========================================';
        RAISE NOTICE '';
        RAISE NOTICE 'All assertions passed successfully!';
        RAISE NOTICE 'The best-match selection algorithm correctly:';
        RAISE NOTICE '  1. Identified multiple candidates (TECH and A-SPEC)';
        RAISE NOTICE '  2. Calculated scores for both candidates';
        RAISE NOTICE '  3. Selected ONLY the best match (A-SPEC with ~0.95 score)';
        RAISE NOTICE '  4. Updated ONLY the best match, leaving TECH unchanged';
        RAISE NOTICE '';
        RAISE NOTICE 'Requirements satisfied:';
        RAISE NOTICE '  - [1.0] Best-Match Selection Algorithm';
        RAISE NOTICE '  - [1.5] Update only best match';
    ELSE
        RAISE NOTICE 'TEST RESULT: FAILED';
        RAISE NOTICE '========================================';
        RAISE NOTICE '';
        RAISE NOTICE 'ERRORS:%', error_messages;
        RAISE NOTICE '';
        RAISE NOTICE 'The test failed, indicating the best-match selection';
        RAISE NOTICE 'algorithm is NOT correctly selecting only the best match.';
        RAISE NOTICE '';
        RAISE EXCEPTION 'Integration test failed - see errors above';
    END IF;
    RAISE NOTICE '========================================';

END $$;

-- ============================================================================
-- TEST EXECUTION INSTRUCTIONS
-- ============================================================================
--
-- To run this test:
--   1. Ensure funciones-homologacion-actuales.sql is deployed
--   2. Execute this file: \i tests/integration/test_best_match_selection.sql
--   3. Review NOTICE messages for detailed test progression
--   4. Test passes if no EXCEPTION is raised
--
-- Expected Output:
--   - [ASSERTION 1] PASSED: Exactly 1 record updated
--   - [ASSERTION 2] PASSED: No new records created
--   - [ASSERTION 3] PASSED: Record 1 (TECH) has no ZURICH entry
--   - [ASSERTION 4] PASSED: Record 2 (A-SPEC) has ZURICH entry
--   - [ASSERTION 5] PASSED: Multi-match correctly detected
--   - TEST RESULT: PASSED
--
-- ============================================================================
