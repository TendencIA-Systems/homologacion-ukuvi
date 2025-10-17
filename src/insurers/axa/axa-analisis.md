# 📊 Análisis Catálogo AXA - Estrategia de Normalización y Homologación

## 🔍 Resumen Ejecutivo

**Aseguradora**: AXA  
**Total registros**: 14,252 (rango 2000-2030)  
**Registros activos**: 14,244 (99.94%) ✅  
**Marcas únicas**: 94  
**Modelos únicos**: 921  
**Rango de años**: 2000-2025  
**Estructura de años**: Año inicial y año final (requiere decisión de manejo)

### 🚨 Hallazgos Críticos

1. **Campo activo disponible**: Campo `Activo` con 99.94% de registros vigentes ✅
2. **Estructura del campo versión**: `Descripcion` contiene Modelo + DescripcionLinea concatenados
3. **Transmisión codificada**: Campo numérico `Transmision` (0=No especificada, 1=Manual, 2=Automática)
4. **Años duales**: Cada vehículo tiene `AnoInicial` y `AnoFinal` (requiere estrategia de manejo)
5. **Alta presencia de especificaciones**: 76.5% cilindros, 23.4% cilindrada, 85.9% puertas

---

## 📋 Mapeo de Campos

| Campo Canónico | Campo Origen                            | Transformación Requerida                         |
| -------------- | --------------------------------------- | ------------------------------------------------ |
| marca          | `[axa].[Marca].Descripcion`             | Normalización directa                            |
| modelo         | `[axa].[Versiones].Version`             | Normalización directa                            |
| anio           | `[axa].[Linea].AnoInicial` o `AnoFinal` | **Decisión**: Usar AnoInicial como año principal |
| transmision    | `[axa].[Linea].Transmision`             | Mapeo: 0→NULL, 1→MANUAL, 2→AUTO                  |
| version        | Extraer de `DescripcionLinea`           | Extraer trim limpio (ver estrategia)             |
| motor_config   | Extraer de `Descripcion`                | Patrón: `[0-9]CIL`, `V6`, `L4`, etc.             |
| carroceria     | Extraer de `Descripcion` + puertas      | Inferir por tipo y número de puertas             |
| traccion       | Extraer de `Descripcion`                | Buscar: `4X4`, `AWD`, `4WD`, `QUATTRO`           |

---

## 🔧 Estrategia de Extracción de TRIM y Especificaciones

### Anatomía del Campo `Descripcion` (ejemplos reales):

```
"GRAND CHEROKEE LIMITED LUJO ADVANCE BLINDADA AUT 5.7L 8CIL 4X4 5P QC"
└─────┬─────┘  └────────────┬─────────────┘  └─┘ └┬┘  └┬┘  └┬┘ └┘ └┘
    Modelo            TRIM(s)               Trans Mot  Cil  Trac Prt Eq
```

### Componentes Identificados (orden típico):

1. **MODELO**: Ya está separado en tabla `Versiones.Version`
2. **TRIM(s)**: Primera(s) palabra(s) de `DescripcionLinea`
3. **TRANSMISIÓN**: STD/AUT/MAN/CVT/TIPTRONIC (redundante con campo numérico)
4. **CILINDRADA**: `[0-9].[0-9]L` o `[0-9]L`
5. **CILINDROS**: `[0-9]CIL`
6. **TRACCIÓN**: 4X4/AWD/4WD/QUATTRO
7. **PUERTAS**: `[0-9]P`
8. **EQUIPAMIENTO**: AC, QC, BA, AA, etc.

### 📊 Estadísticas de Elementos Presentes (Solo Activos)

| Elemento             | Registros | Porcentaje | Observaciones                        |
| -------------------- | --------- | ---------- | ------------------------------------ |
| Cilindros            | 10,905    | 76.5%      | Patrón: `[0-9]CIL` muy consistente   |
| Puertas              | 12,239    | 85.9%      | Patrón: `[0-9]P` muy confiable       |
| Transmisión en texto | 10,645    | 74.7%      | Redundante pero útil para validación |
| Cilindrada           | 3,339     | 23.4%      | Patrón: `[0-9].[0-9]L`               |
| Tracción             | 1,979     | 13.9%      | 4X4/AWD más comunes                  |
| Híbrido/Eléctrico    | 1,273     | 8.9%       | MHEV, PHEV, HIBRIDO, ELECTRIC        |
| Turbo                | 389       | 2.7%       | TURBO, CP SC                         |

---

## 🎯 Algoritmo de Normalización Propuesto

```javascript
function normalizarVersionAXA(registro) {
  const resultado = {
    // Campos directos
    marca: normalizarMarca(registro.marca_descripcion),
    modelo: normalizarModelo(registro.version),
    anio: registro.ano_inicial, // Decisión: usar año inicial
    anio_final: registro.ano_final, // Guardar para referencia

    // Transmisión desde campo numérico (más confiable)
    transmision: mapearTransmision(registro.transmision),
    // 0 → null (no especificada)
    // 1 → 'MANUAL'
    // 2 → 'AUTO'

    // Extraer especificaciones del campo Descripcion
    version: null, // TRIM limpio
    motor_config: null, // L4, V6, V8, etc.
    carroceria: null, // SEDAN, SUV, COUPE, etc.
    traccion: null, // 4X4, AWD, FWD, RWD

    // Campos adicionales útiles
    cilindrada: null, // 1.5, 2.0, 3.5
    cilindros: null, // 4, 6, 8
    puertas: null, // 2, 3, 4, 5
    es_hibrido: false,
    es_electrico: false,
  };

  // Procesar DescripcionLinea para extraer TRIM
  resultado.version = extraerTrimAXA(registro.descripcion_linea);

  // Procesar Descripcion completa para specs
  const specs = extraerEspecificacionesAXA(registro.descripcion);
  Object.assign(resultado, specs);

  // Inferir carrocería si no está explícita
  if (!resultado.carroceria) {
    resultado.carroceria = inferirCarroceriaAXA(
      registro.descripcion,
      resultado.puertas
    );
  }

  return resultado;
}
```

---

## 📝 Reglas de Extracción de TRIM

### TRIMs Válidos Identificados (Top frecuencias):

| TRIM        | Frecuencia | Tipo                         |
| ----------- | ---------- | ---------------------------- |
| LIMITED     | 77         | Nivel equipamiento alto      |
| SPORT       | 75         | Versión deportiva            |
| R-DYNAMIC   | 33         | Línea deportiva (Land Rover) |
| BASE        | 28         | Versión entrada              |
| PREMIUM     | 26         | Nivel medio-alto             |
| PLATINUM    | 26         | Nivel alto                   |
| EXCLUSIVE   | 22         | Nivel alto                   |
| ADVANCE     | 16         | Nivel medio                  |
| LUXURY      | 15         | Nivel alto                   |
| COMFORTLINE | 16         | Nivel medio (VW)             |

### Estrategia de Extracción:

```javascript
function extraerTrimAXA(descripcionLinea) {
  // Limpiar descripción
  let texto = descripcionLinea.toUpperCase().trim();

  // Eliminar elementos técnicos conocidos
  const elementosEliminar = [
    /\b\d+\.?\d*L\b/g, // Cilindrada
    /\b\d+CIL\b/g, // Cilindros
    /\b\d+P\b/g, // Puertas
    /\b(STD|AUT|MAN|CVT)\b/g, // Transmisión
    /\b(4X4|AWD|4WD)\b/g, // Tracción
    /\b(DIESEL|TURBO)\b/g, // Motor
    /\b(BA|AA|AC|QC)\b/g, // Equipamiento
  ];

  for (const patron of elementosEliminar) {
    texto = texto.replace(patron, " ");
  }

  // Buscar en lista de TRIMs válidos
  const trimsValidos = [
    "LIMITED",
    "SPORT",
    "R-DYNAMIC",
    "BASE",
    "PREMIUM",
    "PLATINUM",
    "EXCLUSIVE",
    "ADVANCE",
    "LUXURY",
    "COMFORTLINE",
    "TRENDLINE",
    "HIGHLINE", // VW
    "GT",
    "GTI",
    "GTS",
    "RS", // Deportivos
    "SE",
    "SEL",
    "S",
    "EX",
    "LT",
    "LS", // Genéricos
    "ELITE",
    "ALLURE",
    "STYLE",
    "RESERVE",
  ];

  // Buscar primer trim válido
  const palabras = texto.split(" ").filter(Boolean);
  for (const palabra of palabras) {
    if (trimsValidos.includes(palabra)) {
      return palabra;
    }
  }

  // Si no hay trim identificable, retornar null
  return null;
}
```

---

## 🔍 Manejo de Casos Especiales

### 1. Años Duales (AnoInicial/AnoFinal)

**Problema**: Cada registro tiene año inicial y final  
**Solución Propuesta**:

- Usar `AnoInicial` como año principal para homologación
- Si se necesita rango completo, expandir registros por cada año
- Alternativamente, crear campo adicional `rango_anos` en el catálogo

### 2. Transmisión Código 0

**Problema**: 24.8% tiene transmisión = 0 (no especificada)  
**Solución**:

- Intentar detectar del texto (8.22% tiene "AUT", 3.01% tiene "STD")
- Si no se detecta, dejar como NULL
- No asumir automática por defecto

### 3. Marca "TURISTA BANJERCITO"

**Problema**: Marca con 1,200 registros, parece categoría especial  
**Solución**:

- Mantener como marca válida (vehículos importados/fronterizos)
- Considerar agregar flag `es_fronterizo` si es relevante

### 4. Modelos Duplicados entre Marcas

**Problema**: CHEVROLET y OLDSMOBILE comparten modelos (ej: CORVETTE)  
**Solución**:

- Mantener separados por marca en homologación
- Son catálogos históricos diferentes

### 5. Vehículos Comerciales

**Problema**: SPRINTER, CRAFTER con hasta 23 pasajeros  
**Solución**:

- Identificar por palabras clave: VAN, CARGO, CHASIS
- Agregar campo `tipo_uso`: PERSONAL/COMERCIAL/CARGA

---

## 🚨 Problemas Detectados

1. **Inconsistencia Transmisión**: 18.5% de automáticas (código 2) no tienen "AUT" en texto
2. **TRIMs Genéricos**: "GENERICA" aparece 70 veces (ignorar como trim)
3. **Especificaciones Mezcladas**: Algunos registros tienen specs pero no trim real
4. **Cilindrada Baja**: Solo 23.4% tiene cilindrada explícita
5. **Campos de Equipamiento**: AC, QC, BA contaminan el campo versión

---

## 📈 Métricas de Calidad Esperadas

- **Completitud marca/modelo/año**: 100% ✅
- **Transmisión detectada**: 75.2% (resto NULL)
- **TRIMs identificables**: ~45-50% (estimado)
- **Carrocería inferible**: ~70% (por puertas + keywords)
- **Especificaciones motor**: 76.5% (cilindros)
- **Tracción detectada**: 13.9%

---

## 💡 Recomendaciones

1. **Prioridad Alta**:

   - Implementar mapeo de transmisión 0/1/2
   - Definir estrategia para años duales
   - Crear diccionario de TRIMs válidos de AXA

2. **Prioridad Media**:

   - Limpiar equipamiento (AC, QC, BA) del campo versión
   - Validar marca "TURISTA BANJERCITO"
   - Detectar vehículos comerciales

3. **Prioridad Baja**:
   - Extraer potencia (CP/HP) cuando presente
   - Identificar ediciones especiales
   - Mapear códigos de paquetes (PAQ A, PAQ B, etc.)

---

## ✅ Checklist de Validación

- [ ] Filtrar solo registros con `Activo = 1`
- [ ] Decidir manejo de AnoInicial vs AnoFinal
- [ ] Mapear Transmision (0→NULL, 1→MANUAL, 2→AUTO)
- [ ] Extraer TRIM limpio de DescripcionLinea
- [ ] Detectar especificaciones técnicas de Descripcion
- [ ] Inferir carrocería por puertas cuando no explícita
- [ ] Generar hash_comercial con campos normalizados
- [ ] Generar id_canonico único
- [ ] Validar contra muestra de 1000 registros antes de procesamiento completo

---

## 🔄 Siguiente Paso

Implementar código de normalización en n8n siguiendo esta estrategia, con procesamiento en batches de 10,000 registros para alimentar la función RPC `procesar_batch_homologacion` de Supabase.
