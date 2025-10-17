-- =====================================================
-- QUERY DE EXTRACCIÓN PARA HDI
-- Solo registros ACTIVOS (45.15% del total = ~38,186)
-- Estructura con separación por comas muy limpia
-- =====================================================

WITH MarcasUnicas AS (
    -- HDI tiene duplicados en tabla Marca, necesitamos DISTINCT
    SELECT DISTINCT IdMarca, Descripcion
    FROM hdi.Marca
)
SELECT 
    'HDI' as origen_aseguradora,
    v.IdVersion as id_original,
    m.Descripcion as marca,
    v.ClaveSubMarca as modelo,
    v.Anio as anio,
    v.ClaveVersion as version_original,
    -- No hay campo de transmisión directo, se extrae del texto
    NULL as transmision,  -- Se procesará en n8n
    v.Activo as activo
FROM hdi.Version v
LEFT JOIN MarcasUnicas m ON v.IdMarca = m.IdMarca
WHERE 
    v.Activo = 1  -- CRÍTICO: Solo activos (45% del total)
    AND v.Anio BETWEEN 2000 AND 2030
ORDER BY m.Descripcion, v.ClaveSubMarca, v.Anio