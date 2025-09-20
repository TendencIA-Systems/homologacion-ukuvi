-- =====================================================
-- SISTEMA DE HOMOLOGACION VEHICULAR v2.5
-- =====================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

-- =====================================================
-- FUNCION 1: TOKENIZACION
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

    normalized_text := UPPER(version_text);

    normalized_text := translate(
        normalized_text,
        U&'\00C1\00C9\00CD\00D3\00DA\00C4\00CB\00CF\00D6\00DC\00D1',
        'AEIOUAEIOUN'
    );

    normalized_text := regexp_replace(normalized_text, '\s+', ' ', 'g');
    normalized_text := regexp_replace(normalized_text, 'AUT[OA"]?M[AA?]?T[I]?[C]?[OA]?', 'AUTO', 'g');
    normalized_text := regexp_replace(normalized_text, 'MAN[U]?[A]?[L]?', 'MANUAL', 'g');
    normalized_text := regexp_replace(normalized_text, 'CVT|XTRONIC|CONTINUOUSLY VARIABLE', 'CVT', 'g');
    normalized_text := regexp_replace(normalized_text, 'DSG|DUAL CLUTCH|DCT', 'DSG', 'g');
    normalized_text := regexp_replace(normalized_text, 'STD|STANDARD|EST[AA?]NDAR', 'STD', 'g');
    normalized_text := regexp_replace(normalized_text, 'SPORT PACKAGE', 'SPORT', 'g');
    normalized_text := regexp_replace(normalized_text, 'TURBOCARGADO|TURBO CARGADO', 'TURBO', 'g');

    normalized_text := regexp_replace(
        normalized_text,
        '([0-9]+)\.([0-9]+)([A-Z]*)',
        '\1P\2\3',
        'g'
    );

    normalized_text := regexp_replace(normalized_text, '[^A-Z0-9]+', ' ', 'g');
    normalized_text := TRIM(normalized_text);

    SELECT array_agg(DISTINCT final_token ORDER BY final_token)
    INTO tokens
    FROM (
        SELECT final_token
        FROM (
            SELECT CASE
                WHEN raw_token ~ '^[0-9]+P[0-9]+[A-Z]*$' THEN
                    regexp_replace(raw_token, '^([0-9]+)P([0-9]+)([A-Z]*)$', '\1.\2\3')
                ELSE raw_token
            END AS final_token
            FROM (
                SELECT unnest(string_to_array(normalized_text, ' ')) AS raw_token
            ) base
        ) transformed
        WHERE length(final_token) >= 2
          AND final_token NOT IN ('DE', 'LA', 'EL', 'LOS', 'LAS', 'CON', 'SIN')
    ) dedup;

    RETURN COALESCE(tokens, ARRAY[]::text[]);
END;
$$;

-- =====================================================
-- FUNCION 2: JACCARD SIMILARITY
-- =====================================================
CREATE OR REPLACE FUNCTION jaccard_similarity(tokens1 text[], tokens2 text[])
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    intersection_size int;
    union_size int;
BEGIN
    IF tokens1 IS NULL OR tokens2 IS NULL OR
       array_length(tokens1, 1) IS NULL OR array_length(tokens2, 1) IS NULL THEN
        RETURN 0;
    END IF;

    SELECT COUNT(DISTINCT unnest)
    INTO intersection_size
    FROM (
        SELECT unnest(tokens1)
        INTERSECT
        SELECT unnest(tokens2)
    ) t;

    SELECT COUNT(DISTINCT unnest)
    INTO union_size
    FROM (
        SELECT unnest(tokens1)
        UNION
        SELECT unnest(tokens2)
    ) t;

    IF union_size = 0 THEN
        RETURN 0;
    END IF;

    RETURN ROUND(intersection_size::numeric / union_size::numeric, 3);
END;
$$;

-- =====================================================
-- FUNCION 3: CALCULATE MATCH SCORE (v2.3)
-- =====================================================
CREATE OR REPLACE FUNCTION calculate_match_score(
    version1 text,
    version2 text,
    tokens1 text[],
    tokens2 text[]
)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    trigram_score numeric := 0;
    jaccard_score numeric := 0;
    levenshtein_score numeric := 0;
    metaphone_score numeric := 0;
    overlap_ratio numeric := 0;
    numeric_bonus numeric := 0;
    combined_score numeric := 0;
    max_length int := 0;
    tokens1_count int := COALESCE(array_length(tokens1, 1), 0);
    tokens2_count int := COALESCE(array_length(tokens2, 1), 0);
    overlap_count int := 0;
    numeric_overlap int := 0;
BEGIN
    IF tokens1_count = 0 OR tokens2_count = 0 THEN
        RETURN 0;
    END IF;

    trigram_score := similarity(UPPER(version1), UPPER(version2));
    jaccard_score := jaccard_similarity(tokens1, tokens2);

    SELECT COUNT(*) INTO overlap_count
    FROM (
        SELECT unnest(tokens1)
        INTERSECT
        SELECT unnest(tokens2)
    ) t;

    IF overlap_count > 0 THEN
        overlap_ratio := overlap_count::numeric / LEAST(tokens1_count, tokens2_count);
    END IF;

    SELECT COUNT(*) INTO numeric_overlap
    FROM (
        SELECT token FROM unnest(tokens1) AS token WHERE token ~ '\d'
        INTERSECT
        SELECT token FROM unnest(tokens2) AS token WHERE token ~ '\d'
    ) u;

    numeric_bonus := LEAST(numeric_overlap * 0.05, 0.15);

    max_length := GREATEST(length(version1), length(version2));
    IF max_length > 0 THEN
        levenshtein_score := 1.0 - (
            levenshtein_less_equal(
                UPPER(version1),
                UPPER(version2),
                max_length
            )::numeric / max_length
        );
    END IF;

    IF metaphone(version1, 10) = metaphone(version2, 10) THEN
        metaphone_score := 1.0;
    ELSE
        metaphone_score := similarity(
            metaphone(version1, 10),
            metaphone(version2, 10)
        );
    END IF;

    combined_score := (
        jaccard_score     * 0.20 +
        overlap_ratio     * 0.30 +
        trigram_score     * 0.20 +
        levenshtein_score * 0.20 +
        metaphone_score   * 0.10
    ) + numeric_bonus;

    RETURN LEAST(ROUND(combined_score, 3), 1.0);
END;
$$;

-- =====================================================
-- FUNCION 4: PROCESAR BATCH VEHICULOS
-- =====================================================
DROP FUNCTION IF EXISTS public.procesar_batch_vehiculos(jsonb);

CREATE OR REPLACE FUNCTION public.procesar_batch_vehiculos(records jsonb)
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
    match_record RECORD;
    insurer text := NULL;
    current_insurer text;
    normalized_version text;
    input_tokens text[];
    input_token_count int;
    required_overlap_same int;
    required_overlap_cross int;
    match_found boolean;
    best_score numeric;
    best_match_id bigint;
    best_match_has_insurer boolean;
    threshold_same_insurer numeric := 0.85;
    threshold_cross_insurer numeric := 0.50;
    min_token_overlap_same int := 2;
    min_token_overlap_cross int := 2;
    min_tokens_required int := 1;
    existing_entry jsonb;
    existing_ids jsonb;
    existing_versions jsonb;
    merged_entry jsonb;
    merged_ids jsonb;
    merged_versions jsonb;
    has_existing_id boolean;
    has_existing_version boolean;
    historial_count int;
    new_id text;
    new_version_original text;
    candidate_token_count int;
    token_overlap_ratio numeric;
    exact_version_match boolean;
BEGIN
    IF records IS NULL OR jsonb_array_length(records) = 0 THEN
        RETURN jsonb_build_object(
            'error', 'No records provided',
            'total_procesados', 0
        );
    END IF;

    FOR item IN SELECT jsonb_array_elements(records)
    LOOP
        BEGIN
            total := total + 1;
            rec := item;
            match_found := false;
            best_score := 0;
            best_match_id := NULL;
            best_match_has_insurer := false;

            current_insurer := rec->>'origen_aseguradora';
            IF current_insurer IS NULL OR current_insurer = '' THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'mensaje', 'Missing origen_aseguradora in record'
                );
                skipped := skipped + 1;
                CONTINUE;
            END IF;

            IF insurer IS NULL THEN
                insurer := current_insurer;
            ELSIF current_insurer <> insurer THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'mensaje', 'origen_aseguradora mismatch in batch'
                );
                skipped := skipped + 1;
                CONTINUE;
            END IF;

            IF NOT (rec ? 'hash_comercial' AND
                    rec ? 'version_limpia' AND
                    rec ? 'version_original') THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'mensaje', 'Missing required fields'
                );
                skipped := skipped + 1;
                CONTINUE;
            END IF;

            IF NOT (rec ? 'transmision') OR btrim(COALESCE(rec->>'transmision', '')) = '' THEN
                rec := rec || jsonb_build_object('transmision', 'SIN_TRANSMISION');
            END IF;

            normalized_version := UPPER(TRIM(rec->>'version_limpia'));
            IF normalized_version = '' THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'mensaje', 'Empty version_limpia after normalization'
                );
                skipped := skipped + 1;
                CONTINUE;
            END IF;

            input_tokens := tokenize_version(normalized_version);
            input_token_count := COALESCE(array_length(input_tokens, 1), 0);

            IF input_token_count < min_tokens_required THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'mensaje', 'Insufficient tokens in version'
                );
                skipped := skipped + 1;
                CONTINUE;
            END IF;

            required_overlap_same := LEAST(input_token_count, min_token_overlap_same);
            required_overlap_cross := LEAST(input_token_count, min_token_overlap_cross);

            FOR match_record IN
                SELECT
                    ch.id,
                    ch.version,
                    ch.disponibilidad,
                    ch.version_tokens_array,
                    (ch.disponibilidad ? insurer) AS has_insurer,
                    calculate_match_score(
                        normalized_version,
                        ch.version,
                        input_tokens,
                        ch.version_tokens_array
                    ) AS combined_score,
                    (
                        SELECT COUNT(*)::int FROM (
                            SELECT unnest(input_tokens)
                            INTERSECT
                            SELECT unnest(ch.version_tokens_array)
                        ) t
                    ) AS token_overlap,
                    COALESCE(array_length(ch.version_tokens_array, 1), 0) AS candidate_token_count
                FROM catalogo_homologado ch
                WHERE ch.hash_comercial = rec->>'hash_comercial'
                  AND ch.version_tokens_array IS NOT NULL
                  AND (
                      ch.version_tokens_array && input_tokens
                      OR similarity(UPPER(ch.version), normalized_version) > 0.20
                  )
                ORDER BY
                    combined_score DESC,
                    token_overlap DESC,
                    CASE WHEN ch.disponibilidad ? insurer THEN 0 ELSE 1 END
                LIMIT 10
            LOOP
                candidate_token_count := match_record.candidate_token_count;
                IF candidate_token_count IS NULL THEN
                    candidate_token_count := 0;
                END IF;

                IF LEAST(input_token_count, candidate_token_count) > 0 THEN
                    token_overlap_ratio := match_record.token_overlap::numeric
                        / LEAST(input_token_count, candidate_token_count);
                ELSE
                    token_overlap_ratio := 0;
                END IF;

                exact_version_match := (normalized_version = UPPER(match_record.version));

                IF match_record.has_insurer THEN
                    IF exact_version_match OR (
                        match_record.combined_score >= threshold_same_insurer
                        AND match_record.token_overlap >= required_overlap_same
                        AND token_overlap_ratio >= 0.9
                    ) THEN
                        match_found := true;
                        best_score := match_record.combined_score;
                        best_match_id := match_record.id;
                        best_match_has_insurer := true;
                        EXIT;
                    END IF;
                ELSE
                    IF match_record.combined_score >= threshold_cross_insurer
                       AND match_record.token_overlap >= required_overlap_cross THEN
                        IF NOT match_found OR match_record.combined_score > best_score THEN
                            match_found := true;
                            best_score := match_record.combined_score;
                            best_match_id := match_record.id;
                            best_match_has_insurer := false;
                        END IF;
                    END IF;
                END IF;
            END LOOP;

            IF match_found AND best_match_id IS NOT NULL THEN
                UPDATE catalogo_homologado
                SET
                    disponibilidad = jsonb_set(
                        COALESCE(disponibilidad, '{}'::jsonb),
                        ARRAY[insurer],
                        jsonb_build_object(
                            'origen', COALESCE(
                                (disponibilidad -> insurer ->> 'origen')::boolean,
                                best_match_has_insurer
                            ),
                            'disponible', true,
                            'aseguradora', insurer,
                            'id_original', rec->>'id_original',
                            'version_original', rec->>'version_original',
                            'confianza_score', best_score,
                            'fecha_actualizacion', now(),
                            'metodo_match',
                                CASE
                                    WHEN best_match_has_insurer THEN 'combined_scoring_same_insurer'
                                    ELSE 'combined_scoring_cross_insurer'
                                END
                        ),
                        true
                    ),
                    fecha_actualizacion = now()
                WHERE id = best_match_id;

                IF best_match_has_insurer THEN
                    updated := updated + 1;
                ELSE
                    merged := merged + 1;
                END IF;

            ELSE
                BEGIN
                    INSERT INTO catalogo_homologado (
                        hash_comercial,
                        marca,
                        modelo,
                        anio,
                        transmision,
                        version,
                        version_tokens,
                        version_tokens_array,
                        disponibilidad,
                        fecha_creacion,
                        fecha_actualizacion
                    ) VALUES (
                        rec->>'hash_comercial',
                        rec->>'marca',
                        rec->>'modelo',
                        (rec->>'anio')::int,
                        COALESCE(NULLIF(TRIM(rec->>'transmision'), ''), 'SIN_TRANSMISION'),
                        rec->>'version_limpia',
                        to_tsvector('simple', COALESCE(rec->>'version_limpia', '')),
                        input_tokens,
                        jsonb_build_object(
                            insurer, jsonb_build_object(
                                'origen', true,
                                'disponible', true,
                                'aseguradora', insurer,
                                'id_original', rec->>'id_original',
                                'version_original', rec->>'version_original',
                                'confianza_score', 1.0,
                                'fecha_actualizacion', now(),
                                'metodo_match', 'new_entry'
                            )
                        ),
                        now(),
                        now()
                    );
                    created := created + 1;

                EXCEPTION
                    WHEN unique_violation THEN
                        new_id := rec->>'id_original';
                        new_version_original := rec->>'version_original';

                        SELECT disponibilidad -> insurer
                        INTO existing_entry
                        FROM catalogo_homologado
                        WHERE hash_comercial = rec->>'hash_comercial'
                          AND version = rec->>'version_limpia'
                        FOR UPDATE;

                        existing_entry := COALESCE(existing_entry, '{}'::jsonb);

                        existing_ids := CASE
                            WHEN existing_entry ? 'id_original_historial'
                                 AND jsonb_typeof(existing_entry->'id_original_historial') = 'array'
                                THEN existing_entry->'id_original_historial'
                            WHEN existing_entry ? 'id_original'
                                 AND existing_entry->>'id_original' IS NOT NULL
                                THEN jsonb_build_array(existing_entry->>'id_original')
                            ELSE '[]'::jsonb
                        END;

                        existing_versions := CASE
                            WHEN existing_entry ? 'version_original_historial'
                                 AND jsonb_typeof(existing_entry->'version_original_historial') = 'array'
                                THEN existing_entry->'version_original_historial'
                            WHEN existing_entry ? 'version_original'
                                 AND existing_entry->>'version_original' IS NOT NULL
                                THEN jsonb_build_array(existing_entry->>'version_original')
                            ELSE '[]'::jsonb
                        END;

                        SELECT EXISTS (
                            SELECT 1 FROM jsonb_array_elements_text(existing_ids) AS ids(val)
                            WHERE val = new_id
                        ) INTO has_existing_id;

                        IF has_existing_id THEN
                            merged_ids := existing_ids;
                        ELSE
                            merged_ids := existing_ids || to_jsonb(new_id);
                        END IF;

                        SELECT EXISTS (
                            SELECT 1 FROM jsonb_array_elements_text(existing_versions) AS vers(val)
                            WHERE val = new_version_original
                        ) INTO has_existing_version;

                        IF has_existing_version THEN
                            merged_versions := existing_versions;
                        ELSE
                            merged_versions := existing_versions || to_jsonb(new_version_original);
                        END IF;

                        historial_count := COALESCE(jsonb_array_length(merged_ids), 0);
                        IF historial_count = 0 THEN
                            historial_count := 1;
                        END IF;

                        merged_entry := existing_entry;

                        merged_entry := jsonb_set(merged_entry, ARRAY['disponible'], to_jsonb(true), true);
                        merged_entry := jsonb_set(merged_entry, ARRAY['aseguradora'], to_jsonb(insurer), true);
                        merged_entry := jsonb_set(merged_entry, ARRAY['confianza_score'], to_jsonb(1.0), true);
                        merged_entry := jsonb_set(merged_entry, ARRAY['fecha_actualizacion'], to_jsonb(now()), true);
                        merged_entry := jsonb_set(merged_entry, ARRAY['metodo_match'], to_jsonb('exact_match_duplicate'), true);
                        merged_entry := jsonb_set(merged_entry, ARRAY['id_original_historial'], merged_ids, true);
                        merged_entry := jsonb_set(merged_entry, ARRAY['version_original_historial'], merged_versions, true);
                        merged_entry := jsonb_set(merged_entry, ARRAY['ultimo_id_original'], to_jsonb(new_id), true);
                        merged_entry := jsonb_set(merged_entry, ARRAY['ultimo_version_original'], to_jsonb(new_version_original), true);
                        merged_entry := jsonb_set(merged_entry, ARRAY['repeticiones'], to_jsonb(historial_count), true);

                        IF NOT (merged_entry ? 'id_original') OR merged_entry->>'id_original' IS NULL THEN
                            merged_entry := jsonb_set(merged_entry, ARRAY['id_original'], to_jsonb(new_id), true);
                        END IF;

                        IF NOT (merged_entry ? 'version_original') OR merged_entry->>'version_original' IS NULL THEN
                            merged_entry := jsonb_set(merged_entry, ARRAY['version_original'], to_jsonb(new_version_original), true);
                        END IF;

                        UPDATE catalogo_homologado
                        SET
                            disponibilidad = jsonb_set(
                                COALESCE(disponibilidad, '{}'::jsonb),
                                ARRAY[insurer],
                                merged_entry,
                                true
                            ),
                            fecha_actualizacion = now()
                        WHERE hash_comercial = rec->>'hash_comercial'
                          AND version = rec->>'version_limpia';

                        updated := updated + 1;
                END;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            errores := errores || jsonb_build_object(
                'id_original', rec->>'id_original',
                'mensaje', SQLERRM
            );
            skipped := skipped + 1;
        END;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'total_procesados', total,
        'registros_creados', created,
        'registros_actualizados', updated,
        'registros_homologados', merged,
        'registros_omitidos', skipped,
        'tasa_exito', ROUND((total - skipped)::numeric / NULLIF(total, 0) * 100, 2),
        'errores', errores,
        'metodo', 'combined_scoring_v2.5',
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
-- CONSTRAINT UNICO (hash_comercial, version)
-- =====================================================
ALTER TABLE catalogo_homologado
DROP CONSTRAINT IF EXISTS unique_hash_version;

ALTER TABLE catalogo_homologado
ADD CONSTRAINT unique_hash_version
UNIQUE (hash_comercial, version);
