# Análisis Catálogo ANA - Estrategia de Normalización

[📄 Ver archivo completo](computer:///home/claude/ana_analisis_normalizacion.md)

## 📊 Resumen Ejecutivo

- **Total registros (2000-2030)**: 35,704
- **Registros activos**: 28,611 (80.13%) ✅ Excelente porcentaje
- **Registros inactivos**: 7,093 (19.87%)
- **Marcas únicas**: 63
- **Modelos únicos**: 765
- **Rango de años**: 2000-2026
- **Posibles duplicados**: 459

## 🚨 Hallazgos Críticos

### 1. **Campo de Estado Activo**

- ✅ **EXISTE** campo `Activo` tipo bit (1=activo, 0=inactivo)
- 80.13% de registros activos (mucho mejor que Qualitas con 15.47%)
- **Recomendación**: Procesar solo registros con `Activo = 1`

### 2. **Estructura del Campo VersionCorta**

El campo contiene múltiples elementos mezclados:

- **Prefijos de marca** (2 letras): CH CHEVROLET, VW VOLKSWAGEN, MZ MERCEDES
- **TRIM/Versión**: LIMITED, SPORT, GLS, ELITE, S LINE, etc.
- **Cilindrada**: 1.5, 2.0, 3.0T, 2.4
- **Transmisión**: AUTOMATICA, ESTANDAR, MANUAL (redundante con campo dedicado)
- **Puertas**: 2PTAS, 3PTAS, 4PTAS, 5PTAS
- **Equipamiento**: VP, QC, ABS, BA, GPS
- **Tracción**: 4X4, AWD, QUATTRO, 4WD

### 3. **Transmisión**

- ✅ **Campo dedicado** `Transmision` con códigos numéricos:
  - `1` = MANUAL (29.35%)
  - `2` = AUTO (63.56%)
  - `0` = DESCONOCIDO (7.09%)
- La transmisión también aparece en texto dentro de VersionCorta (redundante)

### 4. **Problemas de Calidad Detectados**

- **Marca duplicada**: ISUZU / IZSUZU (mismo catálogo, diferente escritura)
- **Prefijos inconsistentes**: Algunas versiones tienen código de marca de 2 letras, otras no
- **459 posibles duplicados** en el catálogo

## 📋 Mapeo de Campos

| Campo Canónico | Campo Origen                      | Transformación Requerida                                |
| -------------- | --------------------------------- | ------------------------------------------------------- |
| marca          | NMarca.Descripcion                | Normalización y corrección de duplicados (ISUZU/IZSUZU) |
| modelo         | NSubMarca.Descripcion             | Directo, ya normalizado                                 |
| anio           | NVersiones.Modelo                 | Directo (validar rango 2000-2030)                       |
| transmision    | NVersiones.Transmision            | Mapeo: 1→MANUAL, 2→AUTO, 0→NULL                         |
| version        | Extraer de VersionCorta           | Estrategia de extracción compleja                       |
| motor_config   | Extraer de VersionCorta           | Buscar patrones L4, V6, V8, I4                          |
| carroceria     | Inferir de VersionCorta y puertas | Lógica de inferencia por puertas                        |
| traccion       | Extraer de VersionCorta           | Buscar 4X4, AWD, 4WD, QUATTRO                           |

## 🔧 Reglas de Normalización Específicas

### Marcas con Correcciones Necesarias

- `IZSUZU` → `ISUZU` (error ortográfico consistente)
- `MERCEDES BENZ` → conservar con espacio
- Remover prefijos de 2 letras del campo VersionCorta

### Códigos de Transmisión

```javascript
function normalizarTransmision(codigo) {
  switch (codigo) {
    case 1:
      return "MANUAL";
    case 2:
      return "AUTO";
    case 0:
    default:
      return null;
  }
}
```

## 🎯 Estrategia de Extracción de TRIM

### Análisis de Patrones Encontrados

#### TRIMs Identificados con Alta Frecuencia

- **Premium/Lujo**: ELITE, PREMIUM, LIMITED, EXCLUSIVE
- **Deportivos**: SPORT, S LINE, RS, GTI, AMG, M SPORT
- **Niveles medios**: GLS, GLE, GLX, SEL, XLE
- **Básicos**: BASE, GL, DX, LS
- **Pickups**: LARAMIE, LARIAT, KING RANCH, HIGH COUNTRY

### Algoritmo de Extracción Propuesto

```javascript
function extraerTrim(versionCorta) {
  let version = versionCorta.toUpperCase();

  // PASO 1: Eliminar prefijo de marca (2 letras + espacio)
  version = version.replace(/^[A-Z]{2}\s+[A-Z]+\s+/, "");

  // PASO 2: Eliminar transmisión
  version = version.replace(
    /\b(AUTOMATICA|ESTANDAR|MANUAL|CVT|TIPTRONIC|S[\s-]?TRONIC)\b/g,
    ""
  );

  // PASO 3: Eliminar puertas
  version = version.replace(/\b\d+PTAS?\b/g, "");
  version = version.replace(/\b\d+P\b/g, "");

  // PASO 4: Eliminar cilindrada
  version = version.replace(/\b\d+\.\d+[TL]?\b/g, "");

  // PASO 5: Eliminar configuración motor
  version = version.replace(/\b[VLI]\d+\b/g, "");

  // PASO 6: Eliminar equipamiento
  version = version.replace(/\b(VP|QC|ABS|BA|GPS|AA|AC|CD|DVD)\b/g, "");

  // PASO 7: Buscar TRIM en lista blanca
  const TRIMS_VALIDOS = [
    "ELITE",
    "PREMIUM",
    "LIMITED",
    "SPORT",
    "S LINE",
    "GLS",
    "GLE",
    "GLX",
    "SEL",
    "XLE",
    "BASE",
    "LARAMIE",
    "LARIAT",
    "KING RANCH",
    "HIGH COUNTRY",
    "DENALI",
    "AT4",
    "Z71",
    "RUBICON",
    "SAHARA",
  ];

  for (const trim of TRIMS_VALIDOS) {
    if (version.includes(trim)) {
      return trim;
    }
  }

  // Si no hay trim válido, retornar null
  return null;
}
```

## 📊 Especificaciones Técnicas Detectadas

| Especificación   | Registros | Porcentaje | Estrategia de Extracción       |
| ---------------- | --------- | ---------- | ------------------------------ |
| **Puertas**      | 21,445    | 74.95%     | Regex: `/\b(\d+)PTAS?\b/`      |
| **Cilindrada**   | 3,739     | 13.07%     | Regex: `/(\d+\.\d+)[TL]?/`     |
| **Turbo**        | 6,479     | 22.65%     | Buscar: TURBO, TBO, T          |
| **Tracción**     | 2,762     | 9.65%      | Buscar: 4X4, AWD, 4WD, QUATTRO |
| **Config Motor** | 332       | 1.16%      | Regex: `/\b([VLI])(\d+)\b/`    |

### Inferencia de Carrocería por Puertas

```javascript
function inferirCarroceria(versionCorta, modelo) {
  // Búsqueda directa en texto
  if (/SEDAN/i.test(versionCorta)) return "SEDAN";
  if (/SUV/i.test(versionCorta)) return "SUV";
  if (/PICKUP|PICK.UP/i.test(versionCorta)) return "PICKUP";
  if (/COUPE/i.test(versionCorta)) return "COUPE";
  if (/HATCHBACK|HB/i.test(versionCorta)) return "HATCHBACK";
  if (/VAN/i.test(versionCorta)) return "VAN";
  if (/CONVERTIBLE|CABRIO/i.test(versionCorta)) return "CONVERTIBLE";

  // Inferencia por número de puertas
  const puertasMatch = versionCorta.match(/(\d+)PTAS?/);
  if (puertasMatch) {
    const puertas = parseInt(puertasMatch[1]);
    switch (puertas) {
      case 2:
        return "COUPE";
      case 3:
        return "HATCHBACK";
      case 4:
        return "SEDAN";
      case 5:
        return "HATCHBACK"; // o SUV según modelo
    }
  }

  return null;
}
```

## ⚠️ Problemas Detectados

### 1. **Prefijos de Marca Inconsistentes**

- 50% de registros tienen prefijo de 2 letras + nombre completo de marca
- Ejemplo: "CH CHEVROLET EQUINOX RS" vs "EQUINOX RS"
- **Solución**: Eliminar patrón `/^[A-Z]{2}\s+[A-Z]+\s+/`

### 2. **Duplicación de Marca ISUZU**

- ISUZU: 1,618 registros activos
- IZSUZU: 1,618 registros activos (duplicados exactos)
- **Solución**: Normalizar IZSUZU → ISUZU en proceso

### 3. **Transmisión Redundante**

- Aparece en campo dedicado Y en texto de VersionCorta
- **Solución**: Usar campo dedicado, ignorar texto

### 4. **Campos con Alto Porcentaje de Especificaciones**

- 74.95% tienen puertas especificadas
- Solo 13.07% tienen cilindrada
- Solo 1.16% tienen configuración de motor
- **Impacto**: Carrocería se puede inferir bien, motor_config será mayormente NULL

## 🔄 Proceso de Normalización Completo

```javascript
function normalizarRegistroANA(registro) {
  const resultado = {
    // Campos directos
    marca: normalizarMarca(registro.NMarca.Descripcion),
    modelo: registro.NSubMarca.Descripcion,
    anio: registro.Modelo,

    // Transmisión desde campo dedicado
    transmision: normalizarTransmision(registro.Transmision),

    // Extraer del campo VersionCorta
    version: null,
    motor_config: null,
    carroceria: null,
    traccion: null,
  };

  // Limpiar prefijo de marca si existe
  let versionLimpia = limpiarPrefijoMarca(registro.VersionCorta);

  // Extraer especificaciones
  resultado.version = extraerTrim(versionLimpia);
  resultado.motor_config = extraerConfigMotor(versionLimpia);
  resultado.carroceria = inferirCarroceria(versionLimpia, registro.modelo);
  resultado.traccion = extraerTraccion(versionLimpia);

  // Generar identificadores
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

## 📈 Métricas de Calidad Esperadas

- **Completitud del campo versión**: ~40% (muchos no tienen TRIM real)
- **TRIMs identificables**: ~35-40%
- **Transmisión detectada**: 92.91% (campo dedicado)
- **Carrocería inferible**: ~75% (por puertas)
- **Especificaciones técnicas**: ~20% (motor, tracción)

## 💡 Recomendaciones

1. **Procesar solo registros con `Activo = 1`** (28,611 registros)
2. **Corregir duplicación ISUZU/IZSUZU** durante normalización
3. **Usar campo Transmision dedicado**, no el texto
4. **Implementar lógica robusta de inferencia de carrocería** por puertas
5. **Aceptar que muchos campos técnicos serán NULL** (normal y esperado)
6. **Considerar prefijos de marca** en limpieza de VersionCorta

## 🚀 Siguiente Paso

1. Implementar función de normalización en n8n
2. Validar con muestra de 1,000 registros
3. Ajustar reglas según resultados
4. Procesar batch completo de 28,611 registros activos
5. Enviar a RPC `procesar_batch_homologacion`

## 📝 Query de Extracción para n8n

```sql
SELECT
    v.ID as id_original,
    m.Descripcion as marca,
    sm.Descripcion as modelo,
    v.Modelo as anio,
    v.Transmision as transmision_codigo,
    v.VersionCorta as version_completa,
    v.Activo as activo,
    v.DbCatalogosModeloID as catalogo_modelo_id,
    v.DbCatalogosMarcaID as catalogo_marca_id
FROM ana.NVersiones v
INNER JOIN ana.NMarca m ON v.MarcaClave = m.Clave
INNER JOIN ana.NSubMarca sm ON v.SubMarcaClave = sm.Clave
    AND v.MarcaClave = sm.MarcaClave
WHERE v.Activo = 1
    AND v.Modelo BETWEEN 2000 AND 2030
ORDER BY m.Descripcion, sm.Descripcion, v.Modelo;
```
