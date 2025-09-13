CREATE OR REPLACE FUNCTION public.procesar_batch_homologacion(
    p_vehiculos_json JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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