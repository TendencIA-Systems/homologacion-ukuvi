# Guía Técnica - Correcciones para Producción
## Sistema de Homologación UKUVI

**Audiencia:** Equipo de desarrollo técnico
**Objetivo:** Guía paso a paso para corregir problemas identificados

---

## Problema Principal Identificado

### 🎯 Causa Raíz

El alto porcentaje de nulls (59.5% promedio) **NO se debe a problemas en el código de normalización**, sino a **fallas en el proceso de matching/homologación** en la función `procesar_batch_vehiculos()`.

**Evidencia:**
- ✅ Código de normalización correctamente implementado en todas las aseguradoras
- ✅ Datos de origen existen para todas las aseguradoras
- ❌ Vehículos normalizados de AXA/ATLAS no hacen match con catálogo de referencia

---

## Fase 1: Diagnóstico Detallado

### 1.1 Auditar Función de Homologación

**Archivo:** `src/supabase/funciones-homologacion.sql`
**Función:** `procesar_batch_vehiculos(vehiculos_json JSONB)`

#### Pasos de auditoría:

```sql
-- 1. Agregar logging detallado a la función
-- Insertar después de la etapa de matching:

RAISE NOTICE 'Vehículo: % % % % - Hash: %',
    v_marca, v_modelo, v_anio, v_transmision, v_hash_comercial;

RAISE NOTICE 'Candidatos encontrados con mismo hash: %',
    (SELECT COUNT(*) FROM catalogo_homologado WHERE hash_comercial = v_hash_comercial);

RAISE NOTICE 'Score de mejor match: % (umbral: %)',
    v_best_score, v_threshold;

-- 2. Agregar tabla temporal para debug
CREATE TEMP TABLE IF NOT EXISTS matching_debug (
    id_original TEXT,
    marca TEXT,
    modelo TEXT,
    anio INTEGER,
    hash_comercial TEXT,
    candidates_found INTEGER,
    best_score NUMERIC,
    threshold_used NUMERIC,
    matched BOOLEAN,
    reason TEXT
);
```

#### Ejecutar con muestra de AXA:

```sql
-- Tomar 100 vehículos de AXA que tienen null
SELECT id_original, marca, modelo, anio, version_original
FROM catalogo_homologado
WHERE aseguradora_origen = 'AXA'
AND disponibilidad->>'axa' IS NULL
LIMIT 100;

-- Intentar re-procesar estos vehículos con logging activado
-- y analizar los logs
```

### 1.2 Analizar Umbrales de Similitud

**Ubicación actual:** `procesar_batch_vehiculos()` - línea ~200-250

```sql
-- Umbrales actuales (confirmar):
v_threshold_same_insurer := 0.92;  -- Para misma aseguradora
v_threshold_cross_insurer := 0.50;  -- Para aseguradoras diferentes
```

**Experimento sugerido:**

```sql
-- Crear función de prueba con umbrales ajustables
CREATE OR REPLACE FUNCTION test_matching_thresholds(
    p_threshold_same NUMERIC DEFAULT 0.92,
    p_threshold_cross NUMERIC DEFAULT 0.50,
    p_sample_size INTEGER DEFAULT 100
)
RETURNS TABLE (
    threshold_same NUMERIC,
    threshold_cross NUMERIC,
    matches_found INTEGER,
    avg_score NUMERIC,
    nulls_remaining INTEGER
) AS $$
BEGIN
    -- Implementar lógica de prueba
    -- Retornar métricas para diferentes umbrales
END;
$$ LANGUAGE plpgsql;

-- Probar diferentes combinaciones:
SELECT * FROM test_matching_thresholds(0.90, 0.45, 100); -- Más permisivo
SELECT * FROM test_matching_thresholds(0.85, 0.40, 100); -- Aún más permisivo
SELECT * FROM test_matching_thresholds(0.80, 0.35, 100); -- Muy permisivo
```

### 1.3 Auditar Generación de hash_comercial

**Problema potencial:** Si `hash_comercial` no se genera consistentemente, vehículos idénticos tendrán hashes diferentes y nunca harán match.

```javascript
// En código de normalización (AXA, ATLAS, etc.):
function createCommercialHash(vehicle) {
  const normalizedModelo = normalizeModelo(vehicle.marca, vehicle.modelo);

  const key = [
    vehicle.marca || "",
    normalizedModelo || "",
    vehicle.anio ? vehicle.anio.toString() : "",
    vehicle.transmision || "",
  ]
    .join("|")
    .toLowerCase()
    .trim();

  console.log(`[DEBUG] Hash key: ${key}`); // Agregar logging

  return crypto.createHash("sha256").update(key).digest("hex");
}
```

**Validación:**

```sql
-- Comparar hashes generados por diferentes aseguradoras
-- para el mismo vehículo (ej: HONDA HR-V 2020 AUTO)

SELECT
    aseguradora_origen,
    hash_comercial,
    marca,
    modelo,
    anio,
    transmision,
    version
FROM catalogo_homologado
WHERE marca = 'HONDA'
  AND modelo = 'HR-V'
  AND anio = 2020
  AND transmision = 'AUTO'
ORDER BY aseguradora_origen;

-- Resultado esperado: Todos deben tener el MISMO hash_comercial
-- Si son diferentes, hay problema en normalización de marca/modelo
```

---

## Fase 2: Implementación de Correcciones

### 2.1 Opción A: Ajustar Umbrales (Solución Rápida)

Si el diagnóstico muestra que los vehículos tienen scores de similitud entre 0.70-0.90:

```sql
-- Archivo: src/supabase/funciones-homologacion.sql
-- Buscar y reemplazar:

-- ANTES:
v_threshold_same_insurer := 0.92;
v_threshold_cross_insurer := 0.50;

-- DESPUÉS:
v_threshold_same_insurer := 0.85;  -- Reducir de 0.92 a 0.85
v_threshold_cross_insurer := 0.45;  -- Reducir de 0.50 a 0.45
```

**Testing:**
```bash
# 1. Aplicar cambio en Supabase
psql $DATABASE_URL < src/supabase/funciones-homologacion.sql

# 2. Re-procesar muestra de AXA
# (ejecutar workflow de n8n para AXA con 100 registros)

# 3. Validar mejora
SELECT COUNT(*) as nulls_before FROM antes_cambio WHERE axa_version IS NULL;
SELECT COUNT(*) as nulls_after FROM despues_cambio WHERE axa_version IS NULL;
-- Debe haber reducción significativa
```

### 2.2 Opción B: Mejorar Algoritmo de Matching (Solución Robusta)

Si los umbrales no son suficientes, mejorar el algoritmo:

```sql
-- Agregar matching fuzzy para marca/modelo
-- antes de calcular token overlap

CREATE OR REPLACE FUNCTION levenshtein_ratio(s1 TEXT, s2 TEXT)
RETURNS NUMERIC AS $$
BEGIN
    RETURN 1.0 - (levenshtein(s1, s2)::NUMERIC / GREATEST(length(s1), length(s2)));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Modificar procesar_batch_vehiculos para considerar:
-- 1. Exact hash match (actual)
-- 2. Si no match, buscar con Levenshtein en marca/modelo
-- 3. Si no match, usar token overlap con threshold reducido
-- 4. Si no match, crear nuevo registro
```

Implementación:

```sql
-- Dentro de procesar_batch_vehiculos, después de buscar por hash exacto:

IF v_matched_id IS NULL THEN
    -- Buscar con fuzzy matching en marca/modelo
    SELECT id_vehiculo INTO v_matched_id
    FROM catalogo_homologado
    WHERE anio = v_anio
      AND transmision = v_transmision
      AND levenshtein_ratio(marca, v_marca) >= 0.90
      AND levenshtein_ratio(modelo, v_modelo) >= 0.90
    ORDER BY
        (tokenize_version(version) && tokenize_version(v_version_limpia))::INTEGER DESC
    LIMIT 1;

    IF v_matched_id IS NOT NULL THEN
        RAISE NOTICE 'Match encontrado por fuzzy matching: %', v_matched_id;
    END IF;
END IF;
```

### 2.3 Opción C: Matching por Etapas (Solución Híbrida)

```sql
-- Stage 1: Exact hash + high token overlap (threshold 0.92)
-- Stage 2: Exact hash + medium token overlap (threshold 0.75)
-- Stage 3: Fuzzy marca/modelo + low token overlap (threshold 0.60)
-- Stage 4: Create new record

CREATE OR REPLACE FUNCTION match_vehicle_staged(
    p_hash_comercial TEXT,
    p_marca TEXT,
    p_modelo TEXT,
    p_anio INTEGER,
    p_transmision TEXT,
    p_version_tokens TEXT[]
)
RETURNS INTEGER AS $$
DECLARE
    v_matched_id INTEGER;
    v_score NUMERIC;
BEGIN
    -- Stage 1: Exact + High
    SELECT id_vehiculo, token_overlap_score INTO v_matched_id, v_score
    FROM catalogo_homologado
    WHERE hash_comercial = p_hash_comercial
      AND token_overlap_score(version_tokens_array, p_version_tokens) >= 0.92
    ORDER BY token_overlap_score DESC
    LIMIT 1;

    IF v_matched_id IS NOT NULL THEN
        RAISE NOTICE '[Stage 1] Match found with score: %', v_score;
        RETURN v_matched_id;
    END IF;

    -- Stage 2: Exact + Medium
    SELECT id_vehiculo, token_overlap_score INTO v_matched_id, v_score
    FROM catalogo_homologado
    WHERE hash_comercial = p_hash_comercial
      AND token_overlap_score(version_tokens_array, p_version_tokens) >= 0.75
    ORDER BY token_overlap_score DESC
    LIMIT 1;

    IF v_matched_id IS NOT NULL THEN
        RAISE NOTICE '[Stage 2] Match found with score: %', v_score;
        RETURN v_matched_id;
    END IF;

    -- Stage 3: Fuzzy + Low
    SELECT id_vehiculo, token_overlap_score INTO v_matched_id, v_score
    FROM catalogo_homologado
    WHERE anio = p_anio
      AND transmision = p_transmision
      AND levenshtein_ratio(marca, p_marca) >= 0.90
      AND levenshtein_ratio(modelo, p_modelo) >= 0.90
      AND token_overlap_score(version_tokens_array, p_version_tokens) >= 0.60
    ORDER BY token_overlap_score DESC
    LIMIT 1;

    IF v_matched_id IS NOT NULL THEN
        RAISE NOTICE '[Stage 3] Match found with score: %', v_score;
        RETURN v_matched_id;
    END IF;

    -- Stage 4: No match
    RAISE NOTICE '[Stage 4] No match found - will create new record';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

---

## Fase 3: Validación y Testing

### 3.1 Suite de Tests de Regresión

```sql
-- Crear tabla de vehículos de referencia del cliente
CREATE TABLE validation_vehicles (
    id SERIAL PRIMARY KEY,
    marca TEXT,
    modelo TEXT,
    anio INTEGER,
    transmision TEXT,
    expected_min_insurers INTEGER, -- Mínimo de aseguradoras esperadas
    client_reported BOOLEAN DEFAULT true
);

-- Insertar vehículos del cliente
INSERT INTO validation_vehicles (marca, modelo, anio, transmision, expected_min_insurers) VALUES
('HONDA', 'HR-V', 2020, 'AUTO', 8),
('MAZDA', 'CX-5', 2020, 'AUTO', 4),
('NISSAN', 'VERSA', 2020, 'AUTO', 10),
('VOLKSWAGEN', 'JETTA', 2020, 'AUTO', 6);

-- Función de validación
CREATE OR REPLACE FUNCTION validate_quality()
RETURNS TABLE (
    vehicle TEXT,
    insurers_found INTEGER,
    expected INTEGER,
    status TEXT,
    nulls_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.marca || ' ' || v.modelo || ' ' || v.anio::TEXT as vehicle,
        COUNT(DISTINCT
            CASE WHEN c.disponibilidad ? 'ana' AND (c.disponibilidad->>'ana')::JSONB->>'version' IS NOT NULL THEN 'ana' END ||
            CASE WHEN c.disponibilidad ? 'atlas' AND (c.disponibilidad->>'atlas')::JSONB->>'version' IS NOT NULL THEN 'atlas' END
            -- ... repetir para todas las aseguradoras
        )::INTEGER as insurers_found,
        v.expected_min_insurers as expected,
        CASE
            WHEN COUNT(*) >= v.expected_min_insurers THEN '✅ PASS'
            ELSE '❌ FAIL'
        END as status,
        COUNT(CASE WHEN disponibilidad IS NULL THEN 1 END)::INTEGER as nulls_count
    FROM validation_vehicles v
    LEFT JOIN catalogo_homologado c ON
        c.marca = v.marca AND
        c.modelo = v.modelo AND
        c.anio = v.anio AND
        c.transmision = v.transmision
    GROUP BY v.id, v.marca, v.modelo, v.anio, v.expected_min_insurers;
END;
$$ LANGUAGE plpgsql;

-- Ejecutar validación
SELECT * FROM validate_quality();
```

### 3.2 Script de Validación Automática

```bash
#!/bin/bash
# scripts/validate_before_deploy.sh

set -e

echo "🔍 Ejecutando validación pre-deploy..."

# 1. Validar métricas de calidad
echo "📊 Métricas de calidad:"
./scripts/quick_quality_check.sh

# 2. Validar vehículos del cliente
echo ""
echo "🚗 Vehículos del cliente:"
psql $DATABASE_URL <<SQL
SELECT * FROM validate_quality();
SQL

# 3. Verificar que no hay regresiones
echo ""
echo "📈 Verificando regresiones:"
psql $DATABASE_URL <<SQL
-- Comparar con snapshot anterior
SELECT
    CASE WHEN current_nulls > previous_nulls THEN '❌ REGRESIÓN' ELSE '✅ OK' END as status,
    aseguradora,
    current_nulls,
    previous_nulls,
    current_nulls - previous_nulls as diff
FROM quality_snapshots
WHERE snapshot_date = CURRENT_DATE;
SQL

# 4. Decisión final
echo ""
echo "================================"
AVG_NULLS=$(psql $DATABASE_URL -t -c "SELECT AVG(null_percentage) FROM insurer_quality_current;")

if (( $(echo "$AVG_NULLS < 40" | bc -l) )); then
    echo "✅ APROBADO PARA DEPLOY"
    exit 0
else
    echo "❌ NO APROBADO - Promedio de nulls: $AVG_NULLS%"
    exit 1
fi
```

---

## Fase 4: Deploy y Monitoreo

### 4.1 Proceso de Deploy

```bash
# 1. Backup de datos actuales
pg_dump $DATABASE_URL -t catalogo_homologado > backup_pre_deploy_$(date +%Y%m%d).sql

# 2. Aplicar cambios en función de homologación
psql $DATABASE_URL < src/supabase/funciones-homologacion-v2.sql

# 3. Re-procesar catálogo completo
# (ejecutar todos los workflows de n8n en orden)

# 4. Validar calidad
./scripts/validate_before_deploy.sh

# 5. Si falla, rollback
if [ $? -ne 0 ]; then
    echo "❌ Validación falló - haciendo rollback"
    psql $DATABASE_URL < backup_pre_deploy_$(date +%Y%m%d).sql
    exit 1
fi

# 6. Deploy exitoso
echo "✅ Deploy completado exitosamente"
```

### 4.2 Monitoreo Post-Deploy

```sql
-- Crear vista de monitoreo
CREATE OR REPLACE VIEW quality_monitor AS
SELECT
    CURRENT_DATE as check_date,
    CURRENT_TIMESTAMP as check_time,
    COUNT(*) as total_vehicles,
    AVG(CASE WHEN disponibilidad IS NOT NULL THEN
        jsonb_array_length(disponibilidad) ELSE 0 END) as avg_insurers_per_vehicle,
    COUNT(CASE WHEN disponibilidad IS NULL THEN 1 END) as orphan_vehicles,
    (SELECT AVG(null_pct) FROM (
        SELECT
            COUNT(CASE WHEN (disponibilidad->>'ana')::JSONB IS NULL THEN 1 END)::NUMERIC /
            COUNT(*)::NUMERIC * 100 as null_pct
        FROM catalogo_homologado
    ) sub) as avg_null_percentage
FROM catalogo_homologado;

-- Query de monitoreo diario
SELECT * FROM quality_monitor;

-- Alertas
DO $$
DECLARE
    v_avg_nulls NUMERIC;
BEGIN
    SELECT avg_null_percentage INTO v_avg_nulls FROM quality_monitor;

    IF v_avg_nulls > 50 THEN
        RAISE WARNING '🚨 ALERTA: Promedio de nulls es %% - revisar inmediatamente', v_avg_nulls;
    END IF;
END;
$$;
```

---

## Checklist de Correcciones

### Pre-Deploy
- [ ] Diagnóstico completado (Fase 1)
- [ ] Solución implementada (Fase 2)
- [ ] Tests de regresión pasando (Fase 3)
- [ ] Backup de producción creado
- [ ] Validación manual de vehículos del cliente
- [ ] Aprobación de stakeholders

### Durante Deploy
- [ ] Aplicar cambios en Supabase
- [ ] Re-procesar workflows de n8n
- [ ] Monitorear logs en tiempo real
- [ ] Validar métricas post-procesamiento

### Post-Deploy
- [ ] Verificar quality_monitor
- [ ] Validar vehículos del cliente en producción
- [ ] Documentar cambios aplicados
- [ ] Plan de rollback listo si es necesario
- [ ] Monitoreo activo por 48h

---

## Contactos y Recursos

**Documentación relacionada:**
- Reporte completo: `REPORTE-VALIDACION-PRODUCCION.md`
- Resumen ejecutivo: `RESUMEN-EJECUTIVO-VALIDACION.md`
- Script de validación: `scripts/quick_quality_check.sh`

**Archivos clave:**
- Función de homologación: `src/supabase/funciones-homologacion.sql`
- Códigos de normalización: `src/insurers/*/\*-codigo-de-normalizacion.js`
- Workflows n8n: `src/insurers/*/ETL - *.json`

**Herramientas útiles:**
```bash
# Validación rápida
./scripts/quick_quality_check.sh

# Análisis de muestra
awk -F',' 'NR>1 && $2=="AXA" {print}' data/validation/catalogo*.csv | head -10

# Contar nulls en columna específica (ej: AXA = col 10)
awk -F',' 'NR>1 {if ($10=="" || $10=="null") count++} END {print count}' data.csv
```

---

**Última actualización:** 22 de Octubre, 2025
