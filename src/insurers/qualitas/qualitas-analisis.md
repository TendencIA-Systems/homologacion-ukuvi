# Análisis de Patrones del Campo cVersion - Qualitas

## Estrategia de Extracción y Normalización

### 📊 Resumen Ejecutivo del Análisis

**Catálogo Qualitas - Métricas Clave:**

- **Total registros (2000-2030)**: 256,803 vehículos
- **Registros activos**: 39,715 (15.47%) ⚠️ **CRÍTICO: Solo procesar activos**
- **Registros inactivos**: 217,088 (84.53%)
- **Marcas únicas**: 147
- **Modelos únicos**: 1,832
- **Rango de años**: 2000-2026

### 🔍 Anatomía del Campo cVersion

El campo `cVersion` de Qualitas es un campo **altamente contaminado** que mezcla múltiples tipos de información sin estructura consistente. Ejemplo típico:

```
"ADVANCE 5P L4 1.5T BA ABS AA VP AUT., 05 OCUP."
```

#### Componentes Identificados (en orden de aparición típica):

1. **TRIM/VERSIÓN** (inicio): `ADVANCE`, `A-SPEC`, `TYPE S`, `TECH`, etc.
2. **PUERTAS**: `2P`, `3P`, `4P`, `5P`
3. **CONFIG MOTOR**: `L4`, `L6`, `V6`, `V8`, `I4`
4. **CILINDRADA**: `1.5L`, `2.0T`, `3.5L` (L=Litros, T=Turbo)
5. **EQUIPAMIENTO**: Códigos de 2-3 letras
6. **TRANSMISIÓN**: `AUT`, `STD`, `MAN`, `CVT`, `DSG`
7. **OCUPANTES**: `05 OCUP`, `07 OCUP`, etc.

### 📈 Estadísticas de Elementos Presentes (Solo Activos)

| Elemento             | Registros | Porcentaje |
| -------------------- | --------- | ---------- |
| Transmisión en texto | 38,299    | 96.4%      |
| Ocupantes            | 38,080    | 95.9%      |
| Cilindrada           | 22,995    | 57.9%      |
| Número de puertas    | 21,265    | 53.5%      |
| Configuración motor  | 19,308    | 48.6%      |
| Turbo                | 19,296    | 48.6%      |
| Equipamiento         | 17,077    | 43.0%      |
| Tracción             | 5,385     | 13.6%      |
| Rines                | 5,166     | 13.0%      |
| Electrificación      | 2,479     | 6.2%       |

### 🎯 Estrategia de Extracción de TRIM

#### Hallazgo Crítico: Solo el 57.82% tiene TRIM identificable

```javascript
// ESTRATEGIA DE EXTRACCIÓN DE TRIM
function extraerTrim(cVersion) {
  // 1. Limpiar separadores especiales
  let version = cVersion.replace(/[,\.]/g, " ");

  // 2. Buscar en lista blanca (ordenada por prioridad)
  const TRIMS_VALIDOS = [
    // Premium/Deportivos (prioridad alta)
    "TYPE S",
    "TYPE R",
    "TYPE A",
    "A-SPEC",
    "A SPEC",
    "QUADRIFOGLIO",
    "QV",
    "M SPORT",
    "AMG LINE",
    "RS LINE",
    "R LINE",
    "S LINE",

    // Niveles de equipamiento
    "ADVANCE",
    "TECH",
    "EXCLUSIVE",
    "PREMIUM",
    "SPORT",
    "LIMITED",
    "ELITE",
    "TITANIUM",
    "PLATINUM",

    // Italianos
    "VELOCE",
    "TI",
    "LUSSO",
    "SPRINT",
    "ESTREMA",
    "COMPETIZIONE",

    // Pickups
    "DENALI",
    "LARAMIE",
    "LARIAT",
    "KING RANCH",
    "RAPTOR",
    "SAHARA",
    "RUBICON",
    "HIGH COUNTRY",
    "Z71",
    "ZR2",

    // Genéricos (prioridad baja)
    "LTZ",
    "LT",
    "LS",
    "SE",
    "SEL",
    "SV",
    "SL",
    "SR",
    "SR5",
    "XLE",
    "XSE",
    "LE",
    "DX",
    "LX",
    "EX",
    "SI",
    "TOURING",
    "BASE",
  ];

  // 3. Buscar primera coincidencia
  for (const trim of TRIMS_VALIDOS) {
    if (version.includes(trim)) {
      return trim;
    }
  }

  // 4. Si no hay trim válido, retornar null (NO "BASE")
  return null;
}
```

### 🔧 Estrategia de Extracción de Especificaciones Técnicas

```javascript
function extraerEspecificaciones(cVersion) {
  const specs = {
    motor_config: null,
    cilindrada: null,
    turbo: false,
    puertas: null,
    traccion: null,
    transmision_texto: null,
    ocupantes: null,
    electrificacion: null,
  };

  // 1. CONFIGURACIÓN MOTOR (L4, V6, etc.)
  const motorMatch = cVersion.match(/\b([VLIH])(\d+)\b/);
  if (motorMatch) {
    specs.motor_config = motorMatch[0];
  }

  // 2. CILINDRADA (1.5L, 2.0T)
  const cilindradaMatch = cVersion.match(/(\d+\.?\d*)[LT]/);
  if (cilindradaMatch) {
    specs.cilindrada = parseFloat(cilindradaMatch[1]);
  }

  // 3. TURBO
  if (/\b(TURBO|TBO|BITBO|[0-9]T\b)/.test(cVersion)) {
    specs.turbo = true;
  }

  // 4. PUERTAS
  const puertasMatch = cVersion.match(/(\d)P\b/);
  if (puertasMatch) {
    specs.puertas = parseInt(puertasMatch[1]);
  }

  // 5. TRACCIÓN
  if (/\b(AWD|4WD|4X4)\b/.test(cVersion)) {
    specs.traccion = cVersion.match(/\b(AWD|4WD|4X4)\b/)[1];
  } else if (/\b(FWD|RWD)\b/.test(cVersion)) {
    specs.traccion = cVersion.match(/\b(FWD|RWD)\b/)[1];
  }

  // 6. TRANSMISIÓN EN TEXTO (redundante con campo cTransmision)
  if (/\b(AUT|AUTO|AUTOMATIC)\b/.test(cVersion)) {
    specs.transmision_texto = "AUTO";
  } else if (/\b(STD|MAN|MANUAL|EST)\b/.test(cVersion)) {
    specs.transmision_texto = "MANUAL";
  } else if (/\b(CVT|DSG|PDK|DCT)\b/.test(cVersion)) {
    specs.transmision_texto = cVersion.match(/\b(CVT|DSG|PDK|DCT)\b/)[1];
  }

  // 7. OCUPANTES
  const ocupantesMatch = cVersion.match(/(\d+)\s*OCUP/);
  if (ocupantesMatch) {
    specs.ocupantes = parseInt(ocupantesMatch[1]);
  }

  // 8. ELECTRIFICACIÓN
  if (/\b(HIBRIDO|HYBRID|HEV)\b/.test(cVersion)) {
    specs.electrificacion = "HYBRID";
  } else if (/\bPHEV\b/.test(cVersion)) {
    specs.electrificacion = "PHEV";
  } else if (/\bMHEV\b/.test(cVersion)) {
    specs.electrificacion = "MHEV";
  } else if (/\b(ELECTRICO|ELECTRIC|EV\b)/.test(cVersion)) {
    specs.electrificacion = "ELECTRIC";
  }

  return specs;
}
```

### 🚨 Códigos de Equipamiento a Filtrar

Los siguientes códigos deben ser **eliminados** del campo versión ya que son equipamiento, no parte del trim:

| Código    | Significado                     | Frecuencia |
| --------- | ------------------------------- | ---------- |
| BA        | Bolsas de Aire                  | 10,118     |
| AC        | Aire Acondicionado/Climatizador | 11,214     |
| ABS       | Frenos ABS                      | 7,889      |
| QC        | Quemacocos                      | 1,850      |
| VP        | Vidrios Polarizados             | 2,023      |
| NAVI      | Navegación                      | 1,692      |
| CD        | Reproductor CD                  | 1,482      |
| AA        | Aire Acondicionado              | 1,275      |
| DVD       | Reproductor DVD                 | 306        |
| MP3       | Reproductor MP3                 | 539        |
| USB       | Puerto USB                      | 267        |
| GPS       | Sistema GPS                     | 145        |
| R[0-9]{2} | Rines (R16, R17, R18, etc.)     | 5,166      |

### 🎯 Algoritmo Completo de Normalización

```javascript
function normalizarVersionQualitas(registro) {
  const resultado = {
    // Campos directos
    marca: normalizarMarca(registro.marca),
    modelo: normalizarModelo(registro.modelo),
    anio: parseInt(registro.anio),

    // Transmisión desde campo dedicado (más confiable)
    transmision:
      registro.cTransmision === "A"
        ? "AUTO"
        : registro.cTransmision === "S"
        ? "MANUAL"
        : null,

    // Extraer del campo cVersion
    version: null, // TRIM limpio o null
    motor_config: null,
    cilindrada: null,
    turbo: false,
    carroceria: null, // Inferir por puertas/modelo
    traccion: null,
    ocupantes: null,
    electrificacion: null,
  };

  // 1. Extraer TRIM (puede ser null)
  resultado.version = extraerTrim(registro.cVersion);

  // 2. Extraer especificaciones técnicas
  const specs = extraerEspecificaciones(registro.cVersion);
  Object.assign(resultado, specs);

  // 3. Inferir carrocería (si no está explícita)
  resultado.carroceria = inferirCarroceria(
    registro.cVersion,
    resultado.modelo,
    specs.puertas
  );

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

### ⚠️ Casos Especiales y Excepciones

1. **Vehículos sin TRIM real**: 42% de los registros no tienen un trim identificable. Esto es **normal** y debe manejarse con `version = null`.

2. **Códigos con puntos y comas**: Qualitas usa `, XX OCUP.` al final. Siempre limpiar estos separadores.

3. **Transmisión redundante**: El campo `cTransmision` es más confiable que el texto en `cVersion`.

4. **Marcas especiales con espacios**:

   - "GENERAL MOTORS" → "GMC"
   - "ALFA ROMEO" → conservar con espacio
   - "MERCEDES BENZ" → conservar con espacio
   - "LAND ROVER" → "LANDROVER" (sin espacio en algunos casos)

5. **Vehículos comerciales**: SPRINTER, CRAFTER, etc. pueden tener hasta 23 ocupantes.

### 📋 Checklist de Validación

- [ ] **Filtrar por Activo = 1** (CRÍTICO)
- [ ] Años entre 2000-2030
- [ ] Transmisión normalizada (AUTO/MANUAL/null)
- [ ] TRIM extraído o null (no inventar "BASE")
- [ ] Especificaciones técnicas separadas
- [ ] Carrocería inferida cuando sea posible
- [ ] Hash comercial generado
- [ ] ID canónico único generado
- [ ] Equipamiento eliminado del campo versión

### 🔄 Proceso de Actualización

1. **Extracción**: Query solo registros con `Activo = 1`
2. **Normalización**: Aplicar todas las reglas documentadas
3. **Deduplicación**: Por `id_canonico` antes de enviar
4. **Batch**: Procesar en lotes de 10,000 registros
5. **RPC Supabase**: Llamar a `procesar_batch_homologacion`
