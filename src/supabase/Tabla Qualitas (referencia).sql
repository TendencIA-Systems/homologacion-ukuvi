CREATE TABLE public.catalogo_qualitas_ref (
    id BIGSERIAL PRIMARY KEY,
    id_qualitas VARCHAR(50) UNIQUE NOT NULL,
    marca VARCHAR(100) NOT NULL,
    modelo VARCHAR(150) NOT NULL,
    anio INTEGER NOT NULL,
    transmision VARCHAR(20),
    version VARCHAR(200),
    version_completa TEXT,
    motor_config VARCHAR(50),
    cilindrada NUMERIC(3,1),
    carroceria VARCHAR(50),
    traccion VARCHAR(20),
    numero_puertas INTEGER,
    numero_ocupantes INTEGER,
    
    -- Para búsqueda eficiente
    hash_busqueda VARCHAR(64),
    
    fecha_actualizacion TIMESTAMP DEFAULT NOW(),
    activo BOOLEAN DEFAULT true
);

CREATE INDEX idx_qualitas_marca_modelo ON catalogo_qualitas_ref (marca, modelo, anio);
CREATE INDEX idx_qualitas_hash ON catalogo_qualitas_ref (hash_busqueda);