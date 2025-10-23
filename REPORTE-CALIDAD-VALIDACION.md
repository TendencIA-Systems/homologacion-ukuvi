# Reporte de Calidad y Validación del Sistema de Homologación
**Fecha:** 2025-10-22
**Analista:** Claude Code
**Catálogos Analizados:** Zurich (20,505 registros), Zurich+HDI (29,767 registros)

---

## RESUMEN EJECUTIVO

### Estado General: ⚠️ NO LISTO PARA PRODUCCIÓN

El sistema de homologación presenta **un problema crítico** que afecta al 65% de los registros y requiere corrección antes del despliegue a producción. Los principales fixes implementados funcionan correctamente, pero existe una inconsistencia entre la especificación técnica y la implementación actual.

### Métricas Clave
- **Total de registros analizados:** 29,767 (catálogo Zurich+HDI)
- **Tasa de contaminación aparente:** 1.08% (FALSO POSITIVO - ver detalles)
- **Problema crítico identificado:** 65% de registros (19,378) contienen información de ocupantes (XOCUP) que según especificaciones debe ser excluida
- **Fixes primarios validados:** 2/3 PASSED (con 1 falso positivo)
- **Calidad de datos:** Excelente en campos estructurales (marca, modelo, año, transmisión)

---

## HALLAZGOS PRINCIPALES

### ✅ ASPECTOS POSITIVOS

#### 1. Separación BMW/MINI (Issue #2) - ✅ PASS
- **Estado:** Implementado correctamente
- **Resultados:**
  - 0 registros de BMW con MINI en el modelo
  - 874 registros de marca MINI correctamente separados
  - Variantes MINI correctamente normalizadas (COOPER, CLUBMAN, COUNTRYMAN)
  - 0 registros con prefijo "MINI " redundante

#### 2. Completitud de Modelos (Issue #3) - ✅ PASS
- **Estado:** Implementado correctamente
- **Resultados:**
  - 0 modelos BMW con letra única "M" o "X"
  - 0 modelos AUDI con letra única "S" o "R"
  - Todos los modelos tienen identificación completa (e.g., "M3", "X5", "S3", "R8")

#### 3. Transmisión - ✅ EXCELENTE
- **Estado:** 100% de valores válidos
- **Resultados:**
  - 0 registros con valores inválidos de transmisión
  - Solo valores estándar: AUTO, MANUAL, CVT, DSG
  - Perfecta normalización entre aseguradoras

#### 4. Consolidación de Marcas - ✅ EXCELENTE
- **Estado:** Sin problemas detectados
- **Resultados:**
  - 0 marcas con sufijos problemáticos (BMW BW, AUDI II, etc.)
  - 0 marcas inválidas (AUTOS, MOTOCICLETAS, etc.)
  - Normalización consistente

#### 5. Escaping de Caracteres - ✅ EXCELENTE
- **Estado:** Sin problemas
- **Resultados:**
  - 0 backslashes encontrados
  - 0 comillas mal escapadas
  - Limpieza de caracteres funcionando correctamente

#### 6. Distribución de Datos
- **Años:** Cobertura de 2005 a 2026 (15 registros de 2026 probablemente pre-registros)
- **Marcas:** Distribución equilibrada entre 15 marcas principales
- **Top 5 marcas:**
  1. BMW: 2,849 registros
  2. Mercedes Benz: 2,361 registros
  3. Chevrolet: 2,076 registros
  4. Audi: 2,038 registros
  5. Volkswagen: 1,917 registros

---

### ⚠️ PROBLEMAS IDENTIFICADOS

#### 1. Issue #1: Contaminación del Campo Modelo - ⚠️ FALSO POSITIVO

**Descripción del hallazgo:**
El script de validación reporta 321 registros (1.08%) con "contaminación de modelo" por sufijos de una letra.

**Análisis detallado:**
Este es un **FALSO POSITIVO**. Los registros flagueados son modelos legítimos:

| Modelo | Registros | Tipo | Válido |
|--------|-----------|------|--------|
| CLASE E | 269 | Mercedes Benz Clase E | ✅ SÍ |
| CLASE B | 48 | Mercedes Benz Clase B | ✅ SÍ |
| 530 E | 3 | BMW 530e (híbrido) | ✅ SÍ |

**Explicación:**
El patrón de validación `\s+[IiAaBbEe]$` detecta cualquier modelo que termine con las letras I, A, B o E, diseñado para capturar sufijos inválidos como "JETTA I" o "GOLF IA". Sin embargo, también captura nombres legítimos de modelos Mercedes Benz.

**Recomendación:**
- ✅ NO hay contaminación real en los datos
- 🔧 Actualizar el script de validación para excluir: `CLASE [A-Z]` y `\d{3}\s*E` (modelos híbridos BMW)
- 📊 Tasa de contaminación real: **0.00%**

**Conclusión:** ✅ DATOS CORRECTOS - Script de validación requiere ajuste

---

#### 2. Información de Ocupantes en Campo Version - ❌ PROBLEMA CRÍTICO

**Descripción:**
19,378 registros (65% del total) contienen información de ocupantes (formato `XOCUP`) en el campo `version`.

**Ejemplos encontrados:**
```
ACURA ADX | A-SPEC 190HP 1.5L 4CIL 5PUERTAS 5OCUP
ACURA ILX | TECH 150HP 2.0L 4CIL 4PUERTAS 5OCUP
ACURA MDX | AWD 304HP 3.7L 6CIL 5PUERTAS 7OCUP
```

**Especificación según CLAUDE.md:**
> "Security features (ABS, BA) and occupant info (5OCUP) should be excluded from version normalization"

**Análisis de código:**
Revisando `/src/insurers/zurich/zurich-codigo-de-normalizacion.js`:

**Línea 689** - Se elimina OCUP correctamente:
```javascript
.replace(/\b0?\d+\s*OCUP?\.?\b/gi, " ")
```

**Líneas 699-707** - ERROR: Se vuelve a agregar OCUP:
```javascript
if (occupants && !versionLimpia.includes(occupants)) {
  specsToAppend.push(occupants);
}

if (specsToAppend.length > 0) {
  versionLimpia = [versionLimpia, ...specsToAppend]
    .filter(Boolean)
    .join(" ")
    .trim();
}
```

**Línea 600** - Se define occupants:
```javascript
occupants = `${occCount}OCUP`;
```

**Flujo problemático:**
1. ✅ Se extrae ocupantes del string original → variable `occupants`
2. ✅ Se limpia el string eliminando OCUP
3. ❌ **Se vuelve a agregar OCUP al final del string**

**Impacto:**
- Afecta al 65% de los registros del catálogo
- Contamina el campo `version` con datos que deben excluirse
- Inconsistencia con especificaciones del proyecto (CLAUDE.md)
- Puede afectar algoritmos de token-overlap y matching

**Solución requerida:**
Modificar todas las aseguradoras para eliminar las líneas que agregan `occupants` al `versionLimpia`:

```javascript
// ELIMINAR O COMENTAR:
// if (occupants && !versionLimpia.includes(occupants)) {
//   specsToAppend.push(occupants);
// }
```

La variable `occupants` puede mantenerse para propósitos de extracción/análisis, pero NO debe agregarse al campo `version` final.

**Archivos afectados:**
- `/src/insurers/zurich/zurich-codigo-de-normalizacion.js`
- `/src/insurers/hdi/hdi-codigo-de-normalizacion.js`
- `/src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js`
- `/src/insurers/gnp/gnp-codigo-de-normalizacion.js`
- `/src/insurers/mapfre/mapfre-codigo-de-normalizacion.js`
- `/src/insurers/axa/axa-codigo-de-normalizacion.js`
- `/src/insurers/bx/bx-codigo-de-normalizacion.js`
- `/src/insurers/chubb/chubb-codigo-de-normalizacion.js`
- `/src/insurers/atlas/atlas-codigo-de-normalizacion.js`
- `/src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js`
- `/src/insurers/ana/ana-codigo-de-normalizacion.js`

**Prioridad:** 🔴 CRÍTICA - Debe corregirse antes de producción

---

#### 3. Issue #4: Formato de ID MAPFRE - ⚠️ NO VALIDABLE

**Descripción:**
No se pudo validar el formato de ID de MAPFRE porque el campo `disponibilidad` en el catálogo de validación no contiene la información necesaria.

**Estado:** Requiere validación adicional con datos completos del catálogo homologado o consulta directa a Supabase.

**Recomendación:** Validar con query SQL directo a la base de datos:
```sql
SELECT COUNT(*) as total,
       COUNT(CASE WHEN id_original NOT LIKE '%_%' THEN 1 END) as sin_year,
       COUNT(DISTINCT id_original) as unique_ids,
       COUNT(*) - COUNT(DISTINCT id_original) as duplicados
FROM catalogo_homologado
WHERE 'MAPFRE' = ANY(string_to_array(
  jsonb_object_keys(disponibilidad), ','
));
```

---

## CASOS DE ESTUDIO DEL CLIENTE

### Caso 1: Acura ILX 2017 ✅
**Hallazgo del cliente:** Diferentes versiones (A-SPEC vs TECH)

**Validación:**
- ✅ Se encontraron 2-3 registros únicos
- ✅ Versiones correctamente diferenciadas:
  - `TECH 150HP 2.0L 4CIL 4PUERTAS 5OCUP`
  - `A-SPEC 201HP 2.0L 4CIL 4PUERTAS 5OCUP`
  - `TECH 4CIL 2.4L 201HP 4PUERTAS` (HDI - diferente especificación)

**Conclusión:** Sistema funciona correctamente, diferencia entre trims válidos

---

### Caso 2: VW Jetta 2012 ✅
**Hallazgo del cliente:** Inconsistencias de transmisión entre aseguradoras

**Validación:**
- ✅ Se encontraron 53 registros (en catálogo Zurich+HDI)
- ✅ Transmisiones correctamente asignadas:
  - CLASICO CL PAQ SEG → MANUAL
  - CLASICO SPORT → AUTO
  - CLASICO TDI → MANUAL
  - CLASICO GLI TURBO → MANUAL / AUTO (ambas variantes existen)

**Conclusión:** Sistema normaliza correctamente, diferentes versiones tienen diferentes transmisiones (esto es correcto)

---

## ANÁLISIS DE CORRECCIONES APLICADAS

### Revisión de Archivos en `/correcciones/`

Se identificaron los siguientes documentos de corrección:
1. `catalogo_revision_zurich_comparacion_versiones.pdf`
2. `catalogo_revision_zurich_hdi_comparacion_versiones_2.pdf`

**Hallazgo:** Las correcciones documentadas en PDFs han sido implementadas correctamente en el código. La separación BMW/MINI, eliminación de prefijos SERIE, y normalización de modelos funcionan según lo especificado.

---

## ANÁLISIS DE SCRIPTS DE NORMALIZACIÓN

### Fortalezas Identificadas

1. **Diccionarios de limpieza completos**
   - Eliminación de features de confort (AA, EE, CD, DVD, GPS, etc.)
   - Eliminación de características de seguridad (ABS, BA, QC)
   - Tamaños de rin (R14-R23)
   - Indicadores de transmisión

2. **Protección de tokens especiales**
   - A-SPEC, TYPE-S, TYPE-R preservados correctamente
   - Modelos con guiones (HR-V, CR-V) normalizados consistentemente

3. **Normalización de motor**
   - Aliases de motor (T-FSI → TURBO, FSI, GDI)
   - Displacement normalizado (1.8L, 2.0L)
   - Potencia en HP unificada

4. **Normalización de tracción**
   - AWD, 4WD, FWD, RWD correctamente unificados
   - 4MATIC → AWD
   - QUATTRO → AWD

5. **Consolidación de marcas**
   - KIA MOTORS → KIA
   - TESLA MOTORS → TESLA
   - MERCEDES BENZ II → MERCEDES BENZ
   - BMW MINI → MINI

### Debilidades Identificadas

1. **Re-agregación de OCUP** (CRÍTICO)
   - Ver sección de Problema Crítico arriba

2. **Patrón de validación demasiado agresivo**
   - Falso positivo en "CLASE B" y "CLASE E"
   - Requiere refinamiento del regex

---

## MÉTRICAS DE CALIDAD DETALLADAS

### Completitud de Campos
| Campo | Completitud | Estado |
|-------|-------------|--------|
| marca | 100% | ✅ Excelente |
| modelo | 100% | ✅ Excelente |
| anio | 100% | ✅ Excelente |
| transmision | 100% | ✅ Excelente |
| version | 100% | ⚠️ Contiene OCUP |
| hash_comercial | 100% | ✅ Excelente |

### Integridad Referencial
- ✅ Todos los registros tienen hash_comercial válido (SHA-256)
- ✅ No hay duplicados en id_vehiculo
- ✅ Años en rango válido (2005-2026)
- ✅ Transmisiones con valores estándar

### Distribución de Cobertura por Aseguradora

**Nota:** No se pudo validar distribución por aseguradora en este catálogo de validación porque no contiene el campo `disponibilidad` en formato JSONB esperado. Se recomienda validación directa en Supabase.

---

## COMPARACIÓN: CATÁLOGO ZURICH vs ZURICH+HDI

| Métrica | Zurich | Zurich+HDI | Diferencia |
|---------|--------|------------|------------|
| Total registros | 20,505 | 29,767 | +9,262 (+45%) |
| Contaminación aparente | 246 (1.20%) | 321 (1.08%) | +75 |
| - CLASE E | ~200 | 269 | +69 |
| - CLASE B | ~40 | 48 | +8 |
| - 530 E | ~6 | 3 | -3 |
| Registros con OCUP | ~13,300 (65%) | 19,378 (65%) | Proporción igual |
| Marcas MINI | 427 | 874 | +447 (+105%) |

**Interpretación:**
- La adición de HDI aumenta cobertura en ~45%
- El problema de OCUP persiste en la misma proporción (65%)
- Mayor diversidad en modelos MINI con HDI
- Los falsos positivos de "CLASE E/B" aumentan proporcionalmente

---

## RECOMENDACIONES

### 🔴 CRÍTICAS (Antes de Producción)

1. **Eliminar OCUP del campo version**
   - **Prioridad:** MÁXIMA
   - **Archivos:** Todos los scripts de normalización (11 archivos)
   - **Acción:** Comentar/eliminar líneas que agregan `occupants` a `specsToAppend`
   - **Impacto:** 19,378 registros (65%)
   - **Tiempo estimado:** 2-3 horas
   - **Validación:** Re-ejecutar ETL y verificar que campo `version` no contenga XOCUP

2. **Validar formato de ID MAPFRE**
   - **Prioridad:** ALTA
   - **Acción:** Ejecutar query SQL directo en Supabase
   - **Tiempo estimado:** 30 minutos

### 🟡 IMPORTANTES (Post-Producción)

3. **Actualizar script de validación**
   - **Prioridad:** MEDIA
   - **Archivo:** `scripts/simple_catalog_validation.py`
   - **Acción:** Modificar patrón para excluir:
     ```python
     # Excluir modelos legítimos
     if modelo in ['CLASE A', 'CLASE B', 'CLASE C', 'CLASE E', 'CLASE S']:
         continue
     if re.match(r'^\d{3}\s*E$', modelo):  # BMW híbridos (530 E, etc.)
         continue
     ```
   - **Tiempo estimado:** 1 hora

4. **Documentar decisión sobre PUERTAS**
   - **Prioridad:** MEDIA
   - **Acción:** Clarificar en CLAUDE.md si "XPUERTAS" debe incluirse o excluirse
   - **Hallazgo:** Actualmente se incluye, lo cual parece correcto para diferenciación
   - **Tiempo estimado:** 30 minutos (decisión + documentación)

### 🟢 MEJORAS OPCIONALES (Futuro)

5. **Agregar tests automatizados**
   - Validación de no-regresión para OCUP
   - Test de casos de cliente (Acura ILX, VW Jetta)
   - Tiempo estimado: 4-6 horas

6. **Monitoreo de calidad post-despliegue**
   - Dashboard con métricas de calidad
   - Alertas para contaminación > 0.5%
   - Tiempo estimado: 8-10 horas

---

## PLAN DE ACCIÓN PARA PRODUCCIÓN

### Fase 1: Corrección Crítica (BLOQUEANTE)
**Duración estimada: 4-6 horas**

1. ✅ **Backup de scripts actuales** (15 min)
   ```bash
   mkdir -p backups/$(date +%Y%m%d)
   cp -r src/insurers backups/$(date +%Y%m%d)/
   ```

2. 🔧 **Modificar scripts de normalización** (2 horas)
   - Abrir cada archivo `*-codigo-de-normalizacion*.js`
   - Buscar: `if (occupants && !versionLimpia.includes(occupants))`
   - Comentar bloque completo que agrega `occupants` a `specsToAppend`
   - Mantener extracción de `occupants` para trazabilidad

3. 🧪 **Pruebas locales** (1 hora)
   - Ejecutar scripts con datos sample
   - Verificar que `version` no contenga OCUP
   - Validar que otras normalizaciones sigan funcionando

4. 🚀 **Desplegar a n8n** (1 hora)
   - Actualizar workflows de n8n
   - Probar con batch pequeño (100 registros)
   - Validar resultados en Supabase

5. ✅ **Re-validación completa** (1-2 horas)
   - Re-ejecutar `simple_catalog_validation.py`
   - Verificar que OCUP = 0 registros
   - Generar nuevo reporte de calidad

### Fase 2: Validación MAPFRE (NO BLOQUEANTE)
**Duración estimada: 1 hora**

```sql
-- Ejecutar en Supabase
SELECT
  COUNT(*) as total_mapfre,
  COUNT(CASE WHEN id_original NOT LIKE '%_%' THEN 1 END) as sin_year_suffix,
  COUNT(DISTINCT id_original) as ids_unicos,
  COUNT(*) - COUNT(DISTINCT id_original) as duplicados
FROM catalogo_homologado
WHERE disponibilidad ? 'MAPFRE';
```

### Fase 3: Mejoras Post-Producción
**Duración estimada: 2-3 horas**

1. Actualizar script de validación (1 hora)
2. Documentar decisión sobre PUERTAS (30 min)
3. Crear tests de regresión básicos (1-2 horas)

---

## CRITERIOS DE ACEPTACIÓN PARA PRODUCCIÓN

### ✅ DEBE CUMPLIRSE (Bloqueantes)

- [ ] **0 registros con XOCUP en campo version**
  - Actual: 19,378 (65%)
  - Target: 0 (0%)

- [ ] **Validación MAPFRE completada**
  - Actual: No validado
  - Target: 0 IDs sin year, 0 duplicados

- [ ] **Validación en ambiente de staging**
  - Ejecutar ETL completo con correcciones
  - Verificar 1,000+ registros aleatorios

### ✅ RECOMENDADO (No bloqueantes)

- [ ] Script de validación actualizado
- [ ] Decisión sobre PUERTAS documentada
- [ ] Al menos 3 casos de cliente verificados

---

## CONCLUSIONES

### Estado Actual

El sistema de homologación ha implementado correctamente la mayoría de las correcciones identificadas:

✅ **Funcionando bien:**
- Separación BMW/MINI
- Completitud de modelos (no hay letras únicas)
- Normalización de transmisión (100% válido)
- Consolidación de marcas
- Limpieza de caracteres de escape
- Distribución y cobertura de datos

❌ **Requiere corrección:**
- Campo `version` contiene información de ocupantes (XOCUP) que debe excluirse
- Afecta 65% de registros (19,378 de 29,767)

⚠️ **Falso positivo:**
- "Contaminación de modelo" reportada (1.08%) son en realidad modelos legítimos
- No requiere acción en datos, solo ajuste en script de validación

### Listo para Producción: ❌ NO

**Bloqueante principal:** Inclusión de XOCUP en campo version contradice especificaciones del proyecto.

**Tiempo estimado para resolver:** 4-6 horas de trabajo (corrección + validación)

### Siguientes Pasos Inmediatos

1. **HOY:** Implementar corrección de OCUP en scripts de normalización
2. **HOY:** Re-ejecutar ETL con datos corregidos
3. **HOY:** Validar resultados y generar nuevo reporte
4. **MAÑANA:** Ejecutar validación de IDs MAPFRE
5. **MAÑANA:** Si todo ✅ → Aprobación para producción

### Calificación General de Calidad

| Aspecto | Calificación | Nota |
|---------|-------------|------|
| Integridad estructural | 95/100 | ✅ Excelente |
| Normalización de datos | 90/100 | ✅ Muy bueno |
| Conformidad con specs | 35/100 | ❌ Problema crítico OCUP |
| Distribución y cobertura | 95/100 | ✅ Excelente |
| **TOTAL** | **78.75/100** | ⚠️ Aceptable post-corrección |

**Post-corrección estimada:** 95/100 ✅ Excelente

---

## APÉNDICES

### A. Comandos de Validación Ejecutados

```bash
# Validación completa de catálogos
python3 scripts/simple_catalog_validation.py

# Análisis de OCUP
python3 -c "
import csv
import re
filepath = 'data/validation/catalogo_revision_zurich_hdi.csv'
ocup_pattern = re.compile(r'\d+OCUP')
count = sum(1 for row in csv.DictReader(open(filepath))
            if ocup_pattern.search(row.get('version', '')))
print(f'Registros con OCUP: {count:,}')
"

# Análisis de modelos "contaminados"
python3 -c "
import csv
import re
from collections import Counter
filepath = 'data/validation/catalogo_revision_zurich_hdi.csv'
pattern = re.compile(r'\s+[IiAaBbEe]$')
modelo_counts = Counter(row.get('modelo', '') for row in csv.DictReader(open(filepath))
                        if pattern.search(row.get('modelo', '')))
for modelo, count in modelo_counts.most_common(20):
    print(f'{count:>5} | {modelo}')
"
```

### B. Estructura de Archivos Analizados

```
/data/
  /validation/
    - catalogo_revision_zurich.csv (20,505 registros)
    - catalogo_revision_zurich_hdi.csv (29,767 registros)
  /origin/
    - zurich-origin.csv (38,993 registros)
    - hdi-origin.csv (38,186 registros)
    - [otros 9 archivos de aseguradoras]

/src/insurers/
  - 11 directorios de aseguradoras
  - 11 scripts de normalización (.js)

/scripts/
  - simple_catalog_validation.py (usado para análisis)
  - comprehensive_catalog_validation.py
  - [otros 7 scripts de validación]

/correcciones/
  - 2 PDFs de comparación de versiones
```

### C. Referencias

- **Especificación del proyecto:** `CLAUDE.md`
- **Resultados de validación:** `reports/validation_results_zurich_hdi.json`
- **Scripts de normalización:** `src/insurers/*/codigo-de-normalizacion*.js`

---

**Fin del Reporte**

*Generado automáticamente por Claude Code - 2025-10-22*
