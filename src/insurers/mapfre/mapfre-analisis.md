# Análisis Catálogo MAPFRE - Estrategia de Homologación

## 📊 Resumen Ejecutivo

- **Total registros (2000-2030)**: 31,476
- **Registros activos**: No existe campo de activos ⚠️ (se procesarán todos)
- **Rango de años**: 2000-2026
- **Marcas únicas**: 71
- **Modelos únicos**: 999 (campo CodModelo)
- **Estructura**: Solo 2 tablas (Marca y Modelo) - La más simple de todas las aseguradoras

## 🚨 Hallazgos Críticos

1. **NO existe campo de activo/vigente** - Se procesarán todos los registros
2. **Estructura ultra-simplificada**: Solo 2 tablas con información mezclada
3. **Campo NomModelo altamente contaminado**: Contiene modelo + versión + especificaciones sin separadores consistentes
4. **Transmisión**: Campo numérico (0=No especificada 30%, 1=Manual 20%, 2=Automática 49%)
5. **Duplicación de marcas**: VOLKSWAGEN/VOLKSWAGEN VW, BMW/BMW BW, CHEVROLET/CHEVROLET GM
6. **VersionCorta variable**: Desde 2 caracteres ("TA", "LE") hasta texto completo

## 📋 Mapeo de Campos

| Campo Canónico | Campo Origen                      | Transformación Requerida                                 |
| -------------- | --------------------------------- | -------------------------------------------------------- |
| marca          | Marca.NomMarca                    | Normalización y unificación de duplicados                |
| modelo         | Modelo.NomModelo (parcial)        | Extracción del modelo real, eliminando specs             |
| anio           | Modelo.AnioFabrica                | Directo                                                  |
| transmision    | Modelo.Transmision                | Mapeo: 0→NULL, 1→MANUAL, 2→AUTO                          |
| version        | Modelo.VersionCorta (parcial)     | Extracción de TRIM limpio                                |
| motor_config   | Extraer de NomModelo              | Buscar patrones L4, V6, V8, I4, etc.                     |
| cilindrada     | Extraer de NomModelo              | Buscar patrones X.XL, X.XT                               |
| carroceria     | Extraer de NomModelo/VersionCorta | SEDAN, SUV, HB, COUPE, VAN, PICKUP + inferir por puertas |
| traccion       | Extraer de NomModelo              | AWD, 4WD, 4X4, 4X2, FWD, RWD                             |
| puertas        | Extraer de NomModelo              | Buscar patrones 2P, 4P, 5P, X PUERTAS                    |

## 🔍 Análisis de Patrones en NomModelo/VersionCorta

### Estructura típica encontrada:

```
NomModelo: "MODELO VERSIÓN MOTOR CILINDRADA POTENCIA PUERTAS TRANSMISIÓN EQUIPAMIENTO"
VersionCorta: "VERSIÓN [especificaciones parciales]"
```

### Ejemplos reales:

- **Estructurado**: "E 150 VAN L6 4.9L 145 CP 3 PUERTAS AUT AA"
- **Semi-estructurado**: "KING CAB LUJO, L4, 2.4L, 134 CP, 4 PUERTAS, AUT"
- **Mínimo**: "BASE, 4 PUERTAS, MANUAL"
- **Sin estructura**: "ACURA", "AUTOS CLASICOS 5 PASAJEROS"

### Estadísticas de elementos presentes:

| Elemento                     | Registros | Porcentaje | Patrón de Extracción |
| ---------------------------- | --------- | ---------- | -------------------- | ------ | ----- | ---- |
| Transmisión en texto (TA/TM) | 11,075    | 35.2%      | `\bT[AM]\b`          |
| Cilindrada                   | 7,925     | 25.2%      | `\d+\.\d+[LT]`       |
| Config. Motor                | 1,986     | 6.3%       | `[VLIH]\d+`          |
| Puertas explícitas           | 3,107     | 9.9%       | `\d+\s\*(PUERTAS?    | PTAS?  | P\b)` |
| Carrocería SEDAN             | 2,832     | 9.0%       | `SEDAN               | SD\b`  |
| Carrocería HB                | 760       | 2.4%       | `HATCHBACK           | HB\b`  |
| Carrocería COUPE             | 1,518     | 4.8%       | `COUPE`              |
| Carrocería VAN               | 873       | 2.8%       | `VAN                 | CARGO` |
| Tracción                     | 2,018     | 6.4%       | `AWD                 | 4WD    | 4X4   | 4X2` |
| Híbrido/Eléctrico            | 873       | 2.8%       | `HYBRID              | MHEV   | PHEV  | BEV` |

## 🎯 Estrategia de Extracción de TRIM

### TRIMs válidos identificados (Top 30):

1. **SPORT** (125)
2. **LIMITED** (101)
3. **GLX** (89)
4. **EX** (88)
5. **GT** (74)
6. **SE** (68)
7. **ADVANCE** (55)
8. **LT** (49)
9. **EXCLUSIVE** (48)
10. **ACTIVE** (45)
11. **ALLURE** (45)
12. **BASE** (43)
13. **XLE** (43)
14. **PREMIUM** (35)
15. **LE** (34)

### Algoritmo de extracción propuesto:

```javascript
function extraerVersion(nomModelo, versionCorta) {
  // Prioridad 1: Usar VersionCorta si tiene TRIM válido
  let version = normalizarTexto(versionCorta);

  // Eliminar indicadores de transmisión
  version = version.replace(/\b(TA|TM|CVT|DSG|TIPTRONIC)\b/g, "").trim();

  // Eliminar especificaciones técnicas
  version = version.replace(/\d+\.\d+[LT]?/g, ""); // Cilindrada
  version = version.replace(/[VLIH]\d+/g, ""); // Config motor
  version = version.replace(/\d+\s*(HP|CP)/g, ""); // Potencia
  version = version.replace(/\d+\s*(PUERTAS?|PTAS?|P\b)/g, ""); // Puertas

  // Buscar TRIM en lista blanca
  const TRIMS_VALIDOS = [
    "SPORT",
    "LIMITED",
    "GLX",
    "EX",
    "GT",
    "SE",
    "ADVANCE",
    "LT",
    "EXCLUSIVE",
    "ACTIVE",
    "ALLURE",
    "BASE",
    "XLE",
    "PREMIUM",
    "LE",
  ];

  for (const trim of TRIMS_VALIDOS) {
    if (version.includes(trim)) {
      return trim;
    }
  }

  // Si no hay TRIM válido, retornar null
  return null;
}
```

## 🔧 Reglas de Normalización Específicas

### Marcas con duplicación detectada:

- **VOLKSWAGEN** + **VOLKSWAGEN VW** → `VOLKSWAGEN`
- **BMW** + **BMW BW** → `BMW`
- **CHEVROLET** + **CHEVROLET GM** → `CHEVROLET`
- **CHRYSLER-DODGE** + **CHRYSLER-DODGE DG** → `DODGE` o `CHRYSLER` según modelo
- **FORD** + **FORD FR** → `FORD`
- **MINI COOPER** → `MINI`

### Códigos de transmisión:

- `0` = NULL (no especificada)
- `1` = MANUAL
- `2` = AUTO
- Texto `TA` = AUTO
- Texto `TM` = MANUAL
- Texto `CVT`, `DSG`, `TIPTRONIC` = AUTO

### Inferencia de carrocería por puertas:

- 2 puertas + no especificado → COUPE
- 3 puertas → HATCHBACK
- 4 puertas + no especificado → SEDAN
- 5 puertas → HATCHBACK o SUV (validar por modelo)

## ⚠️ Problemas Detectados

1. **Sin campo de activos**: Imposible filtrar vehículos vigentes (31,476 registros totales)
2. **Datos ultra-comprimidos**: Toda la información en 2-3 campos
3. **VersionCorta inconsistente**:
   - A veces solo transmisión ("TA", "TM")
   - A veces solo TRIM ("LE", "SE")
   - A veces descripción completa
4. **Marcas duplicadas**: 5+ casos de la misma marca con diferentes códigos
5. **Modelos genéricos**: "ACURA", "AUTOS CLASICOS", sin información útil
6. **Separadores inconsistentes**: Comas, espacios, sin patrón fijo

## 📈 Métricas de Calidad

- **Campos con transmisión detectada**: 69.65% (campo dedicado)
- **TRIMs identificables**: ~40% (estimado)
- **Especificaciones técnicas presentes**: 25% (cilindrada)
- **Carrocería explícita**: ~20%
- **Datos completos (8 campos)**: <10%

## 💡 Recomendaciones

### Inmediatas:

1. **Asumir todos los registros como activos** (no hay campo de estado)
2. **Priorizar extracción de campos básicos**: marca, modelo, año, transmisión
3. **Usar VersionCorta como fuente principal de TRIM** cuando sea válida
4. **Implementar normalización agresiva de marcas** para unificar duplicados

### Para implementación:

1. **Crear diccionario de modelos conocidos** para mejor extracción
2. **Implementar fuzzy matching** para variaciones de TRIMs
3. **Usar inferencia de carrocería** basada en modelo + puertas
4. **Cachear resultados de extracción** por la complejidad del parsing

### Estrategia de procesamiento:

```javascript
// Pseudo-código para procesamiento
function procesarMapfre(registro) {
  const resultado = {
    marca: normalizarMarca(registro.NomMarca),
    modelo: extraerModelo(registro.NomModelo),
    anio: registro.AnioFabrica,
    transmision: mapearTransmision(registro.Transmision),
    version: extraerVersion(registro.NomModelo, registro.VersionCorta),
    motor_config: extraerConfigMotor(registro.NomModelo),
    cilindrada: extraerCilindrada(registro.NomModelo),
    carroceria: inferirCarroceria(registro.NomModelo, puertas),
    traccion: extraerTraccion(registro.NomModelo),
    activo: true, // Siempre true por falta de campo
  };

  return resultado;
}
```

## 🏁 Conclusión

Mapfre presenta el catálogo **más simplificado y problemático** de todas las aseguradoras analizadas:

- Solo 2 tablas
- Sin campo de activos
- Información altamente comprimida y mezclada
- Requiere parsing intensivo y múltiples heurísticas

**Viabilidad de homologación**: MEDIA-BAJA

- Se puede extraer información básica (marca, modelo, año, transmisión) con 90%+ precisión
- Especificaciones técnicas y TRIM con 40-50% precisión
- Requerirá validación manual significativa

**Tiempo estimado**: 3-4 días de desarrollo + 2 días de validación
