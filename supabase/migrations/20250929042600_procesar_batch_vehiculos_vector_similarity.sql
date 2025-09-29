-- Migration: Add version_vector, index, and update procesar_batch_vehiculos for vector similarity fallback
-- Date: 2025-09-29 04:26:00Z

-- 1) Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- 2) Add vector column (1536 dims)
ALTER TABLE public.catalogo_homologado
  ADD COLUMN IF NOT EXISTS version_vector vector(1536);

-- 3) Vector index (IVFFlat with cosine). Adjust lists for your data size.
CREATE INDEX IF NOT EXISTS idx_catalogo_homologado_version_vector_ivfflat
  ON public.catalogo_homologado
  USING ivfflat (version_vector vector_cosine_ops)
  WITH (lists = 100);

-- 4) Replace procesar_batch_vehiculos to persist embeddings and use cosine similarity fallback
CREATE OR REPLACE FUNCTION public.procesar_batch_vehiculos(
  p_input jsonb,
  p_similarity_threshold numeric DEFAULT 0.96
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_rec RECORD;
  v_now timestamptz := now();
  v_b_tokens text[];
  v_hash text;
  v_ver_canonica text;
  v_aseg text;

  matched_ids bigint[] := ARRAY[]::bigint[];
  v_ins_ids bigint[] := ARRAY[]::bigint[];
  v_upd_ids bigint[] := ARRAY[]::bigint[];
  v_nochange_ids bigint[] := ARRAY[]::bigint[];
  v_errors jsonb := '[]'::jsonb;

  -- vector handling
  v_vec vector(1536);
  v_best_id bigint;
  v_best_sim numeric; -- cosine similarity in [0,1]
  v_threshold numeric := p_similarity_threshold; -- configurable as needed

  payload jsonb;
BEGIN
  IF p_input IS NULL OR p_input ? 'vehiculos_json' = false THEN
    RAISE EXCEPTION 'Entrada inválida: se espera clave vehiculos_json';
  END IF;

  FOR v_rec IN
    SELECT *
    FROM jsonb_to_recordset(p_input->'vehiculos_json') AS x(
      origen_aseguradora   text,
      id_original          bigint,
      marca                text,
      modelo               text,
      anio                 int,
      transmision          text,
      version_original     text,
      version_limpia       text,
      fecha_procesamiento  timestamptz,
      hash_comercial       text,
      version_vector       double precision[]
    )
  LOOP
    BEGIN
      v_hash := v_rec.hash_comercial;
      v_aseg := upper(coalesce(v_rec.origen_aseguradora, ''));
      v_ver_canonica := trim(v_rec.version_limpia);
      v_b_tokens := public.tokenize_version(v_ver_canonica);

      -- Safely build vector if correct dimension
      v_vec := NULL;
      IF v_rec.version_vector IS NOT NULL
         AND array_length(v_rec.version_vector, 1) = 1536 THEN
        BEGIN
          v_vec := ('[' || array_to_string(v_rec.version_vector, ',') || ']')::vector(1536);
        EXCEPTION WHEN others THEN
          v_vec := NULL;
          v_errors := v_errors || jsonb_build_array(
            jsonb_build_object(
              'id_original', v_rec.id_original,
              'hash_comercial', v_hash,
              'warning', 'invalid_embedding_cast'
            )
          );
        END;
      END IF;

      -- Primary match: inclusion coverage must be 1
      matched_ids := ARRAY(
        SELECT a.id
        FROM public.catalogo_homologado a
        WHERE a.hash_comercial = v_hash
          AND public.inclusion_coverage(
                COALESCE(a.version_tokens_array, public.tokenize_version(a.version)),
                v_b_tokens
              ) = 1
      );

      IF array_length(matched_ids, 1) IS NOT NULL AND array_length(matched_ids, 1) > 0 THEN
        payload := jsonb_build_object(
          'origen', true,
          'disponible', true,
          'aseguradora', v_aseg,
          'id_original', v_rec.id_original,
          'metodo_match', 'inclusion_index',
          'confianza_score', 1,
          'version_original', coalesce(v_rec.version_original, v_ver_canonica),
          'fecha_actualizacion', to_char(v_now, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        );

        UPDATE public.catalogo_homologado a
        SET
          disponibilidad = public.merge_disponibilidad(a.disponibilidad, v_aseg, payload),
          version_vector = COALESCE(a.version_vector, v_vec),
          fecha_actualizacion = v_now
        WHERE a.id = ANY(matched_ids);

        v_upd_ids := v_upd_ids || matched_ids;

      ELSE
        -- Fallback: vector similarity within same hash_comercial
        v_best_id := NULL;
        v_best_sim := NULL;

        IF v_vec IS NOT NULL THEN
          SELECT id,
                 (1 - (version_vector <=> v_vec)) AS sim
          INTO v_best_id, v_best_sim
          FROM public.catalogo_homologado
          WHERE hash_comercial = v_hash
            AND version_vector IS NOT NULL
            AND (version_vector <=> v_vec) <= (1 - v_threshold)
          ORDER BY (version_vector <=> v_vec) ASC
          LIMIT 1;
        END IF;

        IF v_best_id IS NOT NULL AND v_best_sim IS NOT NULL AND v_best_sim >= v_threshold THEN
          payload := jsonb_build_object(
            'origen', true,
            'disponible', true,
            'aseguradora', v_aseg,
            'id_original', v_rec.id_original,
            'metodo_match', 'vector_similarity',
            'confianza_score', v_best_sim,
            'version_original', coalesce(v_rec.version_original, v_ver_canonica),
            'fecha_actualizacion', to_char(v_now, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          );

          UPDATE public.catalogo_homologado a
          SET
            disponibilidad = public.merge_disponibilidad(a.disponibilidad, v_aseg, payload),
            version_vector = COALESCE(a.version_vector, v_vec),
            fecha_actualizacion = v_now
          WHERE a.id = v_best_id;

          v_upd_ids := v_upd_ids || ARRAY[v_best_id];

        ELSE
          -- Insert new record
          INSERT INTO public.catalogo_homologado(
            hash_comercial, marca, modelo, anio, transmision,
            version, disponibilidad, fecha_creacion, fecha_actualizacion,
            version_tokens, version_tokens_array, version_vector
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
            v_b_tokens,
            v_vec
          )
          ON CONFLICT (hash_comercial, version)
          DO UPDATE SET
            disponibilidad = public.merge_disponibilidad(
              public.catalogo_homologado.disponibilidad,
              EXCLUDED.disponibilidad,
              EXCLUDED.disponibilidad->>(EXCLUDED.disponibilidad->>'aseguradora')
            ),
            version_vector = COALESCE(public.catalogo_homologado.version_vector, EXCLUDED.version_vector),
            fecha_actualizacion = v_now;
            fecha_actualizacion = v_now;
            IF v_best_id IS NOT NULL THEN
              v_ins_ids := v_ins_ids || ARRAY[v_best_id];
            END IF;
          ELSE
            -- No change: optionally append v_rec.id_original if needed
            -- v_nochange_ids := v_nochange_ids || ARRAY[v_rec.id_original];
          END IF;
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
    'insertados',      coalesce(array_length(v_ins_ids,1),0),
    'actualizados',    coalesce(array_length(v_upd_ids,1),0),
    'sin_cambios',     coalesce(array_length(v_nochange_ids,1),0),
    'ids_insertados',  coalesce(v_ins_ids, ARRAY[]::bigint[]),
    'ids_actualizados',coalesce(v_upd_ids, ARRAY[]::bigint[]),
    'errores',         v_errors
  );
END;
$$;

-- Optional: analyze to help planner
ANALYZE public.catalogo_homologado;
