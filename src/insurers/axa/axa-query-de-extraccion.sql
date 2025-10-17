-- =====================================================
-- QUERY DE EXTRACCIÓN PARA AXA
-- Solo registros ACTIVOS (99.94% = ~14,244)
-- IMPORTANTE: Años duales (inicial y final)
-- =====================================================

SELECT 
    'AXA' as origen_aseguradora,
    l.ID as id_original,
    m.Descripcion as marca,
    v.Version as modelo,
    l.AnoInicial as anio, -- Decisión: usar año inicial
    l.DescripcionLinea as version_original,
    CASE 
        WHEN l.Transmision = 1 THEN 'MANUAL'
        WHEN l.Transmision = 2 THEN 'AUTO'
        ELSE NULL
    END as transmision,
    l.Activo as activo
FROM axa.Linea l
INNER JOIN axa.Versiones v ON l.VersionSecClave = v.VersionSecClave
INNER JOIN axa.Marca m ON v.MarcaClave = m.Clave
WHERE 
    l.Activo = 1
    AND l.AnoInicial BETWEEN 2000 AND 2030
ORDER BY m.Descripcion, v.Version, l.AnoInicial