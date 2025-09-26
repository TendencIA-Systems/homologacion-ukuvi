# Propuestas de Mejora para Homologación Vehicular

## Análisis de Calidad del Proceso de Homologación

### 📊 Resumen Ejecutivo

Tras analizar la tabla `catalogo_homologado` con más de 180,000 registros, se identificaron múltiples áreas críticas de mejora en el proceso de normalización y homologación vehicular entre aseguradoras.

**Hallazgo Crítico**: Solo el **31.75%** de los registros están homologados entre 2 o más aseguradoras, mientras que el **68.25%** permanece sin homologar (con una sola aseguradora). Esto representa una oportunidad masiva de mejora.

### 🔴 Problemas Críticos Identificados

#### 1. **Falta Masiva de Homologación**

- **BMW MINI COOPER 2013**: 84 versiones diferentes para el mismo `hash_comercial`
- **BMW SERIE 3 2005**: 81 versiones diferentes
- **BMW MINI COOPER 2016**: 73 versiones diferentes
- Estos casos representan fallos graves donde vehículos idénticos no fueron reconocidos como tales

#### 2. **Inconsistencias en Nomenclatura de Motores**

- **1,651 casos** con "TURBO"
- **983 casos** con "TFSI"
- **916 casos** con "TDI"
- **554 casos** con "TSI"
- Ejemplo concreto: Audi Q5 2021 tiene versiones con "FSI TURBO" y "TFSI" que son lo mismo pero no se homologaron

#### 3. **Formatos de Datos Inconsistentes**

- **56,833 casos** con "OCUP" sin espacio (5OCUP vs 5 OCUP)
- **32,474 casos** con formato "#CIL"
- **711 casos** con "PTAS" en vez de "PUERTAS"
- **402 casos** con formato V8/V6/V12

#### 4. **Falsos Positivos Detectados (Score < 0.5)**

Casos donde el sistema homologó incorrectamente vehículos diferentes:

| Vehículo            | Aseguradoras    | Versiones                           | Score | Problema                              |
| ------------------- | --------------- | ----------------------------------- | ----- | ------------------------------------- |
| NISSAN ESTACAS 2004 | CHUBB vs ZURICH | "LARGA 1.5T" vs "LARGO DH 2.4L"     | 0.35  | Motor diferente (1.5T vs 2.4L)        |
| BMW SERIE 1 2011    | BX vs ZURICH    | "120iA HB BASICO" vs "120I M SPORT" | 0.35  | Versión diferente (BASICO vs M SPORT) |
| PEUGEOT 206 2008    | BX vs QUALITAS  | "XS FELINE" vs "FELINE"             | 0.35  | Posible versión diferente             |

### 📈 Estadísticas por Aseguradora

| Aseguradora | Total Registros | Usa HP (%) | Usa OCUP (%) |
| ----------- | --------------- | ---------- | ------------ |
| QUALITAS    | 36,748          | 42.8%      | 97.5%        |
| BX          | 36,220          | 40.3%      | 58.5%        |
| GNP         | 34,874          | 21.9%      | 29.2%        |
| ZURICH      | 29,546          | 97.7%      | 88.2%        |

### 📉 Distribución Actual de Homologación

| Número de Aseguradoras | Cantidad de Registros | Porcentaje |
| ---------------------- | --------------------- | ---------- |
| 1 (Sin homologar)      | 108,475               | **68.25%** |
| 2                      | 19,112                | 12.02%     |
| 3                      | 10,060                | 6.33%      |
| 4                      | 6,675                 | 4.20%      |
| 5+                     | 14,616                | 9.20%      |

⚠️ **Insight Crítico**: Más de 108,000 registros (68%) no están homologados con ninguna otra aseguradora, representando una pérdida masiva de información valiosa para comparación de cotizaciones.

---

## 🛠️ Estrategia de Normalización Propuesta

### Fase 1: Normalización Inmediata (Quick Wins)

#### A. Estandarización de Espacios y Formatos

```javascript
// Función de normalización básica
function normalizarEspacios(version) {
  return (
    version
      // Normalizar OCUP
      .replace(/(\d+)OCUP/gi, "$1 OCUP")
      .replace(/(\d+)\s+OCUP/gi, "$1 OCUP")

      // Normalizar CIL
      .replace(/(\d+)CIL/gi, "$1 CIL")
      .replace(/(\d+)\s+CIL/gi, "$1 CIL")

      // Normalizar PUERTAS/PTAS
      .replace(/(\d+)PTAS/gi, "$1 PUERTAS")
      .replace(/(\d+)P(\s|$)/gi, "$1 PUERTAS$2")
      .replace(/(\d+)\s+PUERTAS/gi, "$1 PUERTAS")
  );
}
```

#### B. Unificación de Terminología de Motores

```javascript
// Mapeo de términos equivalentes
const MOTOR_MAPPING = {
  // Turbos
  TFSI: "TURBO",
  TSI: "TURBO",
  "FSI TURBO": "TURBO",
  "T-JET": "TURBO",
  TJET: "TURBO",

  // Diesel
  TDI: "DIESEL_TURBO",
  TDCI: "DIESEL_TURBO",
  CDI: "DIESEL_TURBO",

  // Transmisión
  "AUT.": "AUTO",
  AUTOMATICA: "AUTO",
  AUTOMATIC: "AUTO",
  CVT: "AUTO_CVT",
  "X-TRONIC": "AUTO_CVT",
  XTRONIC: "AUTO_CVT",
  TIPTRONIC: "AUTO",
  DSG: "AUTO_DSG",
  SMG: "AUTO_SMG",
  "S-TRONIC": "AUTO",
  STD: "MANUAL",
  STANDARD: "MANUAL",
};
```

### Fase 2: Normalización por Aseguradora

#### ZURICH (97.7% usa HP, 88.2% usa OCUP)

```javascript
function normalizarZurich(version) {
  // ZURICH es muy consistente, mantener formato pero normalizar espacios
  return version
    .replace(/(\d+)HP/gi, "$1 HP")
    .replace(/(\d+)L/gi, "$1L")
    .replace(/SUV\s+AUT/gi, "SUV AUTO");
}
```

#### QUALITAS (42.8% usa HP, 97.5% usa OCUP)

```javascript
function normalizarQualitas(version) {
  return version
    .replace(/AUT\./gi, "AUTO")
    .replace(/(\d+)\s*OCUP\./gi, "$1 OCUP")
    .replace(/L4/gi, "4CIL")
    .replace(/L6/gi, "6CIL")
    .replace(/V8/gi, "8CIL");
}
```

#### GNP (21.9% usa HP, 29.2% usa OCUP)

```javascript
function normalizarGNP(version) {
  // GNP usa formato más simple, expandir abreviaciones
  return version
    .replace(/STD\./gi, "MANUAL")
    .replace(/C\/A\s+AC/gi, "AIRE_ACONDICIONADO")
    .replace(/\bAUT\b/gi, "AUTO");
}
```

#### HDI (64.5% usa HP/CP, 59.4% usa OCUP)

```javascript
function normalizarHDI(version) {
  return version
    .replace(/(\d+)\s*CP/gi, "$1 HP") // Convertir CP a HP
    .replace(/(\d+)\s*CV/gi, "$1 HP") // Convertir CV a HP
    .replace(/V(\d+)/gi, "$1CIL")
    .replace(/T(\d+\.\d+)/gi, "$1T"); // T2.0 -> 2.0T
}
```

### Fase 3: Algoritmo de Matching Mejorado

#### A. Pre-procesamiento Inteligente

```javascript
function preprocesarParaMatching(version) {
  // Remover información no esencial para el matching
  const specs_irrelevantes = [
    "A/A",
    "A/AC",
    "AIRE ACONDICIONADO",
    "E/E",
    "ELEVADORES ELECTRICOS",
    "PIEL",
    "TELA",
    "VELOUR",
    "CD",
    "MP3",
    "BLUETOOTH",
    "ABS",
    "ESC",
    "VSC",
    "CA",
    "CE",
    "CB",
    "CQ",
    "SM",
    "SQ",
    "VP",
    "TECHO PANORAMICO",
    "TPANOR",
    "QUEMACOCOS",
    "QC",
    "BOLSAS AIRE",
    "BA",
    "IMP",
    "IMPORT",
  ];

  let clean = version.toUpperCase();
  specs_irrelevantes.forEach((spec) => {
    clean = clean.replace(new RegExp(`\\b${spec}\\b`, "gi"), "");
  });

  // Normalizar múltiples espacios
  return clean.replace(/\s+/g, " ").trim();
}
```

#### B. Scoring Combinado Mejorado

```javascript
function calcularScoreHomologacion(version1, version2, mismaAseguradora) {
  // Preprocesar ambas versiones
  const v1_clean = preprocesarParaMatching(version1);
  const v2_clean = preprocesarParaMatching(version2);

  // Calcular similitud base
  const tokenScore = calcularSolapamientoTokens(v1_clean, v2_clean);
  const levenshteinScore =
    1 -
    levenshtein(v1_clean, v2_clean) /
      Math.max(v1_clean.length, v2_clean.length);

  // Detectar términos clave equivalentes
  const equivalenceBonus = detectarEquivalencias(v1_clean, v2_clean);

  // Score final ponderado
  let finalScore =
    tokenScore * 0.5 + levenshteinScore * 0.3 + equivalenceBonus * 0.2;

  // Umbrales ajustados
  if (mismaAseguradora) {
    return finalScore >= 0.85; // Umbral más alto para misma aseguradora
  } else {
    return finalScore >= 0.65; // Umbral más flexible entre aseguradoras
  }
}

function detectarEquivalencias(v1, v2) {
  const equivalencias = [
    ["TFSI", "TURBO"],
    ["TSI", "TURBO"],
    ["TDI", "DIESEL"],
    ["AUTOMATICA", "AUTO"],
    ["PTAS", "PUERTAS"],
  ];

  let bonus = 0;
  equivalencias.forEach(([term1, term2]) => {
    if (
      (v1.includes(term1) && v2.includes(term2)) ||
      (v1.includes(term2) && v2.includes(term1))
    ) {
      bonus += 0.2;
    }
  });

  return Math.min(bonus, 1);
}
```

### Fase 4: Función de Post-Homologación

```sql
-- Función para detectar y fusionar registros similares post-procesamiento
CREATE OR REPLACE FUNCTION mejorar_homologacion_existente()
RETURNS void AS $$
DECLARE
    rec1 RECORD;
    rec2 RECORD;
BEGIN
    -- Buscar registros con mismo hash pero diferentes versiones
    FOR rec1 IN
        SELECT * FROM catalogo_homologado
        WHERE array_length(version_tokens_array, 1) < 5 -- Versiones cortas primero
    LOOP
        FOR rec2 IN
            SELECT * FROM catalogo_homologado
            WHERE hash_comercial = rec1.hash_comercial
            AND id != rec1.id
            AND jsonb_array_length(jsonb_path_query_array(disponibilidad, '$.*')) = 1
        LOOP
            -- Calcular similitud mejorada
            IF calcular_similitud_mejorada(rec1.version, rec2.version) > 0.75 THEN
                -- Fusionar disponibilidad
                UPDATE catalogo_homologado
                SET disponibilidad = disponibilidad || rec2.disponibilidad
                WHERE id = rec1.id;

                -- Eliminar registro duplicado
                DELETE FROM catalogo_homologado WHERE id = rec2.id;
            END IF;
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

---

## 📋 Plan de Implementación

### Semana 1: Quick Wins

1. Implementar normalización de espacios y formatos básicos
2. Aplicar a nuevas inserciones
3. Testear con muestra de 1,000 registros

### Semana 2: Normalización por Aseguradora

1. Implementar funciones específicas por aseguradora
2. Validar con datos históricos
3. Ajustar umbrales basados en resultados

### Semana 3: Mejora del Matching

1. Implementar nuevo algoritmo de scoring
2. Ejecutar función de post-homologación
3. Medir mejora en tasa de homologación

### Semana 4: Monitoreo y Ajustes

1. Analizar métricas de homologación
2. Identificar casos edge restantes
3. Ajustar parámetros finales

---

## 🎯 Métricas de Éxito

### KPIs Propuestos

1. **Tasa de Homologación**: Aumentar de ~30% actual a 75%+
2. **Reducción de Duplicados**: Disminuir versiones únicas en 60%
3. **Precisión**: Mantener falsos positivos bajo 2%
4. **Cobertura**: 95%+ de vehículos con al menos 2 aseguradoras homologadas

### Monitoreo Continuo

```sql
-- Query para monitorear progreso
WITH metricas AS (
    SELECT
        COUNT(DISTINCT hash_comercial) as vehiculos_unicos,
        COUNT(*) as total_registros,
        AVG(jsonb_array_length(jsonb_path_query_array(disponibilidad, '$.*'))) as promedio_aseguradoras,
        COUNT(*) FILTER (WHERE jsonb_array_length(jsonb_path_query_array(disponibilidad, '$.*')) > 1) as homologados,
        COUNT(*) FILTER (WHERE jsonb_array_length(jsonb_path_query_array(disponibilidad, '$.*')) = 1) as sin_homologar
    FROM catalogo_homologado
)
SELECT
    vehiculos_unicos,
    total_registros,
    ROUND(promedio_aseguradoras, 2) as aseguradoras_promedio,
    ROUND((homologados::numeric / total_registros) * 100, 2) as tasa_homologacion,
    sin_homologar as pendientes
FROM metricas;
```

---
