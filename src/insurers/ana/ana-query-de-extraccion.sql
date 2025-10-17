-- =====================================================
-- QUERY DE EXTRACCIÓN PARA ANA
-- Solo registros ACTIVOS (80.13% = ~28,611)
-- Campo VersionCorta con prefijos de marca
-- =====================================================

SELECT 
    'ANA' as origen_aseguradora,
    v.ID as id_original,
    m.Descripcion as marca,
    sm.Descripcion as modelo,
    v.Modelo as anio,
    v.VersionCorta as version_original,
    CASE 
        WHEN v.Transmision = 1 THEN 'MANUAL'
        WHEN v.Transmision = 2 THEN 'AUTO'
        ELSE NULL
    END as transmision,
    v.Activo as activo
FROM ana.NVersiones v
INNER JOIN ana.NMarca m ON v.MarcaClave = m.Clave
INNER JOIN ana.NSubMarca sm ON v.SubMarcaClave = sm.Clave 
    AND v.MarcaClave = sm.MarcaClave
WHERE 
    v.Activo = 1
    AND v.Modelo BETWEEN 2000 AND 2030
ORDER BY m.Descripcion, sm.Descripcion, v.Modelo