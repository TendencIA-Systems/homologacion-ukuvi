# 📊 Análisis Catálogo HDI - Estrategia de Homologación

## Framework de Evaluación y Normalización

### 🎯 Resumen Ejecutivo

**Catálogo HDI - Métricas Clave:**

- **Total registros (2000-2030)**: 84,579 vehículos
- **Registros activos**: 38,186 (45.15%) ✅ **CRÍTICO: Solo procesar activos**
- **Registros inactivos**: 46,393 (54.85%)
- **Marcas únicas**: 107
- **Modelos únicos**: 2,067
- **Rango de años**: 2000-2026

**Comparación con Qualitas:**

- HDI tiene **3 veces mejor ratio de activos** (45% vs 15% de Qualitas)
- Estructura de datos **más limpia y organizada**
- Campo versión con **separación clara por comas**

---

## 🔍 Anatomía del Campo ClaveVersion

HDI utiliza una estructura **altamente estandarizada** con separadores de coma consistentes:

```
"[TRIM], [CONFIG_MOTOR], [CILINDRADA], [POTENCIA] CP, [PUERTAS] PUERTAS, [TRANSMISION], [EXTRAS]"
```

### Ejemplo Típico:

```
"GLS PREMIUM, L4, 1.5L, 113 CP, 5 PUERTAS, AUT, BA, AA"
```

#### Componentes Identificados (en orden típico):

1. **TRIM/VERSIÓN** (antes primera coma): `GLS PREMIUM`, `LIMITED`, `BASE`, `S LINE`
2. **CONFIG MOTOR** (después primera coma): `L4`, `L6`, `V6`, `V8`, `L3`
3. **CILINDRADA**: `1.5L`, `2.0T`, `3.5L` (T=Turbo integrado)
4. **POTENCIA**: `113 CP`, `250 CP` (siempre con "CP")
5. **PUERTAS**: `5 PUERTAS`, `4 PUERTAS`, `2 PUERTAS`
6. **TRANSMISIÓN**: `AUT`, `STD`, `CVT`, `DSG`
7. **EXTRAS/EQUIPAMIENTO**: `BA`, `AA`, `PIEL`, `QC`, etc.
8. **ELECTRIFICACIÓN**: `MHEV`, `HEV`, `PHEV`, `BEV`, `ELECTRICO`

---

## 📈 Estadísticas de Elementos Presentes (Solo Activos)

| Elemento                   | Registros | Porcentaje | Calidad      |
| -------------------------- | --------- | ---------- | ------------ |
| **Puertas especificadas**  | 25,830    | 67.6%      | ✅ Excelente |
| **Cilindrada**             | 26,342    | 69.0%      | ✅ Excelente |
| **Configuración motor**    | 24,128    | 63.2%      | ✅ Buena     |
| **Transmisión automática** | 17,989    | 47.1%      | ✅ Buena     |
| **Transmisión manual**     | 9,143     | 23.9%      | ✅ Buena     |
| **Turbo**                  | 9,406     | 24.6%      | ⚠️ Media     |
| **Tracción 4X4**           | 1,408     | 3.7%       | ⚠️ Baja      |
| **Tracción 4X2**           | 701       | 1.8%       | ⚠️ Baja      |
| **Electrificación total**  | 1,341     | 3.5%       | ⚠️ Baja      |

---

## 🎯 Estrategia de Extracción de TRIM

### Hallazgo Crítico:

HDI tiene una **estructura excepcionalmente limpia** donde el TRIM está **SIEMPRE antes de la primera coma**.

```javascript
function extraerTrimHDI(claveVersion) {
  if (!claveVersion) return null;

  // 1. Buscar posición de primera coma
  const primeraComa = claveVersion.indexOf(",");

  // 2. Si hay coma, extraer todo antes de ella
  if (primeraComa > 0) {
    const trim = claveVersion.substring(0, primeraComa).trim();

    // 3. Validar que no sea un valor técnico
    if (
      trim &&
      !trim.match(/^[LVI]\d+$/) && // No L4, V6, etc.
      !trim.match(/^\d+\.\d+[LT]?$/) && // No 2.0L, 1.5T
      !trim.match(/^\d+ PUERTAS?$/)
    ) {
      // No "4 PUERTAS"
      return trim.toUpperCase();
    }
  }

  // 4. Si no hay coma, es posible que todo sea el TRIM
  if (!claveVersion.includes(",")) {
    return claveVersion.trim().toUpperCase();
  }

  return null;
}
```

### Top 20 TRIMs Identificados:

| TRIM    | Frecuencia | Modelos Distintos |
| ------- | ---------- | ----------------- |
| BASE    | 214        | 66                |
| LIMITED | 106        | 31                |
| LT      | 104        | 20                |
| PREMIUM | 79         | 29                |
| I SPORT | 70         | 8                 |
| SE      | 67         | 19                |
| EX      | 66         | 12                |
| LS      | 65         | 13                |
| GLS     | 64         | 12                |
| ADVANCE | 63         | 14                |
| S LINE  | 62         | 9                 |
| LX      | 61         | 12                |
| LE      | 59         | 9                 |
| LUXURY  | 53         | 23                |
| XLE     | 53         | 9                 |

---

## 🔧 Estrategia de Extracción de Especificaciones Técnicas

```javascript
function extraerEspecificacionesHDI(claveVersion) {
  const specs = {
    motor_config: null,
    cilindrada: null,
    potencia: null,
    puertas: null,
    traccion: null,
    transmision: null,
    carroceria: null,
    electrificacion: null,
  };

  if (!claveVersion) return specs;

  // Separar por comas para análisis estructurado
  const partes = claveVersion.split(",").map((p) => p.trim());

  // 1. TRIM (primera parte) - ya extraído por separado

  // 2. CONFIGURACIÓN MOTOR (típicamente segunda parte)
  const motorPattern = /^[LVIHB](\d+)$/;
  for (const parte of partes) {
    if (motorPattern.test(parte)) {
      specs.motor_config = parte;
      break;
    }
  }

  // 3. CILINDRADA
  const cilindradaPattern = /(\d+\.?\d*)[LT]/;
  for (const parte of partes) {
    const match = parte.match(cilindradaPattern);
    if (match) {
      specs.cilindrada = parseFloat(match[1]);
      break;
    }
  }

  // 4. POTENCIA
  const potenciaPattern = /(\d+)\s*CP/;
  for (const parte of partes) {
    const match = parte.match(potenciaPattern);
    if (match) {
      specs.potencia = parseInt(match[1]);
      break;
    }
  }

  // 5. PUERTAS
  const puertasPattern = /(\d+)\s*PUERTAS?/;
  for (const parte of partes) {
    const match = parte.match(puertasPattern);
    if (match) {
      specs.puertas = parseInt(match[1]);
      break;
    }
  }

  // 6. TRANSMISIÓN
  const transmisiones = {
    AUT: "AUTO",
    STD: "MANUAL",
    MAN: "MANUAL",
    CVT: "AUTO", // Mapear CVT a AUTO
    DSG: "AUTO", // Mapear DSG a AUTO
    TIPTRONIC: "AUTO",
    STRONIC: "AUTO",
    PDK: "AUTO",
    DCT: "AUTO",
  };

  for (const parte of partes) {
    const parteUpper = parte.toUpperCase();
    for (const [key, value] of Object.entries(transmisiones)) {
      if (parteUpper === key || parteUpper.includes(key)) {
        specs.transmision = value;
        break;
      }
    }
    if (specs.transmision) break;
  }

  // 7. TRACCIÓN
  const tracciones = [
    "4X4",
    "4X2",
    "AWD",
    "FWD",
    "RWD",
    "QUATTRO",
    "XDRIVE",
    "4MATIC",
  ];
  for (const parte of partes) {
    const parteUpper = parte.toUpperCase();
    for (const traccion of tracciones) {
      if (parteUpper.includes(traccion)) {
        specs.traccion =
          traccion === "QUATTRO" ||
          traccion === "XDRIVE" ||
          traccion === "4MATIC"
            ? "AWD"
            : traccion;
        break;
      }
    }
    if (specs.traccion) break;
  }

  // 8. ELECTRIFICACIÓN
  const electrificaciones = {
    MHEV: "MHEV",
    "MILD HYBRID": "MHEV",
    HEV: "HEV",
    HYBRID: "HEV",
    HIBRIDO: "HEV",
    PHEV: "PHEV",
    "PLUG-IN": "PHEV",
    BEV: "BEV",
    ELECTRICO: "BEV",
    ELECTRIC: "BEV",
    EPOWER: "BEV",
  };

  for (const parte of partes) {
    const parteUpper = parte.toUpperCase();
    for (const [key, value] of Object.entries(electrificaciones)) {
      if (parteUpper.includes(key)) {
        specs.electrificacion = value;
        break;
      }
    }
    if (specs.electrificacion) break;
  }

  // 9. INFERIR CARROCERÍA
  specs.carroceria = inferirCarroceriaHDI(claveVersion, specs.puertas);

  return specs;
}
```

---

## 🚗 Inferencia de Carrocería

```javascript
function inferirCarroceriaHDI(claveVersion, puertas) {
  const version = claveVersion.toUpperCase();

  // Detección explícita en texto
  if (version.includes("SEDAN")) return "SEDAN";
  if (version.includes("SUV")) return "SUV";
  if (version.includes("HATCHBACK") || version.includes("HB"))
    return "HATCHBACK";
  if (version.includes("COUPE")) return "COUPE";
  if (version.includes("CONVERTIBLE") || version.includes("CABRIO"))
    return "CONVERTIBLE";
  if (version.includes("PICKUP") || version.includes("PICK UP"))
    return "PICKUP";
  if (version.includes("VAN")) return "VAN";
  if (version.includes("WAGON") || version.includes("ESTATE")) return "WAGON";
  if (version.includes("SPORT BACK") || version.includes("SPORTBACK"))
    return "SPORTBACK";

  // Casos especiales
  if (version.includes("CREW CAB") || version.includes("DOBLE CABINA"))
    return "PICKUP";
  if (version.includes("CHASIS CABINA")) return "PICKUP";

  // Inferencia por número de puertas
  if (puertas) {
    if (puertas === 2) return "COUPE";
    if (puertas === 3) return "HATCHBACK";
    if (puertas === 4) return "SEDAN";
    if (puertas === 5) return "SUV"; // Más común en HDI
  }

  return null;
}
```

---

## 📋 Mapeo de Campos HDI → Canónico

| Campo Canónico   | Campo HDI                             | Transformación Requerida                    |
| ---------------- | ------------------------------------- | ------------------------------------------- |
| **marca**        | `hdi.Marca.Descripcion` (con IdMarca) | Join necesario, normalización de texto      |
| **modelo**       | `hdi.Version.ClaveSubMarca`           | Directo, es string no ID                    |
| **anio**         | `hdi.Version.Anio`                    | Directo, ya es INT                          |
| **transmision**  | Extraer de `ClaveVersion`             | Parseo de texto, mapeo AUT→AUTO, STD→MANUAL |
| **version**      | Primera parte de `ClaveVersion`       | Split por coma, tomar primera parte         |
| **motor_config** | Extraer de `ClaveVersion`             | Buscar patrón L4, V6, etc.                  |
| **cilindrada**   | Extraer de `ClaveVersion`             | Buscar patrón decimal + L/T                 |
| **carroceria**   | Inferir de `ClaveVersion` y puertas   | Lógica de inferencia                        |
| **traccion**     | Extraer de `ClaveVersion`             | Buscar 4X4, AWD, FWD, etc.                  |
| **activo**       | `hdi.Version.Activo`                  | Directo, es BIT                             |

---

## ⚠️ Problemas Detectados y Soluciones

### 1. **Tabla Transmision Confusa**

- **Problema**: La tabla `hdi.Transmision` no es un catálogo simple, contiene versiones completas
- **Solución**: Ignorar tabla Transmision, extraer directamente de ClaveVersion

### 2. **Tracción con Baja Presencia**

- **Problema**: Solo 5.5% de registros tienen tracción especificada
- **Solución**: Aceptar null cuando no esté presente, no inventar valores

### 3. **Relaciones entre Tablas**

- **Problema**: ClaveSubMarca no es un ID, es el nombre directo del modelo
- **Solución**: Usar ClaveSubMarca directamente como modelo

### 4. **Marcas sin Nombre Directo**

- **Problema**: Tabla Marca usa "Descripcion" no "Marca"
- **Solución**: Join con hdi.Marca usando IdMarca

---

## 🎯 Algoritmo Completo de Normalización HDI

```javascript
function normalizarVersionHDI(registro) {
  const resultado = {
    // Campos directos
    marca: normalizarMarca(registro.marca_descripcion), // Viene del join
    modelo: normalizarModelo(registro.ClaveSubMarca),
    anio: parseInt(registro.Anio),
    activo: registro.Activo === 1,

    // Extraer del campo ClaveVersion
    version: null,
    transmision: null,
    motor_config: null,
    cilindrada: null,
    carroceria: null,
    traccion: null,
    potencia: null,
    puertas: null,
    electrificacion: null,
  };

  // 1. Extraer TRIM (puede ser null)
  resultado.version = extraerTrimHDI(registro.ClaveVersion);

  // 2. Extraer especificaciones técnicas
  const specs = extraerEspecificacionesHDI(registro.ClaveVersion);
  Object.assign(resultado, specs);

  // 3. Normalizar transmisión a formato canónico
  if (resultado.transmision) {
    resultado.transmision =
      resultado.transmision === "AUTO" ? "AUTO" : "MANUAL";
  }

  // 4. Generar identificadores
  resultado.string_comercial = [
    resultado.marca,
    resultado.modelo,
    resultado.anio,
    resultado.transmision,
  ]
    .filter(Boolean)
    .join("|");

  resultado.string_tecnico = [
    resultado.marca,
    resultado.modelo,
    resultado.anio,
    resultado.transmision,
    resultado.version,
    resultado.motor_config,
    resultado.carroceria,
    resultado.traccion,
  ]
    .filter(Boolean)
    .join("|");

  resultado.hash_comercial = generarHash(
    resultado.marca,
    resultado.modelo,
    resultado.anio,
    resultado.transmision
  );

  resultado.id_canonico = generarHash(
    resultado.marca,
    resultado.modelo,
    resultado.anio,
    resultado.transmision,
    resultado.version,
    resultado.motor_config,
    resultado.carroceria,
    resultado.traccion
  );

  // Metadata
  resultado.origen_aseguradora = "HDI";
  resultado.id_original = registro.IdVersion;
  resultado.version_original = registro.ClaveVersion;

  return resultado;
}
```

---

## 📊 Query de Extracción para HDI

```sql
-- Query optimizada para extracción de HDI con joins necesarios
SELECT
    v.IdVersion as id_original,
    m.Descripcion as marca,
    v.ClaveSubMarca as modelo,
    v.Anio as anio,
    v.ClaveVersion as version_completa,
    v.Activo as activo,
    v.IdMarca,
    v.DbCatalogosModeloID,
    v.DbCatalogosVersionID
FROM hdi.Version v
INNER JOIN (
    SELECT DISTINCT IdMarca, Descripcion
    FROM hdi.Marca
) m ON v.IdMarca = m.IdMarca
WHERE
    v.Activo = 1  -- CRÍTICO: Solo activos
    AND v.Anio BETWEEN 2000 AND 2030
ORDER BY
    m.Descripcion,
    v.ClaveSubMarca,
    v.Anio,
    v.ClaveVersion;
```

---

## ✅ Checklist de Validación HDI

- [x] **Filtrar por Activo = 1** (CRÍTICO)
- [x] Años entre 2000-2030
- [x] Transmisión normalizada (AUTO/MANUAL/null)
- [x] TRIM extraído de primera parte antes de coma
- [x] Especificaciones técnicas separadas sistemáticamente
- [x] Carrocería inferida cuando sea posible
- [x] No inventar valores cuando no existan
- [x] Hash comercial generado correctamente
- [x] ID canónico único generado

---

## 🚀 Ventajas de HDI vs Qualitas

1. **Estructura Superior**: Separación clara por comas vs campo contaminado
2. **Mayor Ratio de Activos**: 45% vs 15%
3. **TRIMs Limpios**: Primera posición consistente
4. **Especificaciones Ordenadas**: Patrón predecible
5. **Menos Ruido**: Menor presencia de códigos de equipamiento

---

## 📈 Métricas de Calidad Esperadas

- **TRIMs identificables**: ~85% (vs 58% en Qualitas)
- **Transmisión detectada**: ~75% (vs 96% en Qualitas)
- **Especificaciones completas**: ~65%
- **Carrocería inferible**: ~70%
- **Registros sin duplicados**: >95%

---

## 🔄 Proceso de Actualización Recomendado

1. **Extracción**: Query con JOIN a tabla Marca, solo Activo = 1
2. **Normalización**: Aplicar funciones de extracción documentadas
3. **Validación**: Verificar TRIMs contra lista conocida
4. **Deduplicación**: Por id_canonico antes de enviar
5. **Batch**: Procesar en lotes de 10,000 registros
6. **RPC Supabase**: Llamar a `procesar_batch_homologacion`
7. **Monitoreo**: Validar ratio de enriquecimiento vs conflictos

---

## 📝 Notas Finales

HDI presenta una **oportunidad excelente** para la homologación debido a su estructura limpia y consistente. La estrategia de extracción por posición (split por comas) es altamente confiable y debería producir resultados de alta calidad con mínima pérdida de información.

**Recomendación**: Procesar HDI como **segunda prioridad** después de Qualitas, ya que su estructura limpia permitirá validar y mejorar las reglas de homologación establecidas.
