# Homologación de catálogos vehiculares

**Objetivo final**

Construir y mantener un **catálogo vehicular homologado** que unifica los catálogos de aseguradoras (Qualitas, HDI, AXA, GNP, Mapfre, Chubb, Zurich, Atlas, BX, El Potosí, ANA) en un **modelo canónico único**, con trazabilidad completa por aseguradora, control de **activos/inactivos**, y un flujo reproducible de ingesta y actualización (n8n ➜ RPC Supabase ➜ `catalogo_homologado`).

---

## 1) Componentes del sistema

- **Fuentes (BD origen)** – tablas disponibles:

  - `ana.NMarca`, `ana.NSubMarca`, `ana.NVersiones`
  - `atlas.Marca`, `atlas.SubTipo_Modelo`, `atlas.Vehiculo_Version`
  - `axa.Linea`, `axa.Marca`, `axa.Subtipo`, `axa.Versiones`
  - `bx.Marca`, `bx.Modelo`, `bx.SubMarca`, `bx.Version`
  - `catalogo.Marca`, `catalogo.Modelo`
  - `chubb.NMarca`, `chubb.NSubMarca`, `chubb.NTipo`, `chubb.NVehiculo`
  - `elpotosi.Marca`, `elpotosi.Modelo`, `elpotosi.Version`
  - `gnp.Armadora`, `gnp.Carroceria`, `gnp.Modelo`, `gnp.Version`
  - `hdi.InformacionVehiculo`, `hdi.Marca`, `hdi.SubMarca`, `hdi.Transmision`, `hdi.Version`
  - `mapfre.Marca`, `mapfre.Modelo`
  - `qualitas.Marca`, `qualitas.Modelo`, `qualitas.Version`
  - `zurich.Marcas`, `zurich.Modelos`, `zurich.SubMarcas`, `zurich.Version`

- **Normalización y orquestación**: **n8n**

  - Obtiene datos de cada fuente.
  - Aplica reglas de normalización y cálculo de claves.
  - Deduplica por `id_canonico`/`hash_comercial` antes del envío.
  - Agrupa en **batches** (p.ej. 10k–50k) y llama a la RPC de Supabase.

- **Persistencia y API**: **Supabase (Postgres + PostgREST)**

  - Tabla canónica: `public.catalogo_homologado` (schema más abajo).
  - Función RPC **`public.homologacion(vehiculos_json jsonb)`**.
  - Triggers y políticas (RLS) para control de escritura.

- **Análisis asistido**: **Agentes MCP**

  - Ejecutan SQLs de perfilado, muestreos y validaciones por tabla de origen.
  - Devuelven métricas y sugerencias de mapeo.

---

## 2) Modelo canónico (tabla maestra)

```sql
CREATE TABLE catalogo_homologado (
    -- Identificación
    id BIGSERIAL PRIMARY KEY,
    id_canonico VARCHAR(64) UNIQUE NOT NULL,
    hash_comercial VARCHAR(64) NOT NULL,

    -- Strings de trazabilidad
    string_comercial TEXT NOT NULL,   -- "TOYOTA|YARIS|2020|AUTO"
    string_tecnico   TEXT NOT NULL,   -- "TOYOTA|YARIS|2020|AUTO|CORE|L4|SEDAN|FWD"

    -- Datos maestros normalizados
    marca VARCHAR(100) NOT NULL,
    modelo VARCHAR(150) NOT NULL,
    anio INTEGER NOT NULL CHECK (anio BETWEEN 2000 AND 2030),
    transmision VARCHAR(20) CHECK (transmision IN ('AUTO','MANUAL', NULL)),
    version VARCHAR(200),
    motor_config VARCHAR(50),     -- L4, V6, V8, ELECTRIC, HYBRID, MHEV, PHEV
    carroceria VARCHAR(50),       -- SEDAN, SUV, HATCHBACK, PICKUP, COUPE, VAN, WAGON
    traccion VARCHAR(20),         -- 4X4, 4X2, AWD, FWD, RWD

    -- Disponibilidad por aseguradora
    disponibilidad JSONB DEFAULT '{}',
    /* Ejemplo:
    {
      "QUALITAS": {
        "activo": true,
        "id_original": "372340",
        "version_original": "ADVANCE 5P L4 1.5T AUT., 05 OCUP.",
        "fecha_actualizacion": "2025-01-15T10:00:00Z"
      },
      "HDI": { ... },
      "ZURICH": { ... }
    }
    */

    -- Métricas de confianza
    confianza_score DECIMAL(3,2) DEFAULT 1.0,

    -- Timestamps
    fecha_creacion TIMESTAMP DEFAULT NOW(),
    fecha_actualizacion TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_marca_modelo_anio_hom ON catalogo_homologado(marca, modelo, anio);
CREATE INDEX idx_hash_comercial_hom ON catalogo_homologado(hash_comercial);
CREATE INDEX idx_disponibilidad_gin_hom ON catalogo_homologado USING GIN(disponibilidad);
CREATE INDEX idx_id_canonico_hom ON catalogo_homologado(id_canonico);
```

### Identificadores y claves

- **`hash_comercial`** = hash SHA-256 de `(marca|modelo|anio|transmision)` **normalizados**.
- **`id_canonico`** = hash SHA-256 de `(hash_comercial|version|motor_config|carroceria|traccion)` **normalizados**.
- Normalización mínima: `UPPER`, trim, eliminar dobles espacios, mapear abreviaturas (p.ej. `AUT.`→`AUTO`).

---

## 3) Reglas de **Activos/Inactivos**

### 3.1 Definición

- **Activo (a nivel aseguradora)**: la aseguradora declara la versión como vigente/ofertable en su catálogo. Se almacena en `disponibilidad->>ASEGURADORA->activo`.
- **Inactivo (a nivel aseguradora)**: la aseguradora lo da de baja o deja de publicarlo; se registra con `activo=false` conservando `id_original`/`version_original` y actualizando `fecha_actualizacion`.
- **Vigencia global (derivada)**: un registro del `catalogo_homologado` se considera **vigente** si **al menos una** aseguradora lo reporta `activo=true`.

### 3.2 Persistencia y actualizaciones

- La RPC **no borra** filas por inactivaciones; actualiza la llave de la aseguradora en `disponibilidad`.
- **Reactivación**: si una aseguradora que estaba inactiva vuelve a reportar el vehículo, se actualiza `activo=true` y `fecha_actualizacion`.
- **Depuración** (job aparte): si **todas** las aseguradoras tienen `activo=false` **por más de N días** (p.ej. 180), marcar para archivado o limpieza controlada.

## 4) Contrato de la RPC `public.procesar_batch_completo2`

**Firma**: `procesar_batch_homologacion(vehiculos_json jsonb)`

**Endpoint PostgREST**: `/rest/v1/rpc/procesar_batch_homologacion`

**Headers**: `apikey`, `Authorization: Bearer <service_role_jwt>`, `Content-Type: application/json`, opcional `Prefer: return=representation|minimal`.

**Body**:

```json
{
  "vehiculos_json": [
    {
      "id_canonico": "66b4fe23a96e8de9b1dac624069d9a03f96d3f17d7319673621254cb42c651dc",
      "hash_comercial": "7cc9374cee0e1c1bc8638521b2690cb010dae9729134790042f19c05346f8d45",
      "string_comercial": "ACURA|ADX|2025|AUTO",
      "string_tecnico": "ACURA|ADX|2025|AUTO|ADVANCE|L4|SUV",
      "marca": "ACURA",
      "modelo": "ADX",
      "anio": 2025,
      "transmision": "AUTO",
      "version": "ADVANCE",
      "motor_config": "L4",
      "carroceria": "SUV",
      "traccion": null,
      "origen_aseguradora": "QUALITAS",
      "id_original": "372340",
      "version_original": "ADVANCE 5P L4 1.5T AUT., 05 OCUP.",
      "activo": true
    },
    {
      "id_canonico": "5955a60b6849b49cd47478385fa2948dcea4f55e5017493e73c0af58b743fd4d",
      "hash_comercial": "7cc9374cee0e1c1bc8638521b2690cb010dae9729134790042f19c05346f8d45",
      "string_comercial": "ACURA|ADX|2025|AUTO",
      "string_tecnico": "ACURA|ADX|2025|AUTO|A-SPEC|L4|SUV",
      "marca": "ACURA",
      "modelo": "ADX",
      "anio": 2025,
      "transmision": "AUTO",
      "version": "A-SPEC",
      "motor_config": "L4",
      "carroceria": "SUV",
      "traccion": null,
      "origen_aseguradora": "QUALITAS",
      "id_original": "372341",
      "version_original": "A-SPEC 5P L4 1.5T AUT., 05 OCUP.",
      "activo": false
    }
  ]
}
```

**Comportamiento esperado** (resumen):

1. Valida que cada objeto tenga las claves mínimas: `id_canonico`, `hash_comercial`, `string_comercial`, `string_tecnico`, `marca`, `modelo`, `anio`, `transmision`, `origen_aseguradora`, `activo`.
2. **Upsert** por `id_canonico`:

   - `INSERT` cuando no existe.
   - `ON CONFLICT (id_canonico) DO UPDATE` actualizando campos canónicos **solo si cambiaron**.

3. **Merge JSONB de `disponibilidad`** para la `origen_aseguradora` del registro:

   - `activo` con el valor entrante (true/false).
   - `id_original`, `version_original`, `fecha_actualizacion` = `NOW()`.
   - No toca las llaves de otras aseguradoras.

4. Actualiza `fecha_actualizacion` de la fila y, opcionalmente, recalcula `confianza_score`.
5. Devuelve métricas del batch: `{inserted_count, updated_count, errors[], warnings[]}`.

**Nota**: la RPC se diseñó **idempotente**: re-ejecutar un mismo batch no debe generar cambios adicionales.

---

## 5) Blueprint del flujo en **n8n**

1. **Nodo por aseguradora (Query/HTTP)** – Recupera catálogo origen.

2. **Transform (Function/Code)** – Normaliza a forma canónica y calcula:

   - `string_comercial = UPPER(marca)|UPPER(modelo)|anio|transmision`.
   - `hash_comercial = sha256(string_comercial)`.
   - `string_tecnico = string_comercial|version|motor_config|carroceria|traccion` (omite nulos).
   - `id_canonico = sha256(hash_comercial|version|motor_config|carroceria|traccion)`.
   - `activo` según regla de la fuente (true/false).

3. **Dedup (Code)** – Elimina duplicados por `id_canonico` y, si aplica, conserva el último por `fecha_actualizacion` de la fuente.

4. **Chunker** – Divide en lotes (p.ej. 10k–50k).

5. **HTTP Request ➜ Supabase RPC** – `POST /rest/v1/rpc/procesar_batch_completo2` con body `{ "vehiculos_json": items }`.

   - Headers: `apikey`, `Authorization: Bearer <service_role>`, `Content-Type: application/json`, `Prefer: return=minimal`.

6. **Logging** – Guarda respuesta por batch: conteos, errores, duración.

7. **Retry/backoff** – Reintentos para 429/5xx. Idempotencia garantizada por `id_canonico`.

---

## 6) Plan de análisis con **MCP** (perfilado por origen)

Para cada tabla, ejecutar:

- **Cardinalidades** y nulos (ej.):

```sql
SELECT COUNT(*) total,
       COUNT(DISTINCT marca) d_marcas,
       COUNT(DISTINCT modelo) d_modelos,
       SUM(CASE WHEN version IS NULL THEN 1 ELSE 0 END) nulos_version
FROM qualitas.Version;
```

- **Muestreos de valores** (marcas/modelos/años/transmisión/carrocería).
- **Reglas de mapeo** por aseguradora: columnas fuente ➜ campos canónicos.

### 6.1 Mapas de origen ➜ canónico (ejemplos reales)

- **Qualitas** (`qualitas.Marca`, `qualitas.Modelo`, `qualitas.Version`):

  - `marca` = `Marca.Nombre`
  - `modelo` = `Modelo.Nombre`
  - `version_original` = `Version.Descripcion`
  - Derivar `anio`, `transmision` (parseo de texto, p.ej. `AUT.`→`AUTO`), `motor_config` (L4, V6…), `carroceria` (SEDAN/SUV…).

- **HDI** (`hdi.InformacionVehiculo`, `hdi.Version`):

  - `marca`/`modelo` desde `InformacionVehiculo`.
  - `transmision` desde `hdi.Transmision`.
  - `version_original` de `hdi.Version`.

- **AXA** (`axa.Marca`, `axa.Subtipo`, `axa.Versiones`, `axa.Linea`):

  - `marca` = `Marca`.
  - `modelo` ≈ `Linea` o `Subtipo` (validar con MCP qué columna representa mejor el modelo canónico).

- **Zurich** (`zurich.Marcas`, `zurich.Modelos`, `zurich.SubMarcas`, `zurich.Version`):

  - `marca` = `Marcas.Nombre`.
  - `modelo` = `Modelos.Nombre` (usar `SubMarcas` cuando aplique).
  - `version_original` = `Version.Texto`.

_(El MCP generará para cada origen un diccionario exacto de campos y funciones de parseo.)_

---

## 12) Criterios de éxito

1. El 100% de las filas de las fuentes quedan representadas en el canónico con trazabilidad en `disponibilidad`.
2. Reprocesar un catálogo completo **no** duplica ni altera más allá de lo informado en el batch.

---

## 13) Próximos pasos

1. Ejecutar el **perfilado MCP** por aseguradora para fijar mapeos exactos.
2. Ajustar la RPC con `jsonb_set` definitivo y métricas de retorno.
3. Publicar el flujo n8n con chunking 10k–50k, reintentos y logging.
4. Crear las vistas `vw_catalogo_activos` y, si aplica, la MV por `hash_comercial`.
