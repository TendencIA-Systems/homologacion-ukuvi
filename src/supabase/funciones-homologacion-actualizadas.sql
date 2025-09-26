-- =====================================================
-- SISTEMA DE HOMOLOGACION VEHICULAR v7.0 
-- Simplified Jaccard-based matching for normalized data
-- =====================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =====================================================
-- FUNCION 1: TOKENIZACION v5 - Optimized for matching
-- =====================================================
DROP FUNCTION IF EXISTS tokenize_version CASCADE;
CREATE OR REPLACE FUNCTION tokenize_version(version_text text)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    tokens text[];
    normalized_text text;
BEGIN
    IF version_text IS NULL OR version_text = '' THEN
        RETURN ARRAY[]::text[];
    END IF;

    -- Uppercase and clean
    normalized_text := UPPER(TRIM(version_text));

    -- Remove accents
    normalized_text := translate(
        normalized_text,
        'ÁÉÍÓÚÄËÏÖÜÑÀÈÌÒÙÂÊÎÔÛ',
        'AEIOUAEIOUNAEIOUAEIOUU'
    );

    -- Normalize spaces
    normalized_text := regexp_replace(normalized_text, '\s+', ' ', 'g');
    
    -- Protect decimal points in engine sizes (1.5L, 2.0L)
    normalized_text := regexp_replace(
        normalized_text,
        '([0-9]+)\.([0-9]+)([A-Z]*)',
        '\1POINT\2\3',
        'g'
    );

    -- Clean non-alphanumeric but keep protected decimals
    normalized_text := regexp_replace(normalized_text, '[^A-Z0-9]+', ' ', 'g');
    normalized_text := TRIM(normalized_text);

    -- Split and process tokens
    SELECT array_agg(DISTINCT final_token ORDER BY final_token)
    INTO tokens
    FROM (
        SELECT CASE
            -- Restore decimal points
            WHEN raw_token ~ '^[0-9]+POINT[0-9]+L?$' THEN
                regexp_replace(raw_token, '^([0-9]+)POINT([0-9]+)(L?)$', '\1.\2\3')
            -- Keep meaningful tokens (2+ chars, not common words)
            WHEN length(raw_token) >= 2 AND 
                 raw_token NOT IN ('DE', 'LA', 'EL', 'LOS', 'LAS', 'CON', 'SIN', 'DEL', 'AL', 'POR', 'EN', 'Y', 'O', 'UN', 'UNA') AND
                 raw_token !~ '^[0-9]$' THEN
                raw_token
            -- Keep single digits if they're likely door/occupant counts
            WHEN raw_token ~ '^[2-9]$' THEN
                raw_token
            ELSE NULL
        END AS final_token
        FROM (
            SELECT unnest(string_to_array(normalized_text, ' ')) AS raw_token
        ) base
    ) transformed
    WHERE final_token IS NOT NULL;

    RETURN COALESCE(tokens, ARRAY[]::text[]);
END;
$$;

-- =====================================================
-- FUNCION 2: SIMPLIFIED JACCARD MATCH v7
-- Optimized for same hash_comercial comparisons
-- =====================================================
DROP FUNCTION IF EXISTS calculate_jaccard_match CASCADE;
CREATE OR REPLACE FUNCTION calculate_jaccard_match(
    tokens1 text[],
    tokens2 text[],
    is_same_insurer boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    -- Token counts
    tokens1_count int := COALESCE(array_length(tokens1, 1), 0);
    tokens2_count int := COALESCE(array_length(tokens2, 1), 0);
    
    -- Set operations
    shared_tokens text[];
    all_tokens text[];
    unique_to_1 text[];
    unique_to_2 text[];
    intersection_count int := 0;
    union_count int := 0;
    
    -- Important token detection
    critical_specs text[];
    critical_in_1 int := 0;
    critical_in_2 int := 0;
    critical_shared int := 0;
    
    -- Scores
    jaccard_score numeric := 0;
    weighted_jaccard numeric := 0;
    containment_score numeric := 0;
    match_confidence text;
    should_match boolean := false;
    final_score numeric := 0;
BEGIN
    -- Handle empty cases
    IF tokens1_count = 0 OR tokens2_count = 0 THEN
        RETURN jsonb_build_object(
            'jaccard_score', 0,
            'should_match', false,
            'reason', 'empty_tokens',
            'tokens1_count', tokens1_count,
            'tokens2_count', tokens2_count
        );
    END IF;

    -- Calculate intersection and union
    SELECT array_agg(DISTINCT t) INTO shared_tokens
    FROM unnest(tokens1) t
    WHERE t = ANY(tokens2);
    
    intersection_count := COALESCE(array_length(shared_tokens, 1), 0);

    SELECT array_agg(DISTINCT t) INTO all_tokens
    FROM (
        SELECT unnest(tokens1) AS t
        UNION
        SELECT unnest(tokens2) AS t
    ) combined;
    
    union_count := COALESCE(array_length(all_tokens, 1), 0);

    -- Calculate unique tokens
    SELECT array_agg(t) INTO unique_to_1
    FROM unnest(tokens1) t
    WHERE NOT (t = ANY(tokens2));
    
    SELECT array_agg(t) INTO unique_to_2
    FROM unnest(tokens2) t
    WHERE NOT (t = ANY(tokens1));

    -- Define critical tokens (high weight for matching)
    critical_specs := ARRAY[
        -- Engine specs (most important)
        '1.0L', '1.2L', '1.3L', '1.4L', '1.5L', '1.6L', '1.8L', 
        '2.0L', '2.2L', '2.3L', '2.4L', '2.5L', '2.7L', '2.8L',
        '3.0L', '3.2L', '3.3L', '3.5L', '3.6L', '3.7L', '3.8L',
        '4.0L', '4.2L', '4.3L', '4.6L', '4.7L', '5.0L', '5.3L', 
        '5.7L', '6.0L', '6.2L', '6.4L',
        -- Cylinders
        '3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL',
        -- Performance
        'TURBO', 'BITURBO', 'SUPERCHARGED',
        -- Trims (important for differentiation)
        'SPORT', 'LUXURY', 'PREMIUM', 'BASE', 'LIMITED',
        'GT', 'GTI', 'RS', 'ST', 'SS', 'AMG', 'M3', 'M5',
        -- Special editions
        'PEPPER', 'SALT', 'CHILI', 'CHILLI',
        'BAKER', 'STREET', 'BAYSWATER', 'HIGHGATE',
        -- Body types
        'SEDAN', 'SUV', 'HATCHBACK', 'COUPE', 'CONVERTIBLE', 
        'PICKUP', 'VAN', 'WAGON'
    ];

    -- Count critical tokens
    SELECT COUNT(*) INTO critical_in_1
    FROM unnest(tokens1) t
    WHERE t = ANY(critical_specs);
    
    SELECT COUNT(*) INTO critical_in_2
    FROM unnest(tokens2) t
    WHERE t = ANY(critical_specs);
    
    SELECT COUNT(*) INTO critical_shared
    FROM unnest(shared_tokens) t
    WHERE t = ANY(critical_specs);

    -- Calculate scores
    IF union_count > 0 THEN
        jaccard_score := intersection_count::numeric / union_count::numeric;
    END IF;
    
    -- Containment: how much of the smaller set is in the larger
    IF LEAST(tokens1_count, tokens2_count) > 0 THEN
        containment_score := intersection_count::numeric / LEAST(tokens1_count, tokens2_count)::numeric;
    END IF;

    -- Calculate weighted Jaccard (give more weight to critical tokens)
    IF union_count > 0 THEN
        weighted_jaccard := (
            (intersection_count + (critical_shared * 0.5))::numeric / 
            (union_count + (GREATEST(critical_in_1, critical_in_2) * 0.5))::numeric
        );
    END IF;

    -- SIMPLIFIED MATCHING LOGIC
    -- Since we're already within same hash_comercial, be more lenient
    
    -- Case 1: Identical or near-identical
    IF jaccard_score >= 0.85 THEN
        should_match := true;
        match_confidence := 'high';
        final_score := jaccard_score;
        
    -- Case 2: Very short versions (1-3 tokens) with perfect containment
    ELSIF LEAST(tokens1_count, tokens2_count) <= 3 AND containment_score = 1.0 THEN
        should_match := true;
        match_confidence := 'high_subset';
        final_score := 0.80 + (0.05 * LEAST(tokens1_count, tokens2_count));
        
    -- Case 3: High containment with critical token match
    ELSIF containment_score >= 0.75 AND critical_shared >= 1 THEN
        should_match := true;
        match_confidence := 'good_containment';
        final_score := containment_score * 0.9 + (critical_shared * 0.02);
        
    -- Case 4: Good weighted Jaccard (considers critical tokens)
    ELSIF weighted_jaccard >= 0.60 THEN
        should_match := true;
        match_confidence := 'weighted_match';
        final_score := weighted_jaccard;
        
    -- Case 5: Moderate Jaccard with shared critical specs
    ELSIF jaccard_score >= 0.45 AND critical_shared >= 2 THEN
        should_match := true;
        match_confidence := 'moderate_with_critical';
        final_score := jaccard_score + (critical_shared * 0.05);
        
    -- Case 6: High containment alone (one version subset of another)
    ELSIF containment_score >= 0.80 THEN
        should_match := true;
        match_confidence := 'subset';
        final_score := containment_score * 0.85;
        
    -- Case 7: Same insurer re-processing (be more aggressive)
    ELSIF is_same_insurer AND jaccard_score >= 0.35 THEN
        should_match := true;
        match_confidence := 'same_insurer_fuzzy';
        final_score := jaccard_score + 0.10;
        
    -- Case 8: No match
    ELSE
        should_match := false;
        match_confidence := 'no_match';
        final_score := GREATEST(jaccard_score, weighted_jaccard);
    END IF;

    -- Cap final score at 1.0
    final_score := LEAST(final_score, 1.0);

    RETURN jsonb_build_object(
        'jaccard_score', ROUND(jaccard_score, 3),
        'weighted_jaccard', ROUND(weighted_jaccard, 3),
        'containment_score', ROUND(containment_score, 3),
        'final_score', ROUND(final_score, 3),
        'should_match', should_match,
        'match_confidence', match_confidence,
        'intersection_count', intersection_count,
        'union_count', union_count,
        'critical_shared', critical_shared,
        'tokens1_count', tokens1_count,
        'tokens2_count', tokens2_count,
        'shared_tokens', shared_tokens,
        'unique_to_1', unique_to_1,
        'unique_to_2', unique_to_2
    );
END;
$$;

-- =====================================================
-- FUNCION 3: SIMPLIFIED BATCH PROCESSOR v7
-- =====================================================
DROP FUNCTION IF EXISTS public.procesar_batch_vehiculos CASCADE;

CREATE OR REPLACE FUNCTION public.procesar_batch_vehiculos(records jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    -- Processing variables
    item jsonb;
    rec jsonb;
    total int := 0;
    created int := 0;
    updated int := 0;
    merged int := 0;
    skipped int := 0;
    errores jsonb := '[]'::jsonb;
    
    -- Batch info
    batch_start_time timestamp;
    insurer text;
    current_insurer text;
    
    -- Matching variables
    normalized_version text;
    input_tokens text[];
    best_match_id bigint;
    best_match_score numeric;
    best_confidence text;
    match_result jsonb;
    match_record RECORD;
BEGIN
    -- Validate input
    IF records IS NULL OR jsonb_array_length(records) = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'No records provided',
            'total_procesados', 0
        );
    END IF;

    batch_start_time := clock_timestamp();

    -- Process each record
    FOR item IN SELECT jsonb_array_elements(records)
    LOOP
        BEGIN
            total := total + 1;
            rec := item;
            
            -- Validate insurer
            current_insurer := rec->>'origen_aseguradora';
            IF current_insurer IS NULL OR current_insurer = '' THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'mensaje', 'Missing origen_aseguradora'
                );
                skipped := skipped + 1;
                CONTINUE;
            END IF;

            IF insurer IS NULL THEN
                insurer := current_insurer;
            ELSIF current_insurer <> insurer THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'mensaje', 'Mixed insurers in batch'
                );
                skipped := skipped + 1;
                CONTINUE;
            END IF;

            -- Validate required fields
            IF NOT (rec ? 'hash_comercial' AND rec ? 'version_limpia') THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'mensaje', 'Missing required fields'
                );
                skipped := skipped + 1;
                CONTINUE;
            END IF;

            -- Normalize and tokenize
            normalized_version := UPPER(TRIM(rec->>'version_limpia'));
            IF normalized_version = '' THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'mensaje', 'Empty version_limpia'
                );
                skipped := skipped + 1;
                CONTINUE;
            END IF;

            input_tokens := tokenize_version(normalized_version);

            -- Skip if tokenization failed
            IF array_length(input_tokens, 1) IS NULL THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'mensaje', 'Tokenization failed',
                    'version', normalized_version
                );
                skipped := skipped + 1;
                CONTINUE;
            END IF;

            -- Try exact match first (fastest)
            SELECT id INTO best_match_id
            FROM catalogo_homologado
            WHERE hash_comercial = rec->>'hash_comercial'
              AND version = normalized_version
            LIMIT 1;

            IF best_match_id IS NOT NULL THEN
                -- Exact match - update availability
                UPDATE catalogo_homologado
                SET disponibilidad = jsonb_set(
                        COALESCE(disponibilidad, '{}'::jsonb),
                        ARRAY[insurer],
                        jsonb_build_object(
                            'origen', true,
                            'disponible', true,
                            'aseguradora', insurer,
                            'id_original', rec->>'id_original',
                            'version_original', rec->>'version_original',
                            'match_score', 1.0,
                            'match_confidence', 'exact',
                            'metodo', 'exact_v7',
                            'fecha_actualizacion', now()
                        ),
                        true
                    ),
                    fecha_actualizacion = now()
                WHERE id = best_match_id;
                
                updated := updated + 1;
            ELSE
                -- Find best fuzzy match using simplified Jaccard
                best_match_id := NULL;
                best_match_score := 0;
                best_confidence := NULL;
                
                FOR match_record IN
                    SELECT 
                        ch.id,
                        ch.version_tokens_array,
                        (ch.disponibilidad ? insurer) as is_same_insurer
                    FROM catalogo_homologado ch
                    WHERE ch.hash_comercial = rec->>'hash_comercial'
                      AND ch.version_tokens_array IS NOT NULL
                      AND array_length(ch.version_tokens_array, 1) > 0
                      -- Optimize: only check if some overlap or very short versions
                      AND (
                          ch.version_tokens_array && input_tokens
                          OR array_length(ch.version_tokens_array, 1) <= 3
                          OR array_length(input_tokens, 1) <= 3
                      )
                    LIMIT 100  -- Check up to 100 candidates
                LOOP
                    match_result := calculate_jaccard_match(
                        input_tokens,
                        match_record.version_tokens_array,
                        match_record.is_same_insurer
                    );
                    
                    IF (match_result->>'should_match')::boolean = true AND
                       (match_result->>'final_score')::numeric > best_match_score THEN
                        best_match_id := match_record.id;
                        best_match_score := (match_result->>'final_score')::numeric;
                        best_confidence := match_result->>'match_confidence';
                        
                        -- Early exit for excellent matches
                        IF best_match_score >= 0.85 THEN
                            EXIT;
                        END IF;
                    END IF;
                END LOOP;

                IF best_match_id IS NOT NULL THEN
                    -- Match found - merge
                    UPDATE catalogo_homologado
                    SET disponibilidad = jsonb_set(
                            COALESCE(disponibilidad, '{}'::jsonb),
                            ARRAY[insurer],
                            jsonb_build_object(
                                'origen', true,
                                'disponible', true,
                                'aseguradora', insurer,
                                'id_original', rec->>'id_original',
                                'version_original', rec->>'version_original',
                                'match_score', best_match_score,
                                'match_confidence', best_confidence,
                                'metodo', 'jaccard_v7',
                                'fecha_actualizacion', now()
                            ),
                            true
                        ),
                        fecha_actualizacion = now()
                    WHERE id = best_match_id;
                    
                    merged := merged + 1;
                ELSE
                    -- No match - create new entry
                    BEGIN
                        INSERT INTO catalogo_homologado (
                            hash_comercial, marca, modelo, anio, transmision,
                            version, version_tokens, version_tokens_array,
                            disponibilidad, fecha_creacion, fecha_actualizacion
                        ) VALUES (
                            rec->>'hash_comercial',
                            rec->>'marca', 
                            rec->>'modelo',
                            (rec->>'anio')::int,
                            COALESCE(rec->>'transmision', 'SIN_TRANSMISION'),
                            normalized_version,
                            to_tsvector('simple', normalized_version),
                            input_tokens,
                            jsonb_build_object(
                                insurer, jsonb_build_object(
                                    'origen', true,
                                    'disponible', true,
                                    'aseguradora', insurer,
                                    'id_original', rec->>'id_original',
                                    'version_original', rec->>'version_original',
                                    'metodo', 'new_v7',
                                    'fecha_actualizacion', now()
                                )
                            ),
                            now(), now()
                        );
                        created := created + 1;
                        
                    EXCEPTION WHEN unique_violation THEN
                        -- Race condition - update instead
                        UPDATE catalogo_homologado
                        SET disponibilidad = jsonb_set(
                                COALESCE(disponibilidad, '{}'::jsonb),
                                ARRAY[insurer],
                                jsonb_build_object(
                                    'origen', true,
                                    'disponible', true,
                                    'aseguradora', insurer,
                                    'id_original', rec->>'id_original',
                                    'version_original', rec->>'version_original',
                                    'metodo', 'duplicate_v7',
                                    'fecha_actualizacion', now()
                                ),
                                true
                            ),
                            fecha_actualizacion = now()
                        WHERE hash_comercial = rec->>'hash_comercial'
                          AND version = normalized_version;
                        
                        updated := updated + 1;
                    END;
                END IF;
            END IF;

            -- Performance control
            IF total % 100 = 0 THEN
                PERFORM pg_sleep(0.001);
            END IF;
            
        EXCEPTION WHEN OTHERS THEN
            errores := errores || jsonb_build_object(
                'id_original', rec->>'id_original',
                'mensaje', SQLERRM,
                'version', normalized_version
            );
            skipped := skipped + 1;
        END;
    END LOOP;

    -- Return results
    RETURN jsonb_build_object(
        'success', true,
        'total_procesados', total,
        'registros_creados', created,
        'registros_actualizados', updated,
        'registros_homologados', merged,
        'registros_omitidos', skipped,
        'tasa_exito', ROUND((total - skipped)::numeric / NULLIF(total, 0) * 100, 2),
        'tasa_homologacion', ROUND(merged::numeric / NULLIF(total - skipped, 0) * 100, 2),
        'errores', CASE 
            WHEN jsonb_array_length(errores) > 100 THEN 
                errores #> '{0,99}'
            ELSE errores 
        END,
        'metodo', 'simplified_jaccard_v7',
        'tiempo_proceso', EXTRACT(EPOCH FROM (clock_timestamp() - batch_start_time)),
        'timestamp', now()
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM,
        'total_procesados', total,
        'timestamp', now()
    );
END;
$$;

-- =====================================================
-- HELPER FUNCTION: Analyze homologation quality
-- =====================================================
CREATE OR REPLACE FUNCTION analyze_homologation_quality(
    sample_limit int DEFAULT 100
)
RETURNS TABLE (
    metric_name text,
    metric_value numeric,
    details jsonb
) 
LANGUAGE plpgsql
AS $$
BEGIN
    -- Total vehicles
    RETURN QUERY
    SELECT 
        'total_vehicles'::text,
        COUNT(*)::numeric,
        NULL::jsonb
    FROM catalogo_homologado;
    
    -- Homologation rate
    RETURN QUERY
    WITH insurer_counts AS (
        SELECT 
            id,
            array_length(array(SELECT jsonb_object_keys(disponibilidad)), 1) as num_insurers
        FROM catalogo_homologado
    )
    SELECT 
        'homologation_rate'::text,
        ROUND(
            COUNT(CASE WHEN num_insurers > 1 THEN 1 END)::numeric * 100 / 
            NULLIF(COUNT(*), 0), 
            2
        ),
        jsonb_build_object(
            'single_insurer', COUNT(CASE WHEN num_insurers = 1 THEN 1 END),
            'multi_insurer', COUNT(CASE WHEN num_insurers > 1 THEN 1 END)
        )
    FROM insurer_counts;
    
    -- Average insurers per vehicle
    RETURN QUERY
    SELECT 
        'avg_insurers_per_vehicle'::text,
        ROUND(AVG(array_length(array(SELECT jsonb_object_keys(disponibilidad)), 1))::numeric, 2),
        NULL::jsonb
    FROM catalogo_homologado;
    
    -- Coverage by insurer
    RETURN QUERY
    SELECT 
        'coverage_by_insurer'::text,
        NULL::numeric,
        jsonb_object_agg(
            insurer,
            count
        )
    FROM (
        SELECT 
            jsonb_object_keys(disponibilidad) as insurer,
            COUNT(*) as count
        FROM catalogo_homologado
        GROUP BY jsonb_object_keys(disponibilidad)
    ) t;
END;
$$;
