-- =====================================================
-- QUERY DE EXTRACCIÓN PARA ZURICH
-- Todos los registros (no tiene campo activo = ~38,984)
-- Optimizado para n8n sin timeout
-- =====================================================

SELECT 
    'ZURICH' as origen_aseguradora,
    v.fiId as id_original,
    m.fcMarca as marca,
    sm.fcSubMarca as modelo,
    v.fiModelo as anio,
    ISNULL(v.VersionCorta, v.fcVersion) as version_original,
    CASE 
        WHEN v.fiTransmision = 1 THEN 'MANUAL'
        WHEN v.fiTransmision = 2 THEN 'AUTO'
        ELSE NULL
    END as transmision,
    1 as activo  -- Todos se consideran activos
FROM zurich.Version v
INNER JOIN zurich.Marcas m ON v.fiMarcaId = m.fiMarcaId
INNER JOIN zurich.SubMarcas sm ON v.fiMarcaId = sm.fiMarcaId 
    AND v.fiSubMarcaId = sm.fiSubMarcaId
WHERE 
    v.fiModelo BETWEEN 2000 AND 2030
ORDER BY m.fcMarca, sm.fcSubMarca, v.fiModelo