-- =====================================================
-- SISTEMA DE HOMOLOGACION VEHICULAR v7.0 
-- Essential functions for vehicle homologation
-- =====================================================

-- Extensions are created in the table creation migration

-- =====================================================
-- FUNCION 1: TOKENIZACION v7 - Optimized for matching
-- =====================================================
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
-- FUNCION 2: TOKEN SIMILARITY CALCULATION
-- =====================================================
CREATE OR REPLACE FUNCTION calculate_token_similarity(tokens1 text[], tokens2 text[])
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    intersection_count int := 0;
    union_count int := 0;
    tokens1_count int := COALESCE(array_length(tokens1, 1), 0);
    tokens2_count int := COALESCE(array_length(tokens2, 1), 0);
BEGIN
    -- Handle empty arrays
    IF tokens1_count = 0 OR tokens2_count = 0 THEN
        RETURN 0.0;
    END IF;

    -- Calculate intersection
    SELECT COUNT(DISTINCT t) INTO intersection_count
    FROM (
        SELECT unnest(tokens1) AS t
        INTERSECT
        SELECT unnest(tokens2) AS t
    ) intersection;

    -- Calculate union
    SELECT COUNT(DISTINCT t) INTO union_count
    FROM (
        SELECT unnest(tokens1) AS t
        UNION
        SELECT unnest(tokens2) AS t
    ) union_set;

    -- Return Jaccard similarity
    IF union_count > 0 THEN
        RETURN ROUND(intersection_count::numeric / union_count::numeric, 4);
    ELSE
        RETURN 0.0;
    END IF;
END;
$$;

-- =====================================================
-- FUNCION 3: BATCH PROCESSOR v7 - Simplified
-- =====================================================
CREATE OR REPLACE FUNCTION procesar_batch_vehiculos(records jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
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
    match_record RECORD;
    threshold_same_insurer numeric := 0.85;
    threshold_cross_insurer numeric := 0.50;
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
                -- Find best fuzzy match
                best_match_id := NULL;
                best_match_score := 0;
                
                FOR match_record IN
                    SELECT 
                        ch.id,
                        ch.version_tokens_array,
                        (ch.disponibilidad ? insurer) as is_same_insurer,
                        calculate_token_similarity(input_tokens, ch.version_tokens_array) AS token_score,
                        similarity(normalized_version, ch.version) AS trgm_score
                    FROM catalogo_homologado ch
                    WHERE ch.hash_comercial = rec->>'hash_comercial'
                      AND ch.version_tokens_array IS NOT NULL
                      AND array_length(ch.version_tokens_array, 1) > 0
                    ORDER BY 
                        calculate_token_similarity(input_tokens, ch.version_tokens_array) DESC,
                        similarity(normalized_version, ch.version) DESC
                    LIMIT 10
                LOOP
                    -- Use the better of token or trigram similarity
                    best_match_score := GREATEST(match_record.token_score, match_record.trgm_score);
                    
                    -- Check if it meets threshold
                    IF (match_record.is_same_insurer AND best_match_score >= threshold_same_insurer) OR
                       (NOT match_record.is_same_insurer AND best_match_score >= threshold_cross_insurer) THEN
                        best_match_id := match_record.id;
                        EXIT; -- Found good enough match
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
                                'match_confidence', 'fuzzy',
                                'metodo', 'similarity_v7',
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
        'errores', errores,
        'metodo', 'simplified_homologation_v7',
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
CREATE OR REPLACE FUNCTION analyze_homologation_quality()
RETURNS TABLE (
    metric_name text,
    metric_value numeric,
    details text
) 
LANGUAGE plpgsql
AS $$
BEGIN
    -- Total vehicles
    RETURN QUERY
    SELECT 
        'total_vehicles'::text,
        COUNT(*)::numeric,
        'Total entries in catalog'::text
    FROM catalogo_homologado;
    
    -- Homologation rate
    RETURN QUERY
    WITH insurer_counts AS (
        SELECT 
            id,
            jsonb_object_keys(disponibilidad) as insurers
        FROM catalogo_homologado
    )
    SELECT 
        'homologation_rate'::text,
        ROUND(
            COUNT(DISTINCT CASE WHEN EXISTS(
                SELECT 1 FROM insurer_counts i2 
                WHERE i2.id = i1.id AND i2.insurers != i1.insurers
            ) THEN i1.id END)::numeric * 100 / 
            NULLIF(COUNT(DISTINCT i1.id), 0), 
            2
        ),
        'Percentage of vehicles available from multiple insurers'::text
    FROM insurer_counts i1;
    
    -- Average insurers per vehicle
    RETURN QUERY
    SELECT 
        'avg_insurers_per_vehicle'::text,
        ROUND(AVG(jsonb_object_keys_count)::numeric, 2),
        'Average number of insurers per vehicle'::text
    FROM (
        SELECT array_length(array(SELECT jsonb_object_keys(disponibilidad)), 1) as jsonb_object_keys_count
        FROM catalogo_homologado
    ) t;
END;
$$;

-- Indexes are created in the table creation migration
