-- =====================================================
-- QUERY DE EXTRACCIÓN PARA BX
-- Registros esperados: 39,292 (confirmado)
-- Transmisión: 2=AUTO, 1=MANUAL, 0=NULL
-- CRÍTICO: Usar llave compuesta idMarca en SubMarca
-- =====================================================
SELECT 
    'BX' as origen_aseguradora,
    CAST(v.ID as VARCHAR(50)) as id_original,
    UPPER(LTRIM(RTRIM(m.descMarca))) as marca,
    UPPER(LTRIM(RTRIM(s.descSubMarca))) as modelo,
    v.idModelo as anio,
    v.descVersion as version_original,
    CASE 
        WHEN v.Transmision = 2 THEN 'AUTO'
        WHEN v.Transmision = 1 THEN 'MANUAL'
        ELSE NULL
    END as transmision,
    CAST(v.Activa as INT) as activo
FROM bx.Version v
INNER JOIN bx.Marca m ON v.idMarca = m.idMarca
INNER JOIN bx.SubMarca s ON v.idSubMarca = s.idSubMarca 
    AND v.idMarca = s.idMarca  -- CRÍTICO: Llave compuesta
WHERE v.idModelo BETWEEN 2000 AND 2030
    AND v.Activa = 1
ORDER BY m.descMarca, s.descSubMarca, v.idModelo;