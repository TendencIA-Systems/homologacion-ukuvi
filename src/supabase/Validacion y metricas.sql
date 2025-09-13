-- Query para validar el nivel de homologación alcanzado
WITH metricas AS (
    SELECT 
        COUNT(*) as total_vehiculos_canonicos,
        COUNT(*) FILTER (WHERE array_length(aseguradoras_activas, 1) >= 2) as con_2_o_mas_aseguradoras,
        COUNT(*) FILTER (WHERE array_length(aseguradoras_activas, 1) >= 3) as con_3_o_mas_aseguradoras,
        AVG(array_length(aseguradoras_activas, 1)) as promedio_aseguradoras,
        MAX(array_length(aseguradoras_activas, 1)) as max_aseguradoras
    FROM vehiculos_maestro
)
SELECT 
    total_vehiculos_canonicos,
    con_2_o_mas_aseguradoras,
    ROUND(100.0 * con_2_o_mas_aseguradoras / total_vehiculos_canonicos, 2) as porcentaje_homologacion_2,
    con_3_o_mas_aseguradoras,
    ROUND(100.0 * con_3_o_mas_aseguradoras / total_vehiculos_canonicos, 2) as porcentaje_homologacion_3,
    ROUND(promedio_aseguradoras::numeric, 2) as promedio_aseguradoras,
    max_aseguradoras
FROM metricas;