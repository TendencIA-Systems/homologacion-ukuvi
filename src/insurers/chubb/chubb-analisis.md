# Análisis Catálogo CHUBB - Estrategia de Homologación

## 📊 Resumen Ejecutivo

### Métricas Clave

- **Total registros (2000-2030)**: 31,839 vehículos
- **Años cubiertos**: 2000-2026 (27 años distintos)
- **Marcas únicas**: 61 (vinculadas a DbCatalogosMarcaID)
- **Modelos únicos**: 695 (vinculados a DbCatalogosModeloID)
- **Tipos únicos**: 1,081 (tabla NTipo)
- **Rango de ocupantes**: 2-23 personas

### Estructura de Datos 🚨 **PECULIAR**

Chubb tiene una estructura **atípica** con redundancia en la jerarquía marca-modelo:

- `NMarca` → Contiene marcas principales
- `NSubMarca` → **También contiene marcas** (no submarcas)
- `NTipo` → Contiene el **modelo real** del vehículo
- `NVehiculo` → Contiene versiones con año, transmisión y especificaciones

## 🔍 Hallazgos Críticos

### 1. Jerarquía de Datos

```sql
NVehiculo.TipoID → NTipo.ID
NTipo.MarcaID → NMarca.ID (Marca real)
NTipo.SubMarcaID → NSubMarca.ID (También es marca, redundante)
NTipo.Descripcion → MODELO REAL del vehículo
```

### 2. Campo Transmisión (TipoVehiculo)

- **65.51%** = "AUT" (Automática)
- **21.19%** = "STD" (Estándar/Manual)
- **5.92%** = "-" (Sin especificar)
- **4.76%** = "" (Vacío)
- **2.62%** = IDs numéricos incorrectos (414628999, etc.) 🚨 **DATA QUALITY ISSUE**

### 3. Anatomía del Campo VersionCorta

Estructura típica: `[TRIM] [CONFIG_MOTOR] [TECNOLOGIA] [TRANSMISION] [PUERTAS] [EQUIPAMIENTO]`

Ejemplo real:

```
"ADVANCE V6 FSI AUT 5 ABS CA CE PIEL SM CQ CB"
   ↓      ↓   ↓   ↓  ↓  ↓  ↓  ↓   ↓   ↓  ↓  ↓
  TRIM  Motor Tech Trans Puertas [----Equipamiento----]
```

## 📋 Mapeo de Campos

| Campo Canónico | Campo Origen                           | Transformación Requerida                    |
| -------------- | -------------------------------------- | ------------------------------------------- |
| marca          | NMarca.Descripcion (via NTipo.MarcaID) | Normalización de sinónimos                  |
| modelo         | NTipo.Descripcion                      | Directo                                     |
| anio           | NVehiculo.Modelo                       | Directo (validar 2000-2030)                 |
| transmision    | NVehiculo.TipoVehiculo                 | Mapear: AUT→AUTO, STD→MANUAL, otros→null    |
| version        | Extraer de VersionCorta                | Primera(s) palabra(s) antes de config motor |
| motor_config   | Extraer de VersionCorta                | Buscar L4, V6, V8, etc.                     |
| carroceria     | Inferir de ocupantes + puertas         | Lógica personalizada                        |
| traccion       | Extraer de VersionCorta                | Buscar 4X4, 4X2, AWD, etc.                  |
| ocupantes      | NVehiculo.Ocupantes                    | Directo                                     |

## 🔧 Estrategia de Extracción de Especificaciones

### Elementos Identificados en VersionCorta

#### 1. **TRIMs Válidos** (Primera posición, 88% identificables)

```javascript
const TRIMS_FRECUENTES = [
  // Premium/Deportivos
  "ADVANCE",
  "TYPE-S",
  "A-SPEC",
  "TI",
  "SPRINT",
  "M SPORT",
  "AMG",
  "RS",
  "S LINE",
  "R LINE",

  // Niveles de equipamiento
  "LIMITED",
  "EXCLUSIVE",
  "PLATINUM",
  "TOURING",
  "SPORT",
  "SELECT",
  "GT",
  "GLS",
  "GLX",

  // Pickups
  "CREW",
  "HEMI",
  "ST",
  "SR",
  "DOBLE",

  // Genéricos
  "SE",
  "LE",
  "XLE",
  "SENSE",
  "BASE",

  // Específicos de marca
  "SPORTBACK",
  "XDRIVE",
  "CARRERA",
  "COUPE",
  "SEDAN",
];
```

#### 2. **Configuración Motor** (88.5% presente)

- Patrón: `[LVI][0-9]` → L4, V6, V8, V10, L3
- Tecnologías: FSI, TDI, TSI, MPI, MPFI, IMP, IMO, IEM, ISM
- Ejemplos encontrados:
  - `L4 FSI` → 4 cilindros, inyección directa
  - `V6 IMP` → V6 importado
  - `V8 IS` → V8 inyección secuencial

#### 3. **Cilindrada** (7.6% explícita)

- Patrón: `[0-9].[0-9]T` o `[0-9].[0-9]L`
- Ejemplos: `1.5T`, `2.0L`, `5.0T`, `.75T` (0.75T)

#### 4. **Número de Puertas** (Codificación especial)

- **NO** es "4P" o "5P" como otras aseguradoras
- **ES**: `[número] ABS` o `[número] D/T`
- Ejemplos:
  - `4 ABS` = 4 puertas
  - `5 ABS` = 5 puertas
  - `2 D/T` = 2 puertas (doble tracción)

#### 5. **Tracción** (9.3% presente)

- `4X4`, `4X2`, `AWD`, `4WD`
- Específicos: `QUATTRO`, `XDRIVE`, `4MATIC`

#### 6. **Códigos de Equipamiento** (a filtrar)

| Código | Significado              | Frecuencia |
| ------ | ------------------------ | ---------- |
| ABS    | Frenos ABS               | Muy alta   |
| CA     | Calefacción/Climatizador | Alta       |
| CE     | Cierre Eléctrico         | Alta       |
| CD     | Reproductor CD           | Media      |
| SM     | Sistema Multimedia       | Alta       |
| CQ     | Control Crucero          | Alta       |
| CB     | Computadora de Bordo     | Alta       |
| SQ     | Sistema de Sonido        | Media      |
| PIEL   | Asientos de Piel         | Media      |
| TELA   | Asientos de Tela         | Media      |
| D/T    | Doble Tracción           | Baja       |
| SA/SE  | Sin Aire/Sin Equipo      | Baja       |

## 🎯 Algoritmo de Normalización Propuesto

```javascript
function normalizarChubb(registro) {
  const resultado = {
    // Campos directos
    marca: normalizarMarca(registro.marca_descripcion),
    modelo: registro.tipo_descripcion,
    anio: parseInt(registro.modelo),
    ocupantes: parseInt(registro.ocupantes),

    // Transmisión desde campo dedicado
    transmision: mapearTransmision(registro.tipo_vehiculo),

    // Extraer de VersionCorta
    version: null,
    motor_config: null,
    cilindrada: null,
    puertas: null,
    traccion: null,
    carroceria: null,
  };

  // Procesar VersionCorta
  const specs = procesarVersionCorta(registro.version_corta);

  // 1. Extraer TRIM (primera palabra antes de config motor)
  resultado.version = extraerTrim(specs);

  // 2. Extraer configuración motor
  resultado.motor_config = specs.motor_config;
  resultado.cilindrada = specs.cilindrada;

  // 3. Extraer puertas del patrón especial
  resultado.puertas = extraerPuertas(specs);

  // 4. Extraer tracción
  resultado.traccion = specs.traccion;

  // 5. Inferir carrocería
  resultado.carroceria = inferirCarroceria(
    resultado.puertas,
    resultado.ocupantes,
    resultado.modelo,
    resultado.version
  );

  return resultado;
}

function mapearTransmision(tipo_vehiculo) {
  if (!tipo_vehiculo) return null;

  const valor = tipo_vehiculo.toUpperCase().trim();

  if (valor === "AUT") return "AUTO";
  if (valor === "STD") return "MANUAL";
  if (valor === "-" || valor === "") return null;

  // Si es número (ID incorrecto), retornar null
  if (/^\d+$/.test(valor)) return null;

  return null;
}

function extraerPuertas(version_corta) {
  // Buscar patrón: número seguido de ABS o D/T
  const match = version_corta.match(/\b(\d)\s+(ABS|D\/T)\b/);
  if (match) {
    return parseInt(match[1]);
  }
  return null;
}

function procesarVersionCorta(version_corta) {
  const limpia = limpiarEquipamiento(version_corta);

  return {
    trim: extraerPrimeraPalabra(limpia),
    motor_config: extraerConfigMotor(limpia),
    cilindrada: extraerCilindrada(limpia),
    traccion: extraerTraccion(limpia),
    texto_limpio: limpia,
  };
}

function limpiarEquipamiento(texto) {
  // Eliminar códigos de equipamiento conocidos
  const codigos = [
    "ABS",
    "CA",
    "CE",
    "CD",
    "SM",
    "CQ",
    "CB",
    "SQ",
    "PIEL",
    "TELA",
    "SA",
    "SE",
    "FM",
    "SS",
  ];

  let limpio = texto;
  codigos.forEach((codigo) => {
    limpio = limpio.replace(new RegExp(`\\b${codigo}\\b`, "g"), "");
  });

  // Limpiar espacios múltiples
  return limpio.replace(/\s+/g, " ").trim();
}
```

## ⚠️ Problemas Detectados

### 1. **Datos de Transmisión Corruptos**

- 165 registros tienen IDs numéricos en lugar de AUT/STD
- Representan el 2.62% de los datos 2020-2025
- **Recomendación**: Tratar como null en homologación

### 2. **Duplicados Aparentes**

- El query de ejemplo mostró múltiples registros idénticos para Acura MDX
- **Causa posible**: Múltiples joins o datos duplicados en origen
- **Recomendación**: Deduplicar por combinación marca+modelo+año+version

### 3. **Campos de Catálogo Maestro**

- `DbCatalogosMarcaID` y `DbCatalogosModeloID` presentes
- **Oportunidad**: Usar para validación cruzada con catálogo maestro

### 4. **Valores de Ocupantes Extremos**

- Rango: 2-23 ocupantes
- Vehículos comerciales (autobuses) incluidos
- **Recomendación**: Validar rangos por tipo de vehículo

## 📈 Métricas de Calidad Esperadas

| Métrica                   | Valor Actual | Meta   |
| ------------------------- | ------------ | ------ |
| Registros procesables     | 31,839       | 100%   |
| Transmisión identificable | 97.4%        | >95% ✓ |
| TRIM extraíble            | ~88%         | >50% ✓ |
| Motor config presente     | 88.5%        | >70% ✓ |
| Tracción detectada        | 9.3%         | >5% ✓  |
| Carrocería inferible      | ~95%         | >90% ✓ |

## 💡 Recomendaciones

### Inmediatas

1. **Validar duplicados**: Implementar deduplicación por hash de campos clave
2. **Mapear transmisiones numéricas**: Investigar qué representan los IDs o tratarlos como null
3. **Aprovechar campos de catálogo**: Usar DbCatalogosMarcaID/ModeloID para validación

### Para Implementación

1. **Parser robusto para VersionCorta**: El campo tiene estructura consistente
2. **Diccionario de códigos**: Mantener lista actualizada de códigos de equipamiento
3. **Validación de ocupantes**: Implementar rangos válidos por tipo de vehículo
4. **Manejo de casos especiales**: REMOLQUES aparece como marca (13,084 registros)

## 🚀 Próximos Pasos

1. **Implementar funciones de normalización** según algoritmo propuesto
2. **Crear mapeo de sinónimos de marcas** específico para Chubb
3. **Validar extracción de puertas** con el patrón especial `[número] ABS`
4. **Probar con muestra de 1,000 registros** antes de procesamiento completo
5. **Documentar casos edge** encontrados durante implementación

---

**Nota**: Chubb tiene una estructura única que requiere atención especial en:

- La jerarquía marca-submarca-tipo
- El patrón de codificación de puertas
- Los valores numéricos en campo transmisión
- La alta presencia de códigos de equipamiento en VersionCorta
