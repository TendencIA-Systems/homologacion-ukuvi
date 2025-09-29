-- ============================================
-- Helpers para tokenizar y cubrir inclusión
-- ============================================

-- 1) Normaliza y tokeniza una versión ya "limpia".
--    - Uppercase, trim, colapsa espacios, separa por espacios
--    - Elimina tokens vacíos y devuelve tokens ÚNICOS conservando orden relativo
CREATE OR REPLACE FUNCTION public.tokenize_version(p_version text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
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

-- 2) Calcula Inclusion(A,B) = |A ∩ B| / |B|
--    A = tokens homologados (array de la tabla)
--    B = tokens de la versión entrante (array)
CREATE OR REPLACE FUNCTION public.inclusion_coverage(a text[], b text[])
RETURNS numeric
LANGUAGE sql
IMMUTABLE
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

-- 3) Upsert de clave de aseguradora dentro de 'disponibilidad'
--    Reemplaza (o crea) la clave = nombre de aseguradora con el payload dado.
CREATE OR REPLACE FUNCTION public.merge_disponibilidad(
  orig jsonb,
  aseguradora text,
  payload jsonb
) RETURNS jsonb
LANGUAGE sql
IMMUTABLE
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

-- ============================================
-- Función principal: procesar_batch_vehiculos
--   Entrada: JSONB con clave 'vehiculos_json' (array)
--   Lógica: Inclusion(A,B) debe ser EXACTAMENTE 1
-- ============================================

CREATE OR REPLACE FUNCTION public.procesar_batch_vehiculos(p_input jsonb)
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

-- ============================================
-- Sugerencia de índices (ejecutar una vez)
-- ============================================

-- Acelera la búsqueda por hash
CREATE INDEX IF NOT EXISTS idx_catalogo_homologado_hash
  ON public.catalogo_homologado (hash_comercial);

-- Si quieres acelerar búsquedas por tokens (opcional):
-- requiere extensión btree_gin si usas GIN sobre arrays, o usar GIN sobre tsvector
CREATE INDEX IF NOT EXISTS idx_catalogo_homologado_tokens
  ON public.catalogo_homologado USING GIN (version_tokens);
