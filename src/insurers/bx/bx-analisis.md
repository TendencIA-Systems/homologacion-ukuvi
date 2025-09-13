# Análisis Catálogo BX+ - Estrategia de Normalización

## Sistema de Homologación de Catálogos Vehiculares

### 📊 Resumen Ejecutivo

**Catálogo BX+ - Métricas Clave:**

- **Total registros (2000-2030)**: 39,728 vehículos
- **Registros activos**: 39,325 (98.99%) ⚠️ **CRÍTICO: Solo procesar activos**
- **Registros inactivos**: 403 (1.01%)
- **Marcas únicas**: 118
- **Modelos únicos (SubMarcas)**: 67 ⚠️ **ALERTA: Número bajo indica posibles duplicados**
- **Años distintos**: 27 (2000-2026)

### 🚨 Hallazgos Críticos

1. **Campo de activo/vigente**: Existe como `Activa` (bit) con excelente cobertura (98.99% activos)
2. **Estructura del campo versión**: Altamente heterogénea con 3 formatos principales
3. **Transmisión**: Campo dedicado `Transmision` con códigos: 2=AUTO (67.76%), 1=MANUAL (31.23%), 0=No especificado (1.01%)
4. **Duplicados masivos**: Datos con hasta 137K versiones para BMW (claramente anómalo)
5. **Problemas de integridad**: Modelos mal asignados a marcas (ej: "COOPER S" en KIA)

### 📋 Mapeo de Campos

| Campo Canónico | Campo Origen                              | Transformación Requerida                           |
| -------------- | ----------------------------------------- | -------------------------------------------------- |
| marca          | `bx.Marca.descMarca`                      | Normalización directa con diccionario de sinónimos |
| modelo         | `bx.SubMarca.descSubMarca`                | Normalización directa                              |
| anio           | `bx.Modelo.idModelo`                      | Conversión directa (ya es INT)                     |
| transmision    | `bx.Version.Transmision`                  | Mapeo: 2→AUTO, 1→MANUAL, 0→null                    |
| version        | Extraer de `descVersion` o `VersionCorta` | Estrategia compleja de extracción (ver abajo)      |
| motor_config   | Extraer de `descVersion`                  | Buscar patrones L4, V6, V8, etc.                   |
| carroceria     | Extraer de `descVersion`                  | Inferir por palabras clave y puertas               |
| traccion       | Extraer de `descVersion`                  | Buscar 4X4, 4X2, AWD, FWD, RWD                     |

### 🔍 Anatomía del Campo `descVersion`

#### Tres Formatos Principales Identificados:

**Formato 1: Con Ocupantes (24.6% de registros)**

```
"CHASIS CAB SILVERADO 3500 A STD. 03 OCUP."
[TIPO] [TRIM/MODELO] [ESPECIFICACIONES] [TRANSMISIÓN]. [OCUPANTES] OCUP.
```

**Formato 2: Con Comas (registros más nuevos)**

```
"UNLIMITED RUBICON RECON, V6, 3.6L, 285 CP, 5 PTAS, AUT, NAVI"
[TRIM], [CONFIG_MOTOR], [CILINDRADA], [POTENCIA], [PUERTAS], [TRANSMISIÓN], [EQUIPAMIENTO]
```

**Formato 3: Espacios sin estructura clara**

```
"STINGRAY Z51 COUPE PERFORMANCE PACKAGE V8 6.2L 460 2PTAS AUT"
[TRIM MÚLTIPLE] [CONFIG_MOTOR] [CILINDRADA] [POTENCIA] [PUERTAS] [TRANSMISIÓN]
```

### 📊 Estadísticas de Elementos Presentes

| Elemento             | Registros | Porcentaje | Patrón de Extracción       |
| -------------------- | --------- | ---------- | -------------------------- | -------- | ------ | --- | ---- |
| Config Motor         | 4,415     | 11.2%      | `\b[VLI]\d+\b`             |
| Cilindrada           | 29,513    | 75.0%      | `\d+\.\d+[LT]`             |
| Turbo                | 10,080    | 25.6%      | `TURBO                     | TBO      | T\s`   |
| Puertas              | ~15,000   | ~38%       | `\d+\s\*P(TAS?             | UERTAS)` |
| Tracción             | 5,004     | 12.7%      | `4X4                       | 4X2      | AWD    | FWD | RWD` |
| Transmisión texto    | 29,701    | 75.5%      | `AUT\.                     | STD\.    | MAN\b` |
| Ocupantes            | 9,667     | 24.6%      | `\d{2}\s+OCUP\.`           |
| Carrocería explícita | ~5,500    | ~14%       | Palabras clave específicas |

### 🎯 Estrategia de Extracción de TRIM

#### TRIMs Válidos Identificados (Top 30)

| TRIM      | Frecuencia | Versiones Distintas |
| --------- | ---------- | ------------------- |
| BASE      | 110        | 58                  |
| LIMITED   | 107        | 56                  |
| GLS       | 80         | 33                  |
| GL        | 68         | 29                  |
| LT        | 68         | 25                  |
| GT        | 66         | 33                  |
| PREMIUM   | 61         | 31                  |
| EX        | 59         | 26                  |
| SPORT     | 54         | 23                  |
| ADVANCE   | 50         | 20                  |
| GLX       | 48         | 21                  |
| LX        | 44         | 17                  |
| ALLURE    | 41         | 16                  |
| PLATINUM  | 41         | 22                  |
| EXCLUSIVE | 40         | 20                  |

### 🔧 Algoritmo de Normalización Propuesto

```javascript
function normalizarVersionBX(registro) {
  const resultado = {
    // Campos directos
    marca: normalizarMarca(registro.descMarca),
    modelo: normalizarModelo(registro.descSubMarca),
    anio: parseInt(registro.idModelo),

    // Transmisión desde campo dedicado
    transmision:
      registro.Transmision === 2
        ? "AUTO"
        : registro.Transmision === 1
        ? "MANUAL"
        : null,

    // Campos a extraer
    version: null,
    motor_config: null,
    carroceria: null,
    traccion: null,
  };

  // Seleccionar campo fuente (VersionCorta generalmente más limpia)
  const campoVersion = registro.VersionCorta || registro.descVersion;

  // 1. Detectar formato
  const formato = detectarFormato(campoVersion);

  // 2. Extraer según formato
  if (formato === "OCUPANTES") {
    resultado.version = extraerTrimFormatoOcupantes(campoVersion);
    resultado.ocupantes = extraerOcupantes(campoVersion);
  } else if (formato === "COMAS") {
    const partes = campoVersion.split(",").map((p) => p.trim());
    resultado.version = extraerTrimDeParte(partes[0]);
    resultado.motor_config = extraerMotorConfig(partes[1]);
    // ... procesar otras partes
  } else {
    resultado.version = extraerTrimGenerico(campoVersion);
  }

  // 3. Extraer especificaciones técnicas
  resultado.motor_config = extraerMotorConfig(campoVersion);
  resultado.traccion = extraerTraccion(campoVersion);
  resultado.carroceria = inferirCarroceria(campoVersion, resultado.modelo);

  // 4. Generar identificadores
  resultado.hash_comercial = generarHash(
    resultado.marca,
    resultado.modelo,
    resultado.anio,
    resultado.transmision
  );

  resultado.id_canonico = generarHash(
    resultado.hash_comercial,
    resultado.version,
    resultado.motor_config,
    resultado.carroceria,
    resultado.traccion
  );

  return resultado;
}
```

### ⚠️ Problemas Detectados y Mitigaciones

#### 1. **Duplicados Masivos**

- **Problema**: BMW con 137K versiones activas (imposible en realidad)
- **Causa**: Posible problema en joins o datos duplicados en origen
- **Mitigación**: Deduplicar por combinación única antes de procesar

#### 2. **Modelos Incorrectos**

- **Problema**: Modelos asignados a marcas incorrectas (ej: "COOPER S" en múltiples marcas)
- **Causa**: Error en datos origen o mapeo incorrecto
- **Mitigación**: Validación cruzada marca-modelo con catálogo maestro

#### 3. **Formato Inconsistente**

- **Problema**: Tres formatos completamente diferentes en `descVersion`
- **Causa**: Evolución histórica sin normalización
- **Mitigación**: Detectar formato antes de procesar

#### 4. **TRIMs No Estándar**

- **Problema**: Algunos registros tienen "CHASIS CAB" como trim
- **Causa**: Mezcla de tipo de carrocería con trim
- **Mitigación**: Lista de exclusión para términos que no son trim

### 📐 Reglas de Normalización Específicas

#### Detección de Formato

```javascript
function detectarFormato(version) {
  if (/\d{2}\s+OCUP\.?$/.test(version)) return "OCUPANTES";
  if (version.includes(",")) return "COMAS";
  return "ESPACIOS";
}
```

#### Extracción de Ocupantes

```javascript
function extraerOcupantes(version) {
  const match = version.match(/(\d{2})\s+OCUP\.?/);
  return match ? parseInt(match[1]) : null;
}
```

#### Limpieza de TRIM

```javascript
function limpiarTrim(version) {
  // Eliminar todo después de "OCUP."
  let clean = version.replace(/\.\s*\d{2}\s+OCUP\.?$/, "");

  // Eliminar transmisión
  clean = clean.replace(/\b(AUT|STD|MAN|CVT)\.?\s*$/, "");

  // Eliminar códigos de equipamiento
  clean = clean.replace(/\b(BA|AA|QC|CD|VP|NAVI|PIEL)\b/g, "");

  // Obtener primera palabra significativa
  const palabras = clean
    .split(/[\s,]+/)
    .filter(
      (p) => p.length > 1 && !["L4", "V6", "V8", "4X4", "4X2"].includes(p)
    );

  return validarTrim(palabras[0]) ? palabras[0] : null;
}
```

### 🏗️ Inferencia de Carrocería

```javascript
function inferirCarroceria(version, modelo) {
  const versionUpper = version.toUpperCase();

  // 1. Buscar indicadores explícitos
  if (/\bSEDAN\b/.test(versionUpper)) return "SEDAN";
  if (/\bSUV\b/.test(versionUpper)) return "SUV";
  if (/\b(HATCHBACK|HB)\b/.test(versionUpper)) return "HATCHBACK";
  if (/\b(PICKUP|PICK[\s-]UP)\b/.test(versionUpper)) return "PICKUP";
  if (/\bCOUPE\b/.test(versionUpper)) return "COUPE";
  if (/\b(CONVERTIBLE|CABRIO)\b/.test(versionUpper)) return "CONVERTIBLE";
  if (/\b(VAN|BUS)\b/.test(versionUpper)) return "VAN";
  if (/\bCHASIS\s+CAB\b/.test(versionUpper)) return "PICKUP";

  // 2. Inferir por número de puertas
  const puertasMatch = versionUpper.match(/(\d)\s*P(TAS?|UERTAS)?/);
  if (puertasMatch) {
    const puertas = parseInt(puertasMatch[1]);
    if (puertas === 2) return "COUPE";
    if (puertas === 3) return "HATCHBACK";
    if (puertas === 4) return "SEDAN";
    if (puertas === 5) return "HATCHBACK";
  }

  // 3. Por ocupantes (vans/buses)
  const ocupantesMatch = versionUpper.match(/(\d+)\s+OCUP/);
  if (ocupantesMatch) {
    const ocupantes = parseInt(ocupantesMatch[1]);
    if (ocupantes > 8) return "VAN";
  }

  return null;
}
```

### 📋 Checklist de Validación

- [x] **Filtrar por Activa = 1** (CRÍTICO - 98.99% de registros)
- [x] Años entre 2000-2030
- [x] Transmisión normalizada (AUTO/MANUAL/null) desde campo dedicado
- [x] TRIM extraído o null (manejar 3 formatos diferentes)
- [x] Especificaciones técnicas separadas
- [x] Carrocería inferida cuando sea posible
- [x] Hash comercial generado
- [x] ID canónico único generado
- [x] Ocupantes extraídos cuando aplique

### 🚨 Recomendaciones Críticas

1. **Deduplicación Urgente**: Antes de cualquier procesamiento, deduplicar por marca+modelo+año+versión
2. **Validación Marca-Modelo**: Crear tabla de validación para evitar modelos en marcas incorrectas
3. **Procesamiento por Formato**: Implementar 3 pipelines diferentes según formato detectado
4. **Logging Extensivo**: Registrar todos los casos donde no se puede extraer TRIM
5. **Revisión Manual**: Los 67 modelos únicos sugieren problemas graves de mapeo

### 📊 Métricas de Calidad Esperadas

- Completitud del campo versión: ~40% (muchos no tienen TRIM real)
- TRIMs identificables: ~35-40%
- Transmisión detectada: 99% (campo dedicado)
- Carrocería inferible: ~60%
- Especificaciones técnicas presentes: ~75%

### 🔄 Proceso de Actualización

1. **Extracción**: Query solo registros con `Activa = 1`
2. **Deduplicación**: Eliminar duplicados obvios antes de normalizar
3. **Normalización**: Aplicar pipeline según formato detectado
4. **Validación**: Verificar marca-modelo contra catálogo maestro
5. **Batch**: Procesar en lotes de 5,000 registros (por los duplicados)
6. **RPC Supabase**: Llamar a `procesar_batch_homologacion`

### ⚡ Casos Especiales BX+

1. **Formato "OCUP."**: 24.6% de registros terminan con ". XX OCUP."
2. **CHASIS CAB**: Común en pickups, mapear a carrocería PICKUP
3. **Transmisión código 0**: 1% de casos, posiblemente híbridos o eléctricos
4. **Versiones idénticas**: Múltiples modelos con exactamente la misma versión (error de datos)
5. **VersionCorta vs descVersion**: Generalmente idénticas, preferir VersionCorta si existe

### 🎯 Próximos Pasos

1. Implementar script de deduplicación
2. Crear pipeline de normalización con detección de formato
3. Validar muestra de 1,000 registros
4. Ajustar reglas según resultados
5. Procesar lote completo de activos
