-- =====================================================
-- QUERY DE EXTRACCIÓN PARA CHUBB
-- TODOS los registros (no tiene campo activo explícito)
-- ESTRUCTURA ATÍPICA: NTipo contiene el modelo real
-- =====================================================

SELECT DISTINCT
    'CHUBB' as origen_aseguradora,
    v.ID as id_original,
    m.Descripcion as marca,
    t.Descripcion as modelo, -- NTipo contiene el modelo
    v.Modelo as anio,
    v.VersionCorta as version_original,
    CASE 
        WHEN v.TipoVehiculo = 'AUT' THEN 'AUTO'
        WHEN v.TipoVehiculo = 'STD' THEN 'MANUAL'
        ELSE NULL
    END as transmision,
    1 as activo -- Todos se consideran activos
FROM chubb.NVehiculo v
INNER JOIN chubb.NTipo t ON v.TipoID = t.ID
INNER JOIN chubb.NMarca m ON t.MarcaID = m.ID
WHERE 
    v.Modelo BETWEEN 2000 AND 2030
ORDER BY m.Descripcion, t.Descripcion, v.Modelo