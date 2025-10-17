# 📊 Análisis Catálogo El Potosí - Estrategia de Normalización

## Framework de Evaluación y Homologación

### 🎯 Resumen Ejecutivo

- **Total registros (2000-2030)**: 28,218 vehículos
- **Registros activos**: 23,040 (81.65%) ✅ **PROCESAR SOLO ESTOS**
- **Registros inactivos**: 5,178 (18.35%)
- **Marcas únicas activas**: 55
- **Modelos únicos activos**: 700
- **Rango de años**: 2000-2026
- **Tipos de transmisión**: 3 (Manual, Automática, No especificado)

### 🚨 Hallazgos Críticos

#### 1. **Estructura de Tablas**

```sql
-- Estructura identificada:
-- elpotosi.Marca: IdMarca (PK), Descripcion, TipoVehiculo, Anio, Activo
-- elpotosi.Modelo: IdModelo (PK), Descripcion, TipoVehiculo, Anio, IdMarca (FK), Activo
-- elpotosi.Version: IdVersion (PK), CveVersion, Descripcion, Transmision,
--                   TipoVehiculo, Anio, IdMarca, IdModelo, Activo, VersionCorta
```

#### 2. **Campo de Transmisión**

- Codificado numéricamente en campo `Transmision`:
  - `1` = Manual/STD (27.27%)
  - `2` = Automática/AUT (72.37%)
  - `0` = No especificado (0.36%)

#### 3. **Estructura del Campo Version**

El Potosí tiene DOS formatos principales en `VersionCorta`:

**Formato Nuevo (más estructurado)**:

```
"TRIM, TRANS PUERTAS OCUP, CIL, EQUIPAMIENTO"
Ejemplo: "GT 1.2AUT 5 PTAS 5 OCUP , 4 CIL, ABS, A/A, E/E, TELA, Q/C, B/A"
```

**Formato Antiguo**:

```
"TRIM TRANS TON OCUP PUERTAS CONFIG_MOTOR EQUIPAMIENTO"
Ejemplo: "GLS SEDAN A 0 TON 5 OCUP 4 PTAS L4 DIS CA CE TELA CD SQ CB"
```

#### 4. **Problemas Detectados**

- **Inconsistencia extrema en mapeo Marca-Modelo**: Ejemplos aberrantes como PEUGEOT/KANGOO (Renault), NISSAN/A6 (Audi), SEAT/OUTLANDER (Mitsubishi)
- **Campo VersionCorta a veces está vacío**: Se debe usar `Descripcion` como fallback
- **Duplicación masiva**: NISSAN tiene 25,440 versiones activas (desproporcionado)
- **Mezcla de información**: El campo versión contiene TRIM + especificaciones técnicas + equipamiento

### 📋 Mapeo de Campos

| Campo Canónico | Campo Origen                        | Transformación Requerida                   |
| -------------- | ----------------------------------- | ------------------------------------------ |
| marca          | elpotosi.Marca.Descripcion          | Normalización de texto, mapeo de sinónimos |
| modelo         | elpotosi.Modelo.Descripcion         | Normalización, validación contra marca     |
| anio           | elpotosi.Version.Anio               | Directo (validar 2000-2030)                |
| transmision    | elpotosi.Version.Transmision        | Mapeo: 1→MANUAL, 2→AUTO, 0→null            |
| version        | Extraer de VersionCorta/Descripcion | Extracción de TRIM limpio                  |
| motor_config   | Extraer de VersionCorta             | Buscar L4, V6, V8, etc.                    |
| carroceria     | Inferir de puertas + TipoVehiculo   | Lógica de inferencia                       |
| traccion       | Extraer de VersionCorta             | Buscar 4X4, AWD, 4X2, etc.                 |

### 🔧 Estrategia de Extracción de Especificaciones

#### **Paso 1: Preparación del Campo Version**

```python
def preparar_version(registro):
    # Usar VersionCorta si existe, sino usar Descripcion
    version_raw = registro.get('VersionCorta') or registro.get('Descripcion', '')

    # Limpiar prefijos de marca/modelo si están presentes
    # Ejemplo: "NISSAN SENTRA SR BITONO..." → "SR BITONO..."
    if version_raw.startswith(registro['marca']):
        version_raw = version_raw[len(registro['marca']):].strip()
    if version_raw.startswith(registro['modelo']):
        version_raw = version_raw[len(registro['modelo']):].strip()

    return version_raw.upper()
```

#### **Paso 2: Extracción de TRIM (Version)**

```python
def extraer_trim(version_text):
    # Lista de TRIMs válidos identificados en El Potosí
    TRIMS_VALIDOS = [
        # Premium/Lujo
        'LIMITED', 'EXCLUSIVE', 'PLATINUM', 'SIGNATURE',

        # Niveles medios-altos
        'ADVANCE', 'ACTIVE', 'ALLURE', 'DYNAMIC',

        # Niveles estándar
        'GLS', 'GLX', 'GLE', 'GL', 'GT',
        'LT', 'LE', 'LX', 'LS',
        'SE', 'SEL', 'SR', 'SV', 'SL',

        # Deportivos
        'SPORT', 'RS', 'ST', 'GTI', 'TYPE R',

        # Específicos de marca
        'COMFORTLINE', 'TRENDLINE', 'HIGHLINE',  # VW
        'STYLE', 'REFERENCE', 'FR',  # SEAT
        'SENSE', 'INTENS', 'ZEN',  # Renault

        # Básicos
        'BASE', 'CORE'
    ]

    # Buscar primera coincidencia antes de comas o números
    parts = version_text.split(',')[0].split()

    for i, part in enumerate(parts):
        # Verificar si es un TRIM válido
        if part in TRIMS_VALIDOS:
            # Verificar si hay modificador siguiente (PACK, PLUS, etc.)
            if i + 1 < len(parts):
                next_part = parts[i + 1]
                if next_part in ['PACK', 'PLUS', 'PREMIUM', 'SPORT', 'LINE']:
                    return f"{part} {next_part}"
            return part

        # Detectar TRIMs compuestos comunes
        if i + 1 < len(parts):
            compound = f"{part} {parts[i + 1]}"
            if compound in ['EX PACK', 'GT LINE', 'S LINE', 'R LINE']:
                return compound

    return None  # No "BASE" artificial
```

#### **Paso 3: Extracción de Configuración de Motor**

```python
def extraer_motor_config(version_text):
    # Patrones de configuración de motor
    import re

    # L4, L3, L6, V6, V8, I4
    motor_match = re.search(r'\b([LVI])([3468])\b', version_text)
    if motor_match:
        return f"{motor_match.group(1)}{motor_match.group(2)}"

    # Detectar híbridos/eléctricos
    if any(term in version_text for term in ['HYBRID', 'HEV', 'HV', 'HIBRIDO']):
        return 'HYBRID'
    if any(term in version_text for term in ['E-POWER', 'ELECTRIC', 'EV']):
        return 'ELECTRIC'
    if 'PHEV' in version_text:
        return 'PHEV'
    if 'MHEV' in version_text:
        return 'MHEV'

    # Detectar número de cilindros
    cil_match = re.search(r'(\d+)\s*CIL', version_text)
    if cil_match:
        num_cil = cil_match.group(1)
        if num_cil == '4': return 'L4'
        if num_cil == '6': return 'V6'
        if num_cil == '8': return 'V8'

    return None
```

#### **Paso 4: Inferencia de Carrocería**

```python
def inferir_carroceria(version_text, tipo_vehiculo, num_puertas=None):
    # Si es pickup, es directo
    if tipo_vehiculo == 'PIC':
        return 'PICKUP'

    # Buscar carrocería explícita
    carrocerias_explicitas = {
        'SEDAN': ['SEDAN'],
        'HATCHBACK': ['HATCHBACK', 'HB'],
        'SUV': ['SUV'],
        'COUPE': ['COUPE', 'CUPE'],
        'CONVERTIBLE': ['CONVERTIBLE', 'CABRIO'],
        'VAN': ['VAN', 'MINIVAN'],
        'WAGON': ['WAGON', 'SPORTWAGEN']
    }

    for tipo, keywords in carrocerias_explicitas.items():
        if any(kw in version_text for kw in keywords):
            return tipo

    # Inferir por número de puertas
    if not num_puertas:
        # Extraer puertas del texto
        import re
        puertas_match = re.search(r'(\d+)\s*(?:ptas|PTAS|P\b)', version_text)
        if puertas_match:
            num_puertas = int(puertas_match.group(1))

    if num_puertas:
        if num_puertas == 2:
            return 'COUPE'
        elif num_puertas == 3:
            return 'HATCHBACK'
        elif num_puertas == 4:
            return 'SEDAN'
        elif num_puertas == 5:
            # Necesita más contexto, por defecto SUV si no hay más info
            return 'HATCHBACK'  # O 'SUV' según contexto

    return None
```

#### **Paso 5: Extracción de Tracción**

```python
def extraer_traccion(version_text):
    # Orden de prioridad en detección
    tracciones = {
        '4X4': ['4X4', '4x4'],
        '4X2': ['4X2', '4x2'],
        'AWD': ['AWD', 'ALL WHEEL DRIVE'],
        '4WD': ['4WD'],
        'FWD': ['FWD', 'FRONT WHEEL'],
        'RWD': ['RWD', 'REAR WHEEL'],
        # Sistemas propietarios
        'AWD': ['XDRIVE', 'QUATTRO', '4MATIC', '4MOTION']
    }

    for tipo, keywords in tracciones.items():
        if any(kw in version_text for kw in keywords):
            return tipo

    return None
```

### 📊 Métricas de Calidad del Catálogo

| Métrica                           | Valor  | Observación                                             |
| --------------------------------- | ------ | ------------------------------------------------------- |
| **Completitud del campo versión** | 100%   | Todos tienen Descripcion, la mayoría tiene VersionCorta |
| **TRIMs identificables**          | ~60%   | Muchos tienen TRIM claro al inicio                      |
| **Transmisión detectada**         | 99.64% | Solo 0.36% sin especificar                              |
| **Configuración motor presente**  | 72.6%  | Alta presencia de L4, V6, etc.                          |
| **Puertas especificadas**         | 89.7%  | Permite inferir carrocería                              |
| **Tracción especificada**         | 3.8%   | Muy baja, mayoría sin especificar                       |
| **Cilindrada presente**           | 26.9%  | Presente en formato X.XL                                |

### ⚠️ Casos Especiales y Excepciones

1. **Vehículos con marca/modelo incorrectos**: Validar contra catálogo maestro y corregir mapeos evidentemente erróneos
2. **Formato inconsistente de VersionCorta**: Siempre usar fallback a Descripcion si está vacío
3. **Códigos de equipamiento a filtrar**:
   - `ABS, CA, CE, CD, CQ, CB, SA, SE, SQ, SB` = equipamiento
   - `D/T, D/V, DIS` = dirección
   - `TELA, PIEL` = material de asientos
   - `A/A, E/E, Q/C, B/A` = aire acondicionado, elevavidrios, quemacocos, bolsas aire
4. **Tonelaje en pickups**: Buscar patrón `X TON` o `X.X TON`
5. **Ocupantes**: Patrón `X OCUP` (útil para validación pero no para homologación)

### 🔄 Algoritmo Completo de Normalización

```python
def normalizar_version_elpotosi(registro):
    resultado = {
        # Campos directos
        'marca': normalizar_texto(registro['marca_descripcion']),
        'modelo': normalizar_texto(registro['modelo_descripcion']),
        'anio': int(registro['anio']),

        # Transmisión desde campo dedicado
        'transmision': {
            1: 'MANUAL',
            2: 'AUTO',
            0: None
        }.get(registro['transmision'], None),

        # Campos a extraer
        'version': None,
        'motor_config': None,
        'carroceria': None,
        'traccion': None,

        # Metadata
        'origen_aseguradora': 'EL_POTOSI',
        'id_original': str(registro['id_version']),
        'version_original': registro.get('version_corta') or registro['descripcion'],
        'activo': bool(registro['activo'])
    }

    # Solo procesar si está activo
    if not resultado['activo']:
        return None

    # Preparar texto de versión
    version_text = preparar_version(registro)

    # Extraer especificaciones
    resultado['version'] = extraer_trim(version_text)
    resultado['motor_config'] = extraer_motor_config(version_text)
    resultado['carroceria'] = inferir_carroceria(
        version_text,
        registro['tipo_vehiculo']
    )
    resultado['traccion'] = extraer_traccion(version_text)

    # Generar identificadores
    resultado['string_comercial'] = '|'.join([
        str(v) if v else 'NULL'
        for v in [resultado['marca'], resultado['modelo'],
                  resultado['anio'], resultado['transmision']]
    ])

    resultado['string_tecnico'] = '|'.join([
        str(v) if v else 'NULL'
        for v in [resultado['marca'], resultado['modelo'],
                  resultado['anio'], resultado['transmision'],
                  resultado['version'], resultado['motor_config'],
                  resultado['carroceria'], resultado['traccion']]
    ])

    resultado['hash_comercial'] = generar_hash(resultado['string_comercial'])
    resultado['id_canonico'] = generar_hash(resultado['string_tecnico'])

    return resultado
```

### 📋 Checklist de Validación

- [x] **Filtrar por Activo = 1** (CRÍTICO - 23,040 registros)
- [x] Años entre 2000-2030
- [x] Transmisión normalizada (MANUAL/AUTO/null)
- [x] TRIM extraído o null (no inventar "BASE")
- [x] Configuración motor identificada (L4, V6, etc.)
- [x] Carrocería inferida por puertas/tipo
- [x] Tracción extraída cuando presente
- [x] Equipamiento eliminado del campo versión
- [x] Hash comercial generado
- [x] ID canónico único generado

### 💡 Recomendaciones

1. **Prioridad Alta**: Corregir mapeo marca-modelo antes de homologación
2. **Validación cruzada**: Verificar marcas/modelos contra catálogo maestro
3. **Deduplicación agresiva**: El Potosí tiene mucha duplicación, usar hash_comercial
4. **Procesamiento en batch**: Procesar en lotes de 5,000 registros
5. **Monitoreo de calidad**: Validar que al menos 50% tenga TRIM identificado
6. **Fallback inteligente**: Siempre usar Descripcion si VersionCorta está vacío

### 🚀 Próximos Pasos

1. **Implementar funciones de normalización** en n8n
2. **Ejecutar prueba con 1,000 registros** para validar extracción
3. **Revisar y ajustar** diccionario de TRIMs según resultados
4. **Procesar batch completo** de 23,040 registros activos
5. **Enviar a Supabase** mediante RPC de homologación
6. **Validar resultados** en tabla catalogo_homologado
