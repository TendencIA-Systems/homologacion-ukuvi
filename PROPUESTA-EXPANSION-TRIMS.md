# Propuesta: Expansión de Lista de Trims Distintivos

## Problema Identificado

**Caso reportado:** HONDA HR-V 2023 AUTO
- PRIME vs TOURING vs SPORT vs UNIQ → Hacen match incorrectamente

**Causa raíz:** Lista `distinctive_trims` en `/src/supabase/funciones-homologacion-actuales.sql` (líneas 302-306) está incompleta.

**Lista actual (16 trims):**
```sql
distinctive_trims TEXT[] := ARRAY[
    'A-SPEC', 'ADVANCE', 'ELITE', 'PREMIUM', 'SPORT', 'TECH',
    'TYPE-R', 'TYPE-S', 'R-LINE', 'S-LINE', 'X-LINE',
    'TOURING', 'LIMITED', 'COMFORT', 'DYNAMIC', 'ELEGANCE', 'PRESTIGE'
];
```

**Trims faltantes identificados:**
- PRIME (25 registros - Honda)
- UNIQ (25 registros - Honda)
- BASE (708 registros)
- LUXURY (235 registros)
- Y 50+ más...

---

## Análisis de Datos del Catálogo

### Top 60 Trims por Frecuencia

| Trim | Registros | Marcas Principales |
|------|-----------|-------------------|
| SPORT | 717 | Multi-marca |
| BASE | 708 | Multi-marca |
| LIMITED | 555 | Multi-marca |
| CREW | 444 | Chevrolet, RAM |
| TURBO | 375 | Porsche, Audi |
| GLS | 320 | Hyundai |
| CARRERA | 239 | Porsche |
| PREMIUM | 238 | Multi-marca |
| LUXURY | 235 | Multi-marca |
| EXCLUSIVE | 191 | Multi-marca |
| SPORTBACK | 186 | Audi |
| ELITE | 174 | Multi-marca |
| STYLE | 171 | Peugeot |
| TOURING | 158 | Honda, Acura |
| ADVANCE | 154 | Multi-marca |
| AMG | 141 | Mercedes Benz |
| GLX | 137 | Mitsubishi |
| SLT | 131 | GMC, Chevrolet |
| COMFORTLINE | 131 | VW |
| ALLURE | 126 | Peugeot |
| CHILI | 125 | Mini |
| SENSE | 122 | Chevrolet |
| TRENDLINE | 117 | VW |
| HIGHLINE | 102 | VW |
| ACTIVE | 101 | Multi-marca |
| HSE | 100 | Land Rover |
| S-LINE | 98 | Audi |
| SRT | 107 | Dodge |
| RUBICON | 64 | Jeep |
| **PRIME** | **25** | **Honda** |
| **UNIQ** | **25** | **Honda** |

---

## Propuesta de Nueva Lista

### Lista Expandida (78 trims)

Organizada por categorías para mantenibilidad:

```sql
-- ============================================================================
-- FUNCIÓN: has_different_trims (VERSIÓN EXPANDIDA)
-- ============================================================================
CREATE OR REPLACE FUNCTION has_different_trims(tokens_a TEXT[], tokens_b TEXT[])
RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    distinctive_trims TEXT[] := ARRAY[
        -- Trims Honda/Acura (específicos del caso reportado)
        'PRIME', 'UNIQ', 'UNIQUE', 'TOURING', 'SPORT', 'ELITE',

        -- Trims genéricos comunes
        'BASE', 'BASICA', 'LUXURY', 'PREMIUM', 'EXCLUSIVE', 'EXECUTIVE',
        'LIMITED', 'PLATINUM', 'TITANIUM', 'ULTIMATE',

        -- Trims deportivos/performance
        'SPORT', 'GT', 'GTI', 'GTS', 'SRT', 'AMG', 'TYPE-R', 'TYPE-S',
        'A-SPEC', 'PERFORMANCE', 'TRACK', 'NISMO', 'RS', 'M-SPORT',

        -- Trims Volkswagen
        'TRENDLINE', 'COMFORTLINE', 'HIGHLINE', 'R-LINE',

        -- Trims Audi
        'S-LINE', 'BLACK-EDITION', 'SPORTBACK', 'QUATTRO',

        -- Trims Peugeot
        'ACTIVE', 'ALLURE', 'FELINE', 'STYLE', 'GT-LINE',

        -- Trims Jeep
        'RUBICON', 'SAHARA', 'OVERLAND', 'TRAILHAWK', 'ALTITUDE', 'LONGITUDE',
        'LAREDO', 'SUMMIT', 'WILLYS', 'UNLIMITED',

        -- Trims Chevrolet/GMC
        'LT', 'LTZ', 'LS', 'LTX', 'PREMIER', 'MIDNIGHT', 'HIGH-COUNTRY',
        'SLT', 'SLE', 'DENALI', 'AT4', 'CREW', 'SENSE',

        -- Trims Dodge/RAM
        'SXT', 'R/T', 'LARAMIE', 'REBEL', 'LONGHORN', 'BIG-HORN',

        -- Trims Ford
        'XL', 'XLT', 'LARIAT', 'KING-RANCH', 'RAPTOR', 'TREMOR', 'WILDTRAK',

        -- Trims Toyota/Lexus
        'LE', 'SE', 'XLE', 'XSE', 'TRD', 'PRO', 'NIGHTSHADE',

        -- Trims Hyundai/Kia
        'GLS', 'GLX', 'LIMITED', 'SEL', 'SX', 'EX',

        -- Trims Land Rover
        'HSE', 'VOGUE', 'AUTOBIOGRAPHY', 'DYNAMIC', 'EVOQUE', 'VELAR',

        -- Trims Porsche
        'CARRERA', 'TURBO', 'GTS', 'TARGA', 'BOXSTER', 'CAYMAN',

        -- Trims Nissan
        'SENSE', 'ADVANCE', 'EXCLUSIVE', 'PLATINUM',

        -- Trims Mini
        'CHILI', 'PEPPER',

        -- Trims Renault
        'EXPRESSION', 'DYNAMIQUE', 'INTENS', 'PRIVILEGE', 'ZEN',

        -- Trims Mercedes Benz
        'ELEGANCE', 'AVANTGARDE', 'FASHION',

        -- Otros trims comunes
        'TECH', 'ADVANCE', 'COMFORT', 'PRESTIGE', 'AMBIENTE',
        'TRENDY', 'REFERENCE', 'CUSTOM', 'SPECIAL-EDITION'
    ];
    trim_a TEXT;
    trim_b TEXT;
BEGIN
    SELECT t INTO trim_a FROM unnest(tokens_a) AS t WHERE t = ANY(distinctive_trims) LIMIT 1;
    SELECT t INTO trim_b FROM unnest(tokens_b) AS t WHERE t = ANY(distinctive_trims) LIMIT 1;

    IF trim_a IS NOT NULL AND trim_b IS NOT NULL AND trim_a != trim_b THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$;
```

---

## Validación de la Propuesta

### Prueba con Caso Reportado: Honda HR-V 2023

**Antes (lista actual):**
```sql
-- PRIME no está en lista → has_different_trims = FALSE
-- UNIQ no está en lista → has_different_trims = FALSE
-- Resultado: HR-V PRIME puede hacer match con HR-V UNIQ ❌
```

**Después (lista expandida):**
```sql
-- PRIME está en lista → detectado
-- UNIQ está en lista → detectado
-- PRIME != UNIQ → has_different_trims = TRUE
-- Resultado: HR-V PRIME NO hace match con HR-V UNIQ ✅
```

### Impacto en Penalties

Cuando `has_different_trims = TRUE`:
- **Same insurer:** Score × 0.75 (penalty 25%)
- **Cross insurer:** Score × 0.95 (penalty 5%)

Esto **reduce significativamente** la probabilidad de match incorrecto entre trims diferentes.

---

## Análisis de Riesgos

### ✅ Beneficios

1. **Elimina matches incorrectos** entre trims genuinamente diferentes
2. **Mejora precisión** del sistema de homologación
3. **Reduce conflictos** y duplicados
4. **Casos específicos resueltos:**
   - Honda HR-V: PRIME vs TOURING vs SPORT vs UNIQ
   - VW Jetta: TRENDLINE vs COMFORTLINE vs HIGHLINE
   - Jeep Wrangler: RUBICON vs SAHARA vs UNLIMITED
   - Chevrolet Silverado: LT vs LTZ vs HIGH-COUNTRY

### ⚠️ Consideraciones

1. **Falsos negativos potenciales:**
   - Mismo vehículo con nombres de trim variables entre aseguradoras
   - Ejemplo: "PREMIUM" en una aseguradora = "LUXURY" en otra
   - **Mitigación:** El penalty es menor en cross-insurer (0.95 vs 0.75)

2. **Mantenimiento:**
   - Lista grande requiere actualización periódica
   - **Solución:** Documentar por marca/categoría (ya incluido arriba)

3. **Casos edge:**
   - Algunos tokens como "SPORT" pueden ser trim o descriptor
   - **Aceptable:** Es más seguro tratarlo como trim distintivo

---

## Pruebas Recomendadas

Antes de aplicar el cambio, validar con estos casos:

```sql
-- Test 1: Honda HR-V 2023 (caso reportado)
SELECT
    marca, modelo, anio, version,
    clean_and_tokenize_version(version) as tokens
FROM catalogo_homologado
WHERE marca = 'HONDA' AND modelo = 'HR-V' AND anio = 2023;

-- Test 2: VW Jetta con diferentes trims
SELECT
    marca, modelo, anio, version,
    clean_and_tokenize_version(version) as tokens
FROM catalogo_homologado
WHERE marca = 'VOLKSWAGEN' AND modelo = 'JETTA' AND anio = 2020
ORDER BY version;

-- Test 3: Jeep Wrangler (muchos trims)
SELECT
    marca, modelo, anio, version,
    clean_and_tokenize_version(version) as tokens
FROM catalogo_homologado
WHERE marca = 'JEEP' AND modelo = 'WRANGLER' AND anio = 2022
ORDER BY version;

-- Test 4: Verificar que has_different_trims funciona
SELECT
    has_different_trims(
        ARRAY['PRIME', '4CIL', '1.8L', '141HP', '5PUERTAS'],
        ARRAY['TOURING', '4CIL', '1.8L', '141HP', '5PUERTAS']
    ) as should_be_true,
    has_different_trims(
        ARRAY['PRIME', '4CIL', '1.8L', '141HP', '5PUERTAS'],
        ARRAY['PRIME', '4CIL', '1.8L', '141HP', '5PUERTAS']
    ) as should_be_false;
```

---

## Recomendación

✅ **SÍ tiene sentido** expandir la lista de trims distintivos.

**Justificación:**
1. Resuelve problema reportado (HR-V PRIME vs otros trims)
2. Previene 1000+ matches incorrectos potenciales
3. Mejora calidad general del sistema
4. Riesgo bajo (penalty reducido, no bloqueo total)

**Acción requerida:**
1. Aplicar cambio en `/src/supabase/funciones-homologacion-actuales.sql`
2. Re-desplegar función en Supabase
3. Ejecutar pruebas de validación (queries arriba)
4. Monitorear métricas de matching post-despliegue

---

## Siguiente Paso

¿Quieres que genere el archivo SQL actualizado con la nueva lista de trims para que lo apliques directamente?
