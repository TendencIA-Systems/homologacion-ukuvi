-- =====================================================
-- QUERY DE EXTRACCIÓN PARA GNP
-- Registros esperados: ~39,821 (expandidos por años)
-- Versiones únicas: 11,674
-- Transmisión: 1=MANUAL, 2=AUTO, 0=NULL
-- NOTA: Una versión puede tener múltiples años
-- =====================================================
SELECT 
    'GNP' as origen_aseguradora,
    CAST(v.IdVersion as VARCHAR(50)) + 
        CASE 
            WHEN m.Clave IS NOT NULL THEN '_' + m.Clave 
            ELSE '' 
        END as id_original,
    UPPER(LTRIM(RTRIM(a.Armadora))) as marca,
    UPPER(LTRIM(RTRIM(c.Carroceria))) as modelo,
    TRY_CAST(m.Clave as INT) as anio,
    v.Version as version_original,
    CASE 
        WHEN v.Transmision = 2 THEN 'AUTO'
        WHEN v.Transmision = 1 THEN 'MANUAL'
        ELSE NULL
    END as transmision,
    1 as activo
FROM gnp.Version v
LEFT JOIN gnp.Armadora a ON v.ClaveArmadora = a.Clave
LEFT JOIN gnp.Carroceria c ON v.ClaveCarroceria = c.Clave 
    AND v.ClaveArmadora = c.ClaveArmadora
LEFT JOIN gnp.Modelo m ON m.ClaveCarroceria = v.ClaveCarroceria
    AND m.ClaveArmadora = v.ClaveArmadora
    AND m.ClaveVersion = v.Clave
    AND TRY_CAST(m.Clave as INT) BETWEEN 2000 AND 2030
WHERE v.IdVersion IS NOT NULL
ORDER BY v.IdVersion, m.Clave;