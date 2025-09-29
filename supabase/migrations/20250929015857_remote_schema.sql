

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "fuzzystrmatch" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "wrappers" WITH SCHEMA "public";






CREATE OR REPLACE FUNCTION "public"."_procesar_batch_vehiculos"("vehiculos_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $_$
DECLARE
    item                 jsonb;
    rec                  jsonb;
    total                int := 0;
    created              int := 0;
    updated              int := 0;
    merged               int := 0;
    duplicates           int := 0;
    invalid              int := 0;
    errores              jsonb := '[]'::jsonb;
    errores_limit        constant int := 200;
    insurer              text;
    signature            text;
    normalized_version   text;
    normalized_tokens    text[];
    best_id              bigint;
    best_score           double precision;
    best_has_insurer     boolean;
    threshold            double precision;
    threshold_same       constant double precision := 0.92;
    threshold_cross      constant double precision := 0.50;
    token_sim            double precision;
    combined_score       double precision;
    candidate            RECORD;
    existing_disponibilidad jsonb;
    match_score_sum      double precision := 0;
    match_count          int := 0;
    errores_count        int;
    status               text;
    seen_signatures      jsonb := '{}'::jsonb;
BEGIN
    IF vehiculos_json IS NULL OR jsonb_typeof(vehiculos_json) <> 'array' THEN
        RAISE EXCEPTION 'vehiculos_json payload must be a JSON array';
    END IF;

    CREATE TEMP TABLE tmp_catalogo_tocados (
        id bigint PRIMARY KEY
    ) ON COMMIT DROP;

    SELECT vehiculos_json->0->>'origen_aseguradora' INTO insurer;
    IF insurer IS NULL THEN
        RAISE EXCEPTION 'Missing origen_aseguradora in input payload';
    END IF;

    FOR item IN SELECT jsonb_array_elements(vehiculos_json)
    LOOP
        total := total + 1;
        rec := item;

        IF coalesce(rec->>'origen_aseguradora', '') <> insurer THEN
            invalid := invalid + 1;
            IF jsonb_array_length(errores) < errores_limit THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'codigo_error', 'ASEGURADORA_INCONSISTENTE',
                    'mensaje', format('El registro pertenece a %s, pero el batch es de %s', rec->>'origen_aseguradora', insurer),
                    'datos_originales', rec
                );
            END IF;
            CONTINUE;
        END IF;

        signature := coalesce(rec->>'hash_comercial', '') || '|' || coalesce(rec->>'version_limpia', '');
        IF signature = '|' THEN
            invalid := invalid + 1;
            IF jsonb_array_length(errores) < errores_limit THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'codigo_error', 'FALTAN_CAMPOS',
                    'mensaje', 'hash_comercial y version_limpia son obligatorios',
                    'datos_originales', rec
                );
            END IF;
            CONTINUE;
        END IF;

        IF NOT (rec ? 'version_original' AND rec ? 'marca' AND rec ? 'modelo' AND rec ? 'anio' AND rec ? 'transmision') THEN
            invalid := invalid + 1;
            IF jsonb_array_length(errores) < errores_limit THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'codigo_error', 'FALTAN_CAMPOS',
                    'mensaje', 'Campos obligatorios ausentes',
                    'datos_originales', rec
                );
            END IF;
            CONTINUE;
        END IF;

        IF coalesce(rec->>'transmision', '') = '' OR rec->>'anio' IS NULL OR NOT (rec->>'anio' ~ '^\d+$') THEN
            invalid := invalid + 1;
            IF jsonb_array_length(errores) < errores_limit THEN
                errores := errores || jsonb_build_object(
                    'id_original', rec->>'id_original',
                    'codigo_error', 'DATOS_INVALIDOS',
                    'mensaje', 'anio o transmision no tienen un formato válido',
                    'datos_originales', rec
                );
            END IF;
            CONTINUE;
        END IF;

        IF seen_signatures ? signature THEN
            duplicates := duplicates + 1;
            CONTINUE;
        END IF;

        seen_signatures := seen_signatures || jsonb_build_object(signature, true);

        normalized_version := upper(coalesce(rec->>'version_limpia', ''));
        normalized_version := regexp_replace(normalized_version, '\\b(\\d)\\.0L\\b', '\\1L', 'g');
        normalized_version := regexp_replace(normalized_version, '\\bPICK[- ]?UP\\b', 'PICKUP', 'g');
        normalized_version := regexp_replace(normalized_version, '\\s+', ' ', 'g');
        normalized_version := trim(normalized_version);

        normalized_tokens := tokenize_version(normalized_version);

        best_id := NULL;
        best_score := 0;
        best_has_insurer := false;

        FOR candidate IN
            SELECT c.id,
                   c.disponibilidad,
                   coalesce(c.version_tokens_array, tokenize_version(coalesce(c.version, ''))) AS tokens,
                   similarity(upper(coalesce(c.version, '')), normalized_version) AS trigram_sim
            FROM catalogo_homologado c
            WHERE c.hash_comercial = rec->>'hash_comercial'
        LOOP
            token_sim := calculate_token_similarity(normalized_tokens, candidate.tokens);
            combined_score := GREATEST(token_sim, candidate.trigram_sim);

            IF combined_score > best_score THEN
                best_score := combined_score;
                best_id := candidate.id;
                best_has_insurer := candidate.disponibilidad ? insurer;
            END IF;
        END LOOP;

        IF best_id IS NOT NULL THEN
            threshold := CASE WHEN best_has_insurer THEN threshold_same ELSE threshold_cross END;
        ELSE
            threshold := threshold_cross;
        END IF;

        IF best_id IS NULL OR best_score < threshold THEN
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
                    fecha_actualizacion
                ) VALUES (
                    rec->>'hash_comercial',
                    rec->>'marca',
                    rec->>'modelo',
                    (rec->>'anio')::int,
                    rec->>'transmision',
                    rec->>'version_limpia',
                    to_tsvector('simple', normalized_version),
                    coalesce(normalized_tokens, ARRAY[]::text[]),
                    jsonb_build_object(
                        insurer,
                        jsonb_build_object(
                            'aseguradora', insurer,
                            'id_original', rec->>'id_original',
                            'version_original', rec->>'version_original',
                            'disponible', true,
                            'confianza_score', 1.0,
                            'origen', true,
                            'fecha_actualizacion', clock_timestamp()
                        )
                    ),
                    clock_timestamp()
                )
                RETURNING id INTO best_id;
                INSERT INTO tmp_catalogo_tocados(id)
                VALUES (best_id)
                ON CONFLICT DO NOTHING;

                created := created + 1;
            EXCEPTION WHEN unique_violation THEN
                SELECT c.id, c.disponibilidad
                INTO best_id, existing_disponibilidad
                FROM catalogo_homologado c
                WHERE c.hash_comercial = rec->>'hash_comercial'
                  AND c.version = rec->>'version_limpia'
                LIMIT 1;

                IF best_id IS NULL THEN
                    RAISE;
                END IF;

                best_has_insurer := coalesce(existing_disponibilidad ? insurer, false);

                UPDATE catalogo_homologado
                SET disponibilidad = jsonb_set(
                        coalesce(disponibilidad, '{}'::jsonb),
                        ARRAY[insurer],
                        jsonb_build_object(
                            'aseguradora', insurer,
                            'id_original', rec->>'id_original',
                            'version_original', rec->>'version_original',
                            'disponible', true,
                            'confianza_score', 1.0,
                            'origen', best_has_insurer,
                            'fecha_actualizacion', clock_timestamp()
                        ),
                        true
                    ),
                    version_tokens = coalesce(version_tokens, to_tsvector('simple', normalized_version)),
                    version_tokens_array = coalesce(version_tokens_array, normalized_tokens),
                    fecha_actualizacion = clock_timestamp()
                WHERE id = best_id;

                IF best_has_insurer THEN
                    updated := updated + 1;
                ELSE
                    merged := merged + 1;
                END IF;
                match_score_sum := match_score_sum + 1.0;
                match_count := match_count + 1;

                INSERT INTO tmp_catalogo_tocados(id)
                VALUES (best_id)
                ON CONFLICT DO NOTHING;
            END;

            CONTINUE;
        END IF;

        UPDATE catalogo_homologado
        SET disponibilidad = jsonb_set(
                coalesce(disponibilidad, '{}'::jsonb),
                ARRAY[insurer],
                jsonb_build_object(
                    'aseguradora', insurer,
                    'id_original', rec->>'id_original',
                    'version_original', rec->>'version_original',
                    'disponible', true,
                    'confianza_score', round(best_score::numeric, 3),
                    'origen', best_has_insurer,
                    'fecha_actualizacion', clock_timestamp()
                ),
                true
            ),
            version_tokens = coalesce(version_tokens, to_tsvector('simple', normalized_version)),
            version_tokens_array = coalesce(version_tokens_array, normalized_tokens),
            fecha_actualizacion = clock_timestamp()
        WHERE id = best_id;

        IF best_has_insurer THEN
            updated := updated + 1;
        ELSE
            merged := merged + 1;
        END IF;
        match_score_sum := match_score_sum + best_score;
        match_count := match_count + 1;

        INSERT INTO tmp_catalogo_tocados(id)
        VALUES (best_id)
        ON CONFLICT DO NOTHING;

    END LOOP;

    UPDATE catalogo_homologado AS c
    SET disponibilidad = jsonb_set(
            jsonb_set(
                coalesce(c.disponibilidad, '{}'::jsonb),
                ARRAY[insurer, 'disponible'],
                'false'::jsonb,
                true
            ),
            ARRAY[insurer, 'fecha_actualizacion'],
            to_jsonb(clock_timestamp()),
            true
        ),
        fecha_actualizacion = clock_timestamp()
    WHERE c.disponibilidad ? insurer
      AND coalesce((c.disponibilidad->insurer->>'disponible')::boolean, true)
      AND NOT EXISTS (
            SELECT 1
            FROM tmp_catalogo_tocados t
            WHERE t.id = c.id
        );

    errores_count := jsonb_array_length(errores);

    status := CASE
                WHEN errores_count = 0 AND invalid = 0 AND duplicates = 0 THEN 'success'
                WHEN created + updated + merged > 0 THEN 'partial_success'
                ELSE 'error'
              END;

    RETURN jsonb_build_object(
        'status', status,
        'total_procesados', total,
        'registros_creados', created,
        'registros_actualizados', updated,
        'registros_homologados', merged,
        'duplicados_omitidos', duplicates,
        'registros_invalidos', invalid,
        'errores', errores_count,
        'errores_detalle', errores,
        'detalles', jsonb_build_object(
            'matches_encontrados', updated + merged,
            'fuzzy_matches', merged,
            'nuevos_vehiculos', created,
            'similaridad_promedio', CASE WHEN match_count > 0 THEN round((match_score_sum / match_count)::numeric, 3) ELSE NULL END
        )
    );
END;
$_$;


ALTER FUNCTION "public"."_procesar_batch_vehiculos"("vehiculos_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."actualizar_existente"("request_data" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    actualizados INTEGER := 0;
    errores INTEGER := 0;
    vehiculo_id BIGINT;
    aseguradoras_actuales TEXT[];
    nueva_aseguradora TEXT;
    update_data JSONB;
BEGIN
    -- Extract data from body wrapper if present
    update_data := CASE 
        WHEN request_data ? 'body' THEN request_data->'body'
        ELSE request_data
    END;
    
    nueva_aseguradora := update_data->>'origen_aseguradora';
    
    -- Buscar vehículo y obtener aseguradoras actuales
    SELECT id, aseguradoras_disponibles 
    INTO vehiculo_id, aseguradoras_actuales
    FROM vehiculos_maestro 
    WHERE hash_tecnico = update_data->>'hash_tecnico';
    
    IF vehiculo_id IS NOT NULL THEN
        aseguradoras_actuales := COALESCE(aseguradoras_actuales, ARRAY[]::TEXT[]);
        
        IF NOT (nueva_aseguradora = ANY(aseguradoras_actuales)) THEN
            aseguradoras_actuales := array_append(aseguradoras_actuales, nueva_aseguradora);
            
            UPDATE vehiculos_maestro SET
                aseguradoras_disponibles = aseguradoras_actuales,
                fecha_actualizacion = NOW()
            WHERE id = vehiculo_id;
            
            actualizados := 1;
        END IF;
    ELSE
        errores := 1;
    END IF;
    
    RETURN jsonb_build_object(
        'actualizados', actualizados,
        'errores', errores,
        'hash_tecnico', update_data->>'hash_tecnico'
    );
END;
$$;


ALTER FUNCTION "public"."actualizar_existente"("request_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."actualizar_existente_n8n"("update_data" json) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_actualizados INTEGER := 0;
    v_es_array BOOLEAN;
BEGIN
    -- Detectar si es un array o un objeto único
    v_es_array := (json_typeof(update_data) = 'array');
    
    -- Si es un objeto único, convertirlo a array
    IF NOT v_es_array THEN
        update_data := json_build_array(update_data);
    END IF;
    
    -- Actualizar todos los registros usando un solo UPDATE con JOIN
    WITH updates AS (
        SELECT 
            (u->>'hash_tecnico')::VARCHAR(64) as hash,
            (u->>'origen_aseguradora')::TEXT as aseguradora
        FROM json_array_elements(update_data) AS u
    ),
    updated AS (
        UPDATE vehiculos_maestro v
        SET 
            aseguradoras_disponibles = 
                CASE 
                    -- Si la aseguradora ya existe, no hacer nada
                    WHEN u.aseguradora = ANY(v.aseguradoras_disponibles) 
                    THEN v.aseguradoras_disponibles
                    -- Si no existe, agregarla
                    ELSE array_append(v.aseguradoras_disponibles, u.aseguradora)
                END,
            fecha_actualizacion = NOW()
        FROM updates u
        WHERE v.hash_tecnico = u.hash
            -- Solo actualizar si realmente hay cambio
            AND NOT (u.aseguradora = ANY(v.aseguradoras_disponibles))
        RETURNING v.id
    )
    SELECT COUNT(*) INTO v_actualizados FROM updated;
    
    RETURN json_build_object(
        'success', true,
        'actualizados', v_actualizados,
        'mensaje', format('Se actualizaron %s vehículos', v_actualizados)
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'actualizados', 0,
            'error', SQLERRM
        );
END;
$$;


ALTER FUNCTION "public"."actualizar_existente_n8n"("update_data" json) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."actualizar_existente_n8n"("hash_tecnico" "text", "origen_aseguradora" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    actualizados INTEGER := 0;
    errores INTEGER := 0;
    vehiculo_id BIGINT;
    aseguradoras_actuales TEXT[];
BEGIN
    -- Buscar vehículo y obtener aseguradoras actuales
    SELECT id, aseguradoras_disponibles 
    INTO vehiculo_id, aseguradoras_actuales
    FROM vehiculos_maestro 
    WHERE vehiculos_maestro.hash_tecnico = actualizar_existente_n8n.hash_tecnico;
    
    IF vehiculo_id IS NOT NULL THEN
        aseguradoras_actuales := COALESCE(aseguradoras_actuales, ARRAY[]::TEXT[]);
        
        IF NOT (origen_aseguradora = ANY(aseguradoras_actuales)) THEN
            aseguradoras_actuales := array_append(aseguradoras_actuales, origen_aseguradora);
            
            UPDATE vehiculos_maestro SET
                aseguradoras_disponibles = aseguradoras_actuales,
                fecha_actualizacion = NOW()
            WHERE id = vehiculo_id;
            
            actualizados := 1;
        END IF;
    ELSE
        errores := 1;
    END IF;
    
    RETURN jsonb_build_object(
        'actualizados', actualizados,
        'errores', errores,
        'hash_tecnico', actualizar_existente_n8n.hash_tecnico
    );
END;
$$;


ALTER FUNCTION "public"."actualizar_existente_n8n"("hash_tecnico" "text", "origen_aseguradora" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."actualizar_tokens_existentes"("p_limit" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_updated int := 0;
    v_record RECORD;
BEGIN
    FOR v_record IN
        SELECT id, version
        FROM catalogo_homologado
        WHERE version_tokens_array IS NULL
           OR array_length(version_tokens_array, 1) IS NULL
        ORDER BY id
        LIMIT COALESCE(p_limit, 999999)
    LOOP
        UPDATE catalogo_homologado
        SET version_tokens_array = tokenize_version(version),
            version_tokens = to_tsvector('simple', COALESCE(version, ''))
        WHERE id = v_record.id;
        
        v_updated := v_updated + 1;
    END LOOP;
    
    RETURN jsonb_build_object(
        'registros_actualizados', v_updated,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."actualizar_tokens_existentes"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analizar_calidad_homologacion"() RETURNS TABLE("metrica" "text", "valor" numeric, "descripcion" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH base_stats AS (
        SELECT 
            COUNT(*) as total_registros,
            COUNT(DISTINCT hash_comercial) as vehiculos_unicos
        FROM catalogo_homologado
    ),
    homologation_stats AS (
        SELECT 
            COUNT(*) FILTER (WHERE jsonb_array_length(jsonb_object_keys(disponibilidad)) > 1) as homologados,
            COUNT(*) FILTER (WHERE jsonb_array_length(jsonb_object_keys(disponibilidad)) = 1) as sin_homologar,
            AVG(jsonb_array_length(jsonb_object_keys(disponibilidad))) as promedio_aseguradoras
        FROM catalogo_homologado
    )
    SELECT 'Total Registros'::text, total_registros::numeric, 'Total de versiones únicas'::text 
    FROM base_stats
    UNION ALL
    SELECT 'Vehículos Únicos', vehiculos_unicos::numeric, 'Combinaciones marca-modelo-año-transmisión'
    FROM base_stats
    UNION ALL
    SELECT 'Tasa Homologación %', 
           ROUND((homologados::numeric / NULLIF(total_registros, 0)) * 100, 2),
           'Porcentaje con múltiples aseguradoras'
    FROM base_stats, homologation_stats
    UNION ALL
    SELECT 'Promedio Aseguradoras', 
           ROUND(promedio_aseguradoras, 2),
           'Aseguradoras promedio por registro'
    FROM homologation_stats;
END;
$$;


ALTER FUNCTION "public"."analizar_calidad_homologacion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analizar_resultados_homologacion"() RETURNS TABLE("metrica" "text", "valor" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH stats AS (
        SELECT 
            COUNT(*) as total_registros,
            COUNT(DISTINCT hash_comercial) as vehiculos_unicos,
            COUNT(*) FILTER (WHERE jsonb_array_length(jsonb_object_keys(disponibilidad)) > 1) as homologados,
            COUNT(*) FILTER (WHERE jsonb_array_length(jsonb_object_keys(disponibilidad)) = 1) as sin_homologar
        FROM catalogo_homologado
    )
    SELECT 'Total Registros'::text, total_registros::numeric FROM stats
    UNION ALL
    SELECT 'Vehículos Únicos', vehiculos_unicos::numeric FROM stats
    UNION ALL
    SELECT 'Registros Homologados', homologados::numeric FROM stats
    UNION ALL
    SELECT 'Registros Sin Homologar', sin_homologar::numeric FROM stats
    UNION ALL
    SELECT 'Tasa Homologación %', 
           ROUND((homologados::numeric / NULLIF(total_registros, 0)) * 100, 2) 
    FROM stats;
END;
$$;


ALTER FUNCTION "public"."analizar_resultados_homologacion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analyze_homologation_quality"() RETURNS TABLE("metric" "text", "value" numeric, "details" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    
    -- Total entries and unique vehicles
    SELECT 
        'Total Entries'::text,
        COUNT(*)::numeric,
        format('%s total entries in catalog', COUNT(*))::text
    FROM catalogo_homologado
    
    UNION ALL
    
    SELECT 
        'Unique Vehicles'::text,
        COUNT(DISTINCT hash_comercial)::numeric,
        format('%s unique hash_comercial values', COUNT(DISTINCT hash_comercial))::text
    FROM catalogo_homologado
    
    UNION ALL
    
    -- Average entries per hash (should approach 1.0 with perfect matching)
    SELECT 
        'Avg Entries per Vehicle'::text,
        ROUND(COUNT(*)::numeric / COUNT(DISTINCT hash_comercial), 2),
        format('Average %.2f entries per unique vehicle', 
               COUNT(*)::numeric / COUNT(DISTINCT hash_comercial))::text
    FROM catalogo_homologado
    
    UNION ALL
    
    -- Vehicles with excessive duplicates
    SELECT 
        'Vehicles with >10 Duplicates'::text,
        COUNT(*)::numeric,
        format('%s vehicles have more than 10 duplicate entries', COUNT(*))::text
    FROM (
        SELECT hash_comercial, COUNT(*) as cnt
        FROM catalogo_homologado
        GROUP BY hash_comercial
        HAVING COUNT(*) > 10
    ) t
    
    UNION ALL
    
    -- Cross-insurer matching rate
    SELECT 
        'Multi-Insurer Vehicles'::text,
        COUNT(*)::numeric,
        format('%s vehicles available from multiple insurers', COUNT(*))::text
    FROM catalogo_homologado
    WHERE jsonb_array_length(
        ARRAY(SELECT jsonb_object_keys(disponibilidad))::jsonb
    ) > 1
    
    UNION ALL
    
    -- Perfect consolidation potential
    SELECT 
        'Consolidation Potential'::text,
        SUM(entry_count - 1)::numeric,
        format('%s entries could be consolidated', SUM(entry_count - 1))::text
    FROM (
        SELECT COUNT(*) as entry_count
        FROM catalogo_homologado
        GROUP BY hash_comercial
        HAVING COUNT(*) > 1
    ) t;
    
END;
$$;


ALTER FUNCTION "public"."analyze_homologation_quality"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analyze_homologation_quality"("sample_limit" integer DEFAULT 100) RETURNS TABLE("metric_name" "text", "metric_value" numeric, "details" "jsonb")
    LANGUAGE "plpgsql"
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


ALTER FUNCTION "public"."analyze_homologation_quality"("sample_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analyze_knowledge_base"() RETURNS TABLE("insurer_code" "text", "total_chunks" bigint, "avg_chunk_size" double precision, "doc_types" "text"[], "topics_coverage" "text"[], "coverage_types_summary" "text"[])
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        kc.metadata->>'insurer_code' AS insurer_code,
        COUNT(DISTINCT kc.id) AS total_chunks,
        AVG(CAST(kc.metadata->>'chunk_size' AS INTEGER))::FLOAT AS avg_chunk_size,
        ARRAY_AGG(DISTINCT kc.metadata->>'doc_type') AS doc_types,
        ARRAY_AGG(DISTINCT topic.value) AS topics_coverage,
        ARRAY_AGG(DISTINCT coverage.value) AS coverage_types_summary
    FROM 
        knowledge_base_chunks kc
    LEFT JOIN LATERAL jsonb_array_elements_text(kc.metadata->'topics') AS topic ON true
    -- This COALESCE checks for the correct key first, then the old typo'd key.
    LEFT JOIN LATERAL jsonb_array_elements_text(
        COALESCE(kc.metadata->'coverage_types', kc.metadata->'coverages_types')
    ) AS coverage ON true
    WHERE 
        kc.metadata->>'insurer_code' IS NOT NULL
    GROUP BY 
        kc.metadata->>'insurer_code';
END;
$$;


ALTER FUNCTION "public"."analyze_knowledge_base"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analyze_match_quality"("insurer_name" "text" DEFAULT NULL::"text") RETURNS TABLE("aseguradora" "text", "total_vehicles" bigint, "unique_hashes" bigint, "avg_jaccard_score" numeric, "vehicles_with_cross_match" bigint, "cross_match_percentage" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH insurer_stats AS (
        SELECT 
            key AS aseguradora,
            COUNT(*) AS total_count,
            AVG((value->>'jaccard_score')::numeric) AS avg_score
        FROM catalogo_homologado,
             jsonb_each(disponibilidad)
        WHERE insurer_name IS NULL OR key = insurer_name
        GROUP BY key
    ),
    cross_matches AS (
        SELECT 
            COUNT(*) AS cross_matched
        FROM catalogo_homologado
        WHERE jsonb_array_length(jsonb_object_keys(disponibilidad)::jsonb) > 1
          AND (insurer_name IS NULL OR disponibilidad ? insurer_name)
    ),
    unique_counts AS (
        SELECT 
            COUNT(DISTINCT hash_comercial) AS unique_hashes_count
        FROM catalogo_homologado
        WHERE insurer_name IS NULL OR disponibilidad ? insurer_name
    )
    SELECT 
        s.aseguradora,
        s.total_count,
        u.unique_hashes_count,
        ROUND(s.avg_score, 3),
        c.cross_matched,
        ROUND((c.cross_matched::numeric / s.total_count) * 100, 2)
    FROM insurer_stats s
    CROSS JOIN cross_matches c
    CROSS JOIN unique_counts u;
END;
$$;


ALTER FUNCTION "public"."analyze_match_quality"("insurer_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analyze_matching_performance"() RETURNS TABLE("metric_name" "text", "value" numeric, "description" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        'homologacion_rate'::text,
        ROUND(COUNT(*) FILTER (WHERE jsonb_array_length(jsonb_object_keys(disponibilidad)::jsonb) > 1)::numeric * 100.0 / NULLIF(COUNT(*), 0), 2),
        'Porcentaje con múltiples aseguradoras'::text
    FROM catalogo_homologado
    
    UNION ALL
    
    SELECT 
        'avg_tokens'::text,
        ROUND(AVG(array_length(version_tokens_array, 1))::numeric, 2),
        'Promedio de tokens'::text
    FROM catalogo_homologado
    WHERE version_tokens_array IS NOT NULL
    
    UNION ALL
    
    SELECT 
        'cache_efficiency'::text,
        ROUND(AVG(COALESCE(hits, 0))::numeric, 2),
        'Promedio hits caché'::text
    FROM match_cache;
END;
$$;


ALTER FUNCTION "public"."analyze_matching_performance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analyze_matching_performance_v5"() RETURNS TABLE("metric_name" "text", "value" numeric, "description" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    
    SELECT 
        'homologacion_rate_v5'::text,
        ROUND(
            COUNT(*) FILTER (WHERE jsonb_array_length(jsonb_object_keys(disponibilidad)) > 1)::numeric * 100.0 / 
            NULLIF(COUNT(*), 0),
            2
        ),
        'Porcentaje de registros con múltiples aseguradoras (v5)'::text
    FROM catalogo_homologado
    
    UNION ALL
    
    SELECT 
        'weighted_matches'::text,
        COUNT(*) FILTER (
            WHERE disponibilidad @> '{"metodo_match": "cross_insurer_v5"}'::jsonb
            OR disponibilidad @> '{"algoritmo_version": "weighted_token_v5"}'::jsonb
        )::numeric,
        'Matches using weighted token algorithm'::text
    FROM catalogo_homologado
    
    UNION ALL
    
    SELECT 
        'avg_confidence_score'::text,
        ROUND(AVG((jsonb_each(disponibilidad)).value->>'confianza_score')::numeric, 3),
        'Promedio de confidence score'::text
    FROM catalogo_homologado
    WHERE jsonb_typeof(disponibilidad) = 'object'
    
    UNION ALL
    
    SELECT 
        'cache_hit_rate'::text,
        ROUND(
            COUNT(*) FILTER (WHERE fecha_calculo > now() - INTERVAL '1 day')::numeric * 100.0 /
            NULLIF(COUNT(*), 0),
            2
        ),
        'Cache hit rate (últimas 24h)'::text
    FROM match_cache;
END;
$$;


ALTER FUNCTION "public"."analyze_matching_performance_v5"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analyze_token_distribution"("p_hash_comercial" character varying) RETURNS TABLE("version" "text", "insurer" "text", "token_count" integer, "tokens" "text"[])
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ch.version,
        jsonb_object_keys(ch.disponibilidad) as insurer,
        array_length(ch.version_tokens_array, 1) as token_count,
        ch.version_tokens_array as tokens
    FROM catalogo_homologado ch
    WHERE ch.hash_comercial = p_hash_comercial
    ORDER BY array_length(ch.version_tokens_array, 1) DESC;
END;
$$;


ALTER FUNCTION "public"."analyze_token_distribution"("p_hash_comercial" character varying) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."analyze_unprocessed_records"("input_batch" "jsonb", "insurer_name" "text") RETURNS TABLE("categoria" "text", "cantidad" bigint, "ejemplo_hash" "text", "ejemplo_version" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH input_records AS (
        SELECT 
            rec->>'hash_comercial' as hash,
            rec->>'version_limpia' as version,
            rec->>'id_original' as id_original
        FROM jsonb_array_elements(input_batch) as rec
    ),
    categorized AS (
        SELECT 
            i.hash,
            i.version,
            i.id_original,
            CASE 
                WHEN i.hash IS NULL THEN 'hash_null'
                WHEN i.version IS NULL THEN 'version_null'
                WHEN EXISTS (
                    SELECT 1 FROM catalogo_homologado c 
                    WHERE c.hash_comercial = i.hash 
                    AND c.disponibilidad ? insurer_name
                ) THEN 'ya_existe_mismo_insurer'
                WHEN EXISTS (
                    SELECT 1 FROM catalogo_homologado c 
                    WHERE c.hash_comercial = i.hash
                ) THEN 'existe_otro_insurer'
                ELSE 'nuevo_registro'
            END as category
        FROM input_records i
    )
    SELECT 
        category as categoria,
        COUNT(*) as cantidad,
        MIN(hash) as ejemplo_hash,
        MIN(version) as ejemplo_version
    FROM categorized
    GROUP BY category
    ORDER BY COUNT(*) DESC;
END;
$$;


ALTER FUNCTION "public"."analyze_unprocessed_records"("input_batch" "jsonb", "insurer_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."aplicar_clustering_jerarquico"("p_matrix" "jsonb", "p_threshold" numeric DEFAULT 0.35) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    n int;
    clusters jsonb := '[]'::jsonb;
    active_clusters int[];
    merged boolean;
    best_i int;
    best_j int;
    best_sim numeric;
    i int;
    j int;
    cluster_id int := 0;
    members int[];
BEGIN
    -- Inicializar: cada elemento es su propio cluster
    n := jsonb_array_length(p_matrix);
    
    FOR i IN 0..(n-1) LOOP
        active_clusters := array_append(active_clusters, i);
        clusters := clusters || jsonb_build_object(
            'id', i,
            'members', jsonb_build_array(i)
        );
    END LOOP;
    
    -- Iterar hasta que no haya más merges posibles
    LOOP
        merged := false;
        best_sim := 0;
        best_i := -1;
        best_j := -1;
        
        -- Buscar el mejor par para fusionar (complete linkage)
        FOR i IN 1..array_length(active_clusters, 1) LOOP
            FOR j IN (i+1)..array_length(active_clusters, 1) LOOP
                -- Calcular similitud mínima entre clusters (complete linkage)
                best_sim := calcular_similitud_clusters(
                    p_matrix,
                    clusters->active_clusters[i]->'members',
                    clusters->active_clusters[j]->'members',
                    'complete'
                );
                
                IF best_sim >= p_threshold THEN
                    -- Fusionar clusters
                    clusters := fusionar_clusters(
                        clusters, 
                        active_clusters[i], 
                        active_clusters[j]
                    );
                    
                    -- Actualizar lista de clusters activos
                    active_clusters := array_remove(active_clusters, active_clusters[j]);
                    merged := true;
                    EXIT;
                END IF;
            END LOOP;
            
            IF merged THEN EXIT; END IF;
        END LOOP;
        
        EXIT WHEN NOT merged;
    END LOOP;
    
    RETURN clusters;
END;
$$;


ALTER FUNCTION "public"."aplicar_clustering_jerarquico"("p_matrix" "jsonb", "p_threshold" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buscar_candidatos_homologacion"("p_hash_comercial" "text", "p_version_tokens" "text"[], "p_version_normalized" "text", "p_limit" integer DEFAULT 20) RETURNS TABLE("id" bigint, "version" "text", "version_tokens_array" "text"[], "disponibilidad" "jsonb", "similarity_score" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH candidates AS (
        SELECT 
            ch.id,
            ch.version,
            ch.version_tokens_array,
            ch.disponibilidad,
            -- Usar similarity de pg_trgm como score inicial
            similarity(ch.version, p_version_normalized) AS trgm_score
        FROM catalogo_homologado ch
        WHERE ch.hash_comercial = p_hash_comercial
          -- Pre-filtros eficientes
          AND (
              -- Tienen tokens en común (usando índice GIN)
              ch.version_tokens_array && p_version_tokens
              -- O tienen similitud trigram mínima
              OR similarity(ch.version, p_version_normalized) > 0.15
          )
    )
    SELECT 
        id,
        version,
        version_tokens_array,
        disponibilidad,
        trgm_score AS similarity_score
    FROM candidates
    WHERE version_tokens_array IS NOT NULL
      AND array_length(version_tokens_array, 1) > 0
    ORDER BY 
        -- Priorizar por overlap de tokens
        CASE 
            WHEN version_tokens_array && p_version_tokens 
            THEN array_length(
                ARRAY(
                    SELECT unnest(version_tokens_array)
                    INTERSECT
                    SELECT unnest(p_version_tokens)
                ), 1
            )
            ELSE 0
        END DESC,
        -- Luego por similitud trigram
        trgm_score DESC
    LIMIT p_limit;
END;
$$;


ALTER FUNCTION "public"."buscar_candidatos_homologacion"("p_hash_comercial" "text", "p_version_tokens" "text"[], "p_version_normalized" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buscar_por_hash_tecnico"("hash_list" json) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    resultados JSON;
BEGIN
    -- Convertir JSON array a SQL array y buscar
    WITH vehiculos_encontrados AS (
        SELECT 
            v.id,
            v.hash_tecnico,
            v.marca,
            v.modelo,
            v.anio as "año",  -- Mantener compatibilidad con tu formato
            v.version,
            v.aseguradoras_disponibles
        FROM vehiculos_maestro v
        WHERE v.hash_tecnico IN (
            SELECT json_array_elements_text(hash_list)
        )
    )
    SELECT json_agg(row_to_json(vehiculos_encontrados))
    INTO resultados
    FROM vehiculos_encontrados;
    
    RETURN COALESCE(resultados, '[]'::JSON);
END;
$$;


ALTER FUNCTION "public"."buscar_por_hash_tecnico"("hash_list" json) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calcular_similitud_clusters"("p_matrix" "jsonb", "p_cluster1" "jsonb", "p_cluster2" "jsonb", "p_linkage" "text" DEFAULT 'complete'::"text") RETURNS numeric
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    min_sim numeric := 1.0;
    max_sim numeric := 0.0;
    avg_sim numeric := 0.0;
    count int := 0;
    sim numeric;
    i int;
    j int;
BEGIN
    -- Calcular similitud según el tipo de linkage
    FOR i IN SELECT * FROM jsonb_array_elements(p_cluster1)
    LOOP
        FOR j IN SELECT * FROM jsonb_array_elements(p_cluster2)
        LOOP
            sim := (p_matrix->i->j)::numeric;
            
            IF sim < min_sim THEN min_sim := sim; END IF;
            IF sim > max_sim THEN max_sim := sim; END IF;
            avg_sim := avg_sim + sim;
            count := count + 1;
        END LOOP;
    END LOOP;
    
    IF count > 0 THEN
        avg_sim := avg_sim / count;
    END IF;
    
    -- Retornar según tipo de linkage
    CASE p_linkage
        WHEN 'single' THEN RETURN max_sim;
        WHEN 'complete' THEN RETURN min_sim;
        WHEN 'average' THEN RETURN avg_sim;
        ELSE RETURN min_sim;  -- Default: complete linkage
    END CASE;
END;
$$;


ALTER FUNCTION "public"."calcular_similitud_clusters"("p_matrix" "jsonb", "p_cluster1" "jsonb", "p_cluster2" "jsonb", "p_linkage" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_aggressive_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    intersection_count int := 0;
    union_count int := 0;
    tokens1_count int := COALESCE(array_length(tokens1, 1), 0);
    tokens2_count int := COALESCE(array_length(tokens2, 1), 0);
    shorter_count int := LEAST(tokens1_count, tokens2_count);
    longer_count int := GREATEST(tokens1_count, tokens2_count);
    
    jaccard_score numeric := 0;
    containment_score numeric := 0;  -- How much of shorter is in longer
    subset_score numeric := 0;        -- Is shorter a subset of longer?
    final_score numeric := 0;
    match_confidence text;
    
    critical_tokens_matched int := 0;
    critical_tokens text[];
    shared_tokens text[];
BEGIN
    -- Handle empty cases
    IF tokens1_count = 0 OR tokens2_count = 0 THEN
        RETURN jsonb_build_object(
            'final_score', 0,
            'jaccard_score', 0,
            'containment_score', 0,
            'is_subset', false,
            'match_confidence', 'none',
            'should_match', false
        );
    END IF;

    -- Calculate intersection
    SELECT array_agg(DISTINCT unnest) INTO shared_tokens
    FROM (
        SELECT unnest(tokens1)
        INTERSECT
        SELECT unnest(tokens2)
    ) t;
    
    intersection_count := COALESCE(array_length(shared_tokens, 1), 0);

    -- Calculate union
    SELECT COUNT(DISTINCT unnest) INTO union_count
    FROM (
        SELECT unnest(tokens1)
        UNION
        SELECT unnest(tokens2)
    ) t;

    -- Calculate scores
    IF union_count > 0 THEN
        jaccard_score := intersection_count::numeric / union_count::numeric;
    END IF;

    IF shorter_count > 0 THEN
        containment_score := intersection_count::numeric / shorter_count::numeric;
    END IF;

    -- Check if shorter is subset of longer
    subset_score := CASE 
        WHEN containment_score = 1.0 THEN 1.0  -- Perfect subset
        WHEN containment_score >= 0.8 THEN containment_score  -- Near subset
        ELSE containment_score * 0.5  -- Partial overlap
    END;

    -- Define critical tokens
    critical_tokens := ARRAY[
        -- Engine displacements
        '1.0L', '1.2L', '1.3L', '1.4L', '1.5L', '1.6L', '1.8L', 
        '2.0L', '2.2L', '2.3L', '2.4L', '2.5L', '2.7L', '2.8L',
        '3.0L', '3.2L', '3.3L', '3.5L', '3.6L', '3.7L', '3.8L',
        '4.0L', '4.2L', '4.3L', '4.6L', '4.7L', '5.0L', '5.3L', 
        '5.7L', '6.0L', '6.2L', '6.4L',
        -- Cylinders
        '3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL',
        -- Key trim indicators
        'BASE', 'SPORT', 'LUXURY', 'PREMIUM', 'LIMITED', 'TOURING',
        'ADVANCE', 'ELITE', 'EXECUTIVE', 'PLATINUM', 'PRO',
        -- Special editions
        'TURBO', 'BITURBO', 'TYPE-R', 'TYPE-S', 'A-SPEC', 'S-LINE',
        'AMG', 'RS', 'GTI', 'ST', 'SS', 'Z51', 'Z06', 'ZR1'
    ];

    -- Count critical tokens
    SELECT COUNT(DISTINCT token) INTO critical_tokens_matched
    FROM unnest(shared_tokens) AS token
    WHERE token = ANY(critical_tokens);

    -- AGGRESSIVE SCORING LOGIC
    -- Handle special cases for very short versions
    IF shorter_count <= 3 THEN
        -- For very short versions, if they're mostly contained, match aggressively
        IF containment_score >= 0.67 THEN  -- 2 of 3 tokens match
            final_score := 0.85;
            match_confidence := 'high_short_subset';
        ELSIF intersection_count >= 1 AND critical_tokens_matched >= 1 THEN
            -- At least one critical token matches
            final_score := 0.70;
            match_confidence := 'medium_critical_match';
        ELSE
            final_score := containment_score * 0.6;
            match_confidence := 'low_partial';
        END IF;
        
    -- Handle perfect or near-perfect subsets
    ELSIF containment_score >= 0.90 THEN
        final_score := 0.95;
        match_confidence := 'very_high_subset';
        
    -- Handle good containment with reasonable difference
    ELSIF containment_score >= 0.75 AND longer_count - shorter_count <= 5 THEN
        final_score := 0.80 + (critical_tokens_matched * 0.05);
        match_confidence := 'high_containment';
        
    -- Handle moderate containment with critical tokens
    ELSIF containment_score >= 0.60 AND critical_tokens_matched >= 1 THEN
        final_score := 0.65 + (critical_tokens_matched * 0.05);
        match_confidence := 'medium_with_critical';
        
    -- Standard Jaccard with boost for critical tokens
    ELSE
        final_score := (jaccard_score * 0.6 + containment_score * 0.4) + 
                      (critical_tokens_matched * 0.05);
        match_confidence := CASE 
            WHEN final_score >= 0.7 THEN 'medium_combined'
            WHEN final_score >= 0.5 THEN 'low_combined'
            ELSE 'very_low'
        END;
    END IF;

    -- Cap at 1.0
    final_score := LEAST(final_score, 1.0);

    -- Determine if should match based on context
    DECLARE
        should_match boolean;
    BEGIN
        IF is_same_insurer THEN
            -- Same insurer: still maintain some quality threshold
            should_match := final_score >= 0.60 OR 
                           (containment_score >= 0.75 AND intersection_count >= 2);
        ELSE
            -- Different insurers: be more aggressive
            should_match := final_score >= 0.45 OR 
                           containment_score >= 0.67 OR
                           (intersection_count >= 2 AND critical_tokens_matched >= 1);
        END IF;

        RETURN jsonb_build_object(
            'final_score', ROUND(final_score, 3),
            'jaccard_score', ROUND(jaccard_score, 3),
            'containment_score', ROUND(containment_score, 3),
            'is_subset', containment_score = 1.0,
            'intersection_count', intersection_count,
            'union_count', union_count,
            'shorter_count', shorter_count,
            'longer_count', longer_count,
            'critical_tokens_matched', critical_tokens_matched,
            'shared_tokens', shared_tokens,
            'match_confidence', match_confidence,
            'should_match', should_match
        );
    END;
END;
$$;


ALTER FUNCTION "public"."calculate_aggressive_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_balanced_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    -- Token counts
    tokens1_count int := COALESCE(array_length(tokens1, 1), 0);
    tokens2_count int := COALESCE(array_length(tokens2, 1), 0);
    shorter_count int := LEAST(tokens1_count, tokens2_count);
    longer_count int := GREATEST(tokens1_count, tokens2_count);
    
    -- Shared tokens
    shared_tokens text[];
    token text;
    intersection_count int := 0;
    union_count int := 0;
    
    -- Scores
    jaccard_score numeric := 0;
    containment_score numeric := 0;
    dice_score numeric := 0;
    final_score numeric := 0;
    
    -- Token analysis
    critical_tokens text[];
    critical_matched int := 0;
    special_edition_tokens text[];
    has_special_edition boolean := false;
    special_edition_match boolean := false;
    
    -- Decision
    match_confidence text;
    should_match boolean := false;
    confidence_level int; -- 1=low, 2=medium, 3=high
BEGIN
    -- Handle empty cases
    IF tokens1_count = 0 OR tokens2_count = 0 THEN
        RETURN jsonb_build_object(
            'final_score', 0,
            'should_match', false,
            'confidence_level', 0,
            'reason', 'empty_tokens'
        );
    END IF;

    -- Get shared tokens
    SELECT array_agg(DISTINCT unnest) INTO shared_tokens
    FROM (
        SELECT unnest(tokens1)
        INTERSECT
        SELECT unnest(tokens2)
    ) t;
    
    intersection_count := COALESCE(array_length(shared_tokens, 1), 0);

    -- Calculate union
    SELECT COUNT(DISTINCT unnest) INTO union_count
    FROM (
        SELECT unnest(tokens1)
        UNION
        SELECT unnest(tokens2)
    ) t;

    -- Calculate base scores
    IF union_count > 0 THEN
        jaccard_score := intersection_count::numeric / union_count::numeric;
    END IF;

    IF shorter_count > 0 THEN
        containment_score := intersection_count::numeric / shorter_count::numeric;
    END IF;
    
    IF (tokens1_count + tokens2_count) > 0 THEN
        dice_score := (2.0 * intersection_count) / (tokens1_count + tokens2_count);
    END IF;

    -- Define critical tokens
    critical_tokens := ARRAY[
        -- Engine specs (highest priority)
        '1.0L', '1.2L', '1.3L', '1.4L', '1.5L', '1.6L', '1.8L', 
        '2.0L', '2.2L', '2.3L', '2.4L', '2.5L', '2.7L', '2.8L',
        '3.0L', '3.2L', '3.3L', '3.5L', '3.6L', '3.7L', '3.8L',
        '4.0L', '4.2L', '4.3L', '4.6L', '4.7L', '5.0L', '5.3L', 
        '5.7L', '6.0L', '6.2L', '6.4L',
        -- Cylinders
        '3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL',
        -- Performance/Trim
        'TURBO', 'BITURBO', 'SPORT', 'GT', 'GTI', 'RS', 'ST', 'SS',
        -- Body type
        'SEDAN', 'SUV', 'HATCHBACK', 'COUPE', 'CONVERTIBLE', 'PICKUP', 'VAN'
    ];

    -- Special editions that should match exactly
    special_edition_tokens := ARRAY[
        'CHILI', 'PEPPER', 'SALT', 'BAKER STREET', 'HYDE PARK',
        'AMG', 'M3', 'M5', 'M SPORT', 'TYPE-R', 'TYPE-S', 'JCW', 
        'JOHN COOPER WORKS', 'NISMO', 'STI', 'SRT', 'HELLCAT'
    ];

    -- Count critical token matches
    IF shared_tokens IS NOT NULL THEN
        SELECT COUNT(*) INTO critical_matched
        FROM unnest(shared_tokens) AS t(token)
        WHERE token = ANY(critical_tokens);

        -- Check for special editions
        FOREACH token IN ARRAY special_edition_tokens
        LOOP
            IF token = ANY(tokens1) OR token = ANY(tokens2) THEN
                has_special_edition := true;
                IF token = ANY(shared_tokens) THEN
                    special_edition_match := true;
                END IF;
                EXIT; -- Found one, that's enough
            END IF;
        END LOOP;
    END IF;

    -- BALANCED SCORING LOGIC v6
    
    -- Case 1: Identical or near-identical
    IF tokens1 = tokens2 OR jaccard_score >= 0.95 THEN
        final_score := 1.0;
        should_match := true;
        confidence_level := 3;
        match_confidence := 'identical';

    -- Case 2: Very short versions (1-2 tokens)
    ELSIF shorter_count <= 2 THEN
        IF containment_score = 1.0 THEN
            -- Perfect subset
            final_score := CASE
                WHEN longer_count <= 4 THEN 0.85
                WHEN longer_count <= 6 THEN 0.75
                ELSE 0.65
            END;
            should_match := true;
            confidence_level := CASE 
                WHEN longer_count <= 4 THEN 3
                WHEN longer_count <= 6 THEN 2
                ELSE 1
            END;
            match_confidence := 'short_subset';
            
        ELSIF intersection_count >= 1 THEN
            -- Partial match
            final_score := 0.60 + (critical_matched * 0.15);
            should_match := (critical_matched >= 1 OR containment_score >= 0.5);
            confidence_level := 1;
            match_confidence := 'short_partial';
            
        ELSE
            -- No match
            final_score := 0;
            should_match := false;
            confidence_level := 0;
            match_confidence := 'no_overlap';
        END IF;

    -- Case 3: Special editions - require exact or near-exact match
    ELSIF has_special_edition THEN
        IF special_edition_match AND containment_score >= 0.80 THEN
            final_score := 0.85 + (critical_matched * 0.03);
            should_match := true;
            confidence_level := 3;
            match_confidence := 'special_edition_match';
        ELSIF NOT special_edition_match THEN
            -- Different special editions should NOT match
            final_score := jaccard_score * 0.4; -- Heavy penalty
            should_match := false;
            confidence_level := 0;
            match_confidence := 'special_edition_conflict';
        ELSE
            -- Has special edition but low overlap
            final_score := jaccard_score * 0.6;
            should_match := false;
            confidence_level := 1;
            match_confidence := 'special_edition_weak';
        END IF;

    -- Case 4: High containment (subset matching)
    ELSIF containment_score >= 0.80 THEN
        -- One version is mostly contained in the other
        final_score := 0.70 + 
                      (containment_score - 0.80) * 0.5 + -- Boost for higher containment
                      (critical_matched * 0.05) + -- Boost for critical tokens
                      CASE 
                          WHEN longer_count - shorter_count <= 3 THEN 0.10
                          WHEN longer_count - shorter_count <= 5 THEN 0.05
                          ELSE 0
                      END;
        should_match := true;
        confidence_level := CASE
            WHEN containment_score >= 0.90 THEN 3
            WHEN critical_matched >= 2 THEN 2
            ELSE 1
        END;
        match_confidence := 'high_containment';

    -- Case 5: Good overlap with critical tokens
    ELSIF intersection_count >= 3 AND critical_matched >= 1 THEN
        -- Calculate weighted score
        final_score := (jaccard_score * 0.3 + 
                       containment_score * 0.3 + 
                       dice_score * 0.2 +
                       (critical_matched * 0.08) +
                       CASE 
                           WHEN intersection_count >= 5 THEN 0.12
                           WHEN intersection_count >= 4 THEN 0.08
                           ELSE 0.04
                       END);
        
        should_match := final_score >= 0.50;
        confidence_level := CASE
            WHEN final_score >= 0.70 THEN 2
            ELSE 1
        END;
        match_confidence := 'weighted_overlap';

    -- Case 6: Moderate overlap
    ELSIF intersection_count >= 2 THEN
        final_score := (jaccard_score * 0.4 + containment_score * 0.6) + 
                      (critical_matched * 0.10);
        
        should_match := final_score >= 0.55 OR 
                       (containment_score >= 0.67 AND critical_matched >= 1);
        confidence_level := 1;
        match_confidence := 'moderate_overlap';

    -- Case 7: Poor match
    ELSE
        final_score := jaccard_score * 0.5;
        should_match := false;
        confidence_level := 0;
        match_confidence := 'poor_match';
    END IF;

    -- Adjust for same/different insurer context
    IF is_same_insurer THEN
        -- Same insurer: can be slightly more aggressive
        IF confidence_level = 1 AND final_score >= 0.48 THEN
            should_match := true;
        END IF;
    ELSE
        -- Different insurers: apply balanced thresholds
        -- Already handled in main logic, but can add adjustments here
        IF confidence_level >= 2 OR 
           (confidence_level = 1 AND final_score >= 0.52) THEN
            should_match := true;
        END IF;
    END IF;

    -- Ensure score is capped
    final_score := LEAST(final_score, 1.0);

    RETURN jsonb_build_object(
        'final_score', ROUND(final_score, 3),
        'jaccard_score', ROUND(jaccard_score, 3),
        'containment_score', ROUND(containment_score, 3),
        'dice_score', ROUND(dice_score, 3),
        'intersection_count', intersection_count,
        'union_count', union_count,
        'critical_matched', critical_matched,
        'has_special_edition', has_special_edition,
        'special_edition_match', special_edition_match,
        'confidence_level', confidence_level,
        'match_confidence', match_confidence,
        'should_match', should_match,
        'tokens1_count', tokens1_count,
        'tokens2_count', tokens2_count
    );
END;
$$;


ALTER FUNCTION "public"."calculate_balanced_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_jaccard_match"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
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


ALTER FUNCTION "public"."calculate_jaccard_match"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_jaccard_similarity"("tokens1" "text"[], "tokens2" "text"[]) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    intersection_count int;
    union_count int;
    jaccard_score numeric;
BEGIN
    -- Handle empty arrays
    IF array_length(tokens1, 1) IS NULL OR array_length(tokens2, 1) IS NULL THEN
        RETURN 0.0;
    END IF;

    -- Calculate intersection size
    SELECT COUNT(DISTINCT token)
    INTO intersection_count
    FROM (
        SELECT unnest(tokens1) AS token
        INTERSECT
        SELECT unnest(tokens2)
    ) t;

    -- Calculate union size
    SELECT COUNT(DISTINCT token)
    INTO union_count
    FROM (
        SELECT unnest(tokens1) AS token
        UNION
        SELECT unnest(tokens2)
    ) t;

    -- Calculate Jaccard coefficient
    IF union_count = 0 THEN
        RETURN 0.0;
    ELSE
        jaccard_score := intersection_count::numeric / union_count::numeric;
    END IF;

    RETURN ROUND(jaccard_score, 4);
END;
$$;


ALTER FUNCTION "public"."calculate_jaccard_similarity"("tokens1" "text"[], "tokens2" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_match_score"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[]) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
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
        jaccard_score     * 0.50 +
        overlap_ratio     * 0.30 +
        trigram_score     * 0.05 +
        levenshtein_score * 0.10 +
        metaphone_score   * 0.05
    ) + numeric_bonus;

    RETURN LEAST(ROUND(combined_score, 3), 1.0);
END;
$$;


ALTER FUNCTION "public"."calculate_match_score"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_match_score_v2"("v1_tokens" "text"[], "v2_tokens" "text"[]) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    score numeric := 0;
    common_tokens int := 0;
    i int;
BEGIN
    IF array_length(v1_tokens, 1) IS NULL OR array_length(v2_tokens, 1) IS NULL THEN
        RETURN 0;
    END IF;
    
    -- 1. TRIM MATCH (primeros tokens) - 30% del peso
    IF v1_tokens[1] = v2_tokens[1] THEN
        score := score + 0.20;
    ELSIF v1_tokens[1] = ANY(v2_tokens[1:3]) OR v2_tokens[1] = ANY(v1_tokens[1:3]) THEN
        score := score + 0.10;
    END IF;
    
    -- 2. MOTOR MATCH - 30% del peso
    IF ('4cil' = ANY(v1_tokens) AND '4cil' = ANY(v2_tokens)) OR
       ('6cil' = ANY(v1_tokens) AND '6cil' = ANY(v2_tokens)) OR
       ('8cil' = ANY(v1_tokens) AND '8cil' = ANY(v2_tokens)) OR
       ('l4' = ANY(v1_tokens) AND ('l4' = ANY(v2_tokens) OR '4cil' = ANY(v2_tokens))) OR
       ('v6' = ANY(v1_tokens) AND ('v6' = ANY(v2_tokens) OR '6cil' = ANY(v2_tokens))) OR
       ('v8' = ANY(v1_tokens) AND ('v8' = ANY(v2_tokens) OR '8cil' = ANY(v2_tokens))) THEN
        score := score + 0.30;
    END IF;
    
    -- 3. TOKENS COMUNES - 40% del peso
    FOR i IN 1..array_length(v1_tokens, 1)
    LOOP
        IF v1_tokens[i] = ANY(v2_tokens) THEN
            common_tokens := common_tokens + 1;
        END IF;
    END LOOP;
    
    -- Ratio de tokens comunes
    score := score + (common_tokens::numeric / 
             GREATEST(array_length(v1_tokens, 1), array_length(v2_tokens, 1))) * 0.40;
    
    RETURN LEAST(score, 1.0);
END;
$$;


ALTER FUNCTION "public"."calculate_match_score_v2"("v1_tokens" "text"[], "v2_tokens" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_match_score_v4"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[], "use_cache" boolean DEFAULT true) RETURNS numeric
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    trigram_score numeric := 0;
    jaccard_score numeric := 0;
    levenshtein_score numeric := 0;
    token_position_score numeric := 0;
    combined_score numeric;
    cached_score numeric;
    max_length int;
    common_tokens_count int;
    v1_normalized text;
    v2_normalized text;
BEGIN
    v1_normalized := UPPER(TRIM(version1));
    v2_normalized := UPPER(TRIM(version2));
    
    -- Verificar caché
    IF use_cache THEN
        SELECT score INTO cached_score
        FROM match_cache
        WHERE (version1 = v1_normalized AND version2 = v2_normalized)
           OR (version1 = v2_normalized AND version2 = v1_normalized)
        LIMIT 1;
        
        IF cached_score IS NOT NULL THEN
            RETURN cached_score;
        END IF;
    END IF;
    
    -- Versiones muy cortas
    IF length(v1_normalized) <= 3 OR length(v2_normalized) <= 3 THEN
        IF v1_normalized = v2_normalized THEN
            RETURN 1.0;
        END IF;
        RETURN similarity(v1_normalized, v2_normalized);
    END IF;
    
    -- 1. Trigram similarity
    trigram_score := similarity(v1_normalized, v2_normalized);
    
    -- 2. Jaccard similarity
    jaccard_score := jaccard_similarity(tokens1, tokens2);
    
    -- 3. Levenshtein normalizado
    max_length := GREATEST(length(v1_normalized), length(v2_normalized));
    IF max_length > 0 AND max_length < 255 THEN
        levenshtein_score := 1.0 - (
            levenshtein_less_equal(
                substring(v1_normalized, 1, 255),
                substring(v2_normalized, 1, 255),
                max_length
            )::numeric / max_length
        );
    END IF;
    
    -- 4. Token position similarity
    -- CORRECCIÓN: Contar tokens comunes sin usar operador &
    SELECT COUNT(DISTINCT t) INTO common_tokens_count
    FROM (
        SELECT unnest(tokens1) AS t
        INTERSECT
        SELECT unnest(tokens2)
    ) AS common;
    
    IF common_tokens_count > 0 THEN
        IF array_length(tokens1, 1) > 0 AND array_length(tokens2, 1) > 0 
           AND tokens1[1] = tokens2[1] THEN
            token_position_score := token_position_score + 0.5;
        END IF;
        IF array_length(tokens1, 1) > 1 AND array_length(tokens2, 1) > 1 
           AND tokens1[2] = tokens2[2] THEN
            token_position_score := token_position_score + 0.3;
        END IF;
        -- Bonus por números compartidos
        IF EXISTS (
            SELECT 1 
            FROM (
                SELECT unnest(tokens1) AS t
                INTERSECT
                SELECT unnest(tokens2)
            ) common_tokens
            WHERE t ~ '^[0-9]'
        ) THEN
            token_position_score := token_position_score + 0.2;
        END IF;
    END IF;
    
    -- Combinar scores
    combined_score := (
        jaccard_score * 0.40 +
        trigram_score * 0.30 +
        levenshtein_score * 0.20 +
        token_position_score * 0.10
    );
    
    -- Guardar en caché
    IF use_cache THEN
        INSERT INTO match_cache (hash_comercial, version1, version2, score)
        VALUES ('', v1_normalized, v2_normalized, ROUND(combined_score, 3))
        ON CONFLICT DO NOTHING;
    END IF;
    
    RETURN ROUND(combined_score, 3);
END;
$$;


ALTER FUNCTION "public"."calculate_match_score_v4"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[], "use_cache" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_match_score_v5"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[], "use_cache" boolean DEFAULT true) RETURNS numeric
    LANGUAGE "plpgsql"
    AS $_$
DECLARE
    trigram_score numeric := 0;
    jaccard_score numeric := 0;
    levenshtein_score numeric := 0;
    token_position_score numeric := 0;
    important_token_score numeric := 0;
    combined_score numeric;
    cached_score numeric;
    max_length int;
    v1_normalized text;
    v2_normalized text;
    i int;
BEGIN
    v1_normalized := UPPER(TRIM(COALESCE(version1, '')));
    v2_normalized := UPPER(TRIM(COALESCE(version2, '')));
    
    -- Verificar caché
    IF use_cache THEN
        SELECT score INTO cached_score
        FROM match_cache
        WHERE hash_comercial = ''
          AND ((version1 = v1_normalized AND version2 = v2_normalized)
            OR (version1 = v2_normalized AND version2 = v1_normalized))
        LIMIT 1;
        
        IF cached_score IS NOT NULL THEN
            UPDATE match_cache 
            SET hits = COALESCE(hits, 0) + 1, fecha_calculo = now()
            WHERE hash_comercial = ''
              AND ((version1 = v1_normalized AND version2 = v2_normalized)
                OR (version1 = v2_normalized AND version2 = v1_normalized));
            RETURN cached_score;
        END IF;
    END IF;
    
    -- Match exacto
    IF v1_normalized = v2_normalized THEN
        RETURN 1.0;
    END IF;
    
    -- Versiones muy cortas
    IF length(v1_normalized) <= 3 OR length(v2_normalized) <= 3 THEN
        RETURN similarity(v1_normalized, v2_normalized);
    END IF;
    
    -- Calcular diferentes métricas
    trigram_score := similarity(v1_normalized, v2_normalized);
    jaccard_score := jaccard_similarity(tokens1, tokens2);
    
    max_length := GREATEST(length(v1_normalized), length(v2_normalized));
    IF max_length > 0 AND max_length < 255 THEN
        levenshtein_score := 1.0 - (levenshtein_less_equal(
            substring(v1_normalized, 1, 255),
            substring(v2_normalized, 1, 255),
            max_length
        )::numeric / max_length);
    END IF;
    
    -- Token position scoring
    IF array_length(tokens1, 1) > 0 AND array_length(tokens2, 1) > 0 THEN
        IF tokens1[1] = tokens2[1] THEN
            token_position_score := token_position_score + 0.4;
        END IF;
        IF array_length(tokens1, 1) > 1 AND array_length(tokens2, 1) > 1 
           AND tokens1[2] = tokens2[2] THEN
            token_position_score := token_position_score + 0.3;
        END IF;
        IF tokens1[array_length(tokens1, 1)] = tokens2[array_length(tokens2, 1)] THEN
            token_position_score := token_position_score + 0.3;
        END IF;
    END IF;
    
    -- Important tokens scoring
    IF array_length(tokens1, 1) > 0 AND array_length(tokens2, 1) > 0 THEN
        FOR i IN 1..array_length(tokens1, 1) LOOP
            IF tokens1[i] = ANY(tokens2) THEN
                IF tokens1[i] ~ '^[0-9]+\.?[0-9]*L$' OR  
                   tokens1[i] ~ '^[V|I|L][0-9]+$' OR      
                   tokens1[i] ~ '^[0-9]+P$' OR            
                   tokens1[i] IN ('TURBO', 'SPORT', 'BASE', 'LUXURY', 'LIMITED', 
                                  'AUTO', 'MANUAL', 'CVT', 'DSG', 'AMT',
                                  '4X4', '4X2', 'AWD', 'FWD', 'RWD') THEN
                    important_token_score := important_token_score + 0.2;
                END IF;
            END IF;
        END LOOP;
    END IF;
    
    important_token_score := LEAST(important_token_score, 1.0);
    
    -- Combinar scores
    combined_score := (
        jaccard_score * 0.35 +          
        trigram_score * 0.25 +          
        COALESCE(levenshtein_score, 0) * 0.15 +      
        token_position_score * 0.15 +   
        important_token_score * 0.10    
    );
    
    -- Guardar en caché
    IF use_cache THEN
        INSERT INTO match_cache (hash_comercial, version1, version2, score, hits)
        VALUES ('', v1_normalized, v2_normalized, ROUND(combined_score, 3), 1)
        ON CONFLICT (hash_comercial, version1, version2) 
        DO UPDATE SET 
            score = ROUND(combined_score, 3),
            hits = COALESCE(match_cache.hits, 0) + 1,
            fecha_calculo = now();
    END IF;
    
    RETURN ROUND(combined_score, 3);
END;
$_$;


ALTER FUNCTION "public"."calculate_match_score_v5"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[], "use_cache" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_similarity"("tokens1" "text"[], "tokens2" "text"[], "len1" integer DEFAULT NULL::integer, "len2" integer DEFAULT NULL::integer) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    intersection_size int;
    union_size int;
    jaccard_score numeric;
    size_penalty numeric := 1.0;
    len_ratio numeric;
BEGIN
    -- Validación
    IF tokens1 IS NULL OR tokens2 IS NULL THEN
        RETURN 0;
    END IF;
    
    -- Calcular longitudes si no se proporcionan
    IF len1 IS NULL THEN len1 := array_length(tokens1, 1); END IF;
    IF len2 IS NULL THEN len2 := array_length(tokens2, 1); END IF;
    
    IF len1 IS NULL OR len2 IS NULL OR len1 = 0 OR len2 = 0 THEN
        RETURN 0;
    END IF;
    
    -- Calcular intersección y unión
    SELECT COUNT(DISTINCT token) INTO intersection_size
    FROM (SELECT unnest(tokens1) AS token INTERSECT SELECT unnest(tokens2) AS token) t;
    
    SELECT COUNT(DISTINCT token) INTO union_size
    FROM (SELECT unnest(tokens1) AS token UNION SELECT unnest(tokens2) AS token) t;
    
    IF union_size = 0 THEN
        RETURN 0;
    END IF;
    
    -- Jaccard base
    jaccard_score := intersection_size::numeric / union_size::numeric;
    
    -- Penalización por diferencia de tamaño
    len_ratio := LEAST(len1, len2)::numeric / GREATEST(len1, len2)::numeric;
    IF len_ratio < 0.5 THEN
        -- Si un conjunto es más del doble del otro, aplicar penalización
        size_penalty := 0.9;
    END IF;
    
    -- Bonificación por alta intersección
    IF intersection_size >= 3 AND intersection_size >= LEAST(len1, len2) * 0.8 THEN
        -- Si comparten 3+ tokens y es 80%+ del conjunto menor, bonus
        RETURN LEAST(jaccard_score * size_penalty * 1.1, 1.0);
    END IF;
    
    RETURN ROUND(jaccard_score * size_penalty, 3);
END;
$$;


ALTER FUNCTION "public"."calculate_similarity"("tokens1" "text"[], "tokens2" "text"[], "len1" integer, "len2" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_simple_match_score"("v1_tokens" "text"[], "v2_tokens" "text"[]) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    common_count int;
    total_unique int;
    jaccard_score numeric;
    key_features_match numeric := 0;
    
    -- Características clave
    v1_has_4cil boolean;
    v2_has_4cil boolean;
    v1_has_6cil boolean;
    v2_has_6cil boolean;
    v1_has_turbo boolean;
    v2_has_turbo boolean;
BEGIN
    -- Si alguno está vacío, retornar 0
    IF array_length(v1_tokens, 1) IS NULL OR array_length(v2_tokens, 1) IS NULL THEN
        RETURN 0;
    END IF;
    
    -- Calcular Jaccard básico
    SELECT COUNT(*)
    INTO common_count
    FROM unnest(v1_tokens) t1
    WHERE t1 = ANY(v2_tokens);
    
    total_unique := array_length(
        ARRAY(
            SELECT DISTINCT unnest FROM (
                SELECT unnest(v1_tokens)
                UNION
                SELECT unnest(v2_tokens)
            ) t
        ), 1
    );
    
    IF total_unique > 0 THEN
        jaccard_score := common_count::numeric / total_unique;
    ELSE
        RETURN 0;
    END IF;
    
    -- Bonus por características clave que coinciden
    -- Cilindros
    v1_has_4cil := '4cil' = ANY(v1_tokens) OR 'l4' = ANY(v1_tokens) OR '4cyl' = ANY(v1_tokens);
    v2_has_4cil := '4cil' = ANY(v2_tokens) OR 'l4' = ANY(v2_tokens) OR '4cyl' = ANY(v2_tokens);
    v1_has_6cil := '6cil' = ANY(v1_tokens) OR 'v6' = ANY(v1_tokens) OR '6cyl' = ANY(v1_tokens);
    v2_has_6cil := '6cil' = ANY(v2_tokens) OR 'v6' = ANY(v2_tokens) OR '6cyl' = ANY(v2_tokens);
    
    -- Si ambos especifican cilindros y no coinciden, penalizar fuertemente
    IF (v1_has_4cil OR v1_has_6cil) AND (v2_has_4cil OR v2_has_6cil) THEN
        IF v1_has_4cil = v2_has_4cil AND v1_has_6cil = v2_has_6cil THEN
            key_features_match := key_features_match + 0.2; -- Bonus si coinciden
        ELSE
            RETURN jaccard_score * 0.3; -- Penalización severa si no coinciden
        END IF;
    END IF;
    
    -- Turbo
    v1_has_turbo := 'turbo' = ANY(v1_tokens) OR 't' = ANY(v1_tokens) OR 
                    '15t' = ANY(v1_tokens) OR '20t' = ANY(v1_tokens) OR
                    'tfsi' = ANY(v1_tokens) OR 'tsi' = ANY(v1_tokens);
    v2_has_turbo := 'turbo' = ANY(v2_tokens) OR 't' = ANY(v2_tokens) OR 
                    '15t' = ANY(v2_tokens) OR '20t' = ANY(v2_tokens) OR
                    'tfsi' = ANY(v2_tokens) OR 'tsi' = ANY(v2_tokens);
    
    IF v1_has_turbo = v2_has_turbo THEN
        key_features_match := key_features_match + 0.1;
    END IF;
    
    -- AWD/4WD
    IF ('awd' = ANY(v1_tokens) OR '4wd' = ANY(v1_tokens) OR '4x4' = ANY(v1_tokens)) = 
       ('awd' = ANY(v2_tokens) OR '4wd' = ANY(v2_tokens) OR '4x4' = ANY(v2_tokens)) THEN
        key_features_match := key_features_match + 0.1;
    END IF;
    
    -- Score final: Jaccard + bonus por características clave
    RETURN LEAST(jaccard_score + key_features_match, 1.0);
END;
$$;


ALTER FUNCTION "public"."calculate_simple_match_score"("v1_tokens" "text"[], "v2_tokens" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_smart_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $_$
DECLARE
    -- Token counts
    tokens1_count int := COALESCE(array_length(tokens1, 1), 0);
    tokens2_count int := COALESCE(array_length(tokens2, 1), 0);
    shorter_count int := LEAST(tokens1_count, tokens2_count);
    longer_count int := GREATEST(tokens1_count, tokens2_count);
    
    -- Intersection and shared tokens
    shared_tokens text[];
    token text;  -- For FOREACH loop
    intersection_count int := 0;
    union_count int := 0;
    
    -- Scores
    jaccard_score numeric := 0;
    containment_score numeric := 0;
    weighted_score numeric := 0;
    final_score numeric := 0;
    
    -- Critical token analysis
    critical_tokens text[];
    critical_matched int := 0;
    has_displacement boolean := false;
    has_cylinders boolean := false;
    has_trim boolean := false;
    has_special_edition boolean := false;
    
    -- Decision variables
    match_confidence text;
    should_match boolean := false;
BEGIN
    -- Handle empty cases
    IF tokens1_count = 0 OR tokens2_count = 0 THEN
        RETURN jsonb_build_object(
            'final_score', 0,
            'should_match', false,
            'reason', 'empty_tokens'
        );
    END IF;

    -- Get shared tokens
    SELECT array_agg(DISTINCT unnest) INTO shared_tokens
    FROM (
        SELECT unnest(tokens1)
        INTERSECT
        SELECT unnest(tokens2)
    ) t;
    
    intersection_count := COALESCE(array_length(shared_tokens, 1), 0);

    -- Calculate union
    SELECT COUNT(DISTINCT unnest) INTO union_count
    FROM (
        SELECT unnest(tokens1)
        UNION
        SELECT unnest(tokens2)
    ) t;

    -- Base scores
    IF union_count > 0 THEN
        jaccard_score := intersection_count::numeric / union_count::numeric;
    END IF;

    IF shorter_count > 0 THEN
        containment_score := intersection_count::numeric / shorter_count::numeric;
    END IF;

    -- Analyze critical tokens
    critical_tokens := ARRAY[
        -- Displacements
        '1.0L', '1.2L', '1.3L', '1.4L', '1.5L', '1.6L', '1.8L', 
        '2.0L', '2.2L', '2.3L', '2.4L', '2.5L', '2.7L', '2.8L',
        '3.0L', '3.2L', '3.3L', '3.5L', '3.6L', '3.7L', '3.8L',
        '4.0L', '4.2L', '4.3L', '4.6L', '4.7L', '5.0L', '5.3L', 
        '5.7L', '6.0L', '6.2L', '6.4L',
        -- Cylinders
        '3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL',
        -- Premium trims
        'AMG', 'M3', 'M5', 'RS', 'TYPE-R', 'TYPE-S', 'JCW', 'JOHN COOPER WORKS',
        -- Special editions (important for MINI/BMW)
        'CHILI', 'PEPPER', 'SALT', 'BAKER STREET', 'HYDE PARK'
    ];

    -- Check what types of critical tokens match (FIXED FOREACH)
    IF shared_tokens IS NOT NULL THEN
        FOREACH token IN ARRAY shared_tokens
        LOOP
            IF token ~ '^\d+\.\d+L$' THEN
                has_displacement := true;
            ELSIF token ~ '^\d+CIL$' THEN
                has_cylinders := true;
            ELSIF token = ANY(ARRAY['AMG', 'M3', 'M5', 'RS', 'TYPE-R', 'TYPE-S', 'JCW', 'JOHN COOPER WORKS']) THEN
                has_trim := true;
            ELSIF token = ANY(ARRAY['CHILI', 'PEPPER', 'SALT', 'BAKER STREET', 'HYDE PARK']) THEN
                has_special_edition := true;
            END IF;
        END LOOP;

        SELECT COUNT(*) INTO critical_matched
        FROM unnest(shared_tokens) AS t(token)
        WHERE token = ANY(critical_tokens);
    END IF;

    -- SMART SCORING LOGIC v5
    
    -- Case 1: Very short versions (1-2 tokens)
    IF shorter_count <= 2 THEN
        IF shorter_count = 1 AND longer_count = 1 THEN
            -- Both are single token
            final_score := CASE WHEN intersection_count = 1 THEN 1.0 ELSE 0.0 END;
            should_match := intersection_count = 1;
            match_confidence := 'single_token';
            
        ELSIF containment_score = 1.0 THEN
            -- Short is perfect subset
            final_score := CASE 
                WHEN longer_count - shorter_count <= 3 THEN 0.90  -- Close enough
                WHEN longer_count - shorter_count <= 5 THEN 0.75  -- Moderate difference
                ELSE 0.60  -- Large difference
            END;
            should_match := true;
            match_confidence := 'perfect_subset';
            
        ELSIF intersection_count >= 1 AND critical_matched >= 1 THEN
            -- Has critical token match
            final_score := 0.65 + (critical_matched * 0.10);
            should_match := NOT has_special_edition OR containment_score >= 0.5;
            match_confidence := 'critical_match';
            
        ELSE
            -- Poor match
            final_score := containment_score * 0.5;
            should_match := false;
            match_confidence := 'poor_short';
        END IF;

    -- Case 2: Special edition handling (MINI/BMW)
    ELSIF has_special_edition THEN
        -- These need exact or near-exact matching on edition name
        IF containment_score >= 0.90 OR 
           (jaccard_score >= 0.70 AND critical_matched >= 2) THEN
            final_score := 0.85 + (critical_matched * 0.05);
            should_match := true;
            match_confidence := 'special_edition_match';
        ELSE
            -- Different special editions should NOT match
            final_score := jaccard_score * 0.5;  -- Penalize
            should_match := false;
            match_confidence := 'special_edition_mismatch';
        END IF;

    -- Case 3: Perfect or near-perfect containment
    ELSIF containment_score >= 0.85 THEN
        -- Adjust score based on size difference
        IF longer_count - shorter_count <= 2 THEN
            final_score := 0.95;
            match_confidence := 'near_perfect_subset';
        ELSIF longer_count - shorter_count <= 4 THEN
            final_score := 0.85 + (critical_matched * 0.03);
            match_confidence := 'good_subset';
        ELSE
            final_score := 0.75 + (critical_matched * 0.03);
            match_confidence := 'partial_subset';
        END IF;
        should_match := true;

    -- Case 4: Good overlap with critical tokens
    ELSIF containment_score >= 0.60 AND critical_matched >= 1 THEN
        -- Weight by critical token importance
        weighted_score := containment_score * 0.6 + 
                         (critical_matched * 0.1) +
                         CASE 
                             WHEN has_displacement THEN 0.15
                             WHEN has_cylinders THEN 0.10
                             WHEN has_trim THEN 0.15
                             ELSE 0.0
                         END;
        final_score := LEAST(weighted_score, 1.0);
        should_match := final_score >= 0.55;
        match_confidence := 'weighted_critical';

    -- Case 5: Standard scoring
    ELSE
        final_score := (jaccard_score * 0.5 + containment_score * 0.5) + 
                      (critical_matched * 0.05);
        final_score := LEAST(final_score, 1.0);
        should_match := final_score >= 0.50;
        match_confidence := 'standard';
    END IF;

    -- Adjust thresholds based on context
    IF is_same_insurer THEN
        -- Same insurer: slightly stricter for quality
        should_match := should_match AND final_score >= 0.55;
    ELSE
        -- Different insurers: more aggressive
        should_match := should_match OR 
                       (containment_score >= 0.60 AND intersection_count >= 2) OR
                       (critical_matched >= 2 AND intersection_count >= 2);
    END IF;

    RETURN jsonb_build_object(
        'final_score', ROUND(final_score, 3),
        'jaccard_score', ROUND(jaccard_score, 3),
        'containment_score', ROUND(containment_score, 3),
        'intersection_count', intersection_count,
        'critical_matched', critical_matched,
        'has_displacement', has_displacement,
        'has_cylinders', has_cylinders,
        'has_trim', has_trim,
        'has_special_edition', has_special_edition,
        'match_confidence', match_confidence,
        'should_match', should_match,
        'tokens1_count', tokens1_count,
        'tokens2_count', tokens2_count
    );
END;
$_$;


ALTER FUNCTION "public"."calculate_smart_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_smart_similarity"("v1_tokens" "text"[], "v2_tokens" "text"[]) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    score numeric := 0;
    token_weight numeric;
    i int;
    token text;
    
    -- Contadores para matching
    trim_match boolean := false;
    technical_matches int := 0;
    total_matches int := 0;
BEGIN
    IF array_length(v1_tokens, 1) IS NULL OR array_length(v2_tokens, 1) IS NULL THEN
        RETURN 0;
    END IF;
    
    -- ESTRATEGIA: Dar más peso a tokens según su posición y tipo
    
    -- 1. TRIM (primeros 2-3 tokens) - 40% del peso total
    -- Los TRIMs casi siempre están al inicio
    FOR i IN 1..LEAST(3, array_length(v1_tokens, 1))
    LOOP
        token := v1_tokens[i];
        -- Si el token inicial de v1 existe en los primeros tokens de v2
        IF token = ANY(v2_tokens[1:3]) THEN
            -- No es un token técnico (números, cilindros, etc)
            IF NOT token ~ '^\d+' AND 
               token NOT IN ('4cil','6cil','8cil','l4','v6','v8','auto','manual',
                            '2puertas','3puertas','4puertas','5puertas',
                            '5ocup','7ocup','suv','sedan','hatchback') THEN
                trim_match := true;
                score := score + 0.15;  -- Cada token de TRIM vale mucho
            END IF;
        END IF;
    END LOOP;
    
    -- 2. CARACTERÍSTICAS TÉCNICAS CRÍTICAS - 40% del peso
    -- Motor
    IF ('4cil' = ANY(v1_tokens) AND '4cil' = ANY(v2_tokens)) OR
       ('l4' = ANY(v1_tokens) AND 'l4' = ANY(v2_tokens)) OR
       ('6cil' = ANY(v1_tokens) AND '6cil' = ANY(v2_tokens)) OR
       ('v6' = ANY(v1_tokens) AND 'v6' = ANY(v2_tokens)) OR
       ('8cil' = ANY(v1_tokens) AND '8cil' = ANY(v2_tokens)) OR
       ('v8' = ANY(v1_tokens) AND 'v8' = ANY(v2_tokens)) THEN
        score := score + 0.20;
        technical_matches := technical_matches + 1;
    ELSIF ('4cil' = ANY(v1_tokens) AND '6cil' = ANY(v2_tokens)) OR
          ('4cil' = ANY(v1_tokens) AND '8cil' = ANY(v2_tokens)) OR
          ('6cil' = ANY(v1_tokens) AND '8cil' = ANY(v2_tokens)) THEN
        -- Motores diferentes = NO es el mismo vehículo
        RETURN 0;
    END IF;
    
    -- Turbo
    IF (('turbo' = ANY(v1_tokens) OR 't' = ANY(v1_tokens) OR 
         '15t' = ANY(v1_tokens) OR '20t' = ANY(v1_tokens)) AND
        ('turbo' = ANY(v2_tokens) OR 't' = ANY(v2_tokens) OR 
         '15t' = ANY(v2_tokens) OR '20t' = ANY(v2_tokens))) THEN
        score := score + 0.10;
        technical_matches := technical_matches + 1;
    END IF;
    
    -- AWD/Tracción
    IF (('awd' = ANY(v1_tokens) OR '4wd' = ANY(v1_tokens) OR '4x4' = ANY(v1_tokens)) AND
        ('awd' = ANY(v2_tokens) OR '4wd' = ANY(v2_tokens) OR '4x4' = ANY(v2_tokens))) THEN
        score := score + 0.10;
        technical_matches := technical_matches + 1;
    END IF;
    
    -- 3. TOKENS RESTANTES - 20% del peso
    -- Contar coincidencias generales
    FOR i IN 1..array_length(v1_tokens, 1)
    LOOP
        IF v1_tokens[i] = ANY(v2_tokens) THEN
            total_matches := total_matches + 1;
        END IF;
    END LOOP;
    
    -- Agregar score por coincidencias generales (máximo 0.20)
    score := score + LEAST(0.20, 
        (total_matches::numeric / GREATEST(array_length(v1_tokens, 1), array_length(v2_tokens, 1))) * 0.20
    );
    
    -- BONUS: Si hay match de TRIM Y características técnicas
    IF trim_match AND technical_matches > 0 THEN
        score := score + 0.10;
    END IF;
    
    RETURN LEAST(score, 1.0);
END;
$$;


ALTER FUNCTION "public"."calculate_smart_similarity"("v1_tokens" "text"[], "v2_tokens" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_token_overlap"("tokens1" "text"[], "tokens2" "text"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    intersection_count int := 0;
    union_count int := 0;
    tokens1_count int := COALESCE(array_length(tokens1, 1), 0);
    tokens2_count int := COALESCE(array_length(tokens2, 1), 0);
    min_tokens int := LEAST(tokens1_count, tokens2_count);
    max_tokens int := GREATEST(tokens1_count, tokens2_count);
    overlap_ratio numeric := 0;
    jaccard_score numeric := 0;
    critical_tokens_matched int := 0;
    critical_tokens text[];
BEGIN
    -- Handle empty cases
    IF tokens1_count = 0 OR tokens2_count = 0 THEN
        RETURN jsonb_build_object(
            'jaccard_score', 0,
            'intersection_count', 0,
            'union_count', 0,
            'overlap_ratio', 0,
            'critical_tokens_matched', 0,
            'tokens1_count', tokens1_count,
            'tokens2_count', tokens2_count
        );
    END IF;

    -- Calculate intersection
    SELECT COUNT(DISTINCT unnest)
    INTO intersection_count
    FROM (
        SELECT unnest(tokens1)
        INTERSECT
        SELECT unnest(tokens2)
    ) t;

    -- Calculate union
    SELECT COUNT(DISTINCT unnest)
    INTO union_count
    FROM (
        SELECT unnest(tokens1)
        UNION
        SELECT unnest(tokens2)
    ) t;

    -- Calculate Jaccard score
    IF union_count > 0 THEN
        jaccard_score := intersection_count::numeric / union_count::numeric;
    END IF;

    -- Calculate overlap ratio (intersection / minimum set size)
    IF min_tokens > 0 THEN
        overlap_ratio := intersection_count::numeric / min_tokens::numeric;
    END IF;

    -- Define critical tokens (engine specs, trim levels, body types)
    critical_tokens := ARRAY[
        -- Engine displacements
        '1.0L', '1.2L', '1.3L', '1.4L', '1.5L', '1.6L', '1.8L', 
        '2.0L', '2.2L', '2.3L', '2.4L', '2.5L', '2.7L', '2.8L',
        '3.0L', '3.2L', '3.3L', '3.5L', '3.6L', '3.7L', '3.8L',
        '4.0L', '4.2L', '4.3L', '4.6L', '4.7L', '5.0L', '5.3L', 
        '5.7L', '6.0L', '6.2L', '6.4L',
        -- Cylinders
        '3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL',
        -- Common trim levels
        'BASE', 'SPORT', 'LUXURY', 'PREMIUM', 'LIMITED', 'TOURING',
        'TECH', 'ADVANCE', 'ELITE', 'EXECUTIVE', 'PLATINUM',
        -- Body types
        'SEDAN', 'SUV', 'HATCHBACK', 'COUPE', 'CONVERTIBLE', 
        'PICKUP', 'VAN', 'MINIVAN', 'WAGON',
        -- Doors
        '2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS',
        -- Performance
        'TURBO', 'BITURBO', 'SPORT', 'TYPE-R', 'TYPE-S', 'A-SPEC', 'S-LINE',
        -- Drivetrain
        'AWD', '4WD', 'FWD', 'RWD'
    ];

    -- Count critical tokens that match
    SELECT COUNT(DISTINCT token)
    INTO critical_tokens_matched
    FROM (
        SELECT unnest(tokens1) AS token
        INTERSECT
        SELECT unnest(tokens2)
    ) matched
    WHERE matched.token = ANY(critical_tokens);

    RETURN jsonb_build_object(
        'jaccard_score', ROUND(jaccard_score, 3),
        'intersection_count', intersection_count,
        'union_count', union_count,
        'overlap_ratio', ROUND(overlap_ratio, 3),
        'critical_tokens_matched', critical_tokens_matched,
        'tokens1_count', tokens1_count,
        'tokens2_count', tokens2_count,
        'min_tokens', min_tokens,
        'max_tokens', max_tokens
    );
END;
$$;


ALTER FUNCTION "public"."calculate_token_overlap"("tokens1" "text"[], "tokens2" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_token_similarity"("tokens_a" "text"[], "tokens_b" "text"[]) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE PARALLEL SAFE
    AS $$
DECLARE
    intersection_count INTEGER;
    union_count INTEGER;
BEGIN
    -- Handle nulls and empty arrays
    IF tokens_a IS NULL OR tokens_b IS NULL OR 
       array_length(tokens_a, 1) IS NULL OR array_length(tokens_b, 1) IS NULL THEN
        RETURN 0;
    END IF;
    
    -- If identical, return 1
    IF tokens_a = tokens_b THEN
        RETURN 1.0;
    END IF;
    
    -- Calculate intersection size
    SELECT COUNT(*)
    INTO intersection_count
    FROM (
        SELECT unnest(tokens_a)
        INTERSECT
        SELECT unnest(tokens_b)
    ) AS intersection;
    
    -- Calculate union size
    SELECT COUNT(*)
    INTO union_count
    FROM (
        SELECT unnest(tokens_a)
        UNION
        SELECT unnest(tokens_b)
    ) AS union_set;
    
    -- Avoid division by zero
    IF union_count = 0 THEN
        RETURN 0;
    END IF;
    
    RETURN ROUND((intersection_count::numeric / union_count::numeric), 3);
END;
$$;


ALTER FUNCTION "public"."calculate_token_similarity"("tokens_a" "text"[], "tokens_b" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_vehicle_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    -- Metrics
    jaccard_score numeric;
    containment_score numeric;
    overlap_coefficient numeric;
    
    -- Token analysis
    tokens1_count int := COALESCE(array_length(tokens1, 1), 0);
    tokens2_count int := COALESCE(array_length(tokens2, 1), 0);
    min_count int := LEAST(tokens1_count, tokens2_count);
    max_count int := GREATEST(tokens1_count, tokens2_count);
    intersection_count int;
    
    -- Critical tokens for vehicles
    critical_tokens text[];
    critical_matches int := 0;
    
    -- Decision variables
    should_match boolean := false;
    confidence_level text;
    match_strategy text;
    final_score numeric;
BEGIN
    -- Quick exit for empty sets
    IF tokens1_count = 0 OR tokens2_count = 0 THEN
        RETURN jsonb_build_object(
            'jaccard_score', 0,
            'should_match', false,
            'confidence', 'none',
            'reason', 'empty_tokens'
        );
    END IF;

    -- Calculate intersection
    SELECT COUNT(DISTINCT token)
    INTO intersection_count
    FROM (
        SELECT unnest(tokens1) AS token
        INTERSECT
        SELECT unnest(tokens2)
    ) t;

    -- Calculate Jaccard similarity
    jaccard_score := calculate_jaccard_similarity(tokens1, tokens2);
    
    -- Calculate containment (subset) score
    IF min_count > 0 THEN
        containment_score := intersection_count::numeric / min_count::numeric;
    ELSE
        containment_score := 0;
    END IF;
    
    -- Calculate overlap coefficient (Szymkiewicz–Simpson)
    IF min_count > 0 THEN
        overlap_coefficient := intersection_count::numeric / min_count::numeric;
    ELSE
        overlap_coefficient := 0;
    END IF;

    -- Define critical tokens for vehicles
    critical_tokens := ARRAY[
        -- Engine specs
        '1.0L', '1.2L', '1.3L', '1.4L', '1.5L', '1.6L', '1.8L', 
        '2.0L', '2.2L', '2.3L', '2.4L', '2.5L', '2.7L', '2.8L',
        '3.0L', '3.2L', '3.3L', '3.5L', '3.6L', '3.7L', '3.8L',
        '4.0L', '4.2L', '4.3L', '4.6L', '4.7L', '5.0L', '5.3L', 
        '5.7L', '6.0L', '6.2L', '6.4L',
        -- Cylinders
        '3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL',
        -- Key trims (most distinctive)
        'SPORT', 'LUXURY', 'PREMIUM', 'BASE', 'ADVANCE', 'TECH',
        'GT', 'GTI', 'RS', 'ST', 'SS', 'AMG', 'NISMO', 
        -- Performance
        'TURBO', 'BITURBO', 'SUPERCHARGED',
        -- Doors (important for body type)
        '2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS'
    ];

    -- Count critical token matches
    SELECT COUNT(*)
    INTO critical_matches
    FROM unnest(critical_tokens) ct
    WHERE ct = ANY(tokens1) AND ct = ANY(tokens2);

    -- MATCHING STRATEGY DECISION TREE
    -- Based on entity resolution best practices
    
    -- Strategy 1: Exact match
    IF tokens1 = tokens2 OR jaccard_score = 1.0 THEN
        should_match := true;
        confidence_level := 'exact';
        match_strategy := 'identical_tokens';
        final_score := 1.0;
        
    -- Strategy 2: Near-exact match (Jaccard >= 0.8)
    ELSIF jaccard_score >= 0.8 THEN
        should_match := true;
        confidence_level := 'high';
        match_strategy := 'high_jaccard';
        final_score := jaccard_score;
        
    -- Strategy 3: Complete subset (one version contains the other)
    ELSIF overlap_coefficient = 1.0 THEN
        -- One set is completely contained in the other
        IF max_count - min_count <= 3 THEN
            -- Small difference in token count
            should_match := true;
            confidence_level := 'high';
            match_strategy := 'complete_subset';
            final_score := 0.85;
        ELSIF max_count - min_count <= 5 THEN
            -- Moderate difference
            should_match := true;
            confidence_level := 'medium';
            match_strategy := 'subset_moderate_diff';
            final_score := 0.70;
        ELSE
            -- Large difference - likely different trims
            should_match := false;
            confidence_level := 'low';
            match_strategy := 'subset_large_diff';
            final_score := 0.50;
        END IF;
        
    -- Strategy 4: High overlap with critical tokens
    ELSIF jaccard_score >= 0.5 AND critical_matches >= 2 THEN
        should_match := true;
        confidence_level := 'medium';
        match_strategy := 'critical_token_match';
        final_score := jaccard_score + (critical_matches * 0.05);
        
    -- Strategy 5: Moderate Jaccard with high containment
    ELSIF jaccard_score >= 0.4 AND containment_score >= 0.75 THEN
        should_match := true;
        confidence_level := 'medium';
        match_strategy := 'moderate_jaccard_high_containment';
        final_score := (jaccard_score * 0.7) + (containment_score * 0.3);
        
    -- Strategy 6: Same insurer relaxed threshold
    ELSIF is_same_insurer AND jaccard_score >= 0.35 THEN
        -- Same insurer can have lower threshold due to consistent formatting
        should_match := true;
        confidence_level := 'low';
        match_strategy := 'same_insurer_relaxed';
        final_score := jaccard_score;
        
    -- Strategy 7: Very short versions (1-2 tokens) with any overlap
    ELSIF min_count <= 2 AND intersection_count >= 1 THEN
        IF intersection_count = min_count THEN
            should_match := true;
            confidence_level := 'medium';
            match_strategy := 'short_version_match';
            final_score := 0.65;
        ELSE
            should_match := false;
            confidence_level := 'low';
            match_strategy := 'short_version_partial';
            final_score := 0.30;
        END IF;
        
    -- No match
    ELSE
        should_match := false;
        confidence_level := 'none';
        match_strategy := 'no_match';
        final_score := jaccard_score;
    END IF;

    -- Cap final score at 1.0
    final_score := LEAST(final_score, 1.0);

    RETURN jsonb_build_object(
        'jaccard_score', ROUND(jaccard_score, 4),
        'containment_score', ROUND(containment_score, 4),
        'overlap_coefficient', ROUND(overlap_coefficient, 4),
        'final_score', ROUND(final_score, 4),
        'intersection_count', intersection_count,
        'tokens1_count', tokens1_count,
        'tokens2_count', tokens2_count,
        'critical_matches', critical_matches,
        'should_match', should_match,
        'confidence', confidence_level,
        'strategy', match_strategy
    );
END;
$$;


ALTER FUNCTION "public"."calculate_vehicle_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_version_similarity"("version1_tokens" "text"[], "version2_tokens" "text"[], "version1_text" "text", "version2_text" "text") RETURNS double precision
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    token_overlap_count int;
    max_tokens int;
    token_similarity double precision;
    string_similarity double precision;
    combined_score double precision;
BEGIN
    -- Handle empty cases
    IF version1_tokens IS NULL OR version2_tokens IS NULL OR 
       array_length(version1_tokens, 1) IS NULL OR array_length(version2_tokens, 1) IS NULL THEN
        RETURN similarity(COALESCE(version1_text, ''), COALESCE(version2_text, ''));
    END IF;
    
    -- Calculate token overlap
    SELECT COUNT(DISTINCT t1)
    INTO token_overlap_count
    FROM unnest(version1_tokens) t1
    WHERE t1 = ANY(version2_tokens);
    
    -- Get max token count
    max_tokens := GREATEST(
        array_length(version1_tokens, 1),
        array_length(version2_tokens, 1)
    );
    
    -- Calculate token similarity (Jaccard index)
    IF max_tokens > 0 THEN
        token_similarity := token_overlap_count::double precision / max_tokens;
    ELSE
        token_similarity := 0;
    END IF;
    
    -- Calculate string similarity
    string_similarity := similarity(
        COALESCE(UPPER(version1_text), ''),
        COALESCE(UPPER(version2_text), '')
    );
    
    -- Combined score: heavily weight tokens for cross-insurer matching
    -- 30% string similarity + 70% token similarity
    combined_score := (0.3 * string_similarity) + (0.7 * token_similarity);
    
    RETURN combined_score;
END;
$$;


ALTER FUNCTION "public"."calculate_version_similarity"("version1_tokens" "text"[], "version2_tokens" "text"[], "version1_text" "text", "version2_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calculate_weighted_similarity"("v1_version" "text", "v2_version" "text", "v1_tokens" "text"[], "v2_tokens" "text"[]) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    score numeric := 0;
    
    -- Características estructurales (no TRIMs)
    v1_cilindros int;
    v2_cilindros int;
    v1_litros numeric;
    v2_litros numeric;
    v1_hp int;
    v2_hp int;
    v1_puertas int;
    v2_puertas int;
    v1_turbo boolean;
    v2_turbo boolean;
BEGIN
    -- 1. SIMILITUD BASE (30% del peso)
    score := similarity(v1_version, v2_version) * 0.3;
    
    -- 2. CILINDROS (20% del peso) - Característica CLAVE
    v1_cilindros := CASE 
        WHEN '4cil' = ANY(v1_tokens) OR 'l4' = ANY(v1_tokens) THEN 4
        WHEN '6cil' = ANY(v1_tokens) OR 'v6' = ANY(v1_tokens) THEN 6
        WHEN '8cil' = ANY(v1_tokens) OR 'v8' = ANY(v1_tokens) THEN 8
        WHEN '3cil' = ANY(v1_tokens) THEN 3
        ELSE NULL
    END;
    
    v2_cilindros := CASE 
        WHEN '4cil' = ANY(v2_tokens) OR 'l4' = ANY(v2_tokens) THEN 4
        WHEN '6cil' = ANY(v2_tokens) OR 'v6' = ANY(v2_tokens) THEN 6
        WHEN '8cil' = ANY(v2_tokens) OR 'v8' = ANY(v2_tokens) THEN 8
        WHEN '3cil' = ANY(v2_tokens) THEN 3
        ELSE NULL
    END;
    
    IF v1_cilindros IS NOT NULL AND v2_cilindros IS NOT NULL THEN
        IF v1_cilindros = v2_cilindros THEN
            score := score + 0.2;
        ELSE
            -- Penalización si son diferentes
            RETURN 0; -- No pueden ser el mismo vehículo
        END IF;
    ELSIF v1_cilindros IS NULL OR v2_cilindros IS NULL THEN
        -- Si falta info, dar beneficio parcial
        score := score + 0.1;
    END IF;
    
    -- 3. LITROS/DISPLACEMENT (15% del peso)
    -- Extraer litros de tokens como '20l', '15l', '30l'
    SELECT 
        CASE 
            WHEN '10l' = ANY(v1_tokens) THEN 1.0
            WHEN '12l' = ANY(v1_tokens) THEN 1.2
            WHEN '14l' = ANY(v1_tokens) THEN 1.4
            WHEN '15l' = ANY(v1_tokens) THEN 1.5
            WHEN '16l' = ANY(v1_tokens) THEN 1.6
            WHEN '18l' = ANY(v1_tokens) THEN 1.8
            WHEN '20l' = ANY(v1_tokens) OR '2l' = ANY(v1_tokens) THEN 2.0
            WHEN '24l' = ANY(v1_tokens) THEN 2.4
            WHEN '25l' = ANY(v1_tokens) THEN 2.5
            WHEN '30l' = ANY(v1_tokens) OR '3l' = ANY(v1_tokens) THEN 3.0
            WHEN '35l' = ANY(v1_tokens) THEN 3.5
            WHEN '40l' = ANY(v1_tokens) OR '4l' = ANY(v1_tokens) THEN 4.0
            WHEN '50l' = ANY(v1_tokens) OR '5l' = ANY(v1_tokens) THEN 5.0
            WHEN '57l' = ANY(v1_tokens) THEN 5.7
            WHEN '60l' = ANY(v1_tokens) OR '6l' = ANY(v1_tokens) THEN 6.0
            ELSE NULL
        END INTO v1_litros;
    
    -- Similar para v2
    SELECT 
        CASE 
            WHEN '10l' = ANY(v2_tokens) THEN 1.0
            WHEN '12l' = ANY(v2_tokens) THEN 1.2
            WHEN '14l' = ANY(v2_tokens) THEN 1.4
            WHEN '15l' = ANY(v2_tokens) THEN 1.5
            WHEN '16l' = ANY(v2_tokens) THEN 1.6
            WHEN '18l' = ANY(v2_tokens) THEN 1.8
            WHEN '20l' = ANY(v2_tokens) OR '2l' = ANY(v2_tokens) THEN 2.0
            WHEN '24l' = ANY(v2_tokens) THEN 2.4
            WHEN '25l' = ANY(v2_tokens) THEN 2.5
            WHEN '30l' = ANY(v2_tokens) OR '3l' = ANY(v2_tokens) THEN 3.0
            WHEN '35l' = ANY(v2_tokens) THEN 3.5
            WHEN '40l' = ANY(v2_tokens) OR '4l' = ANY(v2_tokens) THEN 4.0
            WHEN '50l' = ANY(v2_tokens) OR '5l' = ANY(v2_tokens) THEN 5.0
            WHEN '57l' = ANY(v2_tokens) THEN 5.7
            WHEN '60l' = ANY(v2_tokens) OR '6l' = ANY(v2_tokens) THEN 6.0
            ELSE NULL
        END INTO v2_litros;
    
    IF v1_litros IS NOT NULL AND v2_litros IS NOT NULL THEN
        IF ABS(v1_litros - v2_litros) < 0.2 THEN
            score := score + 0.15;
        ELSIF ABS(v1_litros - v2_litros) < 0.5 THEN
            score := score + 0.08;
        END IF;
    ELSIF v1_litros IS NULL OR v2_litros IS NULL THEN
        score := score + 0.08;
    END IF;
    
    -- 4. TURBO (10% del peso)
    v1_turbo := '0t' = ANY(v1_tokens) OR '2t' = ANY(v1_tokens) OR 
                '4t' = ANY(v1_tokens) OR '5t' = ANY(v1_tokens) OR
                'turbo' = ANY(v1_tokens) OR 'tfsi' = ANY(v1_tokens) OR
                'tsi' = ANY(v1_tokens) OR 'tdi' = ANY(v1_tokens);
    
    v2_turbo := '0t' = ANY(v2_tokens) OR '2t' = ANY(v2_tokens) OR 
                '4t' = ANY(v2_tokens) OR '5t' = ANY(v2_tokens) OR
                'turbo' = ANY(v2_tokens) OR 'tfsi' = ANY(v2_tokens) OR
                'tsi' = ANY(v2_tokens) OR 'tdi' = ANY(v2_tokens);
    
    IF v1_turbo = v2_turbo THEN
        score := score + 0.1;
    ELSIF v1_turbo != v2_turbo THEN
        -- Pequeña penalización si uno es turbo y otro no
        score := score - 0.05;
    END IF;
    
    -- 5. PUERTAS (10% del peso)
    -- Extraer número de puertas
    SELECT 
        CASE 
            WHEN '2puertas' = ANY(v1_tokens) OR '2p' = ANY(v1_tokens) THEN 2
            WHEN '3puertas' = ANY(v1_tokens) OR '3p' = ANY(v1_tokens) THEN 3
            WHEN '4puertas' = ANY(v1_tokens) OR '4p' = ANY(v1_tokens) THEN 4
            WHEN '5puertas' = ANY(v1_tokens) OR '5p' = ANY(v1_tokens) THEN 5
            ELSE NULL
        END INTO v1_puertas;
    
    SELECT 
        CASE 
            WHEN '2puertas' = ANY(v2_tokens) OR '2p' = ANY(v2_tokens) THEN 2
            WHEN '3puertas' = ANY(v2_tokens) OR '3p' = ANY(v2_tokens) THEN 3
            WHEN '4puertas' = ANY(v2_tokens) OR '4p' = ANY(v2_tokens) THEN 4
            WHEN '5puertas' = ANY(v2_tokens) OR '5p' = ANY(v2_tokens) THEN 5
            ELSE NULL
        END INTO v2_puertas;
    
    IF v1_puertas IS NOT NULL AND v2_puertas IS NOT NULL THEN
        IF v1_puertas = v2_puertas THEN
            score := score + 0.1;
        END IF;
    ELSIF v1_puertas IS NULL OR v2_puertas IS NULL THEN
        score := score + 0.05;
    END IF;
    
    -- 6. TRACCIÓN (15% del peso)
    IF ('awd' = ANY(v1_tokens) OR '4wd' = ANY(v1_tokens) OR '4x4' = ANY(v1_tokens)) =
       ('awd' = ANY(v2_tokens) OR '4wd' = ANY(v2_tokens) OR '4x4' = ANY(v2_tokens)) THEN
        score := score + 0.15;
    ELSIF ('awd' = ANY(v1_tokens) OR '4wd' = ANY(v1_tokens)) AND 
          NOT ('awd' = ANY(v2_tokens) OR '4wd' = ANY(v2_tokens)) THEN
        -- Penalización si uno es AWD y otro no
        score := score - 0.1;
    END IF;
    
    RETURN LEAST(score, 1.0);
END;
$$;


ALTER FUNCTION "public"."calculate_weighted_similarity"("v1_version" "text", "v2_version" "text", "v1_tokens" "text"[], "v2_tokens" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_existing_catalogo"("hash_list" "text"[]) RETURNS TABLE("id" "uuid", "hash_tecnico" character varying, "hash_comercial" character varying, "aseguradoras_disponibles" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ch.id,
    ch.hash_tecnico,
    ch.hash_comercial,
    ch.aseguradoras_disponibles
  FROM public.catalogo_homologado ch
  WHERE ch.hash_tecnico = ANY(hash_list);
END;
$$;


ALTER FUNCTION "public"."check_existing_catalogo"("hash_list" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_homologation_status"() RETURNS TABLE("metric_name" "text", "value" bigint)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    
    -- Total de registros únicos (por hash_comercial + version)
    SELECT 'total_registros_unicos'::text, COUNT(*)::bigint
    FROM catalogo_homologado
    
    UNION ALL
    
    -- Registros con múltiples aseguradoras (homologados)
    SELECT 'registros_homologados'::text, COUNT(*)::bigint
    FROM catalogo_homologado
    WHERE jsonb_object_keys(disponibilidad)::text[] && ARRAY['QUALITAS', 'HDI', 'AXA', 'GNP']
    GROUP BY id
    HAVING COUNT(DISTINCT jsonb_object_keys(disponibilidad)) > 1
    
    UNION ALL
    
    -- Registros huérfanos (sin aseguradora)
    SELECT 'registros_huerfanos'::text, COUNT(*)::bigint
    FROM catalogo_homologado
    WHERE disponibilidad = '{}' OR disponibilidad IS NULL
    
    UNION ALL
    
    -- Hash comerciales únicos
    SELECT 'hash_comerciales_unicos'::text, COUNT(DISTINCT hash_comercial)::bigint
    FROM catalogo_homologado
    
    UNION ALL
    
    -- Promedio de versiones por hash_comercial
    SELECT 'promedio_versiones_por_hash'::text, 
           ROUND(AVG(version_count))::bigint
    FROM (
        SELECT hash_comercial, COUNT(*) as version_count
        FROM catalogo_homologado
        GROUP BY hash_comercial
    ) t;
END;
$$;


ALTER FUNCTION "public"."check_homologation_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."classify_token_importance"("token" "text") RETURNS integer
    LANGUAGE "plpgsql" IMMUTABLE
    AS $_$
BEGIN
    RETURN CASE 
        -- NIVEL 1: DEFINITIVOS - No pueden diferir si ambos los especifican
        WHEN token IN ('SEDAN', 'COUPE', 'HATCHBACK', 'CONVERTIBLE', 'WAGON', 'SUV', 'PICKUP', 'VAN', 'SPORTBACK', 'SPORTWAGON') THEN 1
        WHEN token ~ '^\d+\.\d+L$' THEN 1  -- 2.0L, 3.5L - Desplazamiento
        WHEN token ~ '^\d+CIL$' THEN 1     -- 4CIL, 6CIL - Cilindros
        WHEN token ~ '^V\d+$' THEN 1       -- V6, V8 - Configuración motor
        
        -- NIVEL 2: ALTAMENTE INDICATIVOS - Fuerte señal de match
        -- Líneas estándar (MUY importantes entre aseguradoras)
        WHEN token IN ('SPORT', 'LUXURY', 'BUSINESS', 'PREMIUM', 'EXCLUSIVE', 'COMFORT', 'TREND', 'HIGHLINE', 'TITANIUM', 'ELEGANCE') THEN 2
        -- Ediciones performance (distintivas)
        WHEN token IN ('GTI', 'GLI', 'RS', 'ST', 'SS', 'GT', 'R', 'M', 'AMG', 'S', 'SRT', 'NISMO', 'TYPE-R', 'SI', 'STI', 'GS', 'F') THEN 2
        -- Paquetes de marcas
        WHEN token IN ('MSPORT', 'SLINE', 'RLINE', 'FSPORT', 'AMGLINE', 'NLINE', 'GTLINE') THEN 2
        -- Turbo (importante)
        WHEN token IN ('TURBO', 'BITURBO', 'TWINTURBO', 'SUPERCHARGED') THEN 2
        
        -- NIVEL 3: COMPLEMENTARIOS - Apoyan el match pero con tolerancia
        WHEN token ~ '^\d{3,4}HP$' THEN 3  -- Potencia (puede variar ±10HP)
        WHEN token IN ('AWD', 'FWD', 'RWD', '4WD', '4X4', '4X2') THEN 3  -- Tracción
        WHEN token IN ('DSG', 'CVT', 'TIPTRONIC', 'DCT', 'SMG', 'PDK') THEN 3  -- Trans específica
        WHEN token IN ('HYBRID', 'PHEV', 'ELECTRIC', 'ETRON', 'EPOWER') THEN 3  -- Propulsión
        
        -- NIVEL 4: VARIABLES - Pueden diferir entre aseguradoras
        WHEN token IN ('BASE', 'BASIC', 'ADVANCE', 'PROGRESSIVE', 'DYNAMIC', 'EXECUTIVE') THEN 4
        WHEN token IN ('LIMITED', 'ANNIVERSARY', 'SPECIAL', 'LAUNCH') THEN 4
        WHEN token IN ('PLUS', 'PRO', 'TECH', 'STYLE', 'DESIGN') THEN 4
        WHEN token ~ '^R\d{2}$' THEN 4  -- R16, R17, R18 - Rines
        WHEN token IN ('LTD', 'DLX', 'GL', 'GLS', 'GLX') THEN 4
        
        -- NIVEL 5: OTROS - Tokens no clasificados
        ELSE 5
    END;
END;
$_$;


ALTER FUNCTION "public"."classify_token_importance"("token" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clean_expired_cache"() RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM query_cache 
    WHERE expires_at < NOW();
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;


ALTER FUNCTION "public"."clean_expired_cache"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."clean_match_cache"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    deleted_old int := 0;
    deleted_low_hits int := 0;
BEGIN
    DELETE FROM match_cache 
    WHERE fecha_calculo < (now() - INTERVAL '7 days') AND COALESCE(hits, 0) < 5;
    GET DIAGNOSTICS deleted_old = ROW_COUNT;
    
    DELETE FROM match_cache 
    WHERE fecha_calculo < (now() - INTERVAL '1 day') AND COALESCE(hits, 0) = 1;
    GET DIAGNOSTICS deleted_low_hits = ROW_COUNT;
    
    RETURN jsonb_build_object(
        'deleted_old', deleted_old,
        'deleted_low_hits', deleted_low_hits,
        'total_remaining', (SELECT COUNT(*) FROM match_cache)
    );
END;
$$;


ALTER FUNCTION "public"."clean_match_cache"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."consolidar_clusters"("p_block_id" "text", "p_clusters" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    cluster jsonb;
    member int;
    master_id bigint;
    temp_rec RECORD;
    merged_count int := 0;
    created_count int := 0;
    updated_count int := 0;
BEGIN
    -- Procesar cada cluster
    FOR cluster IN SELECT * FROM jsonb_array_elements(p_clusters)
    LOOP
        -- Identificar registro maestro (el que ya existe en la BD o el primero)
        SELECT MIN(record_id) INTO master_id
        FROM temp_block_processing t
        WHERE t.record_id IN (
            SELECT (jsonb_array_elements_text(cluster->'members'))::int
        )
        AND t.record_id < 1000;  -- IDs < 1000 son registros existentes
        
        IF master_id IS NULL THEN
            -- Todos son nuevos, crear el primero como maestro
            SELECT MIN(record_id) INTO master_id
            FROM temp_block_processing t
            WHERE t.record_id IN (
                SELECT (jsonb_array_elements_text(cluster->'members'))::int
            );
            
            -- Crear nuevo registro
            SELECT * INTO temp_rec FROM temp_block_processing WHERE record_id = master_id;
            
            INSERT INTO catalogo_homologado (
                hash_comercial, marca, modelo, anio, transmision,
                version, version_tokens_array, disponibilidad,
                fecha_creacion, fecha_actualizacion
            ) VALUES (
                p_block_id,
                temp_rec.metadata->>'marca',
                temp_rec.metadata->>'modelo',
                (temp_rec.metadata->>'anio')::int,
                temp_rec.metadata->>'transmision',
                temp_rec.version,
                temp_rec.version_tokens,
                jsonb_build_object(
                    temp_rec.aseguradora, jsonb_build_object(
                        'origen', true,
                        'disponible', true,
                        'aseguradora', temp_rec.aseguradora,
                        'id_original', temp_rec.metadata->>'id_original',
                        'version_original', temp_rec.metadata->>'version_original',
                        'jaccard_score', 1.0,
                        'fecha_actualizacion', now(),
                        'metodo_match', 'hierarchical_clustering'
                    )
                ),
                now(), now()
            ) RETURNING id INTO master_id;
            
            created_count := created_count + 1;
        END IF;
        
        -- Consolidar todos los miembros del cluster en el maestro
        FOR member IN 
            SELECT (jsonb_array_elements_text(cluster->'members'))::int
            WHERE (jsonb_array_elements_text(cluster->'members'))::int != master_id
        LOOP
            SELECT * INTO temp_rec FROM temp_block_processing WHERE record_id = member;
            
            -- Agregar aseguradora al registro maestro
            UPDATE catalogo_homologado
            SET disponibilidad = disponibilidad || jsonb_build_object(
                temp_rec.aseguradora, jsonb_build_object(
                    'origen', false,
                    'disponible', true,
                    'aseguradora', temp_rec.aseguradora,
                    'id_original', temp_rec.metadata->>'id_original',
                    'version_original', temp_rec.metadata->>'version_original',
                    'jaccard_score', 0.5,  -- Score por clustering
                    'fecha_actualizacion', now(),
                    'metodo_match', 'hierarchical_clustering'
                )
            )
            WHERE id = master_id;
            
            IF member < 1000 THEN
                updated_count := updated_count + 1;
            ELSE
                merged_count := merged_count + 1;
            END IF;
        END LOOP;
    END LOOP;
    
    RETURN jsonb_build_object(
        'created', created_count,
        'updated', updated_count,
        'merged', merged_count,
        'clusters_found', jsonb_array_length(p_clusters)
    );
END;
$$;


ALTER FUNCTION "public"."consolidar_clusters"("p_block_id" "text", "p_clusters" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."consolidar_duplicados_internos"("p_hash_comercial" "text", "p_threshold" numeric DEFAULT 0.85) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    rec RECORD;
    consolidated_count int := 0;
    merged_disponibilidad jsonb;
    kept_version text;
    kept_id bigint;
    delete_ids bigint[] := ARRAY[]::bigint[];
BEGIN
    FOR rec IN
        WITH potential_duplicates AS (
            SELECT 
                ch1.id as id1,
                ch2.id as id2,
                ch1.version as v1,
                ch2.version as v2,
                ch1.disponibilidad as disp1,
                ch2.disponibilidad as disp2,
                ch1.version_tokens_array as tokens1,
                ch2.version_tokens_array as tokens2,
                ARRAY(SELECT unnest(ch1.version_tokens_array) ORDER BY 1) as sorted_tokens1,
                ARRAY(SELECT unnest(ch2.version_tokens_array) ORDER BY 1) as sorted_tokens2,
                calculate_match_score(ch1.version, ch2.version, 
                                    ch1.version_tokens_array, ch2.version_tokens_array) as score
            FROM 
                catalogo_homologado ch1
                INNER JOIN catalogo_homologado ch2 
                    ON ch1.hash_comercial = ch2.hash_comercial
                    AND ch1.id < ch2.id
            WHERE 
                ch1.hash_comercial = p_hash_comercial
                AND ch1.version != ch2.version
        )
        SELECT * FROM potential_duplicates
        WHERE 
            (sorted_tokens1 = sorted_tokens2)
            OR (score >= p_threshold)
            OR (tokens1 <@ tokens2 OR tokens2 <@ tokens1)
        ORDER BY score DESC
    LOOP
        IF NOT EXISTS (
            SELECT 1 
            FROM jsonb_object_keys(rec.disp1) k1
            JOIN jsonb_object_keys(rec.disp2) k2 ON k1 = k2
        ) THEN
            IF array_length(rec.tokens1, 1) >= array_length(rec.tokens2, 1) THEN
                kept_id := rec.id1;
                kept_version := rec.v1;
                merged_disponibilidad := rec.disp1 || rec.disp2;
                delete_ids := array_append(delete_ids, rec.id2);
            ELSE
                kept_id := rec.id2;
                kept_version := rec.v2;
                merged_disponibilidad := rec.disp2 || rec.disp1;
                delete_ids := array_append(delete_ids, rec.id1);
            END IF;
            
            IF NOT (kept_id = ANY(delete_ids)) THEN
                UPDATE catalogo_homologado
                SET 
                    disponibilidad = merged_disponibilidad,
                    version = kept_version,
                    fecha_actualizacion = NOW()
                WHERE id = kept_id;
                
                consolidated_count := consolidated_count + 1;
            END IF;
        END IF;
    END LOOP;
    
    IF array_length(delete_ids, 1) > 0 THEN
        DELETE FROM catalogo_homologado 
        WHERE id = ANY(delete_ids);
    END IF;
    
    RETURN jsonb_build_object(
        'consolidated', consolidated_count,
        'deleted_ids', delete_ids
    );
END;
$$;


ALTER FUNCTION "public"."consolidar_duplicados_internos"("p_hash_comercial" "text", "p_threshold" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."consolidar_versiones_duplicadas"("p_hash_comercial" "text" DEFAULT NULL::"text", "p_dry_run" boolean DEFAULT true, "p_min_similarity" numeric DEFAULT 0.85) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_record RECORD;
    v_match RECORD;
    v_merged_count int := 0;
    v_candidates jsonb := '[]'::jsonb;
    v_result jsonb;
    v_merged_disponibilidad jsonb;
    v_aseguradoras text[];
    v_aseguradora text;
BEGIN
    -- Buscar versiones candidatas a consolidación
    FOR v_record IN
        SELECT 
            ch1.id as id1,
            ch2.id as id2,
            ch1.version as version1,
            ch2.version as version2,
            ch1.hash_comercial,
            ch1.disponibilidad as disp1,
            ch2.disponibilidad as disp2,
            ch1.version_tokens_array as tokens1,
            ch2.version_tokens_array as tokens2,
            calculate_match_score(
                ch1.version, 
                ch2.version,
                ch1.version_tokens_array,
                ch2.version_tokens_array
            ) as score
        FROM catalogo_homologado ch1
        JOIN catalogo_homologado ch2 
            ON ch1.hash_comercial = ch2.hash_comercial 
            AND ch1.id < ch2.id
        WHERE (p_hash_comercial IS NULL OR ch1.hash_comercial = p_hash_comercial)
            AND ch1.version_tokens_array && ch2.version_tokens_array
            AND calculate_match_score(
                ch1.version, 
                ch2.version,
                ch1.version_tokens_array,
                ch2.version_tokens_array
            ) >= p_min_similarity
        ORDER BY score DESC
        LIMIT 1000
    LOOP
        -- Verificar que no compartan aseguradoras
        SELECT array_agg(DISTINCT keys) INTO v_aseguradoras
        FROM (
            SELECT jsonb_object_keys(v_record.disp1) as keys
            UNION ALL
            SELECT jsonb_object_keys(v_record.disp2)
        ) t;
        
        -- Si hay aseguradoras duplicadas, es un caso sospechoso
        IF array_length(v_aseguradoras, 1) < (
            SELECT COUNT(*)
            FROM (
                SELECT jsonb_object_keys(v_record.disp1)
                UNION ALL
                SELECT jsonb_object_keys(v_record.disp2)
            ) t
        ) THEN
            CONTINUE; -- Saltar si ya comparten aseguradoras
        END IF;
        
        -- Agregar candidato
        v_candidates := v_candidates || jsonb_build_object(
            'id_principal', v_record.id1,
            'id_secundario', v_record.id2,
            'version_principal', v_record.version1,
            'version_secundaria', v_record.version2,
            'hash_comercial', v_record.hash_comercial,
            'similitud', v_record.score,
            'tokens_principales', array_length(v_record.tokens1, 1),
            'tokens_secundarios', array_length(v_record.tokens2, 1)
        );
        
        -- Si no es dry run, realizar la consolidación
        IF NOT p_dry_run THEN
            -- Fusionar disponibilidades
            v_merged_disponibilidad := v_record.disp1;
            
            FOR v_aseguradora IN 
                SELECT jsonb_object_keys(v_record.disp2)
            LOOP
                v_merged_disponibilidad := jsonb_set(
                    v_merged_disponibilidad,
                    ARRAY[v_aseguradora],
                    v_record.disp2->v_aseguradora,
                    true
                );
            END LOOP;
            
            -- Actualizar registro principal
            UPDATE catalogo_homologado
            SET disponibilidad = v_merged_disponibilidad,
                fecha_actualizacion = now()
            WHERE id = v_record.id1;
            
            -- Eliminar registro duplicado
            DELETE FROM catalogo_homologado
            WHERE id = v_record.id2;
            
            v_merged_count := v_merged_count + 1;
        END IF;
    END LOOP;
    
    v_result := jsonb_build_object(
        'dry_run', p_dry_run,
        'candidatos_encontrados', jsonb_array_length(v_candidates),
        'registros_consolidados', v_merged_count,
        'umbral_similitud', p_min_similarity,
        'candidatos', v_candidates
    );
    
    RETURN v_result;
END;
$$;


ALTER FUNCTION "public"."consolidar_versiones_duplicadas"("p_hash_comercial" "text", "p_dry_run" boolean, "p_min_similarity" numeric) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."consolidate_duplicates"("target_hash_comercial" "text" DEFAULT NULL::"text", "dry_run" boolean DEFAULT true) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    consolidation_count int := 0;
    hash_record RECORD;
    version_group RECORD;
    master_id bigint;
    merged_disponibilidad jsonb;
    versions_consolidated int;
BEGIN
    -- Find hashes with multiple entries
    FOR hash_record IN
        SELECT 
            hash_comercial,
            COUNT(*) as entry_count,
            array_agg(id ORDER BY array_length(version_tokens_array, 1) DESC, id) as entry_ids,
            array_agg(version ORDER BY array_length(version_tokens_array, 1) DESC, id) as versions,
            array_agg(disponibilidad ORDER BY array_length(version_tokens_array, 1) DESC, id) as disponibilidades
        FROM catalogo_homologado
        WHERE (target_hash_comercial IS NULL OR hash_comercial = target_hash_comercial)
        GROUP BY hash_comercial
        HAVING COUNT(*) > 1
        ORDER BY COUNT(*) DESC
        LIMIT CASE WHEN target_hash_comercial IS NULL THEN 100 ELSE NULL END
    LOOP
        versions_consolidated := 0;
        
        -- Group similar versions
        FOR version_group IN
            WITH version_pairs AS (
                SELECT 
                    v1.id as id1,
                    v1.version as version1,
                    v1.version_tokens_array as tokens1,
                    v1.disponibilidad as disp1,
                    v2.id as id2,
                    v2.version as version2,
                    v2.version_tokens_array as tokens2,
                    v2.disponibilidad as disp2,
                    calculate_aggressive_match_score(
                        v1.version_tokens_array,
                        v2.version_tokens_array,
                        false
                    ) as match_score
                FROM catalogo_homologado v1
                JOIN catalogo_homologado v2 
                    ON v1.hash_comercial = v2.hash_comercial 
                    AND v1.id < v2.id
                WHERE v1.hash_comercial = hash_record.hash_comercial
            )
            SELECT 
                id1, version1, disp1,
                id2, version2, disp2,
                match_score
            FROM version_pairs
            WHERE (match_score->>'should_match')::boolean = true
            ORDER BY (match_score->>'final_score')::numeric DESC
        LOOP
            IF NOT dry_run THEN
                -- Use the longer version as master (more detail)
                IF array_length(version_group.version1::text[], 1) >= 
                   array_length(version_group.version2::text[], 1) THEN
                    master_id := version_group.id1;
                    
                    -- Merge disponibilidad from version2 into version1
                    merged_disponibilidad := version_group.disp1;
                    
                    -- Add all insurers from version2
                    SELECT 
                        merged_disponibilidad || jsonb_object_agg(key, value)
                    INTO merged_disponibilidad
                    FROM jsonb_each(version_group.disp2)
                    WHERE NOT (merged_disponibilidad ? key);
                    
                    -- Update master record
                    UPDATE catalogo_homologado
                    SET disponibilidad = merged_disponibilidad,
                        fecha_actualizacion = now()
                    WHERE id = master_id;
                    
                    -- Delete duplicate
                    DELETE FROM catalogo_homologado
                    WHERE id = version_group.id2;
                ELSE
                    master_id := version_group.id2;
                    
                    -- Merge disponibilidad from version1 into version2
                    merged_disponibilidad := version_group.disp2;
                    
                    SELECT 
                        merged_disponibilidad || jsonb_object_agg(key, value)
                    INTO merged_disponibilidad
                    FROM jsonb_each(version_group.disp1)
                    WHERE NOT (merged_disponibilidad ? key);
                    
                    UPDATE catalogo_homologado
                    SET disponibilidad = merged_disponibilidad,
                        fecha_actualizacion = now()
                    WHERE id = master_id;
                    
                    DELETE FROM catalogo_homologado
                    WHERE id = version_group.id1;
                END IF;
                
                versions_consolidated := versions_consolidated + 1;
            ELSE
                -- Dry run - just count
                versions_consolidated := versions_consolidated + 1;
            END IF;
        END LOOP;
        
        consolidation_count := consolidation_count + versions_consolidated;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'dry_run', dry_run,
        'duplicates_found', consolidation_count,
        'action', CASE 
            WHEN dry_run THEN 'No changes made - dry run'
            ELSE format('%s duplicates consolidated', consolidation_count)
        END
    );
END;
$$;


ALTER FUNCTION "public"."consolidate_duplicates"("target_hash_comercial" "text", "dry_run" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."construir_matriz_similitud"("p_block_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    matrix jsonb := '[]'::jsonb;
    rec1 RECORD;
    rec2 RECORD;
    sim numeric;
    row jsonb;
BEGIN
    FOR rec1 IN 
        SELECT * FROM temp_block_processing 
        WHERE block_id = p_block_id
        ORDER BY record_id
    LOOP
        row := '[]'::jsonb;
        
        FOR rec2 IN 
            SELECT * FROM temp_block_processing 
            WHERE block_id = p_block_id
            ORDER BY record_id
        LOOP
            IF rec1.record_id = rec2.record_id THEN
                sim := 1.0;
            ELSIF rec1.aseguradora = rec2.aseguradora THEN
                -- Misma aseguradora, umbral más alto
                sim := calculate_similarity(
                    rec1.version_tokens, 
                    rec2.version_tokens,
                    array_length(rec1.version_tokens, 1),
                    array_length(rec2.version_tokens, 1)
                );
                IF sim < 0.80 THEN sim := 0; END IF;  -- Umbral para misma aseguradora
            ELSE
                -- Diferente aseguradora, umbral más bajo
                sim := calculate_similarity(
                    rec1.version_tokens, 
                    rec2.version_tokens,
                    array_length(rec1.version_tokens, 1),
                    array_length(rec2.version_tokens, 1)
                );
                IF sim < 0.35 THEN sim := 0; END IF;  -- Umbral cross-aseguradora
            END IF;
            
            row := row || to_jsonb(sim);
        END LOOP;
        
        matrix := matrix || jsonb_build_array(row);
    END LOOP;
    
    RETURN matrix;
END;
$$;


ALTER FUNCTION "public"."construir_matriz_similitud"("p_block_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_nuevo_registro"("item" "jsonb", "tokens" "text"[]) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
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
        item->>'hash_comercial',
        item->>'marca',
        item->>'modelo',
        (item->>'anio')::int,
        COALESCE(item->>'transmision', 'AUTO'),
        item->>'version_limpia',
        to_tsvector('simple', COALESCE(item->>'version_limpia', '')),
        tokens,
        jsonb_build_object(
            item->>'origen_aseguradora', jsonb_build_object(
                'origen', true,
                'disponible', true,
                'aseguradora', item->>'origen_aseguradora',
                'id_original', item->>'id_original',
                'version_original', item->>'version_original',
                'jaccard_score', 1.0,
                'fecha_actualizacion', now(),
                'metodo_match', 'new_entry'
            )
        ),
        now(),
        now()
    );
EXCEPTION
    WHEN unique_violation THEN
        -- Ya existe, actualizar
        UPDATE catalogo_homologado
        SET 
            disponibilidad = jsonb_set(
                COALESCE(disponibilidad, '{}'::jsonb),
                ARRAY[item->>'origen_aseguradora'],
                jsonb_build_object(
                    'origen', true,
                    'disponible', true,
                    'aseguradora', item->>'origen_aseguradora',
                    'id_original', item->>'id_original',
                    'version_original', item->>'version_original',
                    'jaccard_score', 1.0,
                    'fecha_actualizacion', now(),
                    'metodo_match', 'duplicate_exact'
                ),
                true
            ),
            fecha_actualizacion = now()
        WHERE hash_comercial = item->>'hash_comercial'
          AND version = item->>'version_limpia';
END;
$$;


ALTER FUNCTION "public"."crear_nuevo_registro"("item" "jsonb", "tokens" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_nuevo_registro_simple"("item" "jsonb", "tokens" "text"[]) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Intentar insertar
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
        item->>'hash_comercial',
        item->>'marca',
        item->>'modelo',
        (item->>'anio')::int,
        COALESCE(NULLIF(TRIM(item->>'transmision'), ''), 'AUTO'),
        item->>'version_limpia',
        to_tsvector('simple', COALESCE(item->>'version_limpia', '')),
        tokens,
        jsonb_build_object(
            item->>'origen_aseguradora', jsonb_build_object(
                'origen', true,
                'disponible', true,
                'aseguradora', item->>'origen_aseguradora',
                'id_original', item->>'id_original',
                'version_original', item->>'version_original',
                'jaccard_score', 1.0,
                'fecha_actualizacion', now(),
                'metodo_match', 'new_entry'
            )
        ),
        now(),
        now()
    );
    
EXCEPTION
    WHEN unique_violation THEN
        -- El registro ya existe (race condition o duplicado exacto)
        -- Actualizar en lugar de fallar
        UPDATE catalogo_homologado
        SET 
            disponibilidad = jsonb_set(
                COALESCE(disponibilidad, '{}'::jsonb),
                ARRAY[item->>'origen_aseguradora'],
                jsonb_build_object(
                    'origen', true,
                    'disponible', true,
                    'aseguradora', item->>'origen_aseguradora',
                    'id_original', item->>'id_original',
                    'version_original', item->>'version_original',
                    'jaccard_score', 1.0,
                    'fecha_actualizacion', now(),
                    'metodo_match', 'duplicate_exact'
                ),
                true
            ),
            fecha_actualizacion = now()
        WHERE hash_comercial = item->>'hash_comercial'
          AND version = item->>'version_limpia';
    WHEN OTHERS THEN
        -- Re-lanzar otros errores
        RAISE;
END;
$$;


ALTER FUNCTION "public"."crear_nuevo_registro_simple"("item" "jsonb", "tokens" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."crear_registro_vehiculo"("item" "jsonb", "tokens" "text"[]) RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Intentar insertar nuevo registro
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
        item->>'hash_comercial',
        item->>'marca',
        item->>'modelo',
        (item->>'anio')::int,
        COALESCE(NULLIF(TRIM(item->>'transmision'), ''), 'AUTO'),
        item->>'version_limpia',
        to_tsvector('simple', COALESCE(item->>'version_limpia', '')),
        tokens,
        jsonb_build_object(
            item->>'origen_aseguradora', jsonb_build_object(
                'origen', true,
                'disponible', true,
                'aseguradora', item->>'origen_aseguradora',
                'id_original', item->>'id_original',
                'version_original', item->>'version_original',
                'jaccard_score', 1.0,
                'fecha_actualizacion', now(),
                'metodo_match', 'new_entry'
            )
        ),
        now(),
        now()
    );
    
EXCEPTION
    WHEN unique_violation THEN
        -- El registro ya existe (versión idéntica para el mismo vehículo)
        -- Actualizar agregando la nueva aseguradora
        UPDATE catalogo_homologado
        SET 
            disponibilidad = jsonb_set(
                COALESCE(disponibilidad, '{}'::jsonb),
                ARRAY[item->>'origen_aseguradora'],
                jsonb_build_object(
                    'origen', true,
                    'disponible', true,
                    'aseguradora', item->>'origen_aseguradora',
                    'id_original', item->>'id_original',
                    'version_original', item->>'version_original',
                    'jaccard_score', 1.0,
                    'fecha_actualizacion', now(),
                    'metodo_match', 'duplicate_exact'
                ),
                true
            ),
            fecha_actualizacion = now()
        WHERE hash_comercial = item->>'hash_comercial'
          AND version = item->>'version_limpia';
END;
$$;


ALTER FUNCTION "public"."crear_registro_vehiculo"("item" "jsonb", "tokens" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."debug_n8n_request"("raw_data" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN jsonb_build_object(
        'received_data', raw_data,
        'data_length', LENGTH(raw_data),
        'first_200_chars', LEFT(raw_data, 200),
        'is_valid_json', CASE 
            WHEN raw_data::jsonb IS NOT NULL THEN true 
            ELSE false 
        END
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'error', 'Failed to parse',
        'raw_data', raw_data,
        'sql_error', SQLERRM
    );
END;
$$;


ALTER FUNCTION "public"."debug_n8n_request"("raw_data" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."detect_insurer_from_text"("input_text" "text") RETURNS character varying
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    detected_insurer VARCHAR(50);
    search_text TEXT;
BEGIN
    -- Normalizar texto para búsqueda
    search_text := lower(unaccent(input_text));
    
    -- Buscar coincidencias con nombres y aliases
    SELECT insurer_code INTO detected_insurer
    FROM aseguradoras_metadata
    WHERE 
        lower(insurer_name) IN (
            SELECT unnest(string_to_array(search_text, ' '))
        )
        OR EXISTS (
            SELECT 1 
            FROM unnest(aliases) AS alias 
            WHERE search_text LIKE '%' || lower(alias) || '%'
        )
    LIMIT 1;
    
    RETURN detected_insurer;
END;
$$;


ALTER FUNCTION "public"."detect_insurer_from_text"("input_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."extract_misplaced_model"("version_text" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    clean_version text;
    model_patterns text[] := ARRAY[
        -- BMW: 118, 120, 316, 318, 320, 325, 328, 330, 335, 340, etc.
        '\y(1|2|3|4|5|6|7|8)\d{2}[A-Z]{0,3}\y',
        -- Mercedes: C200, E350, S500, etc.
        '\y[A-Z]{1,3}\d{3}[A-Z]{0,3}\y',
        -- Audi: A3, A4, Q5, Q7, etc.
        '\y(A|Q|R|S|RS|TT)[0-9]{1,2}\y',
        -- Mazda: CX3, CX5, MX5
        '\y(CX|MX)\d{1,2}\y',
        -- Series/Serie + número
        '\y(SERIE[S]?|SERIES)\s*\d+\s*'
    ];
    pattern text;
BEGIN
    clean_version := UPPER(TRIM(COALESCE(version_text, '')));
    
    -- Remover patrones de modelo mal ubicados
    FOREACH pattern IN ARRAY model_patterns
    LOOP
        clean_version := regexp_replace(clean_version, pattern, ' ', 'gi');
    END LOOP;
    
    -- Limpiar espacios múltiples
    clean_version := regexp_replace(clean_version, '\s+', ' ', 'g');
    
    RETURN TRIM(clean_version);
END;
$$;


ALTER FUNCTION "public"."extract_misplaced_model"("version_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."extract_vehicle_features"("version_text" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    features jsonb := '{}'::jsonb;
    normalized_text text;
    match text;
BEGIN
    IF version_text IS NULL OR version_text = '' THEN
        RETURN features;
    END IF;
    
    normalized_text := UPPER(version_text);
    
    -- Motor (cilindros y configuración)
    IF normalized_text ~ '\b([VLIH])(\d+)\b' THEN
        SELECT (regexp_match(normalized_text, '\b([VLIH])(\d+)\b'))[1] || (regexp_match(normalized_text, '\b([VLIH])(\d+)\b'))[2] 
        INTO match;
        features := jsonb_set(features, '{motor_config}', to_jsonb(match));
    END IF;
    
    -- Desplazamiento
    IF normalized_text ~ '\b(\d+\.?\d*)\s*L\b' THEN
        SELECT (regexp_match(normalized_text, '\b(\d+\.?\d*)\s*L\b'))[1] 
        INTO match;
        features := jsonb_set(features, '{displacement}', to_jsonb(match || 'L'));
    END IF;
    
    -- Puertas
    IF normalized_text ~ '\b(\d+)\s*P(UERTAS?)?\b' THEN
        SELECT (regexp_match(normalized_text, '\b(\d+)\s*P(UERTAS?)?\b'))[1] 
        INTO match;
        features := jsonb_set(features, '{doors}', to_jsonb(match || 'P'));
    END IF;
    
    -- Potencia
    IF normalized_text ~ '\b(\d+)\s*(HP|PS)\b' THEN
        SELECT (regexp_match(normalized_text, '\b(\d+)\s*(HP|PS)\b'))[1] 
        INTO match;
        features := jsonb_set(features, '{power}', to_jsonb(match || 'HP'));
    END IF;
    
    -- Tracción
    IF normalized_text ~ '\b(4X4|AWD|4WD)\b' THEN
        features := jsonb_set(features, '{traction}', '"4WD"');
    ELSIF normalized_text ~ '\b(4X2|FWD|2WD)\b' THEN
        features := jsonb_set(features, '{traction}', '"2WD"');
    END IF;
    
    RETURN features;
END;
$$;


ALTER FUNCTION "public"."extract_vehicle_features"("version_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."find_match_candidates"("p_hash_comercial" "text", "p_input_tokens" "text"[], "p_normalized_version" "text", "p_limit" integer DEFAULT 10) RETURNS TABLE("id" bigint, "version" "text", "disponibilidad" "jsonb", "version_tokens_array" "text"[], "base_score" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH candidates AS (
        -- Matches exactos
        SELECT 
            ch.id,
            ch.version,
            ch.disponibilidad,
            ch.version_tokens_array,
            1.0 as priority,
            similarity(UPPER(ch.version), p_normalized_version) as sim_score
        FROM catalogo_homologado ch
        WHERE ch.hash_comercial = p_hash_comercial
          AND UPPER(ch.version) = p_normalized_version
        
        UNION ALL
        
        -- Con tokens compartidos
        SELECT 
            ch.id,
            ch.version,
            ch.disponibilidad,
            ch.version_tokens_array,
            0.8 as priority,
            similarity(UPPER(ch.version), p_normalized_version) as sim_score
        FROM catalogo_homologado ch
        WHERE ch.hash_comercial = p_hash_comercial
          AND ch.version_tokens_array && p_input_tokens
          AND ch.version_tokens_array IS NOT NULL
          AND NOT (UPPER(ch.version) = p_normalized_version)
        
        UNION ALL
        
        -- Similitud básica
        SELECT 
            ch.id,
            ch.version,
            ch.disponibilidad,
            ch.version_tokens_array,
            0.6 as priority,
            similarity(UPPER(ch.version), p_normalized_version) as sim_score
        FROM catalogo_homologado ch
        WHERE ch.hash_comercial = p_hash_comercial
          AND similarity(UPPER(ch.version), p_normalized_version) > 0.25
          AND NOT (ch.version_tokens_array && p_input_tokens)
          AND NOT (UPPER(ch.version) = p_normalized_version)
    )
    SELECT DISTINCT ON (c.id)
        c.id,
        c.version,
        c.disponibilidad,
        c.version_tokens_array,
        c.sim_score * c.priority as base_score
    FROM candidates c
    ORDER BY c.id, c.priority DESC, c.sim_score DESC
    LIMIT p_limit;
END;
$$;


ALTER FUNCTION "public"."find_match_candidates"("p_hash_comercial" "text", "p_input_tokens" "text"[], "p_normalized_version" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."find_match_candidates_v5"("p_hash_comercial" "text", "p_input_tokens" "text"[], "p_normalized_version" "text", "p_limit" integer DEFAULT 10) RETURNS TABLE("id" bigint, "version" "text", "disponibilidad" "jsonb", "version_tokens_array" "text"[], "base_score" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ch.id,
        ch.version,
        ch.disponibilidad,
        ch.version_tokens_array,
        1.0::numeric as base_score
    FROM catalogo_homologado ch
    WHERE ch.hash_comercial = p_hash_comercial
      AND UPPER(COALESCE(ch.version, '')) = p_normalized_version
    
    UNION ALL
    
    SELECT 
        ch.id,
        ch.version,
        ch.disponibilidad,
        ch.version_tokens_array,
        (0.8 * similarity(UPPER(COALESCE(ch.version, '')), p_normalized_version))::numeric
    FROM catalogo_homologado ch
    WHERE ch.hash_comercial = p_hash_comercial
      AND ch.version_tokens_array && p_input_tokens
      AND ch.version_tokens_array IS NOT NULL
      AND array_length(ch.version_tokens_array, 1) > 0
      AND UPPER(COALESCE(ch.version, '')) != p_normalized_version
    
    UNION ALL
    
    SELECT 
        ch.id,
        ch.version,
        ch.disponibilidad,
        ch.version_tokens_array,
        (0.6 * similarity(UPPER(COALESCE(ch.version, '')), p_normalized_version))::numeric
    FROM catalogo_homologado ch
    WHERE ch.hash_comercial = p_hash_comercial
      AND similarity(UPPER(COALESCE(ch.version, '')), p_normalized_version) > 0.25
      AND (ch.version_tokens_array IS NULL 
           OR array_length(ch.version_tokens_array, 1) IS NULL
           OR array_length(ch.version_tokens_array, 1) = 0
           OR NOT (ch.version_tokens_array && p_input_tokens))
      AND UPPER(COALESCE(ch.version, '')) != p_normalized_version
    
    ORDER BY base_score DESC
    LIMIT p_limit;
END;
$$;


ALTER FUNCTION "public"."find_match_candidates_v5"("p_hash_comercial" "text", "p_input_tokens" "text"[], "p_normalized_version" "text", "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fusionar_clusters"("p_clusters" "jsonb", "p_cluster1_id" integer, "p_cluster2_id" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    new_clusters jsonb := '[]'::jsonb;
    cluster jsonb;
    merged_members jsonb;
BEGIN
    -- Obtener miembros de ambos clusters
    merged_members := (p_clusters->p_cluster1_id->'members') || 
                     (p_clusters->p_cluster2_id->'members');
    
    -- Reconstruir array de clusters
    FOR cluster IN SELECT * FROM jsonb_array_elements(p_clusters)
    LOOP
        IF (cluster->>'id')::int NOT IN (p_cluster1_id, p_cluster2_id) THEN
            new_clusters := new_clusters || cluster;
        END IF;
    END LOOP;
    
    -- Agregar cluster fusionado
    new_clusters := new_clusters || jsonb_build_object(
        'id', p_cluster1_id,
        'members', merged_members
    );
    
    RETURN new_clusters;
END;
$$;


ALTER FUNCTION "public"."fusionar_clusters"("p_clusters" "jsonb", "p_cluster1_id" integer, "p_cluster2_id" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generar_hash_vehiculo"("p_marca" "text", "p_modelo" "text", "p_año" integer, "p_version" "text") RETURNS character varying
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN encode(
        digest(
            normalizar_texto(p_marca) || '|' || 
            normalizar_texto(p_modelo) || '|' || 
            p_año::TEXT || '|' || 
            normalizar_texto(p_version),
            'sha256'
        ),
        'hex'
    );
END;
$$;


ALTER FUNCTION "public"."generar_hash_vehiculo"("p_marca" "text", "p_modelo" "text", "p_año" integer, "p_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."hybrid_search_knowledge"("query_embedding" "public"."vector", "keyword_query" "text", "filter" "jsonb" DEFAULT '{}'::"jsonb", "semantic_weight" double precision DEFAULT 0.6, "keyword_weight" double precision DEFAULT 0.4, "match_count" integer DEFAULT 10) RETURNS TABLE("id" bigint, "content" "text", "metadata" "jsonb", "combined_score" double precision)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH semantic_search AS (
        SELECT 
            kc.id,
            1 - (kc.embedding <=> query_embedding) AS semantic_score
        FROM knowledge_base_chunks kc
        WHERE (filter = '{}' OR kc.metadata @> filter)
    ),
    keyword_search AS (
        SELECT 
            kc.id,
            ts_rank(to_tsvector('spanish', kc.content), 
                    plainto_tsquery('spanish', keyword_query)) AS keyword_score
        FROM knowledge_base_chunks kc
        WHERE 
            to_tsvector('spanish', kc.content) @@ plainto_tsquery('spanish', keyword_query)
            AND (filter = '{}' OR kc.metadata @> filter)
    )
    SELECT 
        kc.id,
        kc.content,
        kc.metadata,
        (COALESCE(ss.semantic_score, 0) * semantic_weight) + 
        (COALESCE(ks.keyword_score, 0) * keyword_weight) AS combined_score
    FROM knowledge_base_chunks kc
    LEFT JOIN semantic_search ss ON kc.id = ss.id
    LEFT JOIN keyword_search ks ON kc.id = ks.id
    WHERE ss.id IS NOT NULL OR ks.id IS NOT NULL
    ORDER BY combined_score DESC
    LIMIT match_count;
END;
$$;


ALTER FUNCTION "public"."hybrid_search_knowledge"("query_embedding" "public"."vector", "keyword_query" "text", "filter" "jsonb", "semantic_weight" double precision, "keyword_weight" double precision, "match_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."hybrid_search_knowledge"("query_embedding" "public"."vector", "keyword_query" "text", "filter_insurer_code" "text" DEFAULT NULL::"text", "semantic_weight" double precision DEFAULT 0.7, "keyword_weight" double precision DEFAULT 0.3, "match_count" integer DEFAULT 10) RETURNS TABLE("id" bigint, "content" "text", "insurer_code" character varying, "insurer_name" "text", "doc_type" character varying, "title" "text", "combined_score" double precision)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH semantic_search AS (
        SELECT 
            kc.id,
            1 - (kc.embedding <=> query_embedding) AS semantic_score
        FROM knowledge_base_chunks kc
        WHERE filter_insurer_code IS NULL OR kc.insurer_code = filter_insurer_code
    ),
    keyword_search AS (
        SELECT 
            kc.id,
            ts_rank(to_tsvector('spanish', kc.content), 
                   plainto_tsquery('spanish', keyword_query)) AS keyword_score
        FROM knowledge_base_chunks kc
        WHERE 
            to_tsvector('spanish', kc.content) @@ plainto_tsquery('spanish', keyword_query)
            AND (filter_insurer_code IS NULL OR kc.insurer_code = filter_insurer_code)
    )
    SELECT 
        kc.id,
        kc.content,
        kc.insurer_code,
        am.insurer_name,
        kc.doc_type,
        kc.title,
        COALESCE(ss.semantic_score * semantic_weight, 0) + 
        COALESCE(ks.keyword_score * keyword_weight, 0) AS combined_score
    FROM knowledge_base_chunks kc
    LEFT JOIN aseguradoras_metadata am ON kc.insurer_code = am.insurer_code
    LEFT JOIN semantic_search ss ON kc.id = ss.id
    LEFT JOIN keyword_search ks ON kc.id = ks.id
    WHERE ss.id IS NOT NULL OR ks.id IS NOT NULL
    ORDER BY combined_score DESC
    LIMIT match_count;
END;
$$;


ALTER FUNCTION "public"."hybrid_search_knowledge"("query_embedding" "public"."vector", "keyword_query" "text", "filter_insurer_code" "text", "semantic_weight" double precision, "keyword_weight" double precision, "match_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."inclusion_coverage"("a" "text"[], "b" "text"[]) RETURNS numeric
    LANGUAGE "sql" IMMUTABLE
    AS $$
  WITH bset AS (
    SELECT DISTINCT x AS tok FROM unnest(coalesce(b, ARRAY[]::text[])) x
  ),
  aset AS (
    SELECT DISTINCT x AS tok FROM unnest(coalesce(a, ARRAY[]::text[])) x
  ),
  inter AS (
    SELECT COUNT(*)::numeric AS c
    FROM bset
    WHERE tok IN (SELECT tok FROM aset)
  ),
  bcount AS (
    SELECT COUNT(*)::numeric AS c FROM bset
  )
  SELECT CASE WHEN bcount.c = 0 THEN 0
              ELSE inter.c / bcount.c
         END
  FROM inter, bcount;
$$;


ALTER FUNCTION "public"."inclusion_coverage"("a" "text"[], "b" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insertar_nuevo"("vehiculos_data" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$DECLARE
    vehiculo JSONB;
    insertados INTEGER := 0;
    errores INTEGER := 0;
    vehiculo_id BIGINT;
    detalles JSONB[] := '{}';
BEGIN
    FOR vehiculo IN SELECT * FROM jsonb_array_elements(vehiculos_data)
    LOOP
        BEGIN
            INSERT INTO public.vehiculos_maestro (
                marca, modelo, anio, transmision, version,
                motor_config, cilindrada, traccion, carroceria, numero_ocupantes,
                main_specs, tech_specs, hash_comercial, hash_tecnico,
                aseguradoras_disponibles
            ) VALUES (
                vehiculo->>'marca',
                vehiculo->>'modelo',
                (vehiculo->>'anio')::INTEGER,
                NULLIF(vehiculo->>'transmision', ''),
                NULLIF(vehiculo->>'version', ''),
                NULLIF(vehiculo->>'motor_config', ''),
                CASE WHEN vehiculo->>'cilindrada' = '' OR vehiculo->>'cilindrada' IS NULL 
                     THEN NULL ELSE (vehiculo->>'cilindrada')::DECIMAL END,
                NULLIF(vehiculo->>'traccion', ''),
                NULLIF(vehiculo->>'carroceria', ''),
                CASE WHEN vehiculo->>'numero_ocupantes' = '' OR vehiculo->>'numero_ocupantes' IS NULL 
                     THEN NULL ELSE (vehiculo->>'numero_ocupantes')::INTEGER END,
                vehiculo->>'main_specs',
                vehiculo->>'tech_specs',
                vehiculo->>'hash_comercial',
                vehiculo->>'hash_tecnico',
                ARRAY[vehiculo->>'origen_aseguradora']
            ) RETURNING id INTO vehiculo_id;
            
            insertados := insertados + 1;
            detalles := detalles || jsonb_build_object(
                'hash_tecnico', vehiculo->>'hash_tecnico',
                'accion', 'insertado',
                'vehiculo_id', vehiculo_id
            );
            
        EXCEPTION WHEN OTHERS THEN
            errores := errores + 1;
            detalles := detalles || jsonb_build_object(
                'hash_tecnico', vehiculo->>'hash_tecnico',
                'accion', 'error',
                'mensaje', SQLERRM
            );
        END;
    END LOOP;
    
    RETURN jsonb_build_object(
        'insertados', insertados,
        'errores', errores,
        'total_procesados', insertados + errores,
        'detalles', to_jsonb(detalles)
    );
END;$$;


ALTER FUNCTION "public"."insertar_nuevo"("vehiculos_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insertar_nuevo_n8n"("vehiculo_data" json) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_insertados INTEGER := 0;
    v_registro JSON;
    v_aseguradora TEXT;
    v_es_array BOOLEAN;
BEGIN
    -- Detectar si es un array o un objeto único
    v_es_array := (json_typeof(vehiculo_data) = 'array');
    
    -- Si es un objeto único, convertirlo a array
    IF NOT v_es_array THEN
        vehiculo_data := json_build_array(vehiculo_data);
    END IF;
    
    -- Insertar todos los registros de una vez
    WITH inserted AS (
        INSERT INTO vehiculos_maestro (
            marca, modelo, anio, transmision, version,
            motor_config, cilindrada, traccion, carroceria, numero_ocupantes,
            main_specs, tech_specs, hash_comercial, hash_tecnico,
            aseguradoras_disponibles, fecha_creacion, fecha_actualizacion
        )
        SELECT 
            (v->>'marca')::VARCHAR(100),
            (v->>'modelo')::VARCHAR(150),
            (v->>'anio')::INTEGER,
            (v->>'transmision')::VARCHAR(20),
            (v->>'version')::VARCHAR(200),
            (v->>'motor_config')::VARCHAR(50),
            NULLIF(v->>'cilindrada', '')::DECIMAL(3,1),
            (v->>'traccion')::VARCHAR(20),
            (v->>'carroceria')::VARCHAR(50),
            NULLIF(v->>'numero_ocupantes', '')::INTEGER,
            (v->>'main_specs')::TEXT,
            (v->>'tech_specs')::TEXT,
            (v->>'hash_comercial')::VARCHAR(64),
            (v->>'hash_tecnico')::VARCHAR(64),
            string_to_array(v->>'origen_aseguradora', ',')::TEXT[],
            NOW(),
            NOW()
        FROM json_array_elements(vehiculo_data) AS v
        WHERE NOT EXISTS (
            SELECT 1 FROM vehiculos_maestro vm 
            WHERE vm.hash_tecnico = (v->>'hash_tecnico')::VARCHAR(64)
        )
        RETURNING id
    )
    SELECT COUNT(*) INTO v_insertados FROM inserted;
    
    RETURN json_build_object(
        'success', true,
        'insertados', v_insertados,
        'mensaje', format('Se insertaron %s vehículos nuevos', v_insertados)
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'insertados', 0,
            'error', SQLERRM
        );
END;
$$;


ALTER FUNCTION "public"."insertar_nuevo_n8n"("vehiculo_data" json) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insertar_nuevo_n8n"("anio" integer, "hash_comercial" "text", "hash_tecnico" "text", "main_specs" "text", "marca" "text", "modelo" "text", "origen_aseguradora" "text", "tech_specs" "text", "carroceria" "text" DEFAULT NULL::"text", "cilindrada" numeric DEFAULT NULL::numeric, "motor_config" "text" DEFAULT NULL::"text", "numero_ocupantes" integer DEFAULT NULL::integer, "traccion" "text" DEFAULT NULL::"text", "transmision" "text" DEFAULT NULL::"text", "version" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    -- Insert the vehicle with the individual parameters
    INSERT INTO public.vehiculos_maestro (
        marca, modelo, anio, transmision, version,
        motor_config, cilindrada, traccion, carroceria, numero_ocupantes,
        main_specs, tech_specs, hash_comercial, hash_tecnico,
        aseguradoras_disponibles
    ) VALUES (
        marca, modelo, anio,
        NULLIF(transmision, ''),
        NULLIF(version, ''),
        NULLIF(motor_config, ''),
        cilindrada,
        NULLIF(traccion, ''),
        NULLIF(carroceria, ''),
        numero_ocupantes,
        main_specs, tech_specs, hash_comercial, hash_tecnico,
        ARRAY[origen_aseguradora]
    );
    
    RETURN jsonb_build_object(
        'insertados', 1,
        'errores', 0,
        'total_procesados', 1,
        'hash_tecnico', hash_tecnico,
        'mensaje', 'Vehículo insertado exitosamente'
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'insertados', 0,
        'errores', 1,
        'total_procesados', 1,
        'hash_tecnico', hash_tecnico,
        'error', SQLERRM
    );
END;
$$;


ALTER FUNCTION "public"."insertar_nuevo_n8n"("anio" integer, "hash_comercial" "text", "hash_tecnico" "text", "main_specs" "text", "marca" "text", "modelo" "text", "origen_aseguradora" "text", "tech_specs" "text", "carroceria" "text", "cilindrada" numeric, "motor_config" "text", "numero_ocupantes" integer, "traccion" "text", "transmision" "text", "version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jaccard_similarity"("tokens1" "text"[], "tokens2" "text"[]) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
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


ALTER FUNCTION "public"."jaccard_similarity"("tokens1" "text"[], "tokens2" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."kb_sync_chunk"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.chunk is null then
    new.chunk := new.content;
  end if;
  return new;
end$$;


ALTER FUNCTION "public"."kb_sync_chunk"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."limpiar_catalogo_completo"() RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    total_before int;
    total_after int;
    total_consolidated int := 0;
    hash_record RECORD;
    consolidation_result jsonb;
BEGIN
    SELECT COUNT(*) INTO total_before FROM catalogo_homologado;
    
    FOR hash_record IN 
        SELECT DISTINCT hash_comercial 
        FROM catalogo_homologado
        WHERE (
            SELECT COUNT(*) 
            FROM catalogo_homologado ch2 
            WHERE ch2.hash_comercial = catalogo_homologado.hash_comercial
        ) > 1
    LOOP
        consolidation_result := consolidar_duplicados_internos(
            hash_record.hash_comercial, 
            0.85
        );
        total_consolidated := total_consolidated + 
            COALESCE((consolidation_result->>'consolidated')::int, 0);
    END LOOP;
    
    SELECT COUNT(*) INTO total_after FROM catalogo_homologado;
    
    RETURN jsonb_build_object(
        'success', true,
        'registros_antes', total_before,
        'registros_despues', total_after,
        'registros_eliminados', total_before - total_after,
        'consolidaciones_realizadas', total_consolidated,
        'timestamp', NOW()
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM,
        'timestamp', NOW()
    );
END;
$$;


ALTER FUNCTION "public"."limpiar_catalogo_completo"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "filter" "jsonb" DEFAULT '{}'::"jsonb", "match_threshold" double precision DEFAULT 0.3, "match_count" integer DEFAULT 10) RETURNS TABLE("id" bigint, "content" "text", "metadata" "jsonb", "similarity" double precision)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        kc.id,
        kc.content,
        kc.metadata,
        (1 - (kc.embedding <=> query_embedding))::double precision AS similarity
    FROM knowledge_base_chunks kc
    WHERE 
        (kc.embedding IS NOT NULL AND 
         1 - (kc.embedding <=> query_embedding) > match_threshold)
        AND (filter = '{}' OR kc.metadata @> filter)
    ORDER BY 
        CASE WHEN kc.embedding IS NOT NULL 
        THEN kc.embedding <=> query_embedding 
        ELSE 999999 END
    LIMIT match_count;
END;
$$;


ALTER FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "filter" "jsonb", "match_threshold" double precision, "match_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."match_documents_by_insurer"("query_embedding" "public"."vector", "match_count" integer DEFAULT 8, "insurer" "text" DEFAULT NULL::"text", "filter" "jsonb" DEFAULT '{}'::"jsonb") RETURNS TABLE("id" "uuid", "content" "text", "metadata" "jsonb", "similarity" double precision)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
begin
  return query
  select
    kb.id,
    kb.content,
    kb.metadata,
    1 - (kb.embedding <=> query_embedding) as similarity
  from public.knowledge_base_chunks kb
  where
    (filter is null or filter = '{}'::jsonb or kb.metadata @> filter)
    and (insurer is null or kb.metadata->>'insurer_code' = insurer)
  order by kb.embedding <=> query_embedding
  limit greatest(1, match_count);
end;
$$;


ALTER FUNCTION "public"."match_documents_by_insurer"("query_embedding" "public"."vector", "match_count" integer, "insurer" "text", "filter" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."merge_disponibilidad"("orig" "jsonb", "aseguradora" "text", "payload" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  SELECT
    CASE
      WHEN aseguradora IS NULL OR aseguradora = '' THEN orig
      ELSE
        jsonb_set(
          coalesce(orig, '{}'::jsonb),
          ARRAY[aseguradora],
          coalesce(payload, '{}'::jsonb),
          true
        )
    END;
$$;


ALTER FUNCTION "public"."merge_disponibilidad"("orig" "jsonb", "aseguradora" "text", "payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalizar_texto"("texto" "text") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
  RETURN UPPER(
    REGEXP_REPLACE(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          COALESCE(texto, ''),
          '[^A-Z0-9\s]', '', 'gi'  -- Quitar todo excepto letras, números y espacios
        ),
        '\s+', ' ', 'g'  -- Múltiples espacios a uno
      ),
      '^\s+|\s+$', '', 'g'  -- Trim
    )
  );
END;
$_$;


ALTER FUNCTION "public"."normalizar_texto"("texto" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_semantic_tokens"("input_tokens" "text"[]) RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $_$
DECLARE
    normalized_tokens text[];
    token text;
    normalized_token text;
BEGIN
    IF input_tokens IS NULL OR array_length(input_tokens, 1) IS NULL THEN
        RETURN ARRAY[]::text[];
    END IF;
    
    normalized_tokens := ARRAY[]::text[];
    
    FOREACH token IN ARRAY input_tokens
    LOOP
        normalized_token := UPPER(TRIM(token));
        
        -- Normalización de motor y cilindros
        normalized_token := regexp_replace(normalized_token, '^(\d+)\s*CIL(INDROS?)?$', '\1CIL', 'g');
        normalized_token := regexp_replace(normalized_token, '^(\d+)\s*CILINDROS?$', '\1CIL', 'g');
        normalized_token := regexp_replace(normalized_token, '^(L|V|I)(\d+)$', '\1\2', 'g');
        
        -- Normalización de combustible
        normalized_token := regexp_replace(normalized_token, '^(GAS|GASOLINA)$', 'GAS', 'g');
        normalized_token := regexp_replace(normalized_token, '^DIESEL$', 'DIESEL', 'g');
        
        -- Normalización de transmisión
        normalized_token := regexp_replace(normalized_token, '^(AUTO|AUTOMATICO|AUTOMATICA)$', 'AUTO', 'g');
        normalized_token := regexp_replace(normalized_token, '^(MAN|MANUAL)$', 'MANUAL', 'g');
        normalized_token := regexp_replace(normalized_token, '^(CVT|VARIABLE)$', 'CVT', 'g');
        
        -- Normalización de puertas
        normalized_token := regexp_replace(normalized_token, '^(\d+)P(UERTAS?)?$', '\1P', 'g');
        normalized_token := regexp_replace(normalized_token, '^(\d+)\s*PUERTAS?$', '\1P', 'g');
        
        -- Normalización de potencia
        normalized_token := regexp_replace(normalized_token, '^(\d+)\s*(HP|PS)$', '\1HP', 'g');
        normalized_token := regexp_replace(normalized_token, '^(\d+)\s*KW$', '\1KW', 'g');
        
        -- Normalización de desplazamiento
        normalized_token := regexp_replace(normalized_token, '^(\d+\.?\d*)\s*(L|LT|LITROS?)$', '\1L', 'g');
        
        -- Tracción
        normalized_token := regexp_replace(normalized_token, '^(4X4|AWD|4WD)$', '4WD', 'g');
        normalized_token := regexp_replace(normalized_token, '^(4X2|FWD|2WD)$', '2WD', 'g');
        
        -- Carrocería
        normalized_token := regexp_replace(normalized_token, '^(HB|HATCH)$', 'HATCHBACK', 'g');
        
        normalized_tokens := array_append(normalized_tokens, normalized_token);
    END LOOP;
    
    RETURN normalized_tokens;
END;
$_$;


ALTER FUNCTION "public"."normalize_semantic_tokens"("input_tokens" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."obtener_estadisticas"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    stats JSONB;
BEGIN
    SELECT jsonb_build_object(
        'total_vehiculos', COUNT(*),
        'total_marcas', COUNT(DISTINCT marca),
        'por_aseguradora', (
            SELECT jsonb_object_agg(
                aseguradora,
                total_vehiculos
            )
            FROM (
                SELECT 
                    unnest(aseguradoras_disponibles) as aseguradora,
                    COUNT(*) as total_vehiculos
                FROM vehiculos_maestro
                GROUP BY unnest(aseguradoras_disponibles)
            ) stats_por_aseguradora
        ),
        'ultima_actualizacion', MAX(fecha_actualizacion)
    ) INTO stats
    FROM vehiculos_maestro;
    
    RETURN stats;
END;
$$;


ALTER FUNCTION "public"."obtener_estadisticas"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prepare_chunks_for_reranking"("query_embedding" "public"."vector", "initial_count" integer DEFAULT 30) RETURNS TABLE("id" bigint, "content" "text", "initial_score" double precision)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        kc.id,
        kc.content,
        1 - (kc.embedding <=> query_embedding) AS initial_score
    FROM knowledge_base_chunks kc
    ORDER BY kc.embedding <=> query_embedding
    LIMIT initial_count;
END;
$$;


ALTER FUNCTION "public"."prepare_chunks_for_reranking"("query_embedding" "public"."vector", "initial_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."procesar_batch_completo"("vehiculos_json" json) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_insertados INTEGER := 0;
    v_actualizados INTEGER := 0;
    v_omitidos INTEGER := 0;
    v_total INTEGER;
    v_aseguradora TEXT;
BEGIN
    -- Obtener total y aseguradora
    v_total := json_array_length(vehiculos_json);
    v_aseguradora := vehiculos_json->0->>'origen_aseguradora';
    
    -- Usar UPSERT para procesar todo de una vez
    WITH procesados AS (
        INSERT INTO vehiculos_maestro (
            marca, modelo, anio, transmision, version,
            motor_config, cilindrada, traccion, carroceria, numero_ocupantes,
            main_specs, tech_specs, hash_comercial, hash_tecnico,
            aseguradoras_disponibles
        )
        SELECT 
            (v->>'marca')::VARCHAR(100),
            (v->>'modelo')::VARCHAR(150),
            (v->>'anio')::INTEGER,
            (v->>'transmision')::VARCHAR(20),
            (v->>'version')::VARCHAR(200),
            (v->>'motor_config')::VARCHAR(50),
            NULLIF(v->>'cilindrada', '')::DECIMAL(3,1),
            (v->>'traccion')::VARCHAR(20),
            (v->>'carroceria')::VARCHAR(50),
            NULLIF(v->>'numero_ocupantes', '')::INTEGER,
            (v->>'main_specs')::TEXT,
            (v->>'tech_specs')::TEXT,
            (v->>'hash_comercial')::VARCHAR(64),
            (v->>'hash_tecnico')::VARCHAR(64),
            ARRAY[v_aseguradora]::TEXT[]
        FROM json_array_elements(vehiculos_json) AS v
        ON CONFLICT (hash_tecnico) 
        DO UPDATE SET
            aseguradoras_disponibles = 
                CASE 
                    WHEN v_aseguradora = ANY(vehiculos_maestro.aseguradoras_disponibles)
                    THEN vehiculos_maestro.aseguradoras_disponibles
                    ELSE array_append(vehiculos_maestro.aseguradoras_disponibles, v_aseguradora)
                END,
            fecha_actualizacion = NOW()
        WHERE NOT (v_aseguradora = ANY(vehiculos_maestro.aseguradoras_disponibles))
        RETURNING 
            CASE 
                WHEN xmax = 0 THEN 'inserted'
                WHEN xmax != 0 THEN 'updated'
                ELSE 'skipped'
            END as action
    )
    SELECT 
        COUNT(*) FILTER (WHERE action = 'inserted'),
        COUNT(*) FILTER (WHERE action = 'updated')
    INTO v_insertados, v_actualizados
    FROM procesados;
    
    v_omitidos := v_total - v_insertados - v_actualizados;
    
    RETURN json_build_object(
        'success', true,
        'total', v_total,
        'insertados', v_insertados,
        'actualizados', v_actualizados,
        'omitidos', v_omitidos,
        'aseguradora', v_aseguradora,
        'timestamp', NOW()
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', false,
            'error', SQLERRM
        );
END;
$$;


ALTER FUNCTION "public"."procesar_batch_completo"("vehiculos_json" json) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."procesar_batch_completo"("vehiculos_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  t_total        integer := 0;
  t_insertados   integer := 0;
  t_actualizados integer := 0;
BEGIN
  IF vehiculos_json IS NULL OR jsonb_typeof(vehiculos_json) <> 'array' THEN
    RAISE EXCEPTION 'vehiculos_json debe ser un arreglo JSONB';
  END IF;

  WITH incoming AS (
    SELECT
      v->>'id_canonico'                 AS id_canonico,
      v->>'hash_comercial'              AS hash_comercial,
      v->>'string_comercial'            AS string_comercial,
      v->>'string_tecnico'              AS string_tecnico,
      v->>'marca'                       AS marca,
      v->>'modelo'                      AS modelo,
      NULLIF(v->>'anio','')::int        AS anio,
      NULLIF(v->>'transmision','')      AS transmision,
      NULLIF(v->>'version','')          AS version,
      NULLIF(v->>'motor_config','')     AS motor_config,
      NULLIF(v->>'carroceria','')       AS carroceria,
      NULLIF(v->>'traccion','')         AS traccion,
      v->>'origen_aseguradora'          AS origen_aseguradora,
      v->>'id_original'                 AS id_original,
      v->>'version_original'            AS version_original,
      COALESCE((v->>'activo')::boolean, true) AS activo
    FROM jsonb_array_elements(vehiculos_json) v
  ),
  upsert AS (
    INSERT INTO public.catalogo_homologado (
      id_canonico, hash_comercial, string_comercial, string_tecnico,
      marca, modelo, anio, transmision, version, motor_config, carroceria, traccion,
      disponibilidad, confianza_score, fecha_actualizacion
    )
    SELECT
      i.id_canonico, i.hash_comercial, i.string_comercial, i.string_tecnico,
      i.marca, i.modelo, i.anio, i.transmision, i.version, i.motor_config, i.carroceria, i.traccion,
      jsonb_build_object(
        i.origen_aseguradora,
        jsonb_build_object(
          'activo', i.activo,
          'id_original', i.id_original,
          'version_original', i.version_original,
          'fecha_actualizacion', NOW()
        )
      ),
      1.0, NOW()
    FROM incoming i
    ON CONFLICT (hash_comercial) DO UPDATE SET
      id_canonico        = COALESCE(EXCLUDED.id_canonico, catalogo_homologado.id_canonico),
      string_comercial   = COALESCE(EXCLUDED.string_comercial, catalogo_homologado.string_comercial),
      string_tecnico     = COALESCE(catalogo_homologado.string_tecnico, EXCLUDED.string_tecnico),
      marca              = COALESCE(catalogo_homologado.marca, EXCLUDED.marca),
      modelo             = COALESCE(catalogo_homologado.modelo, EXCLUDED.modelo),
      anio               = COALESCE(catalogo_homologado.anio, EXCLUDED.anio),
      transmision        = COALESCE(catalogo_homologado.transmision, EXCLUDED.transmision),
      version            = COALESCE(catalogo_homologado.version, EXCLUDED.version),
      motor_config       = COALESCE(catalogo_homologado.motor_config, EXCLUDED.motor_config),
      carroceria         = COALESCE(catalogo_homologado.carroceria, EXCLUDED.carroceria),
      traccion           = COALESCE(catalogo_homologado.traccion, EXCLUDED.traccion),
      disponibilidad     = COALESCE(catalogo_homologado.disponibilidad, '{}'::jsonb) || EXCLUDED.disponibilidad,
      confianza_score    = LEAST(COALESCE(catalogo_homologado.confianza_score, 1.0) + 0.05, 1.0),
      fecha_actualizacion= NOW()
    RETURNING (xmax = 0) AS inserted
  )
  SELECT COUNT(*) FILTER (WHERE inserted) AS ins, COUNT(*) AS tot
  INTO t_insertados, t_total
  FROM upsert;

  t_actualizados := t_total - t_insertados;

  RETURN jsonb_build_object(
    'success', true,
    'total', t_total,
    'insertados', t_insertados,
    'actualizados', t_actualizados,
    'omitidos', 0
  );
END;
$$;


ALTER FUNCTION "public"."procesar_batch_completo"("vehiculos_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."procesar_batch_completo2"("vehiculos_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  t_total        integer := 0;
  t_insertados   integer := 0;
  t_actualizados integer := 0;
BEGIN
  IF vehiculos_json IS NULL OR jsonb_typeof(vehiculos_json) <> 'array' THEN
    RAISE EXCEPTION 'vehiculos_json debe ser un arreglo JSONB';
  END IF;

  WITH incoming AS (
    SELECT
      v->>'id_canonico'                 AS id_canonico,
      v->>'hash_comercial'              AS hash_comercial,
      v->>'string_comercial'            AS string_comercial,
      v->>'string_tecnico'              AS string_tecnico,
      v->>'marca'                       AS marca,
      v->>'modelo'                      AS modelo,
      NULLIF(v->>'anio','')::int        AS anio,
      NULLIF(v->>'transmision','')      AS transmision,
      NULLIF(v->>'version','')          AS version,
      NULLIF(v->>'motor_config','')     AS motor_config,
      NULLIF(v->>'carroceria','')       AS carroceria,
      NULLIF(v->>'traccion','')         AS traccion,
      v->>'origen_aseguradora'          AS origen_aseguradora,
      v->>'id_original'                 AS id_original,
      v->>'version_original'            AS version_original,
      COALESCE((v->>'activo')::boolean, true) AS activo
    FROM jsonb_array_elements(vehiculos_json) v
  ),
  upsert AS (
    INSERT INTO public.catalogo_homologado (
      id_canonico, hash_comercial, string_comercial, string_tecnico,
      marca, modelo, anio, transmision, version, motor_config, carroceria, traccion,
      disponibilidad, confianza_score, fecha_actualizacion
    )
    SELECT
      i.id_canonico, i.hash_comercial, i.string_comercial, i.string_tecnico,
      i.marca, i.modelo, i.anio, i.transmision, i.version, i.motor_config, i.carroceria, i.traccion,
      jsonb_build_object(
        i.origen_aseguradora,
        jsonb_build_object(
          'activo', i.activo,
          'id_original', i.id_original,
          'version_original', i.version_original,
          'fecha_actualizacion', NOW()
        )
      ),
      1.0, NOW()
    FROM incoming i
    ON CONFLICT (hash_comercial) DO UPDATE SET
      id_canonico        = COALESCE(EXCLUDED.id_canonico, catalogo_homologado.id_canonico),
      string_comercial   = COALESCE(EXCLUDED.string_comercial, catalogo_homologado.string_comercial),
      string_tecnico     = COALESCE(catalogo_homologado.string_tecnico, EXCLUDED.string_tecnico),
      marca              = COALESCE(catalogo_homologado.marca, EXCLUDED.marca),
      modelo             = COALESCE(catalogo_homologado.modelo, EXCLUDED.modelo),
      anio               = COALESCE(catalogo_homologado.anio, EXCLUDED.anio),
      transmision        = COALESCE(catalogo_homologado.transmision, EXCLUDED.transmision),
      version            = COALESCE(catalogo_homologado.version, EXCLUDED.version),
      motor_config       = COALESCE(catalogo_homologado.motor_config, EXCLUDED.motor_config),
      carroceria         = COALESCE(catalogo_homologado.carroceria, EXCLUDED.carroceria),
      traccion           = COALESCE(catalogo_homologado.traccion, EXCLUDED.traccion),
      disponibilidad     = COALESCE(catalogo_homologado.disponibilidad, '{}'::jsonb) || EXCLUDED.disponibilidad,
      confianza_score    = LEAST(COALESCE(catalogo_homologado.confianza_score, 1.0) + 0.05, 1.0),
      fecha_actualizacion= NOW()
    RETURNING (xmax = 0) AS inserted
  )
  SELECT COUNT(*) FILTER (WHERE inserted) AS ins, COUNT(*) AS tot
  INTO t_insertados, t_total
  FROM upsert;

  t_actualizados := t_total - t_insertados;

  RETURN jsonb_build_object(
    'success', true,
    'total', t_total,
    'insertados', t_insertados,
    'actualizados', t_actualizados,
    'omitidos', 0
  );
END;
$$;


ALTER FUNCTION "public"."procesar_batch_completo2"("vehiculos_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."procesar_batch_homologacion"("p_vehiculos_json" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_received INTEGER := 0;
    v_staged INTEGER := 0;
    v_nuevos INTEGER := 0;
    v_enriquecidos INTEGER := 0;
    v_actualizados INTEGER := 0;
    v_conflictos INTEGER := 0;
    v_multiples_matches INTEGER := 0;
    v_warnings TEXT[] := '{}';
    v_errors TEXT[] := '{}';
    v_vehiculos_array JSONB;
    v_match_count INTEGER;
BEGIN
    -- ========================================
    -- 1. VALIDACIÓN Y EXTRACCIÓN DE ENTRADA
    -- ========================================
    IF p_vehiculos_json ? 'vehiculos_json' THEN
        v_vehiculos_array := p_vehiculos_json->'vehiculos_json';
    ELSE
        v_vehiculos_array := p_vehiculos_json;
    END IF;
    
    IF v_vehiculos_array IS NULL OR jsonb_typeof(v_vehiculos_array) != 'array' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Input debe contener un array de vehículos',
            'received', 0
        );
    END IF;
    
    v_received := jsonb_array_length(v_vehiculos_array);
    
    -- ========================================
    -- 2. STAGING EN TABLA TEMPORAL
    -- ========================================
    CREATE TEMP TABLE tmp_batch (
        -- Datos del vehículo
        id_canonico VARCHAR(64),
        hash_comercial VARCHAR(64),
        string_comercial TEXT,
        string_tecnico TEXT,
        marca VARCHAR(100),
        modelo VARCHAR(150),
        anio INTEGER,
        transmision VARCHAR(20),
        version VARCHAR(200),
        motor_config VARCHAR(50),
        carroceria VARCHAR(50),
        traccion VARCHAR(20),
        -- Origen
        origen_aseguradora VARCHAR(50),
        id_original VARCHAR(100),
        version_original TEXT,
        activo BOOLEAN,
        -- Control interno
        procesado BOOLEAN DEFAULT FALSE,
        id_homologado_match BIGINT,
        matches_encontrados INTEGER DEFAULT 0,
        accion TEXT
    ) ON COMMIT DROP;
    
    -- Cargar y normalizar datos
    INSERT INTO tmp_batch (
        id_canonico, hash_comercial, string_comercial, string_tecnico,
        marca, modelo, anio, transmision, version,
        motor_config, carroceria, traccion,
        origen_aseguradora, id_original, version_original, activo
    )
    SELECT DISTINCT ON (v->>'origen_aseguradora', v->>'id_original')
        TRIM(UPPER(v->>'id_canonico'))::VARCHAR(64),
        TRIM(UPPER(v->>'hash_comercial'))::VARCHAR(64),
        TRIM(UPPER(v->>'string_comercial')),
        TRIM(UPPER(v->>'string_tecnico')),
        TRIM(UPPER(v->>'marca')),
        TRIM(UPPER(v->>'modelo')),
        (v->>'anio')::INTEGER,
        UPPER(NULLIF(TRIM(v->>'transmision'), '')),
        NULLIF(TRIM(UPPER(v->>'version')), ''),
        NULLIF(TRIM(UPPER(v->>'motor_config')), ''),
        NULLIF(TRIM(UPPER(v->>'carroceria')), ''),
        NULLIF(TRIM(UPPER(v->>'traccion')), ''),
        TRIM(UPPER(v->>'origen_aseguradora')),
        v->>'id_original',
        v->>'version_original',
        COALESCE((v->>'activo')::BOOLEAN, TRUE)
    FROM jsonb_array_elements(v_vehiculos_array) v
    WHERE (v->>'anio')::INTEGER BETWEEN 2000 AND 2030;
    
    GET DIAGNOSTICS v_staged = ROW_COUNT;
    
    -- ========================================
    -- 3. BÚSQUEDA DE COMPATIBILIDAD MEJORADA
    -- ========================================
    
    -- Primero: buscar matches exactos por id_canonico
    UPDATE tmp_batch t
    SET id_homologado_match = ch.id,
        matches_encontrados = 1,
        accion = 'actualizar_disponibilidad'
    FROM catalogo_homologado ch
    WHERE ch.id_canonico = t.id_canonico;
    
    -- Segundo: buscar vehículos compatibles para enriquecimiento
    -- IMPORTANTE: Solo enriquecer motor_config, carroceria, traccion
    -- transmision y version deben coincidir exactamente o ambos ser NULL
    
    -- Primero contamos cuántos matches potenciales hay
    UPDATE tmp_batch t
    SET matches_encontrados = (
        SELECT COUNT(*)
        FROM catalogo_homologado ch
        WHERE 
            t.id_homologado_match IS NULL  -- No tiene match por id_canonico
            -- Campos obligatorios SIEMPRE deben coincidir
            AND ch.marca = t.marca
            AND ch.modelo = t.modelo
            AND ch.anio = t.anio
            -- Transmisión y versión deben coincidir EXACTAMENTE o ambos ser NULL
            AND (
                (ch.transmision IS NULL AND t.transmision IS NULL) OR 
                (ch.transmision = t.transmision)
            )
            AND (
                (ch.version IS NULL AND t.version IS NULL) OR 
                (ch.version = t.version)
            )
            -- Para las especificaciones técnicas, pueden ser NULL o coincidir
            AND (ch.motor_config IS NULL OR t.motor_config IS NULL OR ch.motor_config = t.motor_config)
            AND (ch.carroceria IS NULL OR t.carroceria IS NULL OR ch.carroceria = t.carroceria)
            AND (ch.traccion IS NULL OR t.traccion IS NULL OR ch.traccion = t.traccion)
            -- Y al menos una especificación técnica puede ser enriquecida
            AND (
                (ch.motor_config IS NULL AND t.motor_config IS NOT NULL)
                OR (ch.carroceria IS NULL AND t.carroceria IS NOT NULL)
                OR (ch.traccion IS NULL AND t.traccion IS NOT NULL)
            )
    )
    WHERE t.id_homologado_match IS NULL;
    
    -- Solo hacer match si hay EXACTAMENTE 1 coincidencia
    UPDATE tmp_batch t
    SET id_homologado_match = (
        SELECT ch.id
        FROM catalogo_homologado ch
        WHERE 
            -- Campos obligatorios
            ch.marca = t.marca
            AND ch.modelo = t.modelo
            AND ch.anio = t.anio
            -- Transmisión y versión exactas
            AND (
                (ch.transmision IS NULL AND t.transmision IS NULL) OR 
                (ch.transmision = t.transmision)
            )
            AND (
                (ch.version IS NULL AND t.version IS NULL) OR 
                (ch.version = t.version)
            )
            -- Especificaciones compatibles
            AND (ch.motor_config IS NULL OR t.motor_config IS NULL OR ch.motor_config = t.motor_config)
            AND (ch.carroceria IS NULL OR t.carroceria IS NULL OR ch.carroceria = t.carroceria)
            AND (ch.traccion IS NULL OR t.traccion IS NULL OR ch.traccion = t.traccion)
            -- Al menos una especificación puede ser enriquecida
            AND (
                (ch.motor_config IS NULL AND t.motor_config IS NOT NULL)
                OR (ch.carroceria IS NULL AND t.carroceria IS NOT NULL)
                OR (ch.traccion IS NULL AND t.traccion IS NOT NULL)
            )
        LIMIT 1
    ),
    accion = 'enriquecer'
    WHERE t.id_homologado_match IS NULL 
        AND t.matches_encontrados = 1;  -- Solo si hay exactamente 1 match
    
    -- Contar vehículos con múltiples matches potenciales
    SELECT COUNT(*) INTO v_multiples_matches
    FROM tmp_batch
    WHERE id_homologado_match IS NULL 
        AND matches_encontrados > 1;
    
    -- Agregar warnings para múltiples matches
    IF v_multiples_matches > 0 THEN
        WITH multiples AS (
            SELECT t.marca || ' ' || t.modelo || ' ' || t.anio || 
                   COALESCE(' ' || t.transmision, '') || 
                   COALESCE(' ' || t.version, '') ||
                   ' [' || t.origen_aseguradora || '] - ' ||
                   t.matches_encontrados || ' matches potenciales, creando nuevo registro' as detalle
            FROM tmp_batch t
            WHERE t.id_homologado_match IS NULL 
                AND t.matches_encontrados > 1
            LIMIT 5
        )
        SELECT array_agg(detalle) INTO v_warnings FROM multiples;
    END IF;
    
    -- ========================================
    -- 4. PROCESAR VEHÍCULOS NUEVOS (sin match o múltiples matches)
    -- ========================================
    WITH nuevos AS (
        INSERT INTO catalogo_homologado (
            id_canonico, hash_comercial, string_comercial, string_tecnico,
            marca, modelo, anio, transmision, version,
            motor_config, carroceria, traccion,
            disponibilidad, confianza_score
        )
        SELECT 
            t.id_canonico, 
            t.hash_comercial, 
            t.string_comercial, 
            t.string_tecnico,
            t.marca, 
            t.modelo, 
            t.anio, 
            t.transmision, 
            t.version,
            t.motor_config, 
            t.carroceria, 
            t.traccion,
            jsonb_build_object(
                t.origen_aseguradora, jsonb_build_object(
                    'activo', t.activo,
                    'id_original', t.id_original,
                    'version_original', t.version_original,
                    'fecha_actualizacion', NOW()
                )
            ),
            CASE 
                WHEN t.matches_encontrados > 1 THEN 0.8  -- Menor confianza si había múltiples opciones
                ELSE 1.0 
            END
        FROM tmp_batch t
        WHERE t.id_homologado_match IS NULL
        ON CONFLICT (id_canonico) DO NOTHING
        RETURNING id
    )
    SELECT COUNT(*) INTO v_nuevos FROM nuevos;
    
    -- Marcar como procesados
    UPDATE tmp_batch SET procesado = TRUE 
    WHERE id_homologado_match IS NULL;
    
    -- ========================================
    -- 5. ENRIQUECER VEHÍCULOS COMPATIBLES (solo especificaciones técnicas)
    -- ========================================
    WITH enriquecidos AS (
        UPDATE catalogo_homologado ch
        SET 
            -- Solo enriquecer especificaciones técnicas, NO transmisión ni versión
            motor_config = COALESCE(ch.motor_config, t.motor_config),
            carroceria = COALESCE(ch.carroceria, t.carroceria),
            traccion = COALESCE(ch.traccion, t.traccion),
            -- Actualizar id_canonico si el nuevo tiene más información
            id_canonico = CASE 
                WHEN t.motor_config IS NOT NULL OR t.carroceria IS NOT NULL OR t.traccion IS NOT NULL
                THEN t.id_canonico 
                ELSE ch.id_canonico 
            END,
            -- Reconstruir string técnico con datos actualizados
            string_tecnico = UPPER(
                ch.marca || '|' || 
                ch.modelo || '|' || 
                ch.anio || '|' || 
                COALESCE(ch.transmision, 'NULL') || '|' ||
                COALESCE(ch.version, 'NULL') || '|' ||
                COALESCE(COALESCE(ch.motor_config, t.motor_config), 'NULL') || '|' ||
                COALESCE(COALESCE(ch.carroceria, t.carroceria), 'NULL') || '|' ||
                COALESCE(COALESCE(ch.traccion, t.traccion), 'NULL')
            ),
            -- Agregar/actualizar disponibilidad de aseguradora
            disponibilidad = ch.disponibilidad || jsonb_build_object(
                t.origen_aseguradora, jsonb_build_object(
                    'activo', t.activo,
                    'id_original', t.id_original,
                    'version_original', t.version_original,
                    'fecha_actualizacion', NOW()
                )
            ),
            -- Aumentar confianza por enriquecimiento
            confianza_score = LEAST(ch.confianza_score + 0.05, 1.0),
            fecha_actualizacion = NOW()
        FROM tmp_batch t
        WHERE ch.id = t.id_homologado_match
            AND t.accion = 'enriquecer'
            AND NOT t.procesado
        RETURNING ch.id
    )
    SELECT COUNT(*) INTO v_enriquecidos FROM enriquecidos;
    
    -- ========================================
    -- 6. ACTUALIZAR SOLO DISPONIBILIDAD (mismo id_canonico)
    -- ========================================
    WITH actualizados AS (
        UPDATE catalogo_homologado ch
        SET 
            disponibilidad = ch.disponibilidad || jsonb_build_object(
                t.origen_aseguradora, jsonb_build_object(
                    'activo', t.activo,
                    'id_original', t.id_original,
                    'version_original', t.version_original,
                    'fecha_actualizacion', NOW()
                )
            ),
            confianza_score = LEAST(ch.confianza_score + 0.01, 1.0),
            fecha_actualizacion = NOW()
        FROM tmp_batch t
        WHERE ch.id = t.id_homologado_match
            AND t.accion = 'actualizar_disponibilidad'
            AND NOT t.procesado
        RETURNING ch.id
    )
    SELECT COUNT(*) INTO v_actualizados FROM actualizados;
    
    -- ========================================
    -- 7. DETECTAR CONFLICTOS
    -- ========================================
    
    -- Detectar vehículos que NO matchearon por conflictos reales
    WITH conflictos_detectados AS (
        SELECT DISTINCT
            t.marca || ' ' || t.modelo || ' ' || t.anio || 
            ' [' || t.origen_aseguradora || '] - Conflicto: ' ||
            CASE 
                WHEN ch.transmision IS NOT NULL AND t.transmision IS NOT NULL AND ch.transmision != t.transmision 
                THEN 'transmision(' || ch.transmision || '≠' || t.transmision || ') '
                ELSE ''
            END ||
            CASE 
                WHEN ch.version IS NOT NULL AND t.version IS NOT NULL AND ch.version != t.version 
                THEN 'version(' || ch.version || '≠' || t.version || ') '
                ELSE ''
            END ||
            CASE 
                WHEN ch.carroceria IS NOT NULL AND t.carroceria IS NOT NULL AND ch.carroceria != t.carroceria 
                THEN 'carroceria(' || ch.carroceria || '≠' || t.carroceria || ') '
                ELSE ''
            END ||
            CASE 
                WHEN ch.motor_config IS NOT NULL AND t.motor_config IS NOT NULL AND ch.motor_config != t.motor_config 
                THEN 'motor(' || ch.motor_config || '≠' || t.motor_config || ') '
                ELSE ''
            END ||
            CASE 
                WHEN ch.traccion IS NOT NULL AND t.traccion IS NOT NULL AND ch.traccion != t.traccion 
                THEN 'traccion(' || ch.traccion || '≠' || t.traccion || ') '
                ELSE ''
            END as detalle
        FROM tmp_batch t
        JOIN catalogo_homologado ch ON 
            ch.marca = t.marca 
            AND ch.modelo = t.modelo 
            AND ch.anio = t.anio
        WHERE t.id_homologado_match IS NULL
            AND t.matches_encontrados = 0  -- No fue por múltiples matches
            AND (
                (ch.transmision IS NOT NULL AND t.transmision IS NOT NULL AND ch.transmision != t.transmision)
                OR (ch.version IS NOT NULL AND t.version IS NOT NULL AND ch.version != t.version)
                OR (ch.carroceria IS NOT NULL AND t.carroceria IS NOT NULL AND ch.carroceria != t.carroceria)
                OR (ch.motor_config IS NOT NULL AND t.motor_config IS NOT NULL AND ch.motor_config != t.motor_config)
                OR (ch.traccion IS NOT NULL AND t.traccion IS NOT NULL AND ch.traccion != t.traccion)
            )
        LIMIT 20
    )
    SELECT COUNT(*) INTO v_conflictos FROM conflictos_detectados;
    
    -- Agregar conflictos a warnings si existen
    IF v_conflictos > 0 THEN
        WITH conflict_details AS (
            SELECT DISTINCT
                t.marca || ' ' || t.modelo || ' ' || t.anio || 
                ' [' || t.origen_aseguradora || '] - Conflicto con existente' as detalle
            FROM tmp_batch t
            JOIN catalogo_homologado ch ON 
                ch.marca = t.marca 
                AND ch.modelo = t.modelo 
                AND ch.anio = t.anio
            WHERE t.id_homologado_match IS NULL
                AND t.matches_encontrados = 0
            LIMIT 5
        )
        SELECT array_cat(COALESCE(v_warnings, '{}'), array_agg(detalle)) 
        INTO v_warnings 
        FROM conflict_details;
    END IF;
    
    -- ========================================
    -- 8. RETORNAR RESPUESTA
    -- ========================================
    
    RETURN jsonb_build_object(
        'success', true,
        'received', v_received,
        'staged', v_staged,
        'procesados', jsonb_build_object(
            'nuevos', v_nuevos,
            'enriquecidos', v_enriquecidos,
            'actualizados', v_actualizados,
            'conflictos', v_conflictos,
            'multiples_matches', v_multiples_matches
        ),
        'warnings', COALESCE(v_warnings, '{}'),
        'errors', v_errors
    );
    
EXCEPTION
    WHEN unique_violation THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Violación de unicidad: ' || SQLERRM,
            'detail', SQLSTATE,
            'received', v_received
        );
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', SQLERRM,
            'detail', SQLSTATE,
            'received', v_received
        );
END;
$$;


ALTER FUNCTION "public"."procesar_batch_homologacion"("p_vehiculos_json" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."procesar_batch_por_chunks"("records" "jsonb", "chunk_size" integer DEFAULT 50) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    total_result jsonb;
    chunk_result jsonb;
    current_chunk jsonb;
    offset_val int := 0;
    total_created int := 0;
    total_updated int := 0;
    total_merged int := 0;
    total_skipped int := 0;
    all_errors jsonb := '[]'::jsonb;
BEGIN
    -- Procesar en chunks
    WHILE offset_val < jsonb_array_length(records)
    LOOP
        -- Extraer chunk actual
        SELECT jsonb_agg(value) INTO current_chunk
        FROM (
            SELECT value 
            FROM jsonb_array_elements(records) 
            WITH ORDINALITY AS t(value, ord)
            WHERE ord > offset_val 
              AND ord <= offset_val + chunk_size
        ) sub;
        
        -- Procesar chunk si tiene datos
        IF current_chunk IS NOT NULL THEN
            chunk_result := procesar_batch_vehiculos(current_chunk);
            
            -- Acumular resultados
            total_created := total_created + COALESCE((chunk_result->>'registros_creados')::int, 0);
            total_updated := total_updated + COALESCE((chunk_result->>'registros_actualizados')::int, 0);
            total_merged := total_merged + COALESCE((chunk_result->>'registros_homologados')::int, 0);
            total_skipped := total_skipped + COALESCE((chunk_result->>'registros_omitidos')::int, 0);
            
            -- Acumular errores si hay
            IF chunk_result->'errores' IS NOT NULL AND jsonb_array_length(chunk_result->'errores') > 0 THEN
                all_errors := all_errors || (chunk_result->'errores');
            END IF;
        END IF;
        
        offset_val := offset_val + chunk_size;
    END LOOP;
    
    RETURN jsonb_build_object(
        'success', true,
        'total_procesados', jsonb_array_length(records),
        'registros_creados', total_created,
        'registros_actualizados', total_updated,
        'registros_homologados', total_merged,
        'registros_omitidos', total_skipped,
        'errores', all_errors,
        'metodo', 'procesamiento_por_chunks_v6',
        'chunk_size', chunk_size,
        'timestamp', now()
    );
END;
$$;


ALTER FUNCTION "public"."procesar_batch_por_chunks"("records" "jsonb", "chunk_size" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."procesar_batch_vehiculos"("p_input" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_rec RECORD;
  v_now timestamptz := now();
  v_b_tokens text[];
  v_hash text;
  v_ver_canonica text;
  v_aseg text;
  v_ins_ids bigint[] := ARRAY[]::bigint[];
  v_upd_ids bigint[] := ARRAY[]::bigint[];
  v_nochange_ids bigint[] := ARRAY[]::bigint[];
  v_errors jsonb := '[]'::jsonb;
  -- filas candidatas por hash
  r_a RECORD;
  matched_ids bigint[] := ARRAY[]::bigint[];
  -- payload para disponibilidad por ítem
  payload jsonb;
BEGIN
  IF p_input IS NULL OR p_input ? 'vehiculos_json' = false THEN
    RAISE EXCEPTION 'Entrada inválida: se espera clave vehiculos_json';
  END IF;

  -- Iterar cada vehículo del batch (misma aseguradora)
  FOR v_rec IN
    SELECT *
    FROM jsonb_to_recordset(p_input->'vehiculos_json') AS x(
      origen_aseguradora text,
      id_original        bigint,
      marca              text,
      modelo             text,
      anio               int,
      transmision        text,
      version_original   text,
      version_limpia     text,
      fecha_procesamiento timestamptz,
      hash_comercial     text
    )
  LOOP
    BEGIN
      v_hash := v_rec.hash_comercial;
      v_aseg := upper(coalesce(v_rec.origen_aseguradora, ''));
      v_ver_canonica := trim(v_rec.version_limpia);
      v_b_tokens := public.tokenize_version(v_ver_canonica);

      -- construir payload de disponibilidad
      payload := jsonb_build_object(
        'origen', true,
        'disponible', true,
        'aseguradora', v_aseg,
        'id_original', v_rec.id_original,
        'metodo_match', 'inclusion_index',
        'confianza_score', 1,              -- porque Inclusion = 1 obligatoria
        'version_original', coalesce(v_rec.version_original, v_ver_canonica),
        'fecha_actualizacion', to_char(v_now, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      );

      -- Buscar todas las A con mismo hash donde Inclusion(A,B) = 1
      matched_ids := ARRAY(
        SELECT a.id
        FROM public.catalogo_homologado a
        WHERE a.hash_comercial = v_hash
          AND (
            -- Si A no tiene tokens precargados, derive on-the-fly
            public.inclusion_coverage(
              COALESCE(a.version_tokens_array, public.tokenize_version(a.version)),
              v_b_tokens
            ) = 1
          )
      );

      IF array_length(matched_ids, 1) IS NOT NULL AND array_length(matched_ids, 1) > 0 THEN
        -- Actualizar disponibilidad en TODAS las A coincidentes
        UPDATE public.catalogo_homologado a
        SET
          disponibilidad = public.merge_disponibilidad(a.disponibilidad, v_aseg, payload),
          fecha_actualizacion = v_now
        WHERE a.id = ANY(matched_ids);

        v_upd_ids := v_upd_ids || matched_ids;

      ELSE
        -- No hubo A con cobertura 1: insertar nueva fila (new_entry)
        INSERT INTO public.catalogo_homologado(
          hash_comercial, marca, modelo, anio, transmision,
          version, disponibilidad, fecha_creacion, fecha_actualizacion,
          version_tokens, version_tokens_array
        )
        VALUES (
          v_hash, v_rec.marca, v_rec.modelo, v_rec.anio, v_rec.transmision,
          v_ver_canonica,
          jsonb_build_object(v_aseg, jsonb_build_object(
            'origen', true,
            'disponible', true,
            'aseguradora', v_aseg,
            'id_original', v_rec.id_original,
            'metodo_match', 'new_entry',
            'confianza_score', 1,
            'version_original', coalesce(v_rec.version_original, v_ver_canonica),
            'fecha_actualizacion', to_char(v_now, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          )),
          v_now, v_now,
          to_tsvector('simple', array_to_string(v_b_tokens, ' ')),
          v_b_tokens
        )
        ON CONFLICT (hash_comercial, version)
        DO UPDATE SET
          disponibilidad = public.merge_disponibilidad(
            public.catalogo_homologado.disponibilidad,
            EXCLUDED.disponibilidad ->> (SELECT key FROM jsonb_each_text(EXCLUDED.disponibilidad) LIMIT 1),
            (SELECT value FROM jsonb_each(EXCLUDED.disponibilidad) LIMIT 1)
          ),
          fecha_actualizacion = v_now
        RETURNING id
        INTO r_a;

        IF r_a.id IS NOT NULL THEN
          v_ins_ids := v_ins_ids || r_a.id;
        ELSE
          -- Si cayó en el ON CONFLICT UPDATE y no retornó ID (por sintaxis),
          -- registrar como actualización sin ID específico.
          v_nochange_ids := v_nochange_ids;
        END IF;
      END IF;

    EXCEPTION WHEN others THEN
      v_errors := v_errors || jsonb_build_array(
        jsonb_build_object(
          'id_original', v_rec.id_original,
          'hash_comercial', v_hash,
          'error', SQLERRM
        )
      );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'insertados', coalesce(array_length(v_ins_ids,1),0),
    'actualizados', coalesce(array_length(v_upd_ids,1),0),
    'sin_cambios', coalesce(array_length(v_nochange_ids,1),0),
    'ids_insertados', coalesce(v_ins_ids, ARRAY[]::bigint[]),
    'ids_actualizados', coalesce(v_upd_ids, ARRAY[]::bigint[]),
    'errores', v_errors
  );
END;
$$;


ALTER FUNCTION "public"."procesar_batch_vehiculos"("p_input" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."procesar_batch_vehiculos_modo"("records" "jsonb", "batch_mode" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Por ahora solo redirige a la función principal
    -- Puedes agregar lógica específica del modo aquí si lo necesitas
    RETURN procesar_batch_vehiculos(records);
END;
$$;


ALTER FUNCTION "public"."procesar_batch_vehiculos_modo"("records" "jsonb", "batch_mode" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."procesar_bloque_completo"("p_hash_comercial" "text", "p_records" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    rec jsonb;
    existing_versions jsonb;
    similarity_matrix jsonb := '[]'::jsonb;
    clusters jsonb;
    result jsonb;
    i int;
    j int;
    sim numeric;
    merged_count int := 0;
    created_count int := 0;
BEGIN
    -- Limpiar tabla temporal
    DELETE FROM temp_block_processing WHERE block_id = p_hash_comercial;
    
    -- 1. Cargar registros existentes del bloque
    INSERT INTO temp_block_processing (block_id, record_id, version, version_tokens, aseguradora, metadata)
    SELECT 
        p_hash_comercial,
        id,
        version,
        version_tokens_array,
        jsonb_object_keys(disponibilidad),
        disponibilidad->jsonb_object_keys(disponibilidad)
    FROM catalogo_homologado
    WHERE hash_comercial = p_hash_comercial;
    
    -- 2. Agregar nuevos registros
    i := (SELECT COALESCE(MAX(record_id), 0) FROM temp_block_processing) + 1000;
    FOR rec IN SELECT * FROM jsonb_array_elements(p_records)
    LOOP
        INSERT INTO temp_block_processing (block_id, record_id, version, version_tokens, aseguradora, metadata)
        VALUES (
            p_hash_comercial,
            i,
            rec->>'version_limpia',
            tokenize_vehicle_version(rec->>'version_limpia'),
            rec->>'origen_aseguradora',
            jsonb_build_object(
                'id_original', rec->>'id_original',
                'version_original', rec->>'version_original',
                'marca', rec->>'marca',
                'modelo', rec->>'modelo',
                'anio', rec->>'anio',
                'transmision', rec->>'transmision'
            )
        );
        i := i + 1;
    END LOOP;
    
    -- 3. Construir matriz de similitud
    similarity_matrix := construir_matriz_similitud(p_hash_comercial);
    
    -- 4. Aplicar clustering jerárquico
    clusters := aplicar_clustering_jerarquico(similarity_matrix, 0.35);
    
    -- 5. Consolidar clusters en la tabla principal
    result := consolidar_clusters(p_hash_comercial, clusters);
    
    RETURN result;
END;
$$;


ALTER FUNCTION "public"."procesar_bloque_completo"("p_hash_comercial" "text", "p_records" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin new.updated_at = now(); return new; end $$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_homologation_matching"() RETURNS TABLE("test_case" "text", "version1" "text", "version2" "text", "string_similarity" numeric, "token_similarity" numeric, "combined_similarity" numeric, "would_match_old" boolean, "would_match_new" boolean, "improvement" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH test_cases AS (
        SELECT 
            'ACURA MDX SH' as test_case,
            'SH AWD SUV 290HP 3.5L 6CIL 5PUERTAS 7OCUP' as v1,
            'SH 6CIL 3.5L AWD R20 5PUERTAS 7OCUP' as v2
        UNION ALL
        SELECT 
            'SEAT IBIZA STYLE',
            'STYLE PLUS P/E R16 COUPE 105HP 2.0L 4CIL 2PUERTAS 5OCUP',
            'STYLE PLUS COUPE 4CIL 2.0L P/E 2PUERTAS 5OCUP'
        UNION ALL
        SELECT 
            'BMW X3 XDRIVE',
            'XDRIVE 30IA OUTDOOR ED SUV 252HP 2.0L 4CIL 5PUERTAS 5OCUP',
            'XDRIVE 30IA OUTDOOR ED 4CIL 2.0T 5PUERTAS 5OCUP'
    ),
    analysis AS (
        SELECT 
            test_case,
            v1,
            v2,
            round(similarity(v1, v2)::numeric, 3) as str_sim,
            round((
                SELECT COUNT(*)::numeric / GREATEST(
                    array_length(tokenize_version(v1), 1),
                    array_length(tokenize_version(v2), 1),
                    1
                )
                FROM unnest(tokenize_version(v1)) t1
                WHERE t1 = ANY(tokenize_version(v2))
            ), 3) as tok_sim
        FROM test_cases
    )
    SELECT 
        a.test_case,
        a.v1 as version1,
        a.v2 as version2,
        a.str_sim as string_similarity,
        a.tok_sim as token_similarity,
        round(0.4 * a.str_sim + 0.6 * a.tok_sim, 3) as combined_similarity,
        -- Old logic: token sim > 0.20 for cross-insurer
        (a.tok_sim > 0.20) as would_match_old,
        -- New logic: combined sim > 0.65 for cross-insurer
        (0.4 * a.str_sim + 0.6 * a.tok_sim > 0.65) as would_match_new,
        CASE 
            WHEN (0.4 * a.str_sim + 0.6 * a.tok_sim > 0.65) AND NOT (a.tok_sim > 0.20) THEN 'Now matches!'
            WHEN NOT (0.4 * a.str_sim + 0.6 * a.tok_sim > 0.65) AND (a.tok_sim > 0.20) THEN 'No longer matches'
            WHEN (0.4 * a.str_sim + 0.6 * a.tok_sim > 0.65) AND (a.tok_sim > 0.20) THEN 'Still matches'
            ELSE 'Still separate'
        END as improvement
    FROM analysis a;
END;
$$;


ALTER FUNCTION "public"."test_homologation_matching"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_vehicle_matching"("qualitas_version" "text", "zurich_version" "text") RETURNS TABLE("qualitas_tokens" "text"[], "zurich_tokens" "text"[], "common_tokens" "text"[], "token_overlap" integer, "min_tokens" integer, "max_tokens" integer, "subset_ratio" numeric, "full_ratio" numeric, "final_score" numeric, "would_match" boolean)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    q_tokens text[];
    z_tokens text[];
    common text[];
    overlap int;
    min_t int;
    max_t int;
    subset_r numeric;
    full_r numeric;
    final_s numeric;
BEGIN
    q_tokens := tokenize_version(qualitas_version);
    z_tokens := tokenize_version(zurich_version);
    
    -- Get common tokens
    SELECT array_agg(DISTINCT t ORDER BY t)
    INTO common
    FROM unnest(q_tokens) t
    WHERE t = ANY(z_tokens);
    
    overlap := COALESCE(array_length(common, 1), 0);
    min_t := LEAST(array_length(q_tokens, 1), array_length(z_tokens, 1));
    max_t := GREATEST(array_length(q_tokens, 1), array_length(z_tokens, 1));
    
    IF min_t > 0 THEN
        subset_r := overlap::numeric / min_t;
    ELSE
        subset_r := 0;
    END IF;
    
    full_r := overlap::numeric / max_t;
    
    -- Calculate final score
    IF min_t < max_t * 0.5 THEN
        final_s := 0.7 * subset_r + 0.3 * full_r;
    ELSE
        final_s := 0.4 * subset_r + 0.6 * full_r;
    END IF;
    
    -- Add string similarity
    final_s := 0.8 * final_s + 0.2 * similarity(UPPER(qualitas_version), UPPER(zurich_version));
    
    RETURN QUERY SELECT 
        q_tokens,
        z_tokens,
        common,
        overlap,
        min_t,
        max_t,
        ROUND(subset_r, 3),
        ROUND(full_r, 3),
        ROUND(final_s, 3),
        final_s >= 0.45;
END;
$$;


ALTER FUNCTION "public"."test_vehicle_matching"("qualitas_version" "text", "zurich_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_version_match"("version1" "text", "version2" "text", "same_insurer" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    tokens1 text[];
    tokens2 text[];
    result jsonb;
BEGIN
    tokens1 := tokenize_version(version1);
    tokens2 := tokenize_version(version2);
    
    result := calculate_vehicle_match_score(tokens1, tokens2, same_insurer);
    
    -- Add token details for debugging
    result := result || jsonb_build_object(
        'version1_tokens', tokens1,
        'version2_tokens', tokens2,
        'shared_tokens', (
            SELECT array_agg(DISTINCT token ORDER BY token)
            FROM (
                SELECT unnest(tokens1) AS token
                INTERSECT
                SELECT unnest(tokens2)
            ) t
        ),
        'unique_to_version1', (
            SELECT array_agg(DISTINCT token ORDER BY token)
            FROM (
                SELECT unnest(tokens1) AS token
                EXCEPT
                SELECT unnest(tokens2)
            ) t
        ),
        'unique_to_version2', (
            SELECT array_agg(DISTINCT token ORDER BY token)
            FROM (
                SELECT unnest(tokens2) AS token
                EXCEPT
                SELECT unnest(tokens1)
            ) t
        )
    );
    
    RETURN result;
END;
$$;


ALTER FUNCTION "public"."test_version_match"("version1" "text", "version2" "text", "same_insurer" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."test_version_matching"("version1" "text", "version2" "text") RETURNS TABLE("version1_input" "text", "version2_input" "text", "tokens1" "text"[], "tokens2" "text"[], "token_overlap" integer, "token_similarity" numeric, "string_similarity" numeric, "combined_score" numeric, "would_match" boolean)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    t1 text[];
    t2 text[];
    overlap int;
BEGIN
    t1 := tokenize_version_enhanced(version1);
    t2 := tokenize_version_enhanced(version2);
    
    SELECT COUNT(DISTINCT x)
    INTO overlap
    FROM unnest(t1) x
    WHERE x = ANY(t2);
    
    RETURN QUERY
    SELECT 
        version1,
        version2,
        t1,
        t2,
        overlap,
        ROUND((overlap::numeric / NULLIF(GREATEST(array_length(t1, 1), array_length(t2, 1)), 0))::numeric, 3),
        ROUND(similarity(UPPER(version1), UPPER(version2))::numeric, 3),
        ROUND(calculate_version_similarity(t1, t2, version1, version2)::numeric, 3),
        calculate_version_similarity(t1, t2, version1, version2) >= 0.50;
END;
$$;


ALTER FUNCTION "public"."test_version_matching"("version1" "text", "version2" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tokenize_vehicle_version"("version_text" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    tokens text[];
    normalized_text text;
    final_tokens text[] := ARRAY[]::text[];
    token text;
BEGIN
    IF version_text IS NULL OR trim(version_text) = '' THEN
        RETURN ARRAY[]::text[];
    END IF;

    normalized_text := UPPER(trim(version_text));
    
    -- Remover acentos
    normalized_text := translate(
        normalized_text,
        'ÁÉÍÓÚÄËÏÖÜÑÀÈÌÒÙ',
        'AEIOUAEIOUNAEIOU'
    );
    
    -- Normalizar STD/ESTANDAR
    normalized_text := regexp_replace(normalized_text, '\b(STD|ESTANDAR|STANDARD)\b', 'STD', 'g');
    
    -- Normalizar litros y HP
    normalized_text := regexp_replace(normalized_text, '(\d+)\.(\d+)\s*L', '\1.\2L', 'g');
    normalized_text := regexp_replace(normalized_text, '(\d+)\s+L\b', '\1.0L', 'g');
    normalized_text := regexp_replace(normalized_text, '(\d+)\s*HP', '\1HP', 'g');
    
    -- Limpiar caracteres especiales
    normalized_text := regexp_replace(normalized_text, '[^A-Z0-9\.\-]+', ' ', 'g');
    normalized_text := regexp_replace(normalized_text, '\s+', ' ', 'g');
    normalized_text := TRIM(normalized_text);
    
    -- Tokenizar
    tokens := string_to_array(normalized_text, ' ');
    
    -- Filtrar tokens problemáticos y muy cortos
    FOREACH token IN ARRAY tokens
    LOOP
        -- Excluir tokens problemáticos
        IF token IN ('4', '5', '6', '7', '8', 'L', 'P', 'A', 'B', 'C', 'D', 'E') THEN
            CONTINUE;
        END IF;
        
        -- Excluir tokens muy cortos excepto importantes
        IF length(token) < 2 AND token NOT IN ('V6', 'V8', 'R', 'S') THEN
            CONTINUE;
        END IF;
        
        -- Excluir stop words
        IF token IN ('DE', 'LA', 'EL', 'CON', 'SIN', 'PARA', 'DIS', 'IMP', 'IMO') THEN
            CONTINUE;
        END IF;
        
        final_tokens := array_append(final_tokens, token);
    END LOOP;
    
    -- Retornar tokens únicos ordenados
    SELECT array_agg(DISTINCT unnest ORDER BY unnest)
    INTO final_tokens
    FROM unnest(final_tokens);
    
    RETURN COALESCE(final_tokens, ARRAY[]::text[]);
END;
$$;


ALTER FUNCTION "public"."tokenize_vehicle_version"("version_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tokenize_version"("p_version" "text") RETURNS "text"[]
    LANGUAGE "sql" IMMUTABLE
    AS $$
  WITH base AS (
    SELECT regexp_replace(upper(coalesce(p_version,'')), '\s+', ' ', 'g') AS s
  ),
  parts AS (
    SELECT unnest(string_to_array(trim(s), ' ')) AS tok FROM base
  ),
  cleaned AS (
    SELECT tok FROM parts WHERE length(tok) > 0
  ),
  dedup AS (
    SELECT tok, row_number() OVER () AS rn
    FROM (
      SELECT DISTINCT ON (tok) tok FROM cleaned
    ) q
  )
  SELECT coalesce(array_agg(tok ORDER BY rn), ARRAY[]::text[])
  FROM dedup;
$$;


ALTER FUNCTION "public"."tokenize_version"("p_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tokenize_version_enhanced"("version_text" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE PARALLEL SAFE
    AS $_$
DECLARE
    normalized text;
    tokens text[];
BEGIN
    IF version_text IS NULL OR version_text = '' THEN
        RETURN ARRAY[]::text[];
    END IF;
    
    -- Normalize text
    normalized := lower(version_text);
    
    -- Preserve important patterns
    normalized := regexp_replace(normalized, '(\d+)\.(\d+)l\b', '\1_\2l', 'g');  -- 3.5L -> 3_5l
    normalized := regexp_replace(normalized, '(\d+)\.(\d+)\s*l\b', '\1_\2l', 'gi'); -- 3.5 L -> 3_5l
    normalized := regexp_replace(normalized, '\b(\d+)hp\b', 'hp\1', 'gi');  -- 290HP -> hp290
    normalized := regexp_replace(normalized, '\b(\d+)cv\b', 'hp\1', 'gi');  -- 290CV -> hp290 (Spanish)
    normalized := regexp_replace(normalized, '\bcil\b', 'cyl', 'gi');        -- CIL -> cyl (standardize)
    normalized := regexp_replace(normalized, '\bpuertas\b', 'door', 'gi');   -- PUERTAS -> door
    normalized := regexp_replace(normalized, '\bocup\b', 'seat', 'gi');      -- OCUP -> seat
    
    -- Standardize common terms
    normalized := regexp_replace(normalized, '\bpick[- ]?up\b', 'pickup', 'gi');
    normalized := regexp_replace(normalized, '\b4x4\b', 'awd', 'gi');
    normalized := regexp_replace(normalized, '\b4x2\b', 'rwd', 'gi');
    normalized := regexp_replace(normalized, '\ball wheel drive\b', 'awd', 'gi');
    normalized := regexp_replace(normalized, '\baut\b', 'auto', 'gi');
    normalized := regexp_replace(normalized, '\bautomatica?\b', 'auto', 'gi');
    normalized := regexp_replace(normalized, '\bmanual\b', 'man', 'gi');
    normalized := regexp_replace(normalized, '\bestandar\b', 'man', 'gi');
    
    -- Remove noise words and special characters
    normalized := regexp_replace(normalized, '\b(aa|ee|cd|ba|qc|vp|abs|a/c|a/a)\b', ' ', 'gi');
    normalized := regexp_replace(normalized, '[^a-z0-9_]+', ' ', 'g');
    normalized := regexp_replace(normalized, '\s+', ' ', 'g');
    
    -- Extract meaningful tokens
    SELECT array_agg(DISTINCT token ORDER BY token)
    INTO tokens
    FROM (
        SELECT unnest(string_to_array(trim(normalized), ' ')) AS token
    ) t
    WHERE 
        length(token) > 1 
        OR token ~ '^\d+$'  -- Keep single digit numbers
        OR token IN ('a', 's', 'r', 'l', 'x', 'z');  -- Keep meaningful single letters (trim levels)
    
    RETURN COALESCE(tokens, ARRAY[]::text[]);
END;
$_$;


ALTER FUNCTION "public"."tokenize_version_enhanced"("version_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tokenize_version_ordered"("version_text" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    clean_text text;
    tokens text[];
BEGIN
    IF version_text IS NULL OR version_text = '' THEN
        RETURN ARRAY[]::text[];
    END IF;
    
    clean_text := lower(version_text);
    clean_text := regexp_replace(clean_text, '[^a-z0-9 ]', ' ', 'g');
    clean_text := regexp_replace(clean_text, '\s+', ' ', 'g');
    clean_text := trim(clean_text);
    
    -- NO ORDENAR - MANTENER ORDEN ORIGINAL
    tokens := string_to_array(clean_text, ' ');
    
    -- Filtrar vacíos pero MANTENER ORDEN
    SELECT array_agg(token)
    INTO tokens
    FROM (
        SELECT token
        FROM unnest(tokens) AS token
        WHERE token IS NOT NULL AND token != '' AND length(token) > 0
    ) t;
    
    RETURN COALESCE(tokens, ARRAY[]::text[]);
END;
$$;


ALTER FUNCTION "public"."tokenize_version_ordered"("version_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tokenize_version_proper"("version_text" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    clean_text text;
    tokens text[];
BEGIN
    IF version_text IS NULL OR version_text = '' THEN
        RETURN ARRAY[]::text[];
    END IF;
    
    -- Convertir a minúsculas y limpiar
    clean_text := lower(version_text);
    
    -- Normalizar elementos comunes ANTES de tokenizar
    clean_text := regexp_replace(clean_text, '\s+', ' ', 'g'); -- múltiples espacios a uno
    clean_text := regexp_replace(clean_text, '[,\.]', ' ', 'g'); -- comas y puntos a espacios
    clean_text := regexp_replace(clean_text, '[^a-z0-9 ]', '', 'g'); -- solo alfanuméricos
    
    -- Crear array de tokens NO VACÍOS
    SELECT array_agg(DISTINCT token ORDER BY token)
    INTO tokens
    FROM (
        SELECT unnest(string_to_array(clean_text, ' ')) AS token
    ) t
    WHERE token IS NOT NULL 
      AND token != ''
      AND length(token) > 0;
    
    RETURN COALESCE(tokens, ARRAY[]::text[]);
END;
$$;


ALTER FUNCTION "public"."tokenize_version_proper"("version_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."tokenize_version_smart"("version_text" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    tokens text[];
    noise_tokens text[] := ARRAY['aa','ee','cd','ba','qc','vp','abs','ac','cc'];
BEGIN
    IF version_text IS NULL OR version_text = '' THEN
        RETURN ARRAY[]::text[];
    END IF;
    
    -- Normalize BEFORE tokenizing
    version_text := lower(version_text);
    -- Critical normalizations
    version_text := regexp_replace(version_text, '\bl4\b', '4cil', 'g');
    version_text := regexp_replace(version_text, '\bquattro\b', 'awd', 'g');
    version_text := regexp_replace(version_text, '\b(\d+)\.0([lt])\b', '\1\2', 'g');
    
    -- Tokenize
    SELECT array_agg(DISTINCT token ORDER BY token)
    INTO tokens
    FROM (
        SELECT unnest(
            string_to_array(
                regexp_replace(version_text, '[^a-z0-9]+', ' ', 'g'),
                ' '
            )
        ) AS token
    ) t
    WHERE length(token) > 1 
      AND NOT (token = ANY(noise_tokens));
    
    RETURN COALESCE(tokens, ARRAY[]::text[]);
END;
$$;


ALTER FUNCTION "public"."tokenize_version_smart"("version_text" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_catalogo_batch"("updates" "jsonb") RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  updated_count integer := 0;
  record jsonb;
BEGIN
  FOR record IN SELECT * FROM jsonb_array_elements(updates)
  LOOP
    UPDATE public.catalogo_homologado
    SET aseguradoras_disponibles = record->>'aseguradoras_disponibles'::jsonb
    WHERE hash_tecnico = record->>'hash_tecnico';
    
    updated_count := updated_count + 1;
  END LOOP;
  
  RETURN updated_count;
END;
$$;


ALTER FUNCTION "public"."update_catalogo_batch"("updates" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_fecha_actualizacion"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.fecha_actualizacion = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_fecha_actualizacion"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.fecha_actualizacion = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_timestamp"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_tokens_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.version_tokens := to_tsvector('simple', COALESCE(NEW.version, ''));
    NEW.version_tokens_array := tokenize_version(COALESCE(NEW.version, ''));
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_tokens_trigger"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_vehicles_batch"("updates" "jsonb"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    update_record jsonb;
    updated_count integer := 0;
    error_count integer := 0;
BEGIN
    FOREACH update_record IN ARRAY updates
    LOOP
        BEGIN
            UPDATE vehiculos_homologados
            SET 
                aseguradoras_disponibles = update_record->'aseguradoras_disponibles',
                marca = update_record->>'marca',
                modelo = update_record->>'modelo',
                año = (update_record->>'año')::integer,
                version = update_record->>'version',
                version_corta = update_record->>'version_corta',
                transmision_codigo = (update_record->>'transmision_codigo')::integer,
                transmision_descripcion = update_record->>'transmision_descripcion',
                marca_normalizada = update_record->>'marca_normalizada',
                modelo_normalizado = update_record->>'modelo_normalizado',
                version_normalizada = update_record->>'version_normalizada',
                fecha_actualizacion = NOW(),
                origen_carga = update_record->>'origen_carga'
            WHERE hash_unico = update_record->>'hash_unico';
            
            updated_count := updated_count + 1;
        EXCEPTION WHEN OTHERS THEN
            error_count := error_count + 1;
        END;
    END LOOP;
    
    RETURN jsonb_build_object(
        'updated', updated_count,
        'errors', error_count,
        'total', array_length(updates, 1)
    );
END;
$$;


ALTER FUNCTION "public"."update_vehicles_batch"("updates" "jsonb"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."weighted_token_similarity"("tokens1" "text"[], "tokens2" "text"[]) RETURNS numeric
    LANGUAGE "plpgsql" IMMUTABLE
    AS $_$
DECLARE
    intersection_weight numeric := 0;
    union_weight numeric := 0;
    token text;
    weight numeric;
    token_weights jsonb := '{
        "motor": 3.0,
        "displacement": 2.5,
        "power": 2.0,
        "doors": 1.8,
        "traction": 1.5,
        "transmission": 1.2,
        "default": 1.0
    }'::jsonb;
BEGIN
    IF tokens1 IS NULL OR tokens2 IS NULL OR 
       array_length(tokens1, 1) IS NULL OR array_length(tokens2, 1) IS NULL THEN
        RETURN 0;
    END IF;
    
    -- Calcular peso de intersección
    FOR token IN SELECT unnest(tokens1) INTERSECT SELECT unnest(tokens2)
    LOOP
        -- Determinar peso del token
        weight := 1.0; -- peso por defecto
        
        -- Configuración de motor (V6, L4, etc.)
        IF token ~ '^[VLIH]\d+$' THEN
            weight := (token_weights->>'motor')::numeric;
        -- Desplazamiento (1.8L, 2.0L, etc.)
        ELSIF token ~ '^\d+\.?\d*L$' THEN
            weight := (token_weights->>'displacement')::numeric;
        -- Potencia (150HP, etc.)
        ELSIF token ~ '^\d+HP$' THEN
            weight := (token_weights->>'power')::numeric;
        -- Puertas (4P, 5P, etc.)
        ELSIF token ~ '^\d+P$' THEN
            weight := (token_weights->>'doors')::numeric;
        -- Tracción
        ELSIF token IN ('4WD', '2WD', 'AWD', 'FWD') THEN
            weight := (token_weights->>'traction')::numeric;
        -- Transmisión
        ELSIF token IN ('AUTO', 'MANUAL', 'CVT') THEN
            weight := (token_weights->>'transmission')::numeric;
        END IF;
        
        intersection_weight := intersection_weight + weight;
    END LOOP;
    
    -- Calcular peso de unión
    FOR token IN SELECT unnest(tokens1) UNION SELECT unnest(tokens2)
    LOOP
        weight := 1.0; -- peso por defecto
        
        IF token ~ '^[VLIH]\d+$' THEN
            weight := (token_weights->>'motor')::numeric;
        ELSIF token ~ '^\d+\.?\d*L$' THEN
            weight := (token_weights->>'displacement')::numeric;
        ELSIF token ~ '^\d+HP$' THEN
            weight := (token_weights->>'power')::numeric;
        ELSIF token ~ '^\d+P$' THEN
            weight := (token_weights->>'doors')::numeric;
        ELSIF token IN ('4WD', '2WD', 'AWD', 'FWD') THEN
            weight := (token_weights->>'traction')::numeric;
        ELSIF token IN ('AUTO', 'MANUAL', 'CVT') THEN
            weight := (token_weights->>'transmission')::numeric;
        END IF;
        
        union_weight := union_weight + weight;
    END LOOP;
    
    IF union_weight = 0 THEN
        RETURN 0;
    END IF;
    
    RETURN ROUND(intersection_weight / union_weight, 3);
END;
$_$;


ALTER FUNCTION "public"."weighted_token_similarity"("tokens1" "text"[], "tokens2" "text"[]) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."aseguradoras_metadata" (
    "id" integer NOT NULL,
    "insurer_code" character varying(50) NOT NULL,
    "insurer_name" character varying(255) NOT NULL,
    "aliases" "text"[],
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "id_api" integer
);


ALTER TABLE "public"."aseguradoras_metadata" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."aseguradoras_metadata_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."aseguradoras_metadata_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."aseguradoras_metadata_id_seq" OWNED BY "public"."aseguradoras_metadata"."id";



CREATE TABLE IF NOT EXISTS "public"."catalogo_homologado" (
    "id" bigint NOT NULL,
    "hash_comercial" character varying(64) NOT NULL,
    "marca" character varying(100) NOT NULL,
    "modelo" character varying(150) NOT NULL,
    "anio" integer NOT NULL,
    "transmision" character varying(20),
    "version" character varying(200),
    "disponibilidad" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "fecha_creacion" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fecha_actualizacion" timestamp with time zone DEFAULT "now"() NOT NULL,
    "version_tokens" "tsvector",
    "version_tokens_array" "text"[],
    "version_vector" "public"."vector"(1536),
    CONSTRAINT "catalogo_homologado_anio_check" CHECK ((("anio" >= 2000) AND ("anio" <= 2030)))
);


ALTER TABLE "public"."catalogo_homologado" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."catalogo_homologado_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."catalogo_homologado_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."catalogo_homologado_id_seq" OWNED BY "public"."catalogo_homologado"."id";



CREATE TABLE IF NOT EXISTS "public"."cotizaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_usuario" "uuid" NOT NULL,
    "id_sesion" "uuid" NOT NULL,
    "marca" character varying,
    "modelo" character varying,
    "anio" character varying,
    "tipo_transmision" character varying,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"(),
    "version" character varying
);


ALTER TABLE "public"."cotizaciones" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cotizaciones_cache" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id_usuario" "uuid",
    "id_sesion" "uuid",
    "marca" character varying,
    "modelo" character varying,
    "anio" character varying,
    "version" character varying,
    "transmision" character varying,
    "codigo_postal" character varying,
    "json_response" "jsonb",
    "created_at" timestamp without time zone,
    "id_vehiculos_homologados" bigint,
    "json_coberturas" "jsonb"
);


ALTER TABLE "public"."cotizaciones_cache" OWNER TO "postgres";


COMMENT ON TABLE "public"."cotizaciones_cache" IS 'Almacenar cotizaciones';



CREATE TABLE IF NOT EXISTS "public"."historial_conversacion" (
    "id" integer NOT NULL,
    "session_id" "uuid" NOT NULL,
    "mensaje" "jsonb",
    "remitente" character varying(5),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."historial_conversacion" OWNER TO "postgres";


ALTER TABLE "public"."historial_conversacion" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."historial_conversacion_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."knowledge_base_chunks" (
    "id" bigint NOT NULL,
    "content" "text" NOT NULL,
    "embedding" "public"."vector"(1536),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb"
);


ALTER TABLE "public"."knowledge_base_chunks" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."knowledge_base_chunks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."knowledge_base_chunks_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."knowledge_base_chunks_id_seq" OWNED BY "public"."knowledge_base_chunks"."id";



CREATE TABLE IF NOT EXISTS "public"."quote_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "session_id" "uuid",
    "aseguradora" character varying(100),
    "cotizacion" "jsonb",
    "respuesta_raw" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."quote_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "expires_at" timestamp without time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "available" boolean DEFAULT true
);


ALTER TABLE "public"."sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."support_tickets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "session_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "channel" "text" DEFAULT 'telegram'::"text",
    "priority" "text" DEFAULT 'normal'::"text",
    "reason" "text",
    "summary" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."support_tickets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_data" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" character varying,
    "telefono" character varying NOT NULL,
    "correo_electronico" character varying,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fecha_nacimiento" "date",
    "genero" character varying,
    "codigo_postal" character varying,
    "crm_id" "text",
    "agentEmail" "text",
    "agentNumber" "text"
);


ALTER TABLE "public"."user_data" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_homologation_stats" AS
 WITH "insurer_stats" AS (
         SELECT "key"."key" AS "insurer",
            "count"(*) AS "vehicle_count"
           FROM "public"."catalogo_homologado",
            LATERAL "jsonb_object_keys"("catalogo_homologado"."disponibilidad") "key"("key")
          GROUP BY "key"."key"
        ), "cross_insurer" AS (
         SELECT "catalogo_homologado"."hash_comercial",
            "jsonb_object_keys"("catalogo_homologado"."disponibilidad") AS "insurer",
            "count"(*) OVER (PARTITION BY "catalogo_homologado"."hash_comercial") AS "insurers_per_vehicle"
           FROM "public"."catalogo_homologado"
        )
 SELECT "i"."insurer",
    "i"."vehicle_count",
    "count"(DISTINCT "c"."hash_comercial") FILTER (WHERE ("c"."insurers_per_vehicle" > 1)) AS "cross_matched",
    "round"(((100.0 * ("count"(DISTINCT "c"."hash_comercial") FILTER (WHERE ("c"."insurers_per_vehicle" > 1)))::numeric) / (NULLIF("count"(DISTINCT "c"."hash_comercial"), 0))::numeric), 2) AS "match_rate_pct"
   FROM ("insurer_stats" "i"
     LEFT JOIN "cross_insurer" "c" ON (("c"."insurer" = "i"."insurer")))
  GROUP BY "i"."insurer", "i"."vehicle_count"
  ORDER BY "i"."vehicle_count" DESC;


ALTER VIEW "public"."v_homologation_stats" OWNER TO "postgres";


ALTER TABLE ONLY "public"."aseguradoras_metadata" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."aseguradoras_metadata_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."catalogo_homologado" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."catalogo_homologado_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."knowledge_base_chunks" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."knowledge_base_chunks_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."aseguradoras_metadata"
    ADD CONSTRAINT "aseguradoras_metadata_insurer_code_key" UNIQUE ("insurer_code");



ALTER TABLE ONLY "public"."aseguradoras_metadata"
    ADD CONSTRAINT "aseguradoras_metadata_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."catalogo_homologado"
    ADD CONSTRAINT "catalogo_homologado_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cotizaciones_cache"
    ADD CONSTRAINT "cotizaciones_cache_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."historial_conversacion"
    ADD CONSTRAINT "historial_conversacion_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."knowledge_base_chunks"
    ADD CONSTRAINT "knowledge_base_chunks_pkey1" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quote_history"
    ADD CONSTRAINT "quote_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."support_tickets"
    ADD CONSTRAINT "support_tickets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."catalogo_homologado"
    ADD CONSTRAINT "unique_hash_version" UNIQUE ("hash_comercial", "version");



ALTER TABLE ONLY "public"."user_data"
    ADD CONSTRAINT "user_data_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cotizaciones"
    ADD CONSTRAINT "vehiculos_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_catalogo_disponibilidad" ON "public"."catalogo_homologado" USING "gin" ("disponibilidad");



CREATE INDEX "idx_catalogo_disponibilidad_gin" ON "public"."catalogo_homologado" USING "gin" ("disponibilidad");



CREATE INDEX "idx_catalogo_fecha_actualizacion" ON "public"."catalogo_homologado" USING "btree" ("fecha_actualizacion" DESC);



CREATE INDEX "idx_catalogo_hash_comercial" ON "public"."catalogo_homologado" USING "btree" ("hash_comercial");



CREATE INDEX "idx_catalogo_hash_version" ON "public"."catalogo_homologado" USING "btree" ("hash_comercial", "version");



CREATE INDEX "idx_catalogo_homologado_disponibilidad" ON "public"."catalogo_homologado" USING "gin" ("disponibilidad");



CREATE INDEX "idx_catalogo_homologado_hash" ON "public"."catalogo_homologado" USING "btree" ("hash_comercial");



CREATE INDEX "idx_catalogo_homologado_tokens" ON "public"."catalogo_homologado" USING "gin" ("version_tokens_array");



CREATE INDEX "idx_catalogo_homologado_tokens_gin" ON "public"."catalogo_homologado" USING "gin" ("version_tokens_array");



CREATE INDEX "idx_catalogo_homologado_version" ON "public"."catalogo_homologado" USING "btree" ("version");



CREATE INDEX "idx_catalogo_homologado_version_trgm" ON "public"."catalogo_homologado" USING "gin" ("version" "public"."gin_trgm_ops");



CREATE INDEX "idx_catalogo_version" ON "public"."catalogo_homologado" USING "btree" ("version");



CREATE INDEX "idx_catalogo_version_tokens_array" ON "public"."catalogo_homologado" USING "gin" ("version_tokens_array");



CREATE INDEX "idx_catalogo_version_tokens_gin" ON "public"."catalogo_homologado" USING "gin" ("version_tokens_array");



CREATE INDEX "idx_catalogo_version_trgm" ON "public"."catalogo_homologado" USING "gin" ("version" "public"."gin_trgm_ops");



CREATE INDEX "idx_catalogo_version_vector_cos_hnsw" ON "public"."catalogo_homologado" USING "hnsw" ("version_vector" "public"."vector_cosine_ops");



CREATE INDEX "idx_disponibilidad_gin" ON "public"."catalogo_homologado" USING "gin" ("disponibilidad");



CREATE INDEX "idx_fecha_actualizacion" ON "public"."catalogo_homologado" USING "btree" ("fecha_actualizacion" DESC);



CREATE INDEX "idx_hash_comercial" ON "public"."catalogo_homologado" USING "btree" ("hash_comercial");



CREATE INDEX "idx_hash_comercial_btree" ON "public"."catalogo_homologado" USING "btree" ("hash_comercial");



CREATE INDEX "idx_hash_comercial_version" ON "public"."catalogo_homologado" USING "btree" ("hash_comercial", "version");



CREATE INDEX "idx_hash_version" ON "public"."catalogo_homologado" USING "btree" ("hash_comercial", "version");



CREATE INDEX "idx_hash_version_compound" ON "public"."catalogo_homologado" USING "btree" ("hash_comercial", "version");



CREATE INDEX "idx_hash_version_search" ON "public"."catalogo_homologado" USING "btree" ("hash_comercial", "version") WHERE ("version" IS NOT NULL);



CREATE INDEX "idx_kb_chunks_content_gin" ON "public"."knowledge_base_chunks" USING "gin" ("to_tsvector"('"spanish"'::"regconfig", "content"));



CREATE INDEX "idx_kb_chunks_metadata" ON "public"."knowledge_base_chunks" USING "gin" ("metadata");



CREATE INDEX "idx_marca_modelo_anio" ON "public"."catalogo_homologado" USING "btree" ("marca", "modelo", "anio");



CREATE INDEX "idx_quote_history_user_id" ON "public"."quote_history" USING "btree" ("user_id");



CREATE INDEX "idx_sessions_user_id" ON "public"."sessions" USING "btree" ("user_id");



CREATE INDEX "idx_support_tickets_session" ON "public"."support_tickets" USING "btree" ("session_id");



CREATE INDEX "idx_support_tickets_user" ON "public"."support_tickets" USING "btree" ("user_id");



CREATE INDEX "idx_tokens_gin" ON "public"."catalogo_homologado" USING "gin" ("version_tokens_array");



CREATE UNIQUE INDEX "idx_unique_hash_version" ON "public"."catalogo_homologado" USING "btree" ("hash_comercial", "version");



CREATE INDEX "idx_user_data_email" ON "public"."user_data" USING "btree" ("correo_electronico");



CREATE INDEX "idx_user_data_telefono" ON "public"."user_data" USING "btree" ("telefono");



CREATE INDEX "idx_version_tokens_array" ON "public"."catalogo_homologado" USING "gin" ("version_tokens_array");



CREATE INDEX "idx_version_tokens_gin" ON "public"."catalogo_homologado" USING "gin" ("version_tokens_array");



CREATE INDEX "idx_version_trgm" ON "public"."catalogo_homologado" USING "gin" ("version" "public"."gin_trgm_ops");



CREATE INDEX "idx_version_trgm_gin" ON "public"."catalogo_homologado" USING "gin" ("version" "public"."gin_trgm_ops");



CREATE OR REPLACE TRIGGER "insert_vector" AFTER INSERT ON "public"."catalogo_homologado" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://zsyapaddgdrnqfdxxzjw.supabase.co/functions/v1/catalogo-embeddings', 'POST', '{"Content-type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpzeWFwYWRkZ2RybnFmZHh4emp3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1MzI5MTc5MiwiZXhwIjoyMDY4ODY3NzkyfQ.fxsYfEUkFGOP6dyrSxn2RYymcVWWQFi2te8nuJrIOyo"}', '{}', '5000');



CREATE OR REPLACE TRIGGER "tr_update_timestamp" BEFORE UPDATE ON "public"."catalogo_homologado" FOR EACH ROW EXECUTE FUNCTION "public"."update_timestamp"();



CREATE OR REPLACE TRIGGER "update_knowledge_chunks_updated_at" BEFORE UPDATE ON "public"."knowledge_base_chunks" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "update_sessions_updated_at" BEFORE UPDATE ON "public"."sessions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "update_support_tickets_updated_at" BEFORE UPDATE ON "public"."support_tickets" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "update_tokens_on_change" BEFORE INSERT OR UPDATE OF "version" ON "public"."catalogo_homologado" FOR EACH ROW EXECUTE FUNCTION "public"."update_tokens_trigger"();



CREATE OR REPLACE TRIGGER "update_user_data_updated_at" BEFORE UPDATE ON "public"."user_data" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."quote_history"
    ADD CONSTRAINT "quote_history_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."sessions"("id");



ALTER TABLE ONLY "public"."quote_history"
    ADD CONSTRAINT "quote_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_data"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_data"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."support_tickets"
    ADD CONSTRAINT "support_tickets_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."support_tickets"
    ADD CONSTRAINT "support_tickets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."user_data"("id") ON DELETE CASCADE;



ALTER TABLE "public"."cotizaciones" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cotizaciones_cache" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."quote_history" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_data" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."catalogo_homologado";






GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_in"("cstring") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_out"("public"."gtrgm") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."_procesar_batch_vehiculos"("vehiculos_json" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."_procesar_batch_vehiculos"("vehiculos_json" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."_procesar_batch_vehiculos"("vehiculos_json" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."actualizar_existente"("request_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."actualizar_existente"("request_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualizar_existente"("request_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."actualizar_existente_n8n"("update_data" json) TO "anon";
GRANT ALL ON FUNCTION "public"."actualizar_existente_n8n"("update_data" json) TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualizar_existente_n8n"("update_data" json) TO "service_role";



GRANT ALL ON FUNCTION "public"."actualizar_existente_n8n"("hash_tecnico" "text", "origen_aseguradora" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."actualizar_existente_n8n"("hash_tecnico" "text", "origen_aseguradora" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualizar_existente_n8n"("hash_tecnico" "text", "origen_aseguradora" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."actualizar_tokens_existentes"("p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."actualizar_tokens_existentes"("p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."actualizar_tokens_existentes"("p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."airtable_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."airtable_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."airtable_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."airtable_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."airtable_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."airtable_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."airtable_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."airtable_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."airtable_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."airtable_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."airtable_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."airtable_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."analizar_calidad_homologacion"() TO "anon";
GRANT ALL ON FUNCTION "public"."analizar_calidad_homologacion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."analizar_calidad_homologacion"() TO "service_role";



GRANT ALL ON FUNCTION "public"."analizar_resultados_homologacion"() TO "anon";
GRANT ALL ON FUNCTION "public"."analizar_resultados_homologacion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."analizar_resultados_homologacion"() TO "service_role";



GRANT ALL ON FUNCTION "public"."analyze_homologation_quality"() TO "anon";
GRANT ALL ON FUNCTION "public"."analyze_homologation_quality"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."analyze_homologation_quality"() TO "service_role";



GRANT ALL ON FUNCTION "public"."analyze_homologation_quality"("sample_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."analyze_homologation_quality"("sample_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."analyze_homologation_quality"("sample_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."analyze_knowledge_base"() TO "anon";
GRANT ALL ON FUNCTION "public"."analyze_knowledge_base"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."analyze_knowledge_base"() TO "service_role";



GRANT ALL ON FUNCTION "public"."analyze_match_quality"("insurer_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."analyze_match_quality"("insurer_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."analyze_match_quality"("insurer_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."analyze_matching_performance"() TO "anon";
GRANT ALL ON FUNCTION "public"."analyze_matching_performance"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."analyze_matching_performance"() TO "service_role";



GRANT ALL ON FUNCTION "public"."analyze_matching_performance_v5"() TO "anon";
GRANT ALL ON FUNCTION "public"."analyze_matching_performance_v5"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."analyze_matching_performance_v5"() TO "service_role";



GRANT ALL ON FUNCTION "public"."analyze_token_distribution"("p_hash_comercial" character varying) TO "anon";
GRANT ALL ON FUNCTION "public"."analyze_token_distribution"("p_hash_comercial" character varying) TO "authenticated";
GRANT ALL ON FUNCTION "public"."analyze_token_distribution"("p_hash_comercial" character varying) TO "service_role";



GRANT ALL ON FUNCTION "public"."analyze_unprocessed_records"("input_batch" "jsonb", "insurer_name" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."analyze_unprocessed_records"("input_batch" "jsonb", "insurer_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."analyze_unprocessed_records"("input_batch" "jsonb", "insurer_name" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."aplicar_clustering_jerarquico"("p_matrix" "jsonb", "p_threshold" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."aplicar_clustering_jerarquico"("p_matrix" "jsonb", "p_threshold" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."aplicar_clustering_jerarquico"("p_matrix" "jsonb", "p_threshold" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."auth0_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."auth0_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."auth0_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth0_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auth0_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."auth0_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."auth0_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth0_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auth0_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."auth0_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."auth0_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth0_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."big_query_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."big_query_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."big_query_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."big_query_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."big_query_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."big_query_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."big_query_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."big_query_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."big_query_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."big_query_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."big_query_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."big_query_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."buscar_candidatos_homologacion"("p_hash_comercial" "text", "p_version_tokens" "text"[], "p_version_normalized" "text", "p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."buscar_candidatos_homologacion"("p_hash_comercial" "text", "p_version_tokens" "text"[], "p_version_normalized" "text", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."buscar_candidatos_homologacion"("p_hash_comercial" "text", "p_version_tokens" "text"[], "p_version_normalized" "text", "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."buscar_por_hash_tecnico"("hash_list" json) TO "anon";
GRANT ALL ON FUNCTION "public"."buscar_por_hash_tecnico"("hash_list" json) TO "authenticated";
GRANT ALL ON FUNCTION "public"."buscar_por_hash_tecnico"("hash_list" json) TO "service_role";



GRANT ALL ON FUNCTION "public"."calcular_similitud_clusters"("p_matrix" "jsonb", "p_cluster1" "jsonb", "p_cluster2" "jsonb", "p_linkage" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."calcular_similitud_clusters"("p_matrix" "jsonb", "p_cluster1" "jsonb", "p_cluster2" "jsonb", "p_linkage" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calcular_similitud_clusters"("p_matrix" "jsonb", "p_cluster1" "jsonb", "p_cluster2" "jsonb", "p_linkage" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_aggressive_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_aggressive_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_aggressive_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_balanced_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_balanced_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_balanced_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_jaccard_match"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_jaccard_match"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_jaccard_match"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_jaccard_similarity"("tokens1" "text"[], "tokens2" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_jaccard_similarity"("tokens1" "text"[], "tokens2" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_jaccard_similarity"("tokens1" "text"[], "tokens2" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_match_score"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_match_score"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_match_score"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_match_score_v2"("v1_tokens" "text"[], "v2_tokens" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_match_score_v2"("v1_tokens" "text"[], "v2_tokens" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_match_score_v2"("v1_tokens" "text"[], "v2_tokens" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_match_score_v4"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[], "use_cache" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_match_score_v4"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[], "use_cache" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_match_score_v4"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[], "use_cache" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_match_score_v5"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[], "use_cache" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_match_score_v5"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[], "use_cache" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_match_score_v5"("version1" "text", "version2" "text", "tokens1" "text"[], "tokens2" "text"[], "use_cache" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_similarity"("tokens1" "text"[], "tokens2" "text"[], "len1" integer, "len2" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_similarity"("tokens1" "text"[], "tokens2" "text"[], "len1" integer, "len2" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_similarity"("tokens1" "text"[], "tokens2" "text"[], "len1" integer, "len2" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_simple_match_score"("v1_tokens" "text"[], "v2_tokens" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_simple_match_score"("v1_tokens" "text"[], "v2_tokens" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_simple_match_score"("v1_tokens" "text"[], "v2_tokens" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_smart_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_smart_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_smart_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_smart_similarity"("v1_tokens" "text"[], "v2_tokens" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_smart_similarity"("v1_tokens" "text"[], "v2_tokens" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_smart_similarity"("v1_tokens" "text"[], "v2_tokens" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_token_overlap"("tokens1" "text"[], "tokens2" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_token_overlap"("tokens1" "text"[], "tokens2" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_token_overlap"("tokens1" "text"[], "tokens2" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_token_similarity"("tokens_a" "text"[], "tokens_b" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_token_similarity"("tokens_a" "text"[], "tokens_b" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_token_similarity"("tokens_a" "text"[], "tokens_b" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_vehicle_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_vehicle_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_vehicle_match_score"("tokens1" "text"[], "tokens2" "text"[], "is_same_insurer" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_version_similarity"("version1_tokens" "text"[], "version2_tokens" "text"[], "version1_text" "text", "version2_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_version_similarity"("version1_tokens" "text"[], "version2_tokens" "text"[], "version1_text" "text", "version2_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_version_similarity"("version1_tokens" "text"[], "version2_tokens" "text"[], "version1_text" "text", "version2_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."calculate_weighted_similarity"("v1_version" "text", "v2_version" "text", "v1_tokens" "text"[], "v2_tokens" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_weighted_similarity"("v1_version" "text", "v2_version" "text", "v1_tokens" "text"[], "v2_tokens" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_weighted_similarity"("v1_version" "text", "v2_version" "text", "v1_tokens" "text"[], "v2_tokens" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."check_existing_catalogo"("hash_list" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."check_existing_catalogo"("hash_list" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_existing_catalogo"("hash_list" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."check_homologation_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."check_homologation_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_homologation_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."classify_token_importance"("token" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."classify_token_importance"("token" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."classify_token_importance"("token" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."clean_expired_cache"() TO "anon";
GRANT ALL ON FUNCTION "public"."clean_expired_cache"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."clean_expired_cache"() TO "service_role";



GRANT ALL ON FUNCTION "public"."clean_match_cache"() TO "anon";
GRANT ALL ON FUNCTION "public"."clean_match_cache"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."clean_match_cache"() TO "service_role";



GRANT ALL ON FUNCTION "public"."click_house_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."click_house_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."click_house_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."click_house_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."click_house_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."click_house_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."click_house_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."click_house_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."click_house_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."click_house_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."click_house_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."click_house_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."cognito_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."cognito_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."cognito_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cognito_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cognito_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."cognito_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."cognito_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cognito_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."cognito_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."cognito_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."cognito_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cognito_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."consolidar_clusters"("p_block_id" "text", "p_clusters" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."consolidar_clusters"("p_block_id" "text", "p_clusters" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."consolidar_clusters"("p_block_id" "text", "p_clusters" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."consolidar_duplicados_internos"("p_hash_comercial" "text", "p_threshold" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."consolidar_duplicados_internos"("p_hash_comercial" "text", "p_threshold" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."consolidar_duplicados_internos"("p_hash_comercial" "text", "p_threshold" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."consolidar_versiones_duplicadas"("p_hash_comercial" "text", "p_dry_run" boolean, "p_min_similarity" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."consolidar_versiones_duplicadas"("p_hash_comercial" "text", "p_dry_run" boolean, "p_min_similarity" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."consolidar_versiones_duplicadas"("p_hash_comercial" "text", "p_dry_run" boolean, "p_min_similarity" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."consolidate_duplicates"("target_hash_comercial" "text", "dry_run" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."consolidate_duplicates"("target_hash_comercial" "text", "dry_run" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."consolidate_duplicates"("target_hash_comercial" "text", "dry_run" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."construir_matriz_similitud"("p_block_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."construir_matriz_similitud"("p_block_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."construir_matriz_similitud"("p_block_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."crear_nuevo_registro"("item" "jsonb", "tokens" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."crear_nuevo_registro"("item" "jsonb", "tokens" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_nuevo_registro"("item" "jsonb", "tokens" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."crear_nuevo_registro_simple"("item" "jsonb", "tokens" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."crear_nuevo_registro_simple"("item" "jsonb", "tokens" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_nuevo_registro_simple"("item" "jsonb", "tokens" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."crear_registro_vehiculo"("item" "jsonb", "tokens" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."crear_registro_vehiculo"("item" "jsonb", "tokens" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."crear_registro_vehiculo"("item" "jsonb", "tokens" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."daitch_mokotoff"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."daitch_mokotoff"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."daitch_mokotoff"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."daitch_mokotoff"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."debug_n8n_request"("raw_data" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."debug_n8n_request"("raw_data" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."debug_n8n_request"("raw_data" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."detect_insurer_from_text"("input_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."detect_insurer_from_text"("input_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."detect_insurer_from_text"("input_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."difference"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."difference"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."difference"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."difference"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."dmetaphone"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."dmetaphone"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."dmetaphone"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dmetaphone"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."dmetaphone_alt"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."dmetaphone_alt"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."dmetaphone_alt"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dmetaphone_alt"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."duckdb_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."duckdb_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."duckdb_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."duckdb_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."duckdb_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."duckdb_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."duckdb_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."duckdb_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."duckdb_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."duckdb_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."duckdb_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."duckdb_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."extract_misplaced_model"("version_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."extract_misplaced_model"("version_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."extract_misplaced_model"("version_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."extract_vehicle_features"("version_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."extract_vehicle_features"("version_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."extract_vehicle_features"("version_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."find_match_candidates"("p_hash_comercial" "text", "p_input_tokens" "text"[], "p_normalized_version" "text", "p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."find_match_candidates"("p_hash_comercial" "text", "p_input_tokens" "text"[], "p_normalized_version" "text", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_match_candidates"("p_hash_comercial" "text", "p_input_tokens" "text"[], "p_normalized_version" "text", "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."find_match_candidates_v5"("p_hash_comercial" "text", "p_input_tokens" "text"[], "p_normalized_version" "text", "p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."find_match_candidates_v5"("p_hash_comercial" "text", "p_input_tokens" "text"[], "p_normalized_version" "text", "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."find_match_candidates_v5"("p_hash_comercial" "text", "p_input_tokens" "text"[], "p_normalized_version" "text", "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."firebase_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."firebase_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."firebase_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."firebase_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."firebase_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."firebase_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."firebase_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."firebase_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."firebase_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."firebase_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."firebase_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."firebase_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."fusionar_clusters"("p_clusters" "jsonb", "p_cluster1_id" integer, "p_cluster2_id" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."fusionar_clusters"("p_clusters" "jsonb", "p_cluster1_id" integer, "p_cluster2_id" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."fusionar_clusters"("p_clusters" "jsonb", "p_cluster1_id" integer, "p_cluster2_id" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."generar_hash_vehiculo"("p_marca" "text", "p_modelo" "text", "p_año" integer, "p_version" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."generar_hash_vehiculo"("p_marca" "text", "p_modelo" "text", "p_año" integer, "p_version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."generar_hash_vehiculo"("p_marca" "text", "p_modelo" "text", "p_año" integer, "p_version" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_extract_query_trgm"("text", "internal", smallint, "internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_extract_value_trgm"("text", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_trgm_consistent"("internal", smallint, "text", integer, "internal", "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gin_trgm_triconsistent"("internal", smallint, "text", integer, "internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_compress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_consistent"("internal", "text", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_decompress"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_distance"("internal", "text", smallint, "oid", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_options"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_penalty"("internal", "internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_picksplit"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_same"("public"."gtrgm", "public"."gtrgm", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "anon";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."gtrgm_union"("internal", "internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "service_role";



GRANT ALL ON FUNCTION "public"."hello_world_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."hello_world_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."hello_world_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hello_world_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."hybrid_search_knowledge"("query_embedding" "public"."vector", "keyword_query" "text", "filter" "jsonb", "semantic_weight" double precision, "keyword_weight" double precision, "match_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."hybrid_search_knowledge"("query_embedding" "public"."vector", "keyword_query" "text", "filter" "jsonb", "semantic_weight" double precision, "keyword_weight" double precision, "match_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hybrid_search_knowledge"("query_embedding" "public"."vector", "keyword_query" "text", "filter" "jsonb", "semantic_weight" double precision, "keyword_weight" double precision, "match_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."hybrid_search_knowledge"("query_embedding" "public"."vector", "keyword_query" "text", "filter_insurer_code" "text", "semantic_weight" double precision, "keyword_weight" double precision, "match_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."hybrid_search_knowledge"("query_embedding" "public"."vector", "keyword_query" "text", "filter_insurer_code" "text", "semantic_weight" double precision, "keyword_weight" double precision, "match_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hybrid_search_knowledge"("query_embedding" "public"."vector", "keyword_query" "text", "filter_insurer_code" "text", "semantic_weight" double precision, "keyword_weight" double precision, "match_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."iceberg_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."iceberg_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."iceberg_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."iceberg_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."iceberg_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."iceberg_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."iceberg_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."iceberg_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."iceberg_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."iceberg_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."iceberg_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."iceberg_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."inclusion_coverage"("a" "text"[], "b" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."inclusion_coverage"("a" "text"[], "b" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."inclusion_coverage"("a" "text"[], "b" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."insertar_nuevo"("vehiculos_data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."insertar_nuevo"("vehiculos_data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."insertar_nuevo"("vehiculos_data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."insertar_nuevo_n8n"("vehiculo_data" json) TO "anon";
GRANT ALL ON FUNCTION "public"."insertar_nuevo_n8n"("vehiculo_data" json) TO "authenticated";
GRANT ALL ON FUNCTION "public"."insertar_nuevo_n8n"("vehiculo_data" json) TO "service_role";



GRANT ALL ON FUNCTION "public"."insertar_nuevo_n8n"("anio" integer, "hash_comercial" "text", "hash_tecnico" "text", "main_specs" "text", "marca" "text", "modelo" "text", "origen_aseguradora" "text", "tech_specs" "text", "carroceria" "text", "cilindrada" numeric, "motor_config" "text", "numero_ocupantes" integer, "traccion" "text", "transmision" "text", "version" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."insertar_nuevo_n8n"("anio" integer, "hash_comercial" "text", "hash_tecnico" "text", "main_specs" "text", "marca" "text", "modelo" "text", "origen_aseguradora" "text", "tech_specs" "text", "carroceria" "text", "cilindrada" numeric, "motor_config" "text", "numero_ocupantes" integer, "traccion" "text", "transmision" "text", "version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."insertar_nuevo_n8n"("anio" integer, "hash_comercial" "text", "hash_tecnico" "text", "main_specs" "text", "marca" "text", "modelo" "text", "origen_aseguradora" "text", "tech_specs" "text", "carroceria" "text", "cilindrada" numeric, "motor_config" "text", "numero_ocupantes" integer, "traccion" "text", "transmision" "text", "version" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "service_role";



GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "service_role";



GRANT ALL ON FUNCTION "public"."jaccard_similarity"("tokens1" "text"[], "tokens2" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."jaccard_similarity"("tokens1" "text"[], "tokens2" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."jaccard_similarity"("tokens1" "text"[], "tokens2" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."kb_sync_chunk"() TO "anon";
GRANT ALL ON FUNCTION "public"."kb_sync_chunk"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."kb_sync_chunk"() TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."levenshtein"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."levenshtein"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."levenshtein"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."levenshtein"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."levenshtein"("text", "text", integer, integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."levenshtein"("text", "text", integer, integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."levenshtein"("text", "text", integer, integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."levenshtein"("text", "text", integer, integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."levenshtein_less_equal"("text", "text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."levenshtein_less_equal"("text", "text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."levenshtein_less_equal"("text", "text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."levenshtein_less_equal"("text", "text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."levenshtein_less_equal"("text", "text", integer, integer, integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."levenshtein_less_equal"("text", "text", integer, integer, integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."levenshtein_less_equal"("text", "text", integer, integer, integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."levenshtein_less_equal"("text", "text", integer, integer, integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."limpiar_catalogo_completo"() TO "anon";
GRANT ALL ON FUNCTION "public"."limpiar_catalogo_completo"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."limpiar_catalogo_completo"() TO "service_role";



GRANT ALL ON FUNCTION "public"."logflare_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."logflare_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."logflare_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."logflare_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."logflare_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."logflare_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."logflare_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."logflare_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."logflare_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."logflare_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."logflare_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."logflare_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "filter" "jsonb", "match_threshold" double precision, "match_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "filter" "jsonb", "match_threshold" double precision, "match_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_documents"("query_embedding" "public"."vector", "filter" "jsonb", "match_threshold" double precision, "match_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."match_documents_by_insurer"("query_embedding" "public"."vector", "match_count" integer, "insurer" "text", "filter" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."match_documents_by_insurer"("query_embedding" "public"."vector", "match_count" integer, "insurer" "text", "filter" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_documents_by_insurer"("query_embedding" "public"."vector", "match_count" integer, "insurer" "text", "filter" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."merge_disponibilidad"("orig" "jsonb", "aseguradora" "text", "payload" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."merge_disponibilidad"("orig" "jsonb", "aseguradora" "text", "payload" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."merge_disponibilidad"("orig" "jsonb", "aseguradora" "text", "payload" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."metaphone"("text", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."metaphone"("text", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."metaphone"("text", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."metaphone"("text", integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."mssql_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."mssql_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."mssql_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mssql_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mssql_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."mssql_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."mssql_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mssql_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mssql_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."mssql_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."mssql_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mssql_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."normalizar_texto"("texto" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalizar_texto"("texto" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalizar_texto"("texto" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_semantic_tokens"("input_tokens" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_semantic_tokens"("input_tokens" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_semantic_tokens"("input_tokens" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."obtener_estadisticas"() TO "anon";
GRANT ALL ON FUNCTION "public"."obtener_estadisticas"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."obtener_estadisticas"() TO "service_role";



GRANT ALL ON FUNCTION "public"."prepare_chunks_for_reranking"("query_embedding" "public"."vector", "initial_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."prepare_chunks_for_reranking"("query_embedding" "public"."vector", "initial_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."prepare_chunks_for_reranking"("query_embedding" "public"."vector", "initial_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."procesar_batch_completo"("vehiculos_json" json) TO "anon";
GRANT ALL ON FUNCTION "public"."procesar_batch_completo"("vehiculos_json" json) TO "authenticated";
GRANT ALL ON FUNCTION "public"."procesar_batch_completo"("vehiculos_json" json) TO "service_role";



GRANT ALL ON FUNCTION "public"."procesar_batch_completo"("vehiculos_json" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."procesar_batch_completo"("vehiculos_json" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."procesar_batch_completo"("vehiculos_json" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."procesar_batch_completo2"("vehiculos_json" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."procesar_batch_completo2"("vehiculos_json" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."procesar_batch_completo2"("vehiculos_json" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."procesar_batch_homologacion"("p_vehiculos_json" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."procesar_batch_homologacion"("p_vehiculos_json" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."procesar_batch_homologacion"("p_vehiculos_json" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."procesar_batch_por_chunks"("records" "jsonb", "chunk_size" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."procesar_batch_por_chunks"("records" "jsonb", "chunk_size" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."procesar_batch_por_chunks"("records" "jsonb", "chunk_size" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."procesar_batch_vehiculos"("p_input" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."procesar_batch_vehiculos"("p_input" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."procesar_batch_vehiculos"("p_input" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."procesar_batch_vehiculos_modo"("records" "jsonb", "batch_mode" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."procesar_batch_vehiculos_modo"("records" "jsonb", "batch_mode" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."procesar_batch_vehiculos_modo"("records" "jsonb", "batch_mode" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."procesar_bloque_completo"("p_hash_comercial" "text", "p_records" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."procesar_bloque_completo"("p_hash_comercial" "text", "p_records" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."procesar_bloque_completo"("p_hash_comercial" "text", "p_records" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."redis_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."redis_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."redis_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."redis_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."redis_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."redis_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."redis_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."redis_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."redis_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."redis_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."redis_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."redis_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."s3_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."s3_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."s3_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."s3_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."s3_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."s3_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."s3_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."s3_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."s3_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."s3_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."s3_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."s3_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "postgres";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "anon";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_limit"(real) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."show_limit"() TO "postgres";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "anon";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."show_limit"() TO "service_role";



GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."show_trgm"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity_dist"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."similarity_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."soundex"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."soundex"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."soundex"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."soundex"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_dist_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."strict_word_similarity_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."stripe_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."stripe_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."stripe_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."stripe_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."stripe_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."stripe_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."stripe_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."stripe_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."stripe_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."stripe_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."stripe_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."stripe_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."test_homologation_matching"() TO "anon";
GRANT ALL ON FUNCTION "public"."test_homologation_matching"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_homologation_matching"() TO "service_role";



GRANT ALL ON FUNCTION "public"."test_vehicle_matching"("qualitas_version" "text", "zurich_version" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."test_vehicle_matching"("qualitas_version" "text", "zurich_version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_vehicle_matching"("qualitas_version" "text", "zurich_version" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."test_version_match"("version1" "text", "version2" "text", "same_insurer" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."test_version_match"("version1" "text", "version2" "text", "same_insurer" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_version_match"("version1" "text", "version2" "text", "same_insurer" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."test_version_matching"("version1" "text", "version2" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."test_version_matching"("version1" "text", "version2" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."test_version_matching"("version1" "text", "version2" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."text_soundex"("text") TO "postgres";
GRANT ALL ON FUNCTION "public"."text_soundex"("text") TO "anon";
GRANT ALL ON FUNCTION "public"."text_soundex"("text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."text_soundex"("text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tokenize_vehicle_version"("version_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."tokenize_vehicle_version"("version_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tokenize_vehicle_version"("version_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tokenize_version"("p_version" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."tokenize_version"("p_version" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tokenize_version"("p_version" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tokenize_version_enhanced"("version_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."tokenize_version_enhanced"("version_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tokenize_version_enhanced"("version_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tokenize_version_ordered"("version_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."tokenize_version_ordered"("version_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tokenize_version_ordered"("version_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tokenize_version_proper"("version_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."tokenize_version_proper"("version_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tokenize_version_proper"("version_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."tokenize_version_smart"("version_text" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."tokenize_version_smart"("version_text" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."tokenize_version_smart"("version_text" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_catalogo_batch"("updates" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."update_catalogo_batch"("updates" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_catalogo_batch"("updates" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_fecha_actualizacion"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_fecha_actualizacion"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_fecha_actualizacion"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_timestamp"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_timestamp"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_timestamp"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_tokens_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_tokens_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_tokens_trigger"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_vehicles_batch"("updates" "jsonb"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."update_vehicles_batch"("updates" "jsonb"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_vehicles_batch"("updates" "jsonb"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."wasm_fdw_handler"() TO "postgres";
GRANT ALL ON FUNCTION "public"."wasm_fdw_handler"() TO "anon";
GRANT ALL ON FUNCTION "public"."wasm_fdw_handler"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."wasm_fdw_handler"() TO "service_role";



GRANT ALL ON FUNCTION "public"."wasm_fdw_meta"() TO "postgres";
GRANT ALL ON FUNCTION "public"."wasm_fdw_meta"() TO "anon";
GRANT ALL ON FUNCTION "public"."wasm_fdw_meta"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."wasm_fdw_meta"() TO "service_role";



GRANT ALL ON FUNCTION "public"."wasm_fdw_validator"("options" "text"[], "catalog" "oid") TO "postgres";
GRANT ALL ON FUNCTION "public"."wasm_fdw_validator"("options" "text"[], "catalog" "oid") TO "anon";
GRANT ALL ON FUNCTION "public"."wasm_fdw_validator"("options" "text"[], "catalog" "oid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."wasm_fdw_validator"("options" "text"[], "catalog" "oid") TO "service_role";



GRANT ALL ON FUNCTION "public"."weighted_token_similarity"("tokens1" "text"[], "tokens2" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."weighted_token_similarity"("tokens1" "text"[], "tokens2" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."weighted_token_similarity"("tokens1" "text"[], "tokens2" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_commutator_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_dist_op"("text", "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "postgres";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "anon";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."word_similarity_op"("text", "text") TO "service_role";












GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "service_role";



GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "service_role";



GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "service_role";









GRANT ALL ON TABLE "public"."aseguradoras_metadata" TO "anon";
GRANT ALL ON TABLE "public"."aseguradoras_metadata" TO "authenticated";
GRANT ALL ON TABLE "public"."aseguradoras_metadata" TO "service_role";



GRANT ALL ON SEQUENCE "public"."aseguradoras_metadata_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."aseguradoras_metadata_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."aseguradoras_metadata_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."catalogo_homologado" TO "anon";
GRANT ALL ON TABLE "public"."catalogo_homologado" TO "authenticated";
GRANT ALL ON TABLE "public"."catalogo_homologado" TO "service_role";



GRANT ALL ON SEQUENCE "public"."catalogo_homologado_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."catalogo_homologado_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."catalogo_homologado_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."cotizaciones" TO "anon";
GRANT ALL ON TABLE "public"."cotizaciones" TO "authenticated";
GRANT ALL ON TABLE "public"."cotizaciones" TO "service_role";



GRANT ALL ON TABLE "public"."cotizaciones_cache" TO "anon";
GRANT ALL ON TABLE "public"."cotizaciones_cache" TO "authenticated";
GRANT ALL ON TABLE "public"."cotizaciones_cache" TO "service_role";



GRANT ALL ON TABLE "public"."historial_conversacion" TO "anon";
GRANT ALL ON TABLE "public"."historial_conversacion" TO "authenticated";
GRANT ALL ON TABLE "public"."historial_conversacion" TO "service_role";



GRANT ALL ON SEQUENCE "public"."historial_conversacion_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."historial_conversacion_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."historial_conversacion_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."knowledge_base_chunks" TO "anon";
GRANT ALL ON TABLE "public"."knowledge_base_chunks" TO "authenticated";
GRANT ALL ON TABLE "public"."knowledge_base_chunks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."knowledge_base_chunks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."knowledge_base_chunks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."knowledge_base_chunks_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."quote_history" TO "anon";
GRANT ALL ON TABLE "public"."quote_history" TO "authenticated";
GRANT ALL ON TABLE "public"."quote_history" TO "service_role";



GRANT ALL ON TABLE "public"."sessions" TO "anon";
GRANT ALL ON TABLE "public"."sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."sessions" TO "service_role";



GRANT ALL ON TABLE "public"."support_tickets" TO "anon";
GRANT ALL ON TABLE "public"."support_tickets" TO "authenticated";
GRANT ALL ON TABLE "public"."support_tickets" TO "service_role";



GRANT ALL ON TABLE "public"."user_data" TO "anon";
GRANT ALL ON TABLE "public"."user_data" TO "authenticated";
GRANT ALL ON TABLE "public"."user_data" TO "service_role";



GRANT ALL ON TABLE "public"."v_homologation_stats" TO "anon";
GRANT ALL ON TABLE "public"."v_homologation_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."v_homologation_stats" TO "service_role";



GRANT ALL ON TABLE "public"."wrappers_fdw_stats" TO "postgres";
GRANT ALL ON TABLE "public"."wrappers_fdw_stats" TO "anon";
GRANT ALL ON TABLE "public"."wrappers_fdw_stats" TO "authenticated";
GRANT ALL ON TABLE "public"."wrappers_fdw_stats" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






























RESET ALL;
CREATE TRIGGER enforce_bucket_name_length_trigger BEFORE INSERT OR UPDATE OF name ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_name_length();

CREATE TRIGGER objects_delete_delete_prefix AFTER DELETE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.delete_prefix_hierarchy_trigger();

CREATE TRIGGER objects_insert_create_prefix BEFORE INSERT ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.objects_insert_prefix_trigger();

CREATE TRIGGER objects_update_create_prefix BEFORE UPDATE ON storage.objects FOR EACH ROW WHEN (((new.name <> old.name) OR (new.bucket_id <> old.bucket_id))) EXECUTE FUNCTION storage.objects_update_prefix_trigger();

CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();

CREATE TRIGGER prefixes_create_hierarchy BEFORE INSERT ON storage.prefixes FOR EACH ROW WHEN ((pg_trigger_depth() < 1)) EXECUTE FUNCTION storage.prefixes_insert_trigger();

CREATE TRIGGER prefixes_delete_hierarchy AFTER DELETE ON storage.prefixes FOR EACH ROW EXECUTE FUNCTION storage.delete_prefix_hierarchy_trigger();



