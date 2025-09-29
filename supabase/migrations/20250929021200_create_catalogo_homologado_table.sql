-- =====================================================
-- CATALOGO HOMOLOGADO TABLE CREATION v7.0
-- Main table for vehicle homologation data
-- =====================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

-- Create the main homologation table
CREATE TABLE IF NOT EXISTS public.catalogo_homologado (
    id bigserial PRIMARY KEY,
    hash_comercial varchar(64) NOT NULL,
    marca varchar(100) NOT NULL,
    modelo varchar(150) NOT NULL,
    anio integer NOT NULL CHECK (anio BETWEEN 2000 AND 2030),
    transmision varchar(20),
    version varchar(200),
    version_tokens tsvector,
    version_tokens_array text[],
    disponibilidad jsonb DEFAULT '{}'::jsonb,
    fecha_creacion timestamptz DEFAULT now(),
    fecha_actualizacion timestamptz DEFAULT now(),
    UNIQUE (hash_comercial, version)
);

-- Create performance indexes
CREATE INDEX IF NOT EXISTS idx_hash_comercial_hom 
    ON public.catalogo_homologado (hash_comercial);

CREATE INDEX IF NOT EXISTS idx_version_trgm_hom 
    ON public.catalogo_homologado USING gin (version gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_version_tokens_hom 
    ON public.catalogo_homologado USING gin (version_tokens);

CREATE INDEX IF NOT EXISTS idx_version_tokens_array_hom 
    ON public.catalogo_homologado USING gin (version_tokens_array);

CREATE INDEX IF NOT EXISTS idx_disponibilidad_gin_hom 
    ON public.catalogo_homologado USING gin (disponibilidad);

-- Add updated timestamp trigger
CREATE OR REPLACE FUNCTION update_updated_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.fecha_actualizacion = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_catalogo_homologado_updated
    BEFORE UPDATE ON public.catalogo_homologado
    FOR EACH ROW EXECUTE FUNCTION update_updated_timestamp();

-- Grant appropriate permissions
GRANT SELECT, INSERT, UPDATE ON public.catalogo_homologado TO authenticated;
GRANT SELECT ON public.catalogo_homologado TO anon;