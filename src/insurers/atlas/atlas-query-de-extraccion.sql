-- =====================================================
-- QUERY DE EXTRACCIÓN PARA ATLAS
-- Activos: ~31,229 registros (confirmado)
-- Transmisión: 1=MANUAL, 2=AUTO, 0=NULL
-- CRÍTICO: Incluir año y todas las llaves en JOINs
-- =====================================================
SELECT 
    'ATLAS' as origen_aseguradora,
    CAST(v.IdVersion as VARCHAR(50)) as id_original,
    UPPER(LTRIM(RTRIM(m.NomMarca))) as marca,
    UPPER(LTRIM(RTRIM(s.Descripcion))) as modelo,
    v.Anio as anio,
    v.Descripcion as version_original,
    CASE 
        WHEN v.Transmision = 2 THEN 'AUTO'
        WHEN v.Transmision = 1 THEN 'MANUAL'
        ELSE NULL
    END as transmision,
    CAST(v.Activo as INT) as activo
FROM atlas.Vehiculo_Version v
INNER JOIN atlas.Marca m ON v.IdMarca = m.IdMarca
    AND v.Anio = m.Anio
    AND v.Categoria = m.Categoria
    AND v.Liga = m.Liga
INNER JOIN atlas.SubTipo_Modelo s ON v.IdSubTipo = s.IdSubTipo
    AND v.Anio = s.Anio
    AND v.IdMarca = s.IdMarca
    AND v.Categoria = s.Categoria
    AND v.Liga = s.Liga
WHERE v.Activo = 1
    AND v.Anio BETWEEN 2000 AND 2030
ORDER BY m.NomMarca, s.Descripcion, v.Anio;
