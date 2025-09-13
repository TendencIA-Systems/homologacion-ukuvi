-- =====================================================
-- QUERY DE EXTRACCIÓN PARA MAPFRE
-- TODOS los registros (no tiene campo activo)
-- Eliminar duplicados masivos con GROUP BY
-- Total esperado: ~31,476 registros únicos
-- =====================================================

SELECT 
    'MAPFRE' as origen_aseguradora,
    mo.CodModelo as id_original,
    m.NomMarca as marca,
    -- NomModelo contiene modelo + versión mezclados
    mo.NomModelo as modelo_version_completo,
    mo.AnioFabrica as anio,
    mo.VersionCorta as version_corta,
    CASE 
        WHEN mo.Transmision = 1 THEN 'MANUAL'
        WHEN mo.Transmision = 2 THEN 'AUTO'
        ELSE NULL  -- 30% sin transmisión especificada
    END as transmision,
    1 as activo  -- Todos se consideran activos
FROM mapfre.Modelo mo
INNER JOIN mapfre.Marca m ON mo.CodMarca = m.CodMarca
WHERE 
    mo.AnioFabrica BETWEEN 2000 AND 2030
GROUP BY 
    mo.CodModelo,
    m.NomMarca, 
    mo.NomModelo, 
    mo.AnioFabrica, 
    mo.VersionCorta, 
    mo.Transmision
ORDER BY m.NomMarca, mo.NomModelo, mo.AnioFabrica