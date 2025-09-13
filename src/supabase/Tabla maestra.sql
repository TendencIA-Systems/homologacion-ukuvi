-- Eliminar tabla anterior si existe
DROP TABLE IF EXISTS vehiculos_maestro CASCADE;

-- Crear nueva tabla con estructura mejorada
CREATE TABLE public.vehiculos_maestro (
    -- ID canónico que se envía al multicotizador
    id_canonico VARCHAR(64) PRIMARY KEY,
    
    -- Datos consolidados/normalizados
    marca VARCHAR(100) NOT NULL,
    modelo VARCHAR(150) NOT NULL,
    anio INTEGER NOT NULL,
    transmision VARCHAR(20),  -- AUTO/MANUAL/null
    version VARCHAR(200),     -- Versión normalizada/consolidada
    motor_config VARCHAR(50), -- L4/V6/V8/null
    carroceria VARCHAR(50),   -- SEDAN/SUV/PICKUP/HATCHBACK/null
    traccion VARCHAR(20),     -- 4X4/2WD/AWD/null (normalizada)
    
    -- Hashes para búsqueda y agrupación
    hash_comercial VARCHAR(64) NOT NULL,  -- marca+modelo+año+transmisión
    
    -- Información de disponibilidad por aseguradora
    disponibilidad_aseguradoras JSONB NOT NULL DEFAULT '{}',
    /* Estructura:
    {
        "HDI": {
            "activo": true,
            "id_original": "HDI_3787",
            "hash_original": "7db26fd4a4...",
            "version_original": "YARIS CORE L4 5.0 SUV",
            "datos_originales": {
                "motor_config": "L4",
                "cilindrada": "5.0",
                "carroceria": "SUV",
                "numero_puertas": null,
                "numero_ocupantes": null
            },
            "fecha_actualizacion": "2025-01-15T10:00:00Z"
        },
        "QUALITAS": {
            "activo": true,
            "id_original": "Q_156789",
            "hash_original": "a7a8fbec4e...",
            "version_original": "YARIS PREMIUM 1.5L SEDAN",
            "datos_originales": {
                "motor_config": null,
                "cilindrada": "1.5",
                "carroceria": "SEDAN",
                "numero_puertas": 4,
                "numero_ocupantes": 5
            },
            "fecha_actualizacion": "2025-01-15T10:00:00Z"
        }
    }
    */
    
    -- Lista simple de aseguradoras activas (para búsqueda rápida)
    aseguradoras_activas TEXT[] GENERATED ALWAYS AS (
        ARRAY(
            SELECT key 
            FROM jsonb_each(disponibilidad_aseguradoras) 
            WHERE (value->>'activo')::boolean = true
        )
    ) STORED,
    
    -- Metadata de homologación
    metadata_homologacion JSONB DEFAULT '{}',
    /* Estructura:
    {
        "metodo": "FUZZY",  -- EXACTO/FUZZY/ENRIQUECIDO
        "confianza": 0.95,
        "fuente_enriquecimiento": "QUALITAS",
        "campos_inferidos": ["carroceria", "motor_config"],
        "fecha_consolidacion": "2025-01-15T10:00:00Z"
    }
    */
    
    -- Timestamps
    fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    fecha_actualizacion TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Índices para búsqueda eficiente
CREATE INDEX idx_marca_modelo_anio ON vehiculos_maestro (marca, modelo, anio);
CREATE INDEX idx_hash_comercial ON vehiculos_maestro (hash_comercial);
CREATE INDEX idx_aseguradoras_activas ON vehiculos_maestro USING GIN (aseguradoras_activas);
CREATE INDEX idx_disponibilidad ON vehiculos_maestro USING GIN (disponibilidad_aseguradoras);

-- Trigger para actualizar fecha
CREATE OR REPLACE FUNCTION update_fecha_actualizacion()
RETURNS TRIGGER AS $$
BEGIN
    NEW.fecha_actualizacion = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_update_fecha
BEFORE UPDATE ON vehiculos_maestro
FOR EACH ROW EXECUTE FUNCTION update_fecha_actualizacion();