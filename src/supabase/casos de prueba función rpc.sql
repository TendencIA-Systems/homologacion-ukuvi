-- ========================================
-- PREPARACIÓN
-- ========================================
BEGIN;

-- Limpiar tabla
TRUNCATE TABLE catalogo_homologado CASCADE;

-- ========================================
-- CASO 1: Inserción inicial - Toyota Yaris SEDAN de Qualitas
-- ========================================
SELECT public.procesar_batch_homologacion(
  jsonb_build_object('vehiculos_json', '[
    {
      "id_canonico": "a7a8fbec4e5bed8535f19ab418fe9bb83bda4eb4d26058eb0e2d2b9218069221",
      "hash_comercial": "98d9e4baceb9ed37cbe3e24512c24e62cb30b125a2d25cbb27348468340990b2",
      "string_comercial": "TOYOTA|YARIS|2014|AUTO",
      "string_tecnico": "TOYOTA|YARIS|2014|AUTO|PREMIUM|NULL|NULL|NULL|SEDAN|NULL",
      "marca": "TOYOTA",
      "modelo": "YARIS",
      "anio": 2014,
      "transmision": "AUTO",
      "version": "PREMIUM",
      "motor_config": null,
      "carroceria": "SEDAN",
      "traccion": null,
      "origen_aseguradora": "QUALITAS",
      "id_original": "Q-123456",
      "version_original": "PREMIUM SEDAN 1.5L AUTO",
      "activo": true
    }
  ]'::jsonb)
) AS resultado_caso_1;

-- Verificar
SELECT id, marca, modelo, anio, version, carroceria, 
       jsonb_object_keys(disponibilidad) as aseguradoras
FROM catalogo_homologado;

-- ========================================
-- CASO 2: Zurich agrega el mismo vehículo (mismo id_canonico)
-- ========================================
SELECT public.procesar_batch_homologacion(
  jsonb_build_object('vehiculos_json', '[
    {
      "id_canonico": "a7a8fbec4e5bed8535f19ab418fe9bb83bda4eb4d26058eb0e2d2b9218069221",
      "hash_comercial": "98d9e4baceb9ed37cbe3e24512c24e62cb30b125a2d25cbb27348468340990b2",
      "string_comercial": "TOYOTA|YARIS|2014|AUTO",
      "string_tecnico": "TOYOTA|YARIS|2014|AUTO|PREMIUM|NULL|NULL|NULL|SEDAN|NULL",
      "marca": "TOYOTA",
      "modelo": "YARIS",
      "anio": 2014,
      "transmision": "AUTO",
      "version": "PREMIUM",
      "motor_config": null,
      "carroceria": "SEDAN",
      "traccion": null,
      "origen_aseguradora": "ZURICH",
      "id_original": "Z-789",
      "version_original": "PREMIUM 1.5L SEDAN",
      "activo": true
    }
  ]'::jsonb)
) AS resultado_caso_2;

-- Verificar: debe haber solo 1 registro con 2 aseguradoras
SELECT id, marca, modelo, version, carroceria,
       jsonb_pretty(disponibilidad) as disponibilidad
FROM catalogo_homologado;

-- ========================================
-- CASO 3: HDI con HATCHBACK (conflicto, debe crear nuevo registro)
-- ========================================
SELECT public.procesar_batch_homologacion(
  jsonb_build_object('vehiculos_json', '[
    {
      "id_canonico": "61c6b5ffc413ec48ed8cc01c49fa7ff9093f5793c078b1c882e271eb77e29ca1",
      "hash_comercial": "98d9e4baceb9ed37cbe3e24512c24e62cb30b125a2d25cbb27348468340990b2",
      "string_comercial": "TOYOTA|YARIS|2014|AUTO",
      "string_tecnico": "TOYOTA|YARIS|2014|AUTO|PREMIUM|NULL|NULL|NULL|HATCHBACK|NULL",
      "marca": "TOYOTA",
      "modelo": "YARIS",
      "anio": 2014,
      "transmision": "AUTO",
      "version": "PREMIUM",
      "motor_config": null,
      "carroceria": "HATCHBACK",
      "traccion": null,
      "origen_aseguradora": "ZURICH",
      "id_original": "Z-HB-456",
      "version_original": "PREMIUM HATCHBACK 1.5L",
      "activo": true
    }
  ]'::jsonb)
) AS resultado_caso_3;

-- Verificar: deben ser 2 registros diferentes
SELECT id, marca, modelo, version, carroceria,
       array_agg(aseguradora) as aseguradoras
FROM catalogo_homologado,
     jsonb_object_keys(disponibilidad) as aseguradora
GROUP BY id, marca, modelo, version, carroceria
ORDER BY carroceria;

-- ========================================
-- CASO 4: HDI enriquece con motor_config L4
-- ========================================
SELECT public.procesar_batch_homologacion(
  jsonb_build_object('vehiculos_json', '[
    {
      "id_canonico": "c7b7b03b4ceac90769f026812e18e828272887727f9570225bb3d27208d27d75",
      "hash_comercial": "98d9e4baceb9ed37cbe3e24512c24e62cb30b125a2d25cbb27348468340990b2",
      "string_comercial": "TOYOTA|YARIS|2014|AUTO",
      "string_tecnico": "TOYOTA|YARIS|2014|AUTO|PREMIUM|L4|NULL|NULL|SEDAN|NULL",
      "marca": "TOYOTA",
      "modelo": "YARIS",
      "anio": 2014,
      "transmision": "AUTO",
      "version": "PREMIUM",
      "motor_config": "L4",
      "carroceria": "SEDAN",
      "traccion": null,
      "origen_aseguradora": "HDI",
      "id_original": "H-001",
      "version_original": "PREMIUM L4 5.0 SEDAN",
      "activo": true
    }
  ]'::jsonb)
) AS resultado_caso_4;

-- Verificar: debe enriquecer el SEDAN existente
SELECT id, marca, modelo, version, motor_config, carroceria,
       array_agg(aseguradora) as aseguradoras,
       confianza_score
FROM catalogo_homologado,
     jsonb_object_keys(disponibilidad) as aseguradora
WHERE carroceria = 'SEDAN'
GROUP BY id, marca, modelo, version, motor_config, carroceria, confianza_score;

-- ========================================
-- CASO 5: HDI con CORE (versión diferente, debe crear nuevo)
-- ========================================
SELECT public.procesar_batch_homologacion(
  jsonb_build_object('vehiculos_json', '[
    {
      "id_canonico": "1b9f61a243b7288140d0c62036f6fde94439921fd3dbc9e13922b324e33a15a4",
      "hash_comercial": "98d9e4baceb9ed37cbe3e24512c24e62cb30b125a2d25cbb27348468340990b2",
      "string_comercial": "TOYOTA|YARIS|2014|AUTO",
      "string_tecnico": "TOYOTA|YARIS|2014|AUTO|CORE|L4|NULL|NULL|SEDAN|NULL",
      "marca": "TOYOTA",
      "modelo": "YARIS",
      "anio": 2014,
      "transmision": "AUTO",
      "version": "CORE",
      "motor_config": "L4",
      "carroceria": "SEDAN",
      "traccion": null,
      "origen_aseguradora": "HDI",
      "id_original": "H-CORE-002",
      "version_original": "CORE L4 5.0 SEDAN",
      "activo": true
    }
  ]'::jsonb)
) AS resultado_caso_5;

-- Verificar: debe haber 3 registros ahora
SELECT id, marca, modelo, version, motor_config, carroceria,
       array_agg(aseguradora) as aseguradoras
FROM catalogo_homologado,
     jsonb_object_keys(disponibilidad) as aseguradora
GROUP BY id, marca, modelo, version, motor_config, carroceria
ORDER BY version, carroceria;

-- ========================================
-- CASO 6: VW GOL sin versión - enriquecimiento progresivo
-- ========================================
-- Primero Qualitas sin versión ni carrocería
SELECT public.procesar_batch_homologacion(
  jsonb_build_object('vehiculos_json', '[
    {
      "id_canonico": "3133a60717f2853b83cea28399b7be501f286b5c0fc6c1de35baf4f34a2ea341",
      "hash_comercial": "8410927aacfaa8ae8aad131e75019a64f6d4ba15aca6c31f5a497737e4051f56",
      "string_comercial": "VOLKSWAGEN|GOL|2017|AUTO",
      "string_tecnico": "VOLKSWAGEN|GOL|2017|AUTO|NULL|NULL|NULL|NULL|NULL|NULL",
      "marca": "VOLKSWAGEN",
      "modelo": "GOL",
      "anio": 2017,
      "transmision": "AUTO",
      "version": null,
      "motor_config": null,
      "carroceria": null,
      "traccion": null,
      "origen_aseguradora": "QUALITAS",
      "id_original": "Q-GOL-003",
      "version_original": "GOL 1.6 AUTO",
      "activo": true
    }
  ]'::jsonb)
) AS resultado_caso_6a;

-- Luego Zurich agrega carrocería HATCHBACK (compatible, debe enriquecer)
SELECT public.procesar_batch_homologacion(
  jsonb_build_object('vehiculos_json', '[
    {
      "id_canonico": "8410927aacfaa8ae8aad131e75019a64f6d4ba15aca6c31f5a497737e4051f56",
      "hash_comercial": "8410927aacfaa8ae8aad131e75019a64f6d4ba15aca6c31f5a497737e4051f56",
      "string_comercial": "VOLKSWAGEN|GOL|2017|AUTO",
      "string_tecnico": "VOLKSWAGEN|GOL|2017|AUTO|NULL|NULL|NULL|NULL|HATCHBACK|NULL",
      "marca": "VOLKSWAGEN",
      "modelo": "GOL",
      "anio": 2017,
      "transmision": "AUTO",
      "version": null,
      "motor_config": null,
      "carroceria": "HATCHBACK",
      "traccion": null,
      "origen_aseguradora": "ZURICH",
      "id_original": "Z-GOL-004",
      "version_original": "GOL 1.6 HATCHBACK",
      "activo": true
    }
  ]'::jsonb)
) AS resultado_caso_6b;

-- Verificar enriquecimiento
SELECT id, marca, modelo, version, carroceria,
       array_agg(aseguradora) as aseguradoras,
       confianza_score
FROM catalogo_homologado,
     jsonb_object_keys(disponibilidad) as aseguradora
WHERE marca = 'VOLKSWAGEN'
GROUP BY id, marca, modelo, version, carroceria, confianza_score;

-- ========================================
-- RESUMEN FINAL
-- ========================================
SELECT 
    'Total registros únicos' as metrica,
    COUNT(*) as valor
FROM catalogo_homologado
UNION ALL
SELECT 
    'Registros con múltiples aseguradoras',
    COUNT(*)
FROM catalogo_homologado
WHERE jsonb_array_length(jsonb_object_keys(disponibilidad)::jsonb[]) > 1
UNION ALL
SELECT 
    'Promedio confianza_score',
    ROUND(AVG(confianza_score)::numeric, 2)
FROM catalogo_homologado;

-- Ver el último resultado con warnings
SELECT resultado_caso_6b;

ROLLBACK; -- O COMMIT si quieres guardar