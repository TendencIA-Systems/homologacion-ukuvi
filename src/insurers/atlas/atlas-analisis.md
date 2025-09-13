# Análisis Catálogo ATLAS - Estrategia de Homologación

## 📊 Resumen Ejecutivo

- **Total registros**: 36,490 (años 2000-2030)
- **Registros activos**: 31,231 (85.59%) ✅ **CRÍTICO: Solo procesar activos**
- **Registros inactivos**: 5,259 (14.41%)
- **Rango de años**: 2000-2026
- **Marcas únicas**: 51
- **Modelos únicos**: 111
- **Posibles duplicados**: 1,635

## 🚨 Hallazgos Críticos

### 1. ⚠️ **PROBLEMA GRAVE DE INTEGRIDAD REFERENCIAL**

Los datos presentan inconsistencias severas en la relación marca-modelo. Se encontraron casos donde:

- NISSAN tiene asociados modelos de Acura, Audi y otras marcas
- Los IDs de SubTipo_Modelo se reutilizan entre diferentes marcas/años
- **Recomendación**: Usar SIEMPRE las tres llaves juntas (IdMarca + IdSubTipo + Anio) para las uniones

### 2. ✅ **Campo de Estado Activo/Inactivo**

- Existe campo `Activo` de tipo bit
- 85.59% de registros activos (mejor ratio que Qualitas)
- **Estrategia**: Filtrar WHERE Activo = 1

### 3. 📝 **Estructura del Campo Versión**

- Usar campo `VersionCorta` (NO incluye marca ni modelo)
- Ejemplos de patrones encontrados:
  - Simple: `LUXURY AUT`, `PREMIUM`, `BASE STD`
  - Complejo: `SPORTBACK S LINE 2.0L TFSI 252HP S TRONIC QUATTRO`
  - Con specs: `GT V6 AUT CD TELA COUPE EQ.`
  - Pickups: `PICK UP CUSTOM 4 V8 IMP STD B.A.`

### 4. 🔄 **Transmisión**

Campo numérico `Transmision` con mapeo claro:

- `0` = No especificado (15.31%)
- `1` = MANUAL (24.82%)
- `2` = AUTO (59.86%)

## 📋 Mapeo de Campos

| Campo Canónico | Campo Origen                         | Transformación Requerida               |
| -------------- | ------------------------------------ | -------------------------------------- |
| marca          | `atlas.Marca.NomMarca`               | Normalización (GENERAL MOTORS → GMC)   |
| modelo         | `atlas.SubTipo_Modelo.Descripcion`   | Normalización básica                   |
| anio           | `atlas.Vehiculo_Version.Anio`        | Directo (INT)                          |
| transmision    | `atlas.Vehiculo_Version.Transmision` | Mapeo: 0→NULL, 1→MANUAL, 2→AUTO        |
| version        | Extraer de `VersionCorta`            | Limpiar specs, conservar trim          |
| motor_config   | Extraer de `VersionCorta`            | Detectar L4, V6, V8, [0-9] CIL         |
| carroceria     | Extraer de `VersionCorta`            | Detectar SEDAN, SUV, HB, COUPE, PICKUP |
| traccion       | Extraer de `VersionCorta`            | Detectar AWD, 4WD, 4X4, FWD, RWD       |

## 📊 Análisis de Especificaciones en VersionCorta

| Especificación                   | Registros | Porcentaje |
| -------------------------------- | --------- | ---------- |
| **Transmisión en texto**         | 22,762    | 72.9%      |
| - AUTO/AUT                       | 14,118    | 45.2%      |
| - STD/MAN                        | 7,931     | 25.4%      |
| - CVT                            | 713       | 2.3%       |
| **Cilindrada** (1.5L, 2.0T)      | 13,562    | 43.4%      |
| **Config. Motor** (V6, L4, 4CIL) | 6,722     | 21.5%      |
| **Puertas** (3P, 5P)             | 3,356     | 10.7%      |
| **Carrocería**                   | 4,719     | 15.1%      |
| - SEDAN                          | 1,497     | 4.8%       |
| - PICKUP                         | 1,277     | 4.1%       |
| - COUPE                          | 1,154     | 3.7%       |
| - HB/HATCHBACK                   | 689       | 2.2%       |
| - SUV                            | 102       | 0.3%       |
| **Tracción** (AWD, 4WD, 4X4)     | 731       | 2.3%       |
| **Turbo**                        | 835       | 2.7%       |
| **Electrificación**              | 654       | 2.1%       |
| - Hybrid/HEV/MHEV                | 375       | 1.2%       |
| - Electric/EV                    | 215       | 0.7%       |
| - PHEV                           | 64        | 0.2%       |

## 🔧 Estrategia de Normalización

### 1. Marcas con Variaciones Detectadas

- `GENERAL MOTORS` → `GMC`
- `CHRYSLER` → `CHRYSLER`
- `MERCEDES BENZ` → `MERCEDES BENZ`
- Mantener espacios en marcas compuestas

### 2. TRIMs Válidos Identificados (Top 40)

```
LIMITED (171), GT (127), GLS (121), GL (117), SPORT (81),
SPORTBACK (73), ADVANCE (71), EX (69), LT (68), SE (66),
EXCLUSIVE (65), PREMIUM (61), XLE (59), LS (57), TRENDLINE (56),
COMFORTLINE (54), ALLURE (52), ACTIVE (50), BASE (50), PLATINUM (49),
SELECT (47), LE (44), FR (43), INTENS (42), LUXURY (42),
STYLE (41), COUPE (40), LX (37), UNLIMITED (35), ICONIC (33),
PREMIER (33), PRO (33)
```

### 3. Algoritmo de Extracción de Versión

```javascript
function extraerVersionAtlas(versionCorta) {
  if (!versionCorta) return null;

  let version = versionCorta.toUpperCase().trim();

  // 1. Eliminar transmisión
  version = version.replace(
    /\b(AUT|STD|MAN|CVT|XTRONIC|S[\s-]?TRONIC|TIPTRONIC)\b/g,
    " "
  );

  // 2. Eliminar especificaciones técnicas
  // Cilindrada y motor
  version = version.replace(/\d+\.\d+L?\s*(TFSI|TSI|TDI|TURBO)?/g, " ");
  version = version.replace(/\b[VLI]\d+\b/g, " ");
  version = version.replace(/\b\d+\s*CIL\b/g, " ");
  version = version.replace(/\b\d+HP\b/g, " ");

  // Puertas y carrocería
  version = version.replace(/\b\d+\s*P(TAS?)?\b/g, " ");
  version = version.replace(
    /\b(HB|SEDAN|COUPE|SUV|PICKUP|PICK[\s-]?UP)\b/g,
    " "
  );

  // Tracción
  version = version.replace(
    /\b(AWD|4WD|4X4|FWD|RWD|QUATTRO|XDRIVE|4MATIC)\b/g,
    " "
  );

  // Equipamiento y códigos
  version = version.replace(
    /\b(CD|DVD|GPS|PIEL|TELA|IMP|EQ|BA|AC|A\/AC|C\/A|PAQ SEG)\b/g,
    " "
  );

  // 3. Limpiar espacios múltiples
  version = version.replace(/\s+/g, " ").trim();

  // 4. Buscar trim válido
  const trimsValidos = [
    "LIMITED",
    "GT",
    "GLS",
    "GL",
    "SPORT",
    "SPORTBACK",
    "ADVANCE",
    "EXCLUSIVE",
    "PREMIUM",
    "TRENDLINE",
    "COMFORTLINE",
    "ALLURE",
    "ACTIVE",
    "BASE",
    "PLATINUM",
    "SELECT",
    "LUXURY",
    "INTENS",
  ];

  for (const trim of trimsValidos) {
    if (version.includes(trim)) {
      return trim;
    }
  }

  // 5. Si no hay trim válido, usar primera palabra significativa
  const palabras = version.split(" ").filter((p) => p.length > 1);
  return palabras.length > 0 ? palabras[0] : null;
}
```

### 4. Extracción de Especificaciones Técnicas

```javascript
function extraerEspecificacionesAtlas(versionCorta) {
  const specs = {
    motor_config: null,
    cilindrada: null,
    turbo: false,
    carroceria: null,
    traccion: null,
    puertas: null,
  };

  if (!versionCorta) return specs;
  const texto = versionCorta.toUpperCase();

  // Motor
  const motorMatch = texto.match(/\b([VLI])(\d+)\b/);
  if (motorMatch) specs.motor_config = motorMatch[0];

  const cilindrosMatch = texto.match(/\b(\d+)\s*CIL\b/);
  if (cilindrosMatch) specs.motor_config = `L${cilindrosMatch[1]}`;

  // Cilindrada
  const cilindradaMatch = texto.match(/(\d+\.\d+)L?/);
  if (cilindradaMatch) specs.cilindrada = parseFloat(cilindradaMatch[1]);

  // Turbo
  if (/\b(TURBO|TBO|BITURBO|TFSI|TSI)\b/.test(texto)) specs.turbo = true;

  // Carrocería
  if (/\bSEDAN\b/.test(texto)) specs.carroceria = "SEDAN";
  else if (/\b(HB|HATCHBACK)\b/.test(texto)) specs.carroceria = "HATCHBACK";
  else if (/\bCOUPE\b/.test(texto)) specs.carroceria = "COUPE";
  else if (/\b(PICKUP|PICK[\s-]?UP)\b/.test(texto)) specs.carroceria = "PICKUP";
  else if (/\bSUV\b/.test(texto)) specs.carroceria = "SUV";
  else if (/\bSPORTBACK\b/.test(texto)) specs.carroceria = "SPORTBACK";

  // Puertas (para inferir carrocería si no está explícita)
  const puertasMatch = texto.match(/\b(\d)\s*P(TAS?)?\b/);
  if (puertasMatch) {
    specs.puertas = parseInt(puertasMatch[1]);
    if (!specs.carroceria) {
      if (specs.puertas === 2) specs.carroceria = "COUPE";
      else if (specs.puertas === 3) specs.carroceria = "HATCHBACK";
      else if (specs.puertas === 4) specs.carroceria = "SEDAN";
      else if (specs.puertas === 5) specs.carroceria = "HATCHBACK";
    }
  }

  // Tracción
  if (/\b4X4\b/.test(texto)) specs.traccion = "4X4";
  else if (/\b4WD\b/.test(texto)) specs.traccion = "4WD";
  else if (/\bAWD\b/.test(texto)) specs.traccion = "AWD";
  else if (/\bFWD\b/.test(texto)) specs.traccion = "FWD";
  else if (/\bRWD\b/.test(texto)) specs.traccion = "RWD";
  else if (/\b(QUATTRO|XDRIVE|4MATIC)\b/.test(texto)) specs.traccion = "AWD";

  return specs;
}
```

## ⚠️ Problemas Detectados

1. **Integridad Referencial Crítica**

   - Los modelos no corresponden correctamente con las marcas
   - Solución: SIEMPRE usar IdMarca + IdSubTipo + Anio en las uniones
   - Validar marca-modelo antes de procesar

2. **Duplicados**

   - 1,635 posibles duplicados detectados
   - Aplicar deduplicación por hash antes de enviar al RPC

3. **Modelos con Nombres Genéricos**

   - Algunos modelos tienen nombres incorrectos o de otras marcas
   - Requerir validación manual o tabla de mapeo correctivo

4. **Campos de Especificaciones Mezclados**
   - VersionCorta mezcla trim, specs técnicas y equipamiento
   - Aplicar limpieza exhaustiva según algoritmo propuesto

## 📈 Métricas de Calidad

- **Completitud del campo versión**: 100% (ningún NULL en activos)
- **TRIMs identificables**: ~60% (estimado basado en patrones)
- **Transmisión detectada**: 84.69% (campo numérico) + 72.9% (en texto)
- **Especificaciones técnicas presentes**: 43.4% (cilindrada), 21.5% (motor)

## 💡 Recomendaciones

1. **CRÍTICO**: Resolver problema de integridad referencial antes de procesar
2. **Usar SIEMPRE** la combinación IdMarca + IdSubTipo + Anio para uniones
3. **Filtrar** solo registros con Activo = 1
4. **Aplicar** algoritmo de limpieza propuesto para VersionCorta
5. **Validar** relación marca-modelo con catálogo maestro
6. **Implementar** caché de marcas/modelos válidos para validación
7. **Considerar** crear tabla de mapeo correctivo para modelos mal asignados

## 🔄 Query de Extracción Sugerido

```sql
SELECT
    v.IdVersion as id_original,
    m.NomMarca as marca,
    s.Descripcion as modelo,
    v.Anio as anio,
    CASE
        WHEN v.Transmision = 1 THEN 'MANUAL'
        WHEN v.Transmision = 2 THEN 'AUTO'
        ELSE NULL
    END as transmision,
    v.VersionCorta as version_completa,
    v.Activo as activo,
    v.IdMarca,
    v.IdSubTipo
FROM atlas.Vehiculo_Version v
INNER JOIN atlas.Marca m ON v.IdMarca = m.IdMarca
    AND v.Anio = m.Anio  -- CRÍTICO: incluir año
INNER JOIN atlas.SubTipo_Modelo s ON v.IdSubTipo = s.IdSubTipo
    AND v.Anio = s.Anio  -- CRÍTICO: incluir año
WHERE v.Activo = 1
    AND v.Anio BETWEEN 2000 AND 2030
ORDER BY m.NomMarca, s.Descripcion, v.Anio;
```

## ✅ Checklist de Validación

- [x] Identificar esquema y tablas relevantes
- [x] Verificar existencia de campo activo/vigente (Activo = bit)
- [x] Confirmar rango de años válidos (2000-2026)
- [x] Identificar campos clave (marca, modelo, año, versión)
- [x] Ejecutar queries estándar de análisis
- [x] Documentar % de registros activos (85.59%)
- [x] Identificar separadores en campo versión (espacios principalmente)
- [x] Mapear códigos de transmisión (0, 1, 2)
- [x] Extraer lista de TRIMs válidos
- [x] Detectar duplicados potenciales (1,635)
- [ ] Resolver problema de integridad referencial
- [ ] Validar marca-modelo contra catálogo maestro
