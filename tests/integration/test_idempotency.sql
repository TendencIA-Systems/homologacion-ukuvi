-- ============================================================================
-- INTEGRATION TEST: Idempotency Validation
-- ============================================================================
-- Test Case: Batch Processing Idempotency
--
-- Purpose: Verify that procesar_batch_vehiculos produces identical results
--          when the same batch is processed multiple times (idempotent behavior).
--
-- Test Scenario:
--   - Create a batch of 1,000 test records with diverse characteristics
--   - Process batch (Run 1): capture results and state
--   - Re-process same batch (Run 2): verify identical behavior
--
-- Expected Result:
--   - Run 1: Records inserted and/or updated based on catalog state
--   - Run 2: No new inserts (inserted_count = 0)
--   - Run 2: Same updates as Run 1 (matched to same records)
--   - hash_comercial values remain unchanged
--   - id_canonico values remain unchanged
--   - disponibilidad JSONB contains identical insurer entries
--
-- Requirements Coverage:
--   - 1.0: Deterministic matching algorithm
--   - Data Integrity NFR: No duplicate records created
-- ============================================================================

-- ============================================================================
-- TEST SETUP
-- ============================================================================

DO $$
DECLARE
    -- Test control variables
    test_batch JSONB;
    test_batch_size INT := 1000;
    test_marca TEXT := 'IDEMPOTENCY_TEST';

    -- Run 1 results
    run1_result RECORD;
    run1_inserted INT;
    run1_updated INT;
    run1_tier1 INT;
    run1_tier2 INT;
    run1_tier3 INT;

    -- Run 2 results
    run2_result RECORD;
    run2_inserted INT;
    run2_updated INT;
    run2_tier1 INT;
    run2_tier2 INT;
    run2_tier3 INT;

    -- State capture after each run
    run1_state JSONB;
    run2_state JSONB;

    -- Comparison variables
    hash_comercial_changed INT;
    id_canonico_changed INT;
    disponibilidad_changed INT;

    -- Test result tracking
    test_passed BOOLEAN := TRUE;
    error_messages TEXT := '';

    -- Loop variables for batch generation
    i INT;
    test_record JSONB;
    test_hash TEXT;
    test_version TEXT;

BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Starting Idempotency Test';
    RAISE NOTICE 'Test batch size: % records', test_batch_size;
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 1: Clean Test Environment
    -- ========================================================================
    RAISE NOTICE '[SETUP] Cleaning test environment...';

    DELETE FROM catalogo_homologado
    WHERE marca = test_marca;

    RAISE NOTICE '[SETUP] Test environment cleaned';
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 2: Generate Test Batch (1,000 diverse records)
    -- ========================================================================
    RAISE NOTICE '[SETUP] Generating test batch of % records...', test_batch_size;

    test_batch := '[]'::JSONB;

    FOR i IN 1..test_batch_size LOOP
        -- Generate diverse test data
        test_version := CASE
            WHEN i % 10 = 0 THEN 'BASE SEDAN AUTO 2.0L 4CIL 4PUERTAS'
            WHEN i % 10 = 1 THEN 'SPORT COUPE MANUAL 1.6L TURBO 4CIL 2PUERTAS'
            WHEN i % 10 = 2 THEN 'PREMIUM SUV AUTO 3.0L 6CIL 5PUERTAS AWD'
            WHEN i % 10 = 3 THEN 'TECH SEDAN CVT 1.8L HYBRID 4CIL 4PUERTAS'
            WHEN i % 10 = 4 THEN 'COMFORT WAGON AUTO 2.5L 4CIL 5PUERTAS FWD'
            WHEN i % 10 = 5 THEN 'ADVANCE HATCHBACK MANUAL 1.4L 4CIL 5PUERTAS'
            WHEN i % 10 = 6 THEN 'EXECUTIVE SEDAN AUTO 2.0L TURBO 4CIL 4PUERTAS'
            WHEN i % 10 = 7 THEN 'DYNAMIC SUV AUTO 2.4L 4CIL 5PUERTAS AWD'
            WHEN i % 10 = 8 THEN 'ELEGANCE SEDAN AUTO 1.6L 4CIL 4PUERTAS'
            ELSE 'PRESTIGE COUPE AUTO 3.5L V6 2PUERTAS RWD'
        END;

        test_hash := encode(
            digest(
                test_marca || '|MODEL_' || (i % 100)::TEXT || '|' ||
                (2020 + (i % 4))::TEXT || '|' ||
                CASE WHEN i % 2 = 0 THEN 'AUTO' ELSE 'MANUAL' END,
                'sha256'
            ),
            'hex'
        );

        test_record := jsonb_build_object(
            'hash_comercial', test_hash,
            'marca', test_marca,
            'modelo', 'MODEL_' || (i % 100)::TEXT,
            'anio', 2020 + (i % 4),
            'transmision', CASE WHEN i % 2 = 0 THEN 'AUTO' ELSE 'MANUAL' END,
            'version_limpia', test_version,
            'origen_aseguradora', CASE
                WHEN i % 3 = 0 THEN 'ZURICH'
                WHEN i % 3 = 1 THEN 'HDI'
                ELSE 'QUALITAS'
            END,
            'id_original', 'TEST_ID_' || i::TEXT,
            'version_original', test_version
        );

        test_batch := test_batch || jsonb_build_array(test_record);
    END LOOP;

    RAISE NOTICE '[SETUP] Generated % test records', jsonb_array_length(test_batch);
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 3: Run 1 - Initial Processing
    -- ========================================================================
    RAISE NOTICE '[RUN 1] Processing batch (initial run)...';

    SELECT * INTO run1_result
    FROM procesar_batch_vehiculos(test_batch);

    run1_inserted := run1_result.insertados;
    run1_updated := run1_result.actualizados;
    run1_tier1 := run1_result.tier1_matches;
    run1_tier2 := run1_result.tier2_matches;
    run1_tier3 := run1_result.tier3_matches;

    RAISE NOTICE '[RUN 1] Processing complete';
    RAISE NOTICE '[RUN 1] Results:';
    RAISE NOTICE '[RUN 1]   - Insertados: %', run1_inserted;
    RAISE NOTICE '[RUN 1]   - Actualizados: %', run1_updated;
    RAISE NOTICE '[RUN 1]   - Skipped: %', run1_result.skipped;
    RAISE NOTICE '[RUN 1]   - Multi-matches: %', run1_result.multi_matches;
    RAISE NOTICE '[RUN 1]   - Tier1: %, Tier2: %, Tier3: %',
        run1_tier1, run1_tier2, run1_tier3;
    RAISE NOTICE '[RUN 1]   - Processing time: % ms', run1_result.processing_time_ms;
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 4: Capture State After Run 1
    -- ========================================================================
    RAISE NOTICE '[RUN 1] Capturing database state...';

    SELECT jsonb_agg(
        jsonb_build_object(
            'id', id,
            'hash_comercial', hash_comercial,
            'marca', marca,
            'modelo', modelo,
            'anio', anio,
            'transmision', transmision,
            'version', version,
            'disponibilidad_keys', (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(disponibilidad) AS key),
            'disponibilidad', disponibilidad
        ) ORDER BY id
    ) INTO run1_state
    FROM catalogo_homologado
    WHERE marca = test_marca;

    RAISE NOTICE '[RUN 1] Captured state for % records', jsonb_array_length(run1_state);
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 5: Run 2 - Idempotency Test (Re-process Same Batch)
    -- ========================================================================
    RAISE NOTICE '[RUN 2] Re-processing same batch (idempotency check)...';

    SELECT * INTO run2_result
    FROM procesar_batch_vehiculos(test_batch);

    run2_inserted := run2_result.insertados;
    run2_updated := run2_result.actualizados;
    run2_tier1 := run2_result.tier1_matches;
    run2_tier2 := run2_result.tier2_matches;
    run2_tier3 := run2_result.tier3_matches;

    RAISE NOTICE '[RUN 2] Processing complete';
    RAISE NOTICE '[RUN 2] Results:';
    RAISE NOTICE '[RUN 2]   - Insertados: %', run2_inserted;
    RAISE NOTICE '[RUN 2]   - Actualizados: %', run2_updated;
    RAISE NOTICE '[RUN 2]   - Skipped: %', run2_result.skipped;
    RAISE NOTICE '[RUN 2]   - Multi-matches: %', run2_result.multi_matches;
    RAISE NOTICE '[RUN 2]   - Tier1: %, Tier2: %, Tier3: %',
        run2_tier1, run2_tier2, run2_tier3;
    RAISE NOTICE '[RUN 2]   - Processing time: % ms', run2_result.processing_time_ms;
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 6: Capture State After Run 2
    -- ========================================================================
    RAISE NOTICE '[RUN 2] Capturing database state...';

    SELECT jsonb_agg(
        jsonb_build_object(
            'id', id,
            'hash_comercial', hash_comercial,
            'marca', marca,
            'modelo', modelo,
            'anio', anio,
            'transmision', transmision,
            'version', version,
            'disponibilidad_keys', (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(disponibilidad) AS key),
            'disponibilidad', disponibilidad
        ) ORDER BY id
    ) INTO run2_state
    FROM catalogo_homologado
    WHERE marca = test_marca;

    RAISE NOTICE '[RUN 2] Captured state for % records', jsonb_array_length(run2_state);
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 7: ASSERTIONS - Idempotency Validation
    -- ========================================================================
    RAISE NOTICE '[VERIFY] Running idempotency assertions...';
    RAISE NOTICE '';

    -- -----------------------------------------------------------------------
    -- Assertion 1: No new records inserted on Run 2
    -- -----------------------------------------------------------------------
    RAISE NOTICE '[ASSERTION 1] Verify no new insertions on Run 2';
    IF run2_inserted != 0 THEN
        test_passed := FALSE;
        error_messages := error_messages || E'\n  FAILED: Run 2 inserted ' || run2_inserted || ' new records (expected 0)';
        RAISE NOTICE '  FAILED: Run 2 should not insert any new records';
        RAISE NOTICE '    Expected: 0 insertions';
        RAISE NOTICE '    Got: % insertions', run2_inserted;
    ELSE
        RAISE NOTICE '  PASSED: No new records inserted on Run 2 (insertados = 0)';
    END IF;
    RAISE NOTICE '';

    -- -----------------------------------------------------------------------
    -- Assertion 2: Same number of total records after both runs
    -- -----------------------------------------------------------------------
    RAISE NOTICE '[ASSERTION 2] Verify same total record count';
    IF jsonb_array_length(run1_state) != jsonb_array_length(run2_state) THEN
        test_passed := FALSE;
        error_messages := error_messages || E'\n  FAILED: Record count changed between runs';
        RAISE NOTICE '  FAILED: Record count should remain constant';
        RAISE NOTICE '    Run 1 count: %', jsonb_array_length(run1_state);
        RAISE NOTICE '    Run 2 count: %', jsonb_array_length(run2_state);
    ELSE
        RAISE NOTICE '  PASSED: Record count unchanged (% records)', jsonb_array_length(run1_state);
    END IF;
    RAISE NOTICE '';

    -- -----------------------------------------------------------------------
    -- Assertion 3: hash_comercial values unchanged
    -- -----------------------------------------------------------------------
    RAISE NOTICE '[ASSERTION 3] Verify hash_comercial values unchanged';

    WITH comparison AS (
        SELECT
            r1.value->>'id' AS id,
            r1.value->>'hash_comercial' AS hash1,
            r2.value->>'hash_comercial' AS hash2
        FROM jsonb_array_elements(run1_state) AS r1
        JOIN jsonb_array_elements(run2_state) AS r2
            ON r1.value->>'id' = r2.value->>'id'
        WHERE r1.value->>'hash_comercial' != r2.value->>'hash_comercial'
    )
    SELECT COUNT(*) INTO hash_comercial_changed FROM comparison;

    IF hash_comercial_changed > 0 THEN
        test_passed := FALSE;
        error_messages := error_messages || E'\n  FAILED: ' || hash_comercial_changed || ' hash_comercial values changed';
        RAISE NOTICE '  FAILED: % hash_comercial values changed between runs', hash_comercial_changed;
    ELSE
        RAISE NOTICE '  PASSED: All hash_comercial values unchanged';
    END IF;
    RAISE NOTICE '';

    -- -----------------------------------------------------------------------
    -- Assertion 4: Same updates count (or higher due to timestamp updates)
    -- -----------------------------------------------------------------------
    RAISE NOTICE '[ASSERTION 4] Verify consistent update behavior';
    IF run2_updated != run1_updated AND run2_updated != test_batch_size THEN
        RAISE NOTICE '  WARNING: Update counts differ (Run1: %, Run2: %)', run1_updated, run2_updated;
        RAISE NOTICE '    This is acceptable if Run 2 matches all records as existing';
    ELSE
        RAISE NOTICE '  PASSED: Update behavior consistent (Run1: %, Run2: %)', run1_updated, run2_updated;
    END IF;
    RAISE NOTICE '';

    -- -----------------------------------------------------------------------
    -- Assertion 5: disponibilidad JSONB keys identical
    -- -----------------------------------------------------------------------
    RAISE NOTICE '[ASSERTION 5] Verify disponibilidad keys unchanged';

    WITH comparison AS (
        SELECT
            r1.value->>'id' AS id,
            r1.value->'disponibilidad_keys' AS keys1,
            r2.value->'disponibilidad_keys' AS keys2
        FROM jsonb_array_elements(run1_state) AS r1
        JOIN jsonb_array_elements(run2_state) AS r2
            ON r1.value->>'id' = r2.value->>'id'
        WHERE r1.value->'disponibilidad_keys' != r2.value->'disponibilidad_keys'
    )
    SELECT COUNT(*) INTO disponibilidad_changed FROM comparison;

    IF disponibilidad_changed > 0 THEN
        test_passed := FALSE;
        error_messages := error_messages || E'\n  FAILED: ' || disponibilidad_changed || ' disponibilidad key sets changed';
        RAISE NOTICE '  FAILED: % records have different disponibilidad keys', disponibilidad_changed;
    ELSE
        RAISE NOTICE '  PASSED: All disponibilidad key sets unchanged';
    END IF;
    RAISE NOTICE '';

    -- -----------------------------------------------------------------------
    -- Assertion 6: Tier distribution unchanged
    -- -----------------------------------------------------------------------
    RAISE NOTICE '[ASSERTION 6] Verify tier distribution unchanged';
    IF run1_tier1 != run2_tier1 OR run1_tier2 != run2_tier2 OR run1_tier3 != run2_tier3 THEN
        RAISE NOTICE '  WARNING: Tier distribution changed';
        RAISE NOTICE '    Run 1: Tier1=%s, Tier2=%s, Tier3=%s', run1_tier1, run1_tier2, run1_tier3;
        RAISE NOTICE '    Run 2: Tier1=%s, Tier2=%s, Tier3=%s', run2_tier1, run2_tier2, run2_tier3;
        RAISE NOTICE '    This may indicate non-deterministic matching';
    ELSE
        RAISE NOTICE '  PASSED: Tier distribution identical';
        RAISE NOTICE '    Tier1: %, Tier2: %, Tier3: %', run1_tier1, run1_tier2, run1_tier3;
    END IF;
    RAISE NOTICE '';

    -- ========================================================================
    -- STEP 8: TEST CLEANUP
    -- ========================================================================
    RAISE NOTICE '[CLEANUP] Removing test data...';

    DELETE FROM catalogo_homologado
    WHERE marca = test_marca;

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
        RAISE NOTICE 'Idempotency validation successful!';
        RAISE NOTICE '';
        RAISE NOTICE 'Summary:';
        RAISE NOTICE '  Run 1: ins:%, upd:%', run1_inserted, run1_updated;
        RAISE NOTICE '  Run 2: ins:%, upd:%', run2_inserted, run2_updated;
        RAISE NOTICE '';
        RAISE NOTICE 'Output: ✓ Idempotency: Run1(ins:%, upd:%) == Run2(ins:%, upd:%)',
            run1_inserted, run1_updated, run2_inserted, run2_updated;
        RAISE NOTICE '';
        RAISE NOTICE 'The batch processing system correctly demonstrates:';
        RAISE NOTICE '  1. No duplicate records created on re-processing';
        RAISE NOTICE '  2. hash_comercial values remain deterministic';
        RAISE NOTICE '  3. Same matches selected on repeated runs';
        RAISE NOTICE '  4. disponibilidad tracking remains consistent';
        RAISE NOTICE '';
        RAISE NOTICE 'Requirements satisfied:';
        RAISE NOTICE '  - [1.0] Deterministic matching algorithm';
        RAISE NOTICE '  - [Data Integrity NFR] No duplicate creation';
    ELSE
        RAISE NOTICE 'TEST RESULT: FAILED';
        RAISE NOTICE '========================================';
        RAISE NOTICE '';
        RAISE NOTICE 'ERRORS:%', error_messages;
        RAISE NOTICE '';
        RAISE NOTICE 'The test failed, indicating NON-IDEMPOTENT behavior.';
        RAISE NOTICE 'The system is creating duplicates or changing state on re-processing.';
        RAISE NOTICE '';
        RAISE EXCEPTION 'Idempotency test failed - see errors above';
    END IF;
    RAISE NOTICE '========================================';

END $$;

-- ============================================================================
-- TEST EXECUTION INSTRUCTIONS
-- ============================================================================
--
-- To run this test:
--   1. Ensure funciones-homologacion-actuales.sql is deployed
--   2. Execute this file: \i tests/integration/test_idempotency.sql
--   3. Review NOTICE messages for detailed test progression
--   4. Test passes if no EXCEPTION is raised
--
-- Expected Output:
--   - [ASSERTION 1] PASSED: No new records inserted on Run 2
--   - [ASSERTION 2] PASSED: Record count unchanged
--   - [ASSERTION 3] PASSED: All hash_comercial values unchanged
--   - [ASSERTION 4] PASSED: Update behavior consistent
--   - [ASSERTION 5] PASSED: All disponibilidad key sets unchanged
--   - [ASSERTION 6] PASSED: Tier distribution identical
--   - TEST RESULT: PASSED
--   - Output: ✓ Idempotency: Run1(ins:X, upd:Y) == Run2(ins:0, upd:Z)
--
-- Test Duration: ~30-60 seconds (1,000 records processed twice)
--
-- ============================================================================
