-- =====================================================
-- QUERY DE EXTRACCIÓN PARA QUALITAS
-- Solo registros ACTIVOS (15.47% del total = ~39,715)
-- Optimizado para n8n sin timeout
-- =====================================================

SELECT 
    'QUALITAS' as origen_aseguradora,
    v.ID as id_original,
    m.cMarcaLarga as marca,
    mo.cTipo as modelo,
    CAST(LEFT(v.cModelo, 4) as INT) as anio,
    v.cVersion as version_original,
    CASE 
        WHEN v.cTransmision = 'A' THEN 'AUTO'
        WHEN v.cTransmision = 'S' THEN 'MANUAL'
        ELSE NULL
    END as transmision,
    v.Activo as activo
FROM qualitas.Version v
INNER JOIN qualitas.Modelo mo ON v.ModeloID = mo.ID
INNER JOIN qualitas.Marca m ON mo.MarcaID = m.ID
WHERE 
    v.Activo = 1  -- CRÍTICO: Solo activos
    AND CAST(LEFT(v.cModelo, 4) as INT) BETWEEN 2000 AND 2030
ORDER BY m.cMarcaLarga, mo.cTipo, CAST(LEFT(v.cModelo, 4) as INT)