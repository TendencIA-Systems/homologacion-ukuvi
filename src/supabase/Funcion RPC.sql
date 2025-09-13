-- =====================================================
-- FUNCIÓN MAESTRA TODO-EN-UNO (OPCIONAL)
-- Procesa todo el batch de una sola vez
-- =====================================================
CREATE OR REPLACE FUNCTION procesar_batch_completo(
    vehiculos_json JSON
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
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

-- =====================================================
CREATE INDEX IF NOT EXISTS idx_hash_tecnico ON vehiculos_maestro(hash_tecnico);
CREATE INDEX IF NOT EXISTS idx_marca_modelo_anio ON vehiculos_maestro(marca, modelo, anio);
CREATE INDEX IF NOT EXISTS idx_aseguradoras ON vehiculos_maestro USING GIN(aseguradoras_disponibles);
CREATE INDEX IF NOT EXISTS idx_fecha_actualizacion ON vehiculos_maestro(fecha_actualizacion DESC);