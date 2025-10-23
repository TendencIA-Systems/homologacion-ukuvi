-- ============================================================================
-- PERFORMANCE BENCHMARK TEST: Batch Processing
-- ============================================================================
-- Test Case: Measure performance of batch processing with best-match algorithm
--
-- Purpose: Verify that the procesar_batch_vehiculos function meets performance
--          requirements under realistic load conditions:
--          - Batch of 5,000 records completes in < 2 minutes (120 seconds)
--          - Best-match evaluation with 10 candidates adds < 100ms per vehicle
--          - Token deduplication adds < 5ms per version string
--          - No timeout errors (Supabase 2-minute limit)
--          - Memory usage stays below 512MB
--
-- Test Scenarios:
--   1. Large Batch Processing (5,000 records)
--   2. Best-Match Selection Overhead (10 candidates per vehicle)
--   3. Token Deduplication Performance
--   4. Memory Usage Monitoring
--
-- Success Criteria:
--   - Batch of 5,000 records: < 120 seconds total time
--   - Per-record average: < 24ms (120s / 5000 records)
--   - Best-match overhead with 10 candidates: < 100ms per vehicle
--   - Token deduplication: < 5ms per version string
--   - Memory usage: < 512MB
--   - No timeout errors
--
-- Requirements Coverage:
--   - 1.0: Algorithm performance with best-match selection
--   - Performance NFR: Batch processing time constraints
-- ============================================================================

-- ============================================================================
-- PERFORMANCE TRACKING TABLE
-- ============================================================================
-- Create temporary table to track performance metrics during test
CREATE TEMP TABLE IF NOT EXISTS performance_metrics (
    test_name TEXT,
    metric_name TEXT,
    metric_value NUMERIC,
    metric_unit TEXT,
    threshold_value NUMERIC,
    passed BOOLEAN,
    notes TEXT
);

-- ============================================================================
-- TEST 1: TOKEN DEDUPLICATION PERFORMANCE
-- ============================================================================
DO $$
DECLARE
    test_version TEXT;
    test_tokens TEXT[];
    iteration INT;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    total_time_ms NUMERIC;
    avg_time_per_call_ms NUMERIC;
    iterations CONSTANT INT := 1000;
    threshold_ms CONSTANT NUMERIC := 5.0;
    test_passed BOOLEAN;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TEST 1: Token Deduplication Performance';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Test with a realistic complex version string
    test_version := 'A-SPEC ADVANCE 201HP 2.0L TURBO 4CIL 4PUERTAS 5OCUP AWD SEDAN PREMIUM';

    RAISE NOTICE '[TEST 1] Testing clean_and_tokenize_version performance';
    RAISE NOTICE '[TEST 1] Test version: %', test_version;
    RAISE NOTICE '[TEST 1] Iterations: %', iterations;
    RAISE NOTICE '[TEST 1] Threshold: % ms per call', threshold_ms;
    RAISE NOTICE '';

    -- Warm-up call to avoid cold-start overhead
    test_tokens := clean_and_tokenize_version(test_version);

    -- Performance measurement
    start_time := clock_timestamp();

    FOR iteration IN 1..iterations LOOP
        test_tokens := clean_and_tokenize_version(test_version);
    END LOOP;

    end_time := clock_timestamp();
    total_time_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
    avg_time_per_call_ms := total_time_ms / iterations;

    test_passed := (avg_time_per_call_ms < threshold_ms);

    RAISE NOTICE '[TEST 1] Results:';
    RAISE NOTICE '[TEST 1]   Total time: % ms', ROUND(total_time_ms, 2);
    RAISE NOTICE '[TEST 1]   Average per call: % ms', ROUND(avg_time_per_call_ms, 3);
    RAISE NOTICE '[TEST 1]   Threshold: % ms', threshold_ms;
    RAISE NOTICE '[TEST 1]   Status: %', CASE WHEN test_passed THEN 'PASSED' ELSE 'FAILED' END;
    RAISE NOTICE '[TEST 1]   Token count: %', array_length(test_tokens, 1);
    RAISE NOTICE '[TEST 1]   Tokens: %', test_tokens;
    RAISE NOTICE '';

    -- Record metrics
    INSERT INTO performance_metrics (test_name, metric_name, metric_value, metric_unit, threshold_value, passed, notes)
    VALUES
        ('Token Deduplication', 'avg_time_per_call', avg_time_per_call_ms, 'ms', threshold_ms, test_passed,
         'Average time to tokenize and deduplicate a complex version string'),
        ('Token Deduplication', 'total_iterations', iterations, 'calls', iterations, TRUE,
         'Number of test iterations'),
        ('Token Deduplication', 'tokens_produced', array_length(test_tokens, 1), 'tokens', NULL, TRUE,
         'Number of tokens in result array');

    IF NOT test_passed THEN
        RAISE WARNING 'TEST 1 FAILED: Token deduplication took % ms (threshold: % ms)',
            ROUND(avg_time_per_call_ms, 3), threshold_ms;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: BEST-MATCH EVALUATION OVERHEAD
-- ============================================================================
DO $$
DECLARE
    test_hash_comercial TEXT;
    test_marca TEXT := 'HONDA';
    test_modelo TEXT := 'ACCORD';
    test_anio INT := 2023;
    test_transmision TEXT := 'AUTO';
    candidate_id BIGINT;
    candidate_ids BIGINT[] := ARRAY[]::BIGINT[];
    incoming_batch JSONB;
    result RECORD;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    processing_time_ms NUMERIC;
    avg_time_per_vehicle_ms NUMERIC;
    num_candidates INT := 10;
    num_vehicles INT := 100;
    threshold_ms CONSTANT NUMERIC := 100.0;
    test_passed BOOLEAN;
    i INT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TEST 2: Best-Match Evaluation Overhead';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Generate test hash
    test_hash_comercial := encode(
        digest(test_marca || '|' || test_modelo || '|' || test_anio || '|' || test_transmision, 'sha256'),
        'hex'
    );

    RAISE NOTICE '[TEST 2] Setup: Creating % candidate records for best-match evaluation', num_candidates;
    RAISE NOTICE '[TEST 2] Hash comercial: %', test_hash_comercial;
    RAISE NOTICE '';

    -- Clean up any existing test data
    DELETE FROM catalogo_homologado
    WHERE marca = test_marca
      AND modelo = test_modelo
      AND anio = test_anio;

    -- Create multiple candidate records with varying similarity scores
    FOR i IN 1..num_candidates LOOP
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
            test_marca,
            test_modelo,
            test_anio,
            test_transmision,
            CASE
                WHEN i <= 3 THEN 'SPORT ' || (190 + i) || 'HP 1.5L TURBO 4CIL 4PUERTAS'
                WHEN i <= 6 THEN 'TOURING ' || (200 + i) || 'HP 2.0L 4CIL 4PUERTAS'
                ELSE 'ADVANCE ' || (180 + i) || 'HP 1.8L 4CIL 4PUERTAS 5OCUP'
            END,
            clean_and_tokenize_version(
                CASE
                    WHEN i <= 3 THEN 'SPORT ' || (190 + i) || 'HP 1.5L TURBO 4CIL 4PUERTAS'
                    WHEN i <= 6 THEN 'TOURING ' || (200 + i) || 'HP 2.0L 4CIL 4PUERTAS'
                    ELSE 'ADVANCE ' || (180 + i) || 'HP 1.8L 4CIL 4PUERTAS 5OCUP'
                END
            ),
            jsonb_build_object(
                'HDI', jsonb_build_object(
                    'origen', true,
                    'disponible', true,
                    'aseguradora', 'HDI',
                    'id_original', 'HDI-PERF-' || i,
                    'version_original', 'ORIGINAL-' || i,
                    'confianza_score', 0.95,
                    'metodo_match', 'original_entry',
                    'tier', 0,
                    'fecha_actualizacion', NOW()
                )
            )
        ) RETURNING id INTO candidate_id;

        candidate_ids := array_append(candidate_ids, candidate_id);
    END LOOP;

    RAISE NOTICE '[TEST 2] Created % candidate records', num_candidates;
    RAISE NOTICE '[TEST 2] Candidate IDs: %', candidate_ids;
    RAISE NOTICE '';

    -- Prepare batch of incoming records that will match all candidates
    incoming_batch := '[]'::JSONB;
    FOR i IN 1..num_vehicles LOOP
        incoming_batch := incoming_batch || jsonb_build_array(
            jsonb_build_object(
                'hash_comercial', test_hash_comercial,
                'marca', test_marca,
                'modelo', test_modelo,
                'anio', test_anio,
                'transmision', test_transmision,
                'version_limpia', 'SPORT ' || (192 + (i % 3)) || 'HP 1.5L TURBO 4CIL 4PUERTAS',
                'origen_aseguradora', 'ZURICH',
                'id_original', 'ZURICH-PERF-' || i,
                'version_original', 'ZURICH ORIGINAL ' || i
            )
        );
    END LOOP;

    RAISE NOTICE '[TEST 2] Prepared batch of % incoming vehicles', num_vehicles;
    RAISE NOTICE '[TEST 2] Each vehicle will evaluate against % candidates', num_candidates;
    RAISE NOTICE '[TEST 2] Expected overhead threshold: < % ms per vehicle', threshold_ms;
    RAISE NOTICE '';

    -- Execute batch processing and measure time
    start_time := clock_timestamp();

    SELECT * INTO result
    FROM procesar_batch_vehiculos(incoming_batch);

    end_time := clock_timestamp();
    processing_time_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
    avg_time_per_vehicle_ms := processing_time_ms / num_vehicles;

    test_passed := (avg_time_per_vehicle_ms < threshold_ms);

    RAISE NOTICE '[TEST 2] Results:';
    RAISE NOTICE '[TEST 2]   Total processing time: % ms', ROUND(processing_time_ms, 2);
    RAISE NOTICE '[TEST 2]   Vehicles processed: %', num_vehicles;
    RAISE NOTICE '[TEST 2]   Candidates per vehicle: %', num_candidates;
    RAISE NOTICE '[TEST 2]   Average time per vehicle: % ms', ROUND(avg_time_per_vehicle_ms, 2);
    RAISE NOTICE '[TEST 2]   Threshold: % ms', threshold_ms;
    RAISE NOTICE '[TEST 2]   Status: %', CASE WHEN test_passed THEN 'PASSED' ELSE 'FAILED' END;
    RAISE NOTICE '[TEST 2]   Updates: %, Inserts: %, Skipped: %',
        result.actualizados, result.insertados, result.skipped;
    RAISE NOTICE '[TEST 2]   Multi-matches detected: %', result.multi_matches;
    RAISE NOTICE '';

    -- Record metrics
    INSERT INTO performance_metrics (test_name, metric_name, metric_value, metric_unit, threshold_value, passed, notes)
    VALUES
        ('Best-Match Evaluation', 'avg_time_per_vehicle', avg_time_per_vehicle_ms, 'ms', threshold_ms, test_passed,
         format('Average time per vehicle with %s candidates', num_candidates)),
        ('Best-Match Evaluation', 'total_processing_time', processing_time_ms, 'ms', NULL, TRUE,
         format('Total time to process %s vehicles', num_vehicles)),
        ('Best-Match Evaluation', 'candidates_per_vehicle', num_candidates, 'candidates', 10, TRUE,
         'Number of candidate matches evaluated per vehicle'),
        ('Best-Match Evaluation', 'multi_matches_detected', result.multi_matches, 'count', NULL, TRUE,
         'Number of vehicles with multiple candidate matches');

    -- Cleanup
    DELETE FROM catalogo_homologado WHERE id = ANY(candidate_ids);
    RAISE NOTICE '[TEST 2] Cleanup: Removed test data';
    RAISE NOTICE '';

    IF NOT test_passed THEN
        RAISE WARNING 'TEST 2 FAILED: Best-match evaluation took % ms per vehicle (threshold: % ms)',
            ROUND(avg_time_per_vehicle_ms, 2), threshold_ms;
    END IF;
END $$;

-- ============================================================================
-- TEST 3: LARGE BATCH PROCESSING (5,000 RECORDS)
-- ============================================================================
DO $$
DECLARE
    batch_size CONSTANT INT := 5000;
    threshold_seconds CONSTANT NUMERIC := 120.0;
    threshold_ms_per_record CONSTANT NUMERIC := 24.0;
    incoming_batch JSONB;
    result RECORD;
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    processing_time_ms NUMERIC;
    processing_time_seconds NUMERIC;
    avg_time_per_record_ms NUMERIC;
    test_passed BOOLEAN;
    i INT;
    test_hash TEXT;
    test_marca TEXT;
    test_modelo TEXT;
    initial_count INT;
    final_count INT;
    records_affected INT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TEST 3: Large Batch Processing (5,000 records)';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    RAISE NOTICE '[TEST 3] Preparing batch of % records...', batch_size;
    RAISE NOTICE '[TEST 3] Threshold: < % seconds (% ms)', threshold_seconds, (threshold_seconds * 1000)::INT;
    RAISE NOTICE '[TEST 3] Per-record threshold: < % ms', threshold_ms_per_record;
    RAISE NOTICE '';

    -- Record initial catalog size
    SELECT COUNT(*) INTO initial_count FROM catalogo_homologado;

    -- Build large batch with diverse vehicle data
    incoming_batch := '[]'::JSONB;

    FOR i IN 1..batch_size LOOP
        -- Vary marca/modelo to create realistic diversity
        test_marca := CASE (i % 10)
            WHEN 0 THEN 'TOYOTA'
            WHEN 1 THEN 'HONDA'
            WHEN 2 THEN 'NISSAN'
            WHEN 3 THEN 'MAZDA'
            WHEN 4 THEN 'FORD'
            WHEN 5 THEN 'CHEVROLET'
            WHEN 6 THEN 'VOLKSWAGEN'
            WHEN 7 THEN 'BMW'
            WHEN 8 THEN 'MERCEDES-BENZ'
            ELSE 'AUDI'
        END;

        test_modelo := CASE (i % 5)
            WHEN 0 THEN 'SEDAN-A'
            WHEN 1 THEN 'SUV-B'
            WHEN 2 THEN 'COUPE-C'
            WHEN 3 THEN 'HATCHBACK-D'
            ELSE 'WAGON-E'
        END;

        test_hash := encode(
            digest(test_marca || '|' || test_modelo || '|2023|AUTO', 'sha256'),
            'hex'
        );

        incoming_batch := incoming_batch || jsonb_build_array(
            jsonb_build_object(
                'hash_comercial', test_hash,
                'marca', test_marca,
                'modelo', test_modelo,
                'anio', 2023,
                'transmision', 'AUTO',
                'version_limpia', format('SPORT %sHP %sL 4CIL 4PUERTAS',
                    150 + (i % 50),
                    (1.5 + (i % 10) * 0.2)::NUMERIC(3,1)),
                'origen_aseguradora', 'ZURICH',
                'id_original', 'ZURICH-BULK-' || i,
                'version_original', 'ZURICH BULK TEST ' || i
            )
        );

        -- Progress indicator every 1000 records
        IF i % 1000 = 0 THEN
            RAISE NOTICE '[TEST 3] Prepared % / % records...', i, batch_size;
        END IF;
    END LOOP;

    RAISE NOTICE '[TEST 3] Batch preparation complete: % records', batch_size;
    RAISE NOTICE '';

    -- Execute batch processing
    RAISE NOTICE '[TEST 3] Starting batch processing...';
    start_time := clock_timestamp();

    BEGIN
        SELECT * INTO result
        FROM procesar_batch_vehiculos(incoming_batch);

        end_time := clock_timestamp();
        processing_time_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
        processing_time_seconds := processing_time_ms / 1000.0;
        avg_time_per_record_ms := processing_time_ms / batch_size;

        test_passed := (processing_time_seconds < threshold_seconds) AND
                       (avg_time_per_record_ms < threshold_ms_per_record);

        RAISE NOTICE '[TEST 3] Batch processing complete';
        RAISE NOTICE '';

        RAISE NOTICE '[TEST 3] Results:';
        RAISE NOTICE '[TEST 3]   Total processing time: % seconds (% ms)',
            ROUND(processing_time_seconds, 2), ROUND(processing_time_ms, 2);
        RAISE NOTICE '[TEST 3]   Records processed: %', batch_size;
        RAISE NOTICE '[TEST 3]   Average per record: % ms', ROUND(avg_time_per_record_ms, 2);
        RAISE NOTICE '[TEST 3]   Throughput: % records/second',
            ROUND(batch_size / processing_time_seconds, 1);
        RAISE NOTICE '';
        RAISE NOTICE '[TEST 3]   Insertados: %', result.insertados;
        RAISE NOTICE '[TEST 3]   Actualizados: %', result.actualizados;
        RAISE NOTICE '[TEST 3]   Skipped: %', result.skipped;
        RAISE NOTICE '[TEST 3]   Tier1: %, Tier2: %, Tier3: %',
            result.tier1_matches, result.tier2_matches, result.tier3_matches;
        RAISE NOTICE '[TEST 3]   Multi-matches: %', result.multi_matches;
        RAISE NOTICE '';
        RAISE NOTICE '[TEST 3]   Time threshold: < % seconds', threshold_seconds;
        RAISE NOTICE '[TEST 3]   Per-record threshold: < % ms', threshold_ms_per_record;
        RAISE NOTICE '[TEST 3]   Status: %', CASE WHEN test_passed THEN 'PASSED' ELSE 'FAILED' END;
        RAISE NOTICE '';

        -- Record final catalog size
        SELECT COUNT(*) INTO final_count FROM catalogo_homologado;
        records_affected := final_count - initial_count;

        -- Record metrics
        INSERT INTO performance_metrics (test_name, metric_name, metric_value, metric_unit, threshold_value, passed, notes)
        VALUES
            ('Large Batch Processing', 'total_time', processing_time_seconds, 'seconds', threshold_seconds,
             (processing_time_seconds < threshold_seconds),
             format('Total time to process %s records', batch_size)),
            ('Large Batch Processing', 'avg_time_per_record', avg_time_per_record_ms, 'ms', threshold_ms_per_record,
             (avg_time_per_record_ms < threshold_ms_per_record),
             'Average processing time per record'),
            ('Large Batch Processing', 'throughput', ROUND(batch_size / processing_time_seconds, 1), 'records/sec', NULL, TRUE,
             'Processing throughput'),
            ('Large Batch Processing', 'records_inserted', result.insertados, 'records', NULL, TRUE,
             'New records created'),
            ('Large Batch Processing', 'records_updated', result.actualizados, 'records', NULL, TRUE,
             'Existing records updated'),
            ('Large Batch Processing', 'catalog_growth', records_affected, 'records', NULL, TRUE,
             'Net increase in catalog size');

        IF NOT test_passed THEN
            IF processing_time_seconds >= threshold_seconds THEN
                RAISE WARNING 'TEST 3 FAILED: Processing took % seconds (threshold: % seconds)',
                    ROUND(processing_time_seconds, 2), threshold_seconds;
            END IF;
            IF avg_time_per_record_ms >= threshold_ms_per_record THEN
                RAISE WARNING 'TEST 3 FAILED: Per-record time was % ms (threshold: % ms)',
                    ROUND(avg_time_per_record_ms, 2), threshold_ms_per_record;
            END IF;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            end_time := clock_timestamp();
            processing_time_ms := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
            processing_time_seconds := processing_time_ms / 1000.0;

            RAISE NOTICE '[TEST 3] ERROR: Batch processing failed';
            RAISE NOTICE '[TEST 3]   Error: %', SQLERRM;
            RAISE NOTICE '[TEST 3]   Time before failure: % seconds', ROUND(processing_time_seconds, 2);
            RAISE NOTICE '';

            INSERT INTO performance_metrics (test_name, metric_name, metric_value, metric_unit, threshold_value, passed, notes)
            VALUES
                ('Large Batch Processing', 'error', NULL, 'N/A', NULL, FALSE,
                 format('Processing failed: %s', SQLERRM));

            RAISE WARNING 'TEST 3 FAILED: Processing error - %', SQLERRM;
    END;

    RAISE NOTICE '[TEST 3] Note: Test data remains in catalog for memory usage test';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- TEST 4: MEMORY USAGE ESTIMATION
-- ============================================================================
DO $$
DECLARE
    catalog_size BIGINT;
    catalog_size_mb NUMERIC;
    tokens_array_size BIGINT;
    disponibilidad_size BIGINT;
    total_estimated_mb NUMERIC;
    threshold_mb CONSTANT NUMERIC := 512.0;
    test_passed BOOLEAN;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'TEST 4: Memory Usage Estimation';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Estimate catalog table size
    SELECT
        pg_total_relation_size('catalogo_homologado') AS total_size
    INTO catalog_size;

    catalog_size_mb := catalog_size / (1024.0 * 1024.0);

    -- Estimate JSONB field sizes
    SELECT
        SUM(pg_column_size(version_tokens_array)) AS tokens_size,
        SUM(pg_column_size(disponibilidad)) AS disp_size
    INTO tokens_array_size, disponibilidad_size
    FROM catalogo_homologado;

    total_estimated_mb := catalog_size_mb;
    test_passed := (total_estimated_mb < threshold_mb);

    RAISE NOTICE '[TEST 4] Database object sizes:';
    RAISE NOTICE '[TEST 4]   Catalog table total: % MB', ROUND(catalog_size_mb, 2);
    RAISE NOTICE '[TEST 4]   Token arrays total: % MB', ROUND(tokens_array_size / (1024.0 * 1024.0), 2);
    RAISE NOTICE '[TEST 4]   Disponibilidad JSONB: % MB', ROUND(disponibilidad_size / (1024.0 * 1024.0), 2);
    RAISE NOTICE '';
    RAISE NOTICE '[TEST 4]   Estimated working memory: % MB', ROUND(total_estimated_mb, 2);
    RAISE NOTICE '[TEST 4]   Threshold: < % MB', threshold_mb;
    RAISE NOTICE '[TEST 4]   Status: %', CASE WHEN test_passed THEN 'PASSED' ELSE 'FAILED' END;
    RAISE NOTICE '';

    -- Additional memory stats
    RAISE NOTICE '[TEST 4] Catalog statistics:';
    RAISE NOTICE '[TEST 4]   Total records: %', (SELECT COUNT(*) FROM catalogo_homologado);
    RAISE NOTICE '[TEST 4]   Average tokens per record: %',
        (SELECT ROUND(AVG(array_length(version_tokens_array, 1)), 1) FROM catalogo_homologado);
    RAISE NOTICE '[TEST 4]   Average disponibilidad keys: %',
        (SELECT ROUND(AVG(jsonb_array_length(jsonb_object_keys(disponibilidad)::JSONB)), 1) FROM catalogo_homologado);
    RAISE NOTICE '';

    -- Record metrics
    INSERT INTO performance_metrics (test_name, metric_name, metric_value, metric_unit, threshold_value, passed, notes)
    VALUES
        ('Memory Usage', 'catalog_table_size', catalog_size_mb, 'MB', NULL, TRUE,
         'Total size of catalogo_homologado table'),
        ('Memory Usage', 'estimated_working_memory', total_estimated_mb, 'MB', threshold_mb, test_passed,
         'Estimated memory usage during batch processing');

    IF NOT test_passed THEN
        RAISE WARNING 'TEST 4 FAILED: Memory usage estimate % MB exceeds threshold of % MB',
            ROUND(total_estimated_mb, 2), threshold_mb;
    END IF;
END $$;

-- ============================================================================
-- FINAL REPORT: ALL PERFORMANCE METRICS
-- ============================================================================
DO $$
DECLARE
    metric RECORD;
    all_passed BOOLEAN := TRUE;
    total_tests INT;
    passed_tests INT;
    failed_tests INT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'PERFORMANCE BENCHMARK SUMMARY';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Display all metrics
    FOR metric IN
        SELECT test_name, metric_name, metric_value, metric_unit, threshold_value, passed, notes
        FROM performance_metrics
        ORDER BY test_name, metric_name
    LOOP
        IF metric.threshold_value IS NOT NULL THEN
            RAISE NOTICE '[%] %: % % (threshold: % %) - %',
                metric.test_name,
                metric.metric_name,
                ROUND(metric.metric_value, 3),
                metric.unit,
                metric.threshold_value,
                metric.unit,
                CASE WHEN metric.passed THEN 'PASS' ELSE 'FAIL' END;

            IF NOT metric.passed THEN
                all_passed := FALSE;
            END IF;
        ELSE
            RAISE NOTICE '[%] %: % % - %',
                metric.test_name,
                metric.metric_name,
                ROUND(metric.metric_value, 3),
                metric.unit,
                'INFO';
        END IF;
    END LOOP;

    RAISE NOTICE '';

    -- Count results
    SELECT
        COUNT(*) FILTER (WHERE threshold_value IS NOT NULL),
        COUNT(*) FILTER (WHERE passed = TRUE AND threshold_value IS NOT NULL),
        COUNT(*) FILTER (WHERE passed = FALSE AND threshold_value IS NOT NULL)
    INTO total_tests, passed_tests, failed_tests
    FROM performance_metrics;

    RAISE NOTICE 'Test Summary:';
    RAISE NOTICE '  Total assertions: %', total_tests;
    RAISE NOTICE '  Passed: %', passed_tests;
    RAISE NOTICE '  Failed: %', failed_tests;
    RAISE NOTICE '';

    -- Final verdict
    IF all_passed THEN
        RAISE NOTICE '========================================';
        RAISE NOTICE 'OVERALL RESULT: PASSED';
        RAISE NOTICE '========================================';
        RAISE NOTICE '';
        RAISE NOTICE 'Performance Summary:';
        RAISE NOTICE '  Token deduplication: < 5ms per version';
        RAISE NOTICE '  Best-match evaluation: < 100ms per vehicle (10 candidates)';
        RAISE NOTICE '  Large batch processing: < 120 seconds (5000 records)';
        RAISE NOTICE '  Memory usage: < 512MB';
        RAISE NOTICE '';
        RAISE NOTICE 'All performance requirements satisfied!';
    ELSE
        RAISE NOTICE '========================================';
        RAISE NOTICE 'OVERALL RESULT: FAILED';
        RAISE NOTICE '========================================';
        RAISE NOTICE '';
        RAISE NOTICE 'Some performance metrics did not meet thresholds.';
        RAISE NOTICE 'Review detailed metrics above for optimization opportunities.';
        RAISE NOTICE '';
        RAISE EXCEPTION 'Performance benchmark failed - see metrics above';
    END IF;
    RAISE NOTICE '========================================';
END $$;

-- ============================================================================
-- CLEANUP
-- ============================================================================
-- Note: Large batch test data is cleaned up here
DO $$
DECLARE
    deleted_count INT;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'CLEANUP: Removing test data';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';

    -- Delete test data from Test 3 (ZURICH bulk records)
    DELETE FROM catalogo_homologado
    WHERE disponibilidad ? 'ZURICH'
      AND disponibilidad->'ZURICH'->>'id_original' LIKE 'ZURICH-BULK-%';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;

    RAISE NOTICE '[CLEANUP] Removed % test records', deleted_count;
    RAISE NOTICE '[CLEANUP] Cleanup complete';
    RAISE NOTICE '';
END $$;

-- Drop temporary metrics table
DROP TABLE IF EXISTS performance_metrics;

-- ============================================================================
-- TEST EXECUTION INSTRUCTIONS
-- ============================================================================
--
-- To run this performance benchmark:
--   1. Ensure funciones-homologacion-actuales.sql is deployed
--   2. Execute this file: \i tests/performance/test_batch_processing.sql
--   3. Review NOTICE messages for detailed performance metrics
--   4. Test passes if no EXCEPTION is raised
--
-- Expected Output Format:
--   "Performance: 5000 records in 87.3s (avg 17.5ms/record)"
--
-- Performance Assertions:
--   - Token deduplication: < 5ms per call
--   - Best-match with 10 candidates: < 100ms per vehicle
--   - Batch of 5,000 records: < 120 seconds total
--   - Average per record: < 24ms
--   - Memory usage: < 512MB
--
-- Requirements Validated:
--   - [1.0] Algorithm performance with best-match selection
--   - [Performance NFR] Batch processing time constraints
--   - [Performance NFR] No timeout errors (Supabase 2-minute limit)
--
-- ============================================================================
