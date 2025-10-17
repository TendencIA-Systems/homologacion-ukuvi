# Análisis Catálogo GNP - Estrategia de Homologación

## 📊 Resumen Ejecutivo

- **Total registros**: 11,674 versiones
- **Registros activos**: No hay campo de activo/vigente (⚠️ **CRÍTICO**)
- **Rango de años**: 2000-2030 (configurado por query)
- **Marcas únicas**: 76
- **Modelos únicos**: 985 carrocerías
- **Combinaciones año-modelo**: 36,503 registros

## 🚨 Hallazgos Críticos

### 1. **NO existe campo de activo/vigente**

- Imposible filtrar registros obsoletos
- Se procesarán TODOS los registros disponibles
- Recomendación: Verificar con Ukuvi si tienen lógica de negocio para determinar vigencia

### 2. **Estructura del campo VersionCorta altamente problemática**

- **60 registros** tienen "S/D" (Sin Definir)
- **Contaminación cruzada severa**: Datos de otras marcas/modelos en el campo
- Mezcla caótica de especificaciones sin estructura consistente
- Desde valores mínimos ("A", "B", "C") hasta descripciones completas de 50+ caracteres

### 3. **Transmisión con doble fuente**

- Campo `Transmision`: 0=No especificada, 1=Manual, 2=Automática
- Campo `TipoVehiculo`: "AUT"=Automóvil, "CA1"=Camioneta/Pickup
- Redundancia en `VersionCorta` con términos AUT/STD/CVT/TIP

### 4. **Marcas duplicadas detectadas**

- GMC / GENERAL MOTORS / GENERAL MOTORS 2
- JAC / JAC SEI
- MG / MG ROVER
- Requieren consolidación en normalización

## 📋 Mapeo de Campos

| Campo Canónico | Campo Origen                           | Transformación Requerida                    |
| -------------- | -------------------------------------- | ------------------------------------------- |
| marca          | gnp.Armadora.Armadora                  | Normalización y consolidación de duplicados |
| modelo         | gnp.Carroceria.Carroceria              | Limpieza de nombres                         |
| anio           | gnp.Modelo.Modelo                      | CAST a INT, validar 2000-2030               |
| transmision    | gnp.Version.Transmision                | Mapeo: 0→null, 1→MANUAL, 2→AUTO             |
| version        | Extraer de gnp.Version.VersionCorta    | Estrategia compleja de extracción           |
| motor_config   | Extraer de VersionCorta                | Buscar patrones L4/V6/V8/etc                |
| carroceria     | Inferir de TipoVehiculo + VersionCorta | CA1→PICKUP, análisis de texto               |
| traccion       | Extraer de VersionCorta                | Buscar 4X4/AWD/FWD/RWD                      |

## 🔧 Reglas de Normalización Específicas

### Marcas con consolidación requerida:

```
GENERAL MOTORS → GMC
GENERAL MOTORS 2 → GMC
JAC SEI → JAC
MG ROVER → MG
```

### Códigos de transmisión:

```
0 = null (no especificada)
1 = MANUAL
2 = AUTO
```

### TRIMs identificados en muestra:

- **Alta frecuencia**: SPORT (142), LIMITED (104), PREMIUM (57), EXCLUSIVE (22), BASE (15), ADVANCE (25)
- **Media frecuencia**: SE, LX, LS, BOLD, LITE
- **Variantes con transmisión**: "SPORT AUT", "PREMIUM AUT", "ADVANCE CVT"

## 📊 Análisis del Campo VersionCorta

### Estadísticas de elementos presentes:

| Elemento                        | Registros | Porcentaje |
| ------------------------------- | --------- | ---------- |
| Configuración motor (L4/V6/etc) | ~3,500    | 30%        |
| Cilindrada (1.5L, 2.0T)         | ~4,700    | 40%        |
| Turbo                           | ~600      | 5%         |
| Transmisión en texto            | ~5,800    | 50%        |
| Trim identificable              | ~1,200    | 10%        |

### Patrones de estructura encontrados:

1. **Mínimos**: "A", "B", "C", "S", "M" (letras sueltas)
2. **Simples**: "SPORT", "LIMITED", "PREMIUM", "BASE"
3. **Con transmisión**: "SE AUT", "SPORT STD", "LIMITED CVT"
4. **Con motor**: "L4 1.6 STD", "V6 3.0 AUT"
5. **Complejos**: "GT LINE L4 2.0 4P IVT", "3.2 S LINE TIPTRONIC QUATTRO 255HP"
6. **Contaminados**: "BMW 325iA EDITION EXCLUSIVE" (en otros modelos)
7. **Con equipamiento**: "SIGNO STD. C/A. AC. V.E. Q.C. V.P."

## 🎯 Estrategia de Extracción de TRIM

### Algoritmo propuesto:

```javascript
function extraerTrimGNP(versionCorta) {
  // 1. Casos especiales - valores mínimos
  if (versionCorta === "S/D" || versionCorta === "") return null;
  if (versionCorta.length <= 2) return null; // A, B, C, etc.

  // 2. Limpiar contaminación de otras marcas
  let version = versionCorta
    .replace(/^(BMW|MERCEDES BENZ|ALFA ROMEO)\s+.*/, "") // Eliminar marcas incorrectas
    .replace(/\d{3}[A-Z]{0,2}\s+/, ""); // Eliminar modelos tipo 325iA, 500CGI

  // 3. Eliminar especificaciones técnicas
  version = version
    .replace(/[LVI]\d+\s+\d+\.\d+[TL]?\s*/g, "") // L4 2.0T
    .replace(/\d+\.\d+[TL]?\s*/g, "") // 2.0T, 1.5L
    .replace(/\d+HP\s*/g, "") // 255HP
    .replace(/\b(STD|AUT|CVT|TIP|TIPTRONIC|XTRONIC|MULTITRONIC)\b/g, "")
    .replace(/\b(4X4|4X2|AWD|FWD|RWD|QUATTRO)\b/g, "")
    .replace(/\b(TURBO|BITURBO|TSI|TDI|TFSI)\b/g, "")
    .replace(/\b\d+P\b/g, "") // 4P, 5P
    .replace(/RIN\s+\d+/g, "") // RIN 17
    .replace(/C\/A\.?\s*A\.?C\.?/g, "") // C/A. AC.
    .replace(/V\.E\.?/g, "") // V.E.
    .replace(/Q\.C\.?/g, "") // Q.C.
    .replace(/V\.P\.?/g, ""); // V.P.

  // 4. Buscar TRIMs válidos
  const TRIMS_VALIDOS_GNP = [
    "SPORT",
    "SPORT LINE",
    "S LINE",
    "LIMITED",
    "LIMITED PLUS",
    "PREMIUM",
    "PREMIUM PLUS",
    "EXCLUSIVE",
    "BASE",
    "ADVANCE",
    "GT LINE",
    "GT",
    "FR",
    "FR LINE",
    "REFERENCE",
    "STYLE",
    "ACTIVE",
    "TRENDY",
    "SIGNO",
    "BOLD",
    "LITE",
    "SE",
    "SEL",
    "SLE",
    "LX",
    "LXE",
    "LS",
    "LT",
    "LTZ",
    "GL",
    "GLS",
    "GLX",
    "XL",
    "XLE",
    "XLT",
  ];

  // Buscar el trim más relevante
  for (const trim of TRIMS_VALIDOS_GNP) {
    if (version.includes(trim)) {
      return trim;
    }
  }

  // 5. Si no hay trim válido, retornar null
  return null;
}
```

## ⚠️ Problemas Detectados

### 1. **Contaminación de datos crítica**

- ~8% de registros tienen marca/modelo incorrectos en VersionCorta
- Ejemplo: "MERCEDES BENZ ML 500 CGI BITURBO" en un Honda Civic
- **Impacto**: Extracción de especificaciones incorrectas
- **Solución**: Validación cruzada y limpieza agresiva

### 2. **Datos faltantes masivos**

- 16% sin transmisión especificada (Transmision=0)
- 90% sin TRIM identificable en VersionCorta
- **Solución**: Usar valores null, no inventar defaults

### 3. **Inconsistencias marca-modelo**

- Modelos con nombres que incluyen otras marcas
- Ejemplo: "LINCOLN CONTINENTAL" bajo Ford
- **Solución**: Mapeo manual de casos conocidos

## 📈 Métricas de Calidad

- **Completitud del campo versión**: 100% (pero con alta contaminación)
- **TRIMs identificables**: ~10%
- **Transmisión detectada**: 84% (desde campo dedicado)
- **Especificaciones técnicas presentes**: 40% (mezcladas caóticamente)
- **Calidad general de datos**: ⚠️ **BAJA** - Requiere limpieza exhaustiva

## 💡 Recomendaciones

### Inmediatas (Sprint actual):

1. **NO confiar en VersionCorta** para información crítica
2. Usar campo Transmision como fuente primaria (más confiable)
3. Implementar validación agresiva de contaminación cruzada
4. Procesar TODOS los registros al no tener campo activo

### Futuras (mejora continua):

1. Solicitar a GNP campo de vigencia/activo
2. Crear diccionario de mapeo manual para casos contaminados frecuentes
3. Implementar ML para detectar anomalías en VersionCorta
4. Considerar excluir GNP de homologación si calidad no mejora

## 🔄 Proceso de Normalización GNP

### Flujo específico:

```sql
-- Query de extracción para GNP
SELECT
    v.IdVersion as id_original,
    a.Armadora as marca,
    c.Carroceria as modelo,
    CAST(m.Modelo as INT) as anio,
    v.Transmision as transmision_codigo,
    v.TipoVehiculo as tipo_vehiculo,
    v.VersionCorta as version_completa,
    v.PickUp as es_pickup
FROM gnp.Version v
INNER JOIN gnp.Carroceria c ON v.ClaveCarroceria = c.Clave
INNER JOIN gnp.Armadora a ON c.ClaveArmadora = a.Clave
INNER JOIN gnp.Modelo m ON m.ClaveCarroceria = c.Clave
    AND m.ClaveVersion = v.Clave
WHERE TRY_CAST(m.Modelo as INT) BETWEEN 2000 AND 2030
ORDER BY a.Armadora, c.Carroceria, m.Modelo;
```

### Consideraciones especiales:

1. **Sin filtro de activos** - Procesar todo
2. **Validación estricta** de marca/modelo contra VersionCorta
3. **Logging extensivo** de casos anómalos para análisis posterior
4. **Fallback conservador** - Mejor null que dato incorrecto

## 📊 Comparación con otras aseguradoras

| Aspecto              | GNP               | Qualitas            | HDI      |
| -------------------- | ----------------- | ------------------- | -------- |
| Campo Activo         | ❌ No existe      | ✅ Sí (15% activos) | ✅ Sí    |
| Calidad VersionCorta | ⚠️ Muy baja       | ⚠️ Baja             | ✅ Media |
| Transmisión dedicada | ✅ Sí (confiable) | ✅ Sí               | ✅ Sí    |
| Contaminación datos  | 🔴 Alta (8%)      | 🟡 Media (3%)       | 🟢 Baja  |
| TRIMs identificables | 10%               | 58%                 | 45%      |

## 🚨 Decisión Crítica

**Recomendación**: Proceder con GNP pero con **expectativas ajustadas**:

- Solo ~10% tendrá TRIM real
- Alta probabilidad de especificaciones incorrectas
- Requerir validación manual post-procesamiento
- Considerar como "Tier 2" en calidad de datos

---

_Documento generado: 2025-01-16_
_Analista: Sistema de Homologación v1.0_
_Siguiente paso: Implementar código de normalización con validaciones estrictas_
