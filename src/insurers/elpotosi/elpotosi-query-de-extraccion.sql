-- =====================================================
-- QUERY DE EXTRACCIÓN PARA EL POTOSÍ
-- Activos: 23,040 registros (confirmado exacto)
-- Transmisión: 1=MANUAL, 2=AUTO, 0=NULL
-- =====================================================
SELECT 
    'ELPOTOSI' as origen_aseguradora,
    CAST(v.IdVersion as VARCHAR(50)) as id_original,
    UPPER(LTRIM(RTRIM(ma.Descripcion))) as marca,
    UPPER(LTRIM(RTRIM(mo.Descripcion))) as modelo,
    v.Anio as anio,
    COALESCE(v.VersionCorta, v.Descripcion) as version_original,
    CASE 
        WHEN v.Transmision = 2 THEN 'AUTO'
        WHEN v.Transmision = 1 THEN 'MANUAL'
        ELSE NULL
    END as transmision,
    CAST(v.Activo as INT) as activo
FROM elpotosi.Version v
INNER JOIN elpotosi.Marca ma ON v.IdMarca = ma.IdMarca
    AND v.Anio = ma.Anio
    AND v.TipoVehiculo = ma.TipoVehiculo
INNER JOIN elpotosi.Modelo mo ON v.IdModelo = mo.IdModelo
    AND v.IdMarca = mo.IdMarca
    AND v.Anio = mo.Anio
    AND v.TipoVehiculo = mo.TipoVehiculo
WHERE v.Activo = 1
    AND v.Anio BETWEEN 2000 AND 2030
ORDER BY ma.Descripcion, mo.Descripcion, v.Anio;