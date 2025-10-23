# Solución Técnica - Normalización de Espaciado

**Fecha:** 22 de Octubre, 2025
**Autor:** ETL Development Team
**Versión:** 2.0 - INDEPENDIENTE (sin imports)

---

## Resumen Ejecutivo

Este documento presenta la solución técnica para resolver problemas de espaciado en campos de versión que afectan el token overlap matching. La implementación se realiza mediante **código inline en cada archivo de normalización**, ya que los workflows de n8n son independientes y no pueden compartir módulos.

### Alcance de la Solución

- **Normalizaciones de ALTA prioridad:** M SPORT, X DRIVE, URBAN LINE, SPORT LINE
- **Impacto estimado:** 5-10% mejora en match rate, ~20,000-30,000 registros mejorados
- **Archivos afectados:** Los 11 archivos `*-codigo-de-normalizacion.js`
- **Método:** Código inline (copy-paste) en cada archivo - SIN imports externos

### Arquitectura de n8n

**IMPORTANTE:** Cada aseguradora corre en un workflow n8n INDEPENDIENTE:
- ❌ NO se pueden usar `require()` o imports de módulos externos
- ❌ NO se puede compartir código entre workflows
- ✅ Cada archivo debe ser completamente autónomo
- ✅ El código de normalización debe estar inline en cada Code Node

---

## Estrategia de Normalización

### Principios Fundamentales

1. **Normalización temprana:** Aplicar antes de tokenización
2. **Consistencia cross-insurer:** Misma forma canónica para todas las aseguradoras
3. **Código inline:** Cada archivo contiene su propia copia del código
4. **Protección de tokens:** Usar placeholders para preservar tokens significativos
5. **Reversibilidad:** Mantener trazabilidad con `version_original`

### Proceso de Normalización

```
Input: "BMW 118i M SPORT AUTOMATICA"
   ↓
[1] Proteger tokens especiales → "BMW 118i __PROTECTED_M_SPORT__ AUTOMATICA"
   ↓
[2] Aplicar limpiezas → (sin cambios, ya protegido)
   ↓
[3] Restaurar con forma canónica → "BMW 118i M-SPORT AUTOMATICA"
   ↓
Output: "BMW 118i M-SPORT AUTOMATICA"
```

---

## Código de Normalización - INLINE TEMPLATE

### Snippet para Agregar a CADA Aseguradora

Este código debe agregarse al inicio de la función `cleanVersion()` en cada archivo `*-codigo-de-normalizacion.js`:

```javascript
/**
 * ============================================================================
 * SPACING NORMALIZATION - v2.0
 * ============================================================================
 * Resuelve inconsistencias de espaciado en trim lines y prefijos
 * que causan fragmentación de tokens y fallan matches.
 *
 * Issue: Spacing issues causing token overlap failures
 * Date: 2025-10-22
 * ============================================================================
 */

/**
 * Paso 1: Definir patrones de spacing a normalizar
 */
const SPACING_NORMALIZATION_PATTERNS = [
  // BMW M Sport (ALTA prioridad - 125+ ocurrencias)
  {
    regex: /\bM\s+SPORT\b/gi,
    placeholder: "__PROTECTED_M_SPORT__",
    canonical: "M-SPORT"
  },
  // BMW xDrive (ALTA prioridad - 15+ ocurrencias)
  {
    regex: /\bX\s+DRIVE\b/gi,
    placeholder: "__PROTECTED_X_DRIVE__",
    canonical: "XDRIVE"
  },
  // BMW Urban Line (ALTA prioridad - 12+ ocurrencias)
  {
    regex: /\bURBAN\s+LINE\b/gi,
    placeholder: "__PROTECTED_URBAN_LINE__",
    canonical: "URBAN-LINE"
  },
  // BMW Sport Line (ALTA prioridad - 10+ ocurrencias)
  {
    regex: /\bSPORT\s+LINE\b/gi,
    placeholder: "__PROTECTED_SPORT_LINE__",
    canonical: "SPORT-LINE"
  },
  // BMW X Line (MEDIA prioridad - 7 ocurrencias)
  {
    regex: /\bX\s+LINE\b/gi,
    placeholder: "__PROTECTED_X_LINE__",
    canonical: "X-LINE"
  },
  // BMW M Competition (MEDIA prioridad - 9 ocurrencias)
  {
    regex: /\bM\s+COMPETITION\b/gi,
    placeholder: "__PROTECTED_M_COMPETITION__",
    canonical: "M-COMPETITION"
  },

  // Patterns adicionales ya existentes (si los hay)
  {
    regex: /\bA[\s-]?SPEC\b/gi,
    placeholder: "__PROTECTED_A_SPEC__",
    canonical: "A-SPEC"
  },
  {
    regex: /\bTYPE[\s-]?S\b/gi,
    placeholder: "__PROTECTED_TYPE_S__",
    canonical: "TYPE-S"
  },
  {
    regex: /\bTYPE[\s-]?R\b/gi,
    placeholder: "__PROTECTED_TYPE_R__",
    canonical: "TYPE-R"
  },
  {
    regex: /\bS[\s-]?LINE\b/gi,
    placeholder: "__PROTECTED_S_LINE__",
    canonical: "S-LINE"
  },
  {
    regex: /\bR[\s-]?LINE\b/gi,
    placeholder: "__PROTECTED_R_LINE__",
    canonical: "R-LINE"
  },
  {
    regex: /\bE[\s-]?TRON\b/gi,
    placeholder: "__PROTECTED_E_TRON__",
    canonical: "E-TRON"
  },
  {
    regex: /\bBI[\s-]?TURBO\b/gi,
    placeholder: "__PROTECTED_BI_TURBO__",
    canonical: "BI-TURBO"
  },
  {
    regex: /\bTWIN[\s-]?TURBO\b/gi,
    placeholder: "__PROTECTED_TWIN_TURBO__",
    canonical: "TWIN-TURBO"
  }
];

/**
 * Paso 2: Función helper para aplicar spacing normalization
 */
function applySpacingNormalization(text) {
  if (!text) return "";

  let normalized = text;

  // PASO 1: Proteger tokens (reemplazar con placeholders)
  SPACING_NORMALIZATION_PATTERNS.forEach(({ regex, placeholder }) => {
    normalized = normalized.replace(regex, placeholder);
  });

  // PASO 2: Aquí van otras limpiezas (tokens irrelevantes, etc.)
  // ... código existente de limpieza ...

  // PASO 3: Restaurar tokens protegidos con forma canónica
  SPACING_NORMALIZATION_PATTERNS.forEach(({ placeholder, canonical }) => {
    normalized = normalized.replace(new RegExp(placeholder, 'g'), canonical);
  });

  return normalized;
}
```

---

## Implementación por Aseguradora

### Paso 1: Ubicar la Función cleanVersion()

En cada archivo `*-codigo-de-normalizacion.js`, encontrar la función que limpia el campo `version`:

**Ejemplo actual (antes de modificar):**
```javascript
function cleanVersion(versionOriginal) {
  if (!versionOriginal) return "";

  let cleaned = versionOriginal.toUpperCase().trim();

  // Remover tokens irrelevantes
  IRRELEVANT_TOKENS.forEach(token => {
    const regex = new RegExp(`\\b${token}\\b`, 'gi');
    cleaned = cleaned.replace(regex, ' ');
  });

  // Limpiar espacios múltiples
  cleaned = cleaned.replace(/\s+/g, ' ').trim();

  return cleaned;
}
```

### Paso 2: Agregar Spacing Normalization

**Ejemplo modificado (después de agregar spacing normalization):**
```javascript
function cleanVersion(versionOriginal) {
  if (!versionOriginal) return "";

  let cleaned = versionOriginal.toUpperCase().trim();

  // ===== NUEVO: SPACING NORMALIZATION =====
  // PASO 1: Proteger tokens con spacing issues
  const SPACING_PATTERNS = [
    { regex: /\bM\s+SPORT\b/gi, placeholder: "__M_SPORT__", canonical: "M-SPORT" },
    { regex: /\bX\s+DRIVE\b/gi, placeholder: "__X_DRIVE__", canonical: "XDRIVE" },
    { regex: /\bURBAN\s+LINE\b/gi, placeholder: "__URBAN_LINE__", canonical: "URBAN-LINE" },
    { regex: /\bSPORT\s+LINE\b/gi, placeholder: "__SPORT_LINE__", canonical: "SPORT-LINE" },
    { regex: /\bX\s+LINE\b/gi, placeholder: "__X_LINE__", canonical: "X-LINE" },
    { regex: /\bM\s+COMPETITION\b/gi, placeholder: "__M_COMP__", canonical: "M-COMPETITION" },
  ];

  SPACING_PATTERNS.forEach(({ regex, placeholder }) => {
    cleaned = cleaned.replace(regex, placeholder);
  });
  // ===== FIN PASO 1 =====

  // PASO 2: Remover tokens irrelevantes (código existente)
  IRRELEVANT_TOKENS.forEach(token => {
    const regex = new RegExp(`\\b${token}\\b`, 'gi');
    cleaned = cleaned.replace(regex, ' ');
  });

  // PASO 3: Limpiar espacios múltiples
  cleaned = cleaned.replace(/\s+/g, ' ').trim();

  // ===== NUEVO: SPACING NORMALIZATION =====
  // PASO 4: Restaurar tokens protegidos con forma canónica
  SPACING_PATTERNS.forEach(({ placeholder, canonical }) => {
    cleaned = cleaned.replace(new RegExp(placeholder, 'g'), canonical);
  });
  // ===== FIN PASO 4 =====

  return cleaned;
}
```

### Paso 3: Template Completo - Copy/Paste Ready

**Agregar este bloque COMPLETO al inicio de cada archivo de normalización:**

```javascript
// ============================================================================
// SPACING NORMALIZATION CONFIGURATION
// Added: 2025-10-22
// Issue: Spacing inconsistencies causing token overlap failures
// ============================================================================

const SPACING_NORMALIZATION_PATTERNS = [
  { regex: /\bM\s+SPORT\b/gi, placeholder: "__M_SPORT__", canonical: "M-SPORT" },
  { regex: /\bX\s+DRIVE\b/gi, placeholder: "__X_DRIVE__", canonical: "XDRIVE" },
  { regex: /\bURBAN\s+LINE\b/gi, placeholder: "__URBAN_LINE__", canonical: "URBAN-LINE" },
  { regex: /\bSPORT\s+LINE\b/gi, placeholder: "__SPORT_LINE__", canonical: "SPORT-LINE" },
  { regex: /\bX\s+LINE\b/gi, placeholder: "__X_LINE__", canonical: "X-LINE" },
  { regex: /\bM\s+COMPETITION\b/gi, placeholder: "__M_COMP__", canonical: "M-COMPETITION" },
  { regex: /\bA[\s-]?SPEC\b/gi, placeholder: "__A_SPEC__", canonical: "A-SPEC" },
  { regex: /\bTYPE[\s-]?S\b/gi, placeholder: "__TYPE_S__", canonical: "TYPE-S" },
  { regex: /\bTYPE[\s-]?R\b/gi, placeholder: "__TYPE_R__", canonical: "TYPE-R" },
  { regex: /\bS[\s-]?LINE\b/gi, placeholder: "__S_LINE__", canonical: "S-LINE" },
  { regex: /\bR[\s-]?LINE\b/gi, placeholder: "__R_LINE__", canonical: "R-LINE" },
  { regex: /\bE[\s-]?TRON\b/gi, placeholder: "__E_TRON__", canonical: "E-TRON" },
  { regex: /\bBI[\s-]?TURBO\b/gi, placeholder: "__BI_TURBO__", canonical: "BI-TURBO" },
];

function applySpacingProtection(text) {
  if (!text) return text;
  let result = text;
  SPACING_NORMALIZATION_PATTERNS.forEach(({ regex, placeholder }) => {
    result = result.replace(regex, placeholder);
  });
  return result;
}

function restoreSpacingNormalized(text) {
  if (!text) return text;
  let result = text;
  SPACING_NORMALIZATION_PATTERNS.forEach(({ placeholder, canonical }) => {
    result = result.replace(new RegExp(placeholder, 'g'), canonical);
  });
  return result;
}

// ============================================================================
// END SPACING NORMALIZATION CONFIGURATION
// ============================================================================
```

**Luego MODIFICAR la función cleanVersion() para usarlo:**

```javascript
function cleanVersion(versionOriginal) {
  if (!versionOriginal) return "";

  let cleaned = versionOriginal.toUpperCase().trim();

  // NUEVO: Proteger spacing patterns ANTES de otras limpiezas
  cleaned = applySpacingProtection(cleaned);

  // ... resto del código de limpieza existente ...
  // (remover tokens irrelevantes, limpiar espacios, etc.)

  // NUEVO: Restaurar con formas canónicas AL FINAL
  cleaned = restoreSpacingNormalized(cleaned);

  return cleaned;
}
```

---

## Archivos a Modificar (11 Aseguradoras)

### Checklist de Implementación

Aplicar el mismo cambio a cada uno de estos archivos:

- [ ] **ANA:** `src/insurers/ana/ana-codigo-de-normalizacion.js`
- [ ] **ATLAS:** `src/insurers/atlas/atlas-codigo-de-normalizacion.js`
- [ ] **AXA:** `src/insurers/axa/axa-codigo-de-normalizacion.js`
- [ ] **BX:** `src/insurers/bx/bx-codigo-de-normalizacion.js`
- [ ] **CHUBB:** `src/insurers/chubb/chubb-codigo-de-normalizacion.js`
- [ ] **EL POTOSÍ:** `src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js`
- [ ] **GNP:** `src/insurers/gnp/gnp-codigo-de-normalizacion.js`
- [ ] **HDI:** `src/insurers/hdi/hdi-codigo-de-normalizacion.js`
- [ ] **MAPFRE:** `src/insurers/mapfre/mapfre-codigo-de-normalizacion.js`
- [ ] **QUALITAS:** `src/insurers/qualitas/qualitas-codigo-de-normalizacion-n8n.js`
- [ ] **ZURICH:** `src/insurers/zurich/zurich-codigo-de-normalizacion.js`

### Proceso por Archivo

Para CADA archivo:

1. **Abrir** el archivo `*-codigo-de-normalizacion.js`
2. **Agregar** el bloque de configuración (líneas 1-30 del template)
3. **Modificar** la función `cleanVersion()`:
   - Agregar `cleaned = applySpacingProtection(cleaned);` AL INICIO
   - Agregar `cleaned = restoreSpacingNormalized(cleaned);` AL FINAL
4. **Guardar** el archivo
5. **Testar** con casos de prueba (ver sección siguiente)

---

## Testing y Validación

### Test Cases Inline (Para cada archivo)

Agregar estos test cases al final del archivo de normalización:

```javascript
// ============================================================================
// TEST CASES - Ejecutar para validar spacing normalization
// ============================================================================
/*
function testSpacingNormalization() {
  const testCases = [
    {
      input: "BMW 118I M SPORT AUTOMATICA 3PTAS",
      expectedContains: "M-SPORT",
      expectedNotContains: "M SPORT"
    },
    {
      input: "BMW IX2 X DRIVE 30 EV AUTOMATICA",
      expectedContains: "XDRIVE",
      expectedNotContains: "X DRIVE"
    },
    {
      input: "BMW 118I URBAN LINE STD 5PTAS",
      expectedContains: "URBAN-LINE",
      expectedNotContains: "URBAN LINE"
    },
    {
      input: "BMW 118I SPORT LINE AUTOMATICA",
      expectedContains: "SPORT-LINE",
      expectedNotContains: "SPORT LINE"
    },
    {
      input: "MINI COOPER S CHILI AUTOMATICA",
      expectedContains: "CHILI",
      expectedNotContains: "S-CHILI"  // S is part of model, not trim
    }
  ];

  let passed = 0;
  let failed = 0;

  testCases.forEach((test, index) => {
    const output = cleanVersion(test.input);
    let success = true;

    if (!output.includes(test.expectedContains)) {
      console.error(`❌ Test ${index + 1} FAILED: Missing "${test.expectedContains}"`);
      console.error(`   Input:  "${test.input}"`);
      console.error(`   Output: "${output}"`);
      success = false;
    }

    if (output.includes(test.expectedNotContains)) {
      console.error(`❌ Test ${index + 1} FAILED: Should not contain "${test.expectedNotContains}"`);
      console.error(`   Input:  "${test.input}"`);
      console.error(`   Output: "${output}"`);
      success = false;
    }

    if (success) {
      console.log(`✅ Test ${index + 1} PASSED`);
      passed++;
    } else {
      failed++;
    }
  });

  console.log(`\n📊 Results: ${passed} passed, ${failed} failed`);
  return failed === 0;
}

// Uncomment to run tests:
// testSpacingNormalization();
*/
```

### Validación en n8n

**Para cada workflow:**

1. **Abrir** el workflow en n8n
2. **Editar** el Code Node de normalización
3. **Pegar** el código actualizado
4. **Ejecutar** con datos de prueba (usar Execute Node)
5. **Verificar** que output contiene formas normalizadas (M-SPORT, XDRIVE, etc.)

---

## Ejemplo Real - ANA

### Archivo: `src/insurers/ana/ana-codigo-de-normalizacion.js`

**ANTES:**
```javascript
const crypto = require("crypto");

// Existing configuration...
const IRRELEVANT_TOKENS = [
  "AA", "EE", "CD", "BA", "ABS", "QC", "VP", ...
];

function cleanVersion(versionOriginal) {
  if (!versionOriginal) return "";
  let cleaned = versionOriginal.toUpperCase().trim();

  // Remove irrelevant tokens
  IRRELEVANT_TOKENS.forEach(token => {
    const regex = new RegExp(`\\b${token}\\b`, 'gi');
    cleaned = cleaned.replace(regex, ' ');
  });

  cleaned = cleaned.replace(/\s+/g, ' ').trim();
  return cleaned;
}

// Rest of the code...
```

**DESPUÉS:**
```javascript
const crypto = require("crypto");

// ============================================================================
// SPACING NORMALIZATION - Added 2025-10-22
// ============================================================================
const SPACING_NORMALIZATION_PATTERNS = [
  { regex: /\bM\s+SPORT\b/gi, placeholder: "__M_SPORT__", canonical: "M-SPORT" },
  { regex: /\bX\s+DRIVE\b/gi, placeholder: "__X_DRIVE__", canonical: "XDRIVE" },
  { regex: /\bURBAN\s+LINE\b/gi, placeholder: "__URBAN_LINE__", canonical: "URBAN-LINE" },
  { regex: /\bSPORT\s+LINE\b/gi, placeholder: "__SPORT_LINE__", canonical: "SPORT-LINE" },
  { regex: /\bX\s+LINE\b/gi, placeholder: "__X_LINE__", canonical: "X-LINE" },
  { regex: /\bM\s+COMPETITION\b/gi, placeholder: "__M_COMP__", canonical: "M-COMPETITION" },
];

function applySpacingProtection(text) {
  if (!text) return text;
  let result = text;
  SPACING_NORMALIZATION_PATTERNS.forEach(({ regex, placeholder }) => {
    result = result.replace(regex, placeholder);
  });
  return result;
}

function restoreSpacingNormalized(text) {
  if (!text) return text;
  let result = text;
  SPACING_NORMALIZATION_PATTERNS.forEach(({ placeholder, canonical }) => {
    result = result.replace(new RegExp(placeholder, 'g'), canonical);
  });
  return result;
}
// ============================================================================

// Existing configuration...
const IRRELEVANT_TOKENS = [
  "AA", "EE", "CD", "BA", "ABS", "QC", "VP", ...
];

function cleanVersion(versionOriginal) {
  if (!versionOriginal) return "";
  let cleaned = versionOriginal.toUpperCase().trim();

  // NUEVO: Protect spacing patterns first
  cleaned = applySpacingProtection(cleaned);

  // Remove irrelevant tokens (existing code)
  IRRELEVANT_TOKENS.forEach(token => {
    const regex = new RegExp(`\\b${token}\\b`, 'gi');
    cleaned = cleaned.replace(regex, ' ');
  });

  cleaned = cleaned.replace(/\s+/g, ' ').trim();

  // NUEVO: Restore with canonical forms
  cleaned = restoreSpacingNormalized(cleaned);

  return cleaned;
}

// Rest of the code...
```

---

## Despliegue en n8n

### Checklist de Despliegue por Workflow

Para CADA aseguradora:

#### Preparación
- [ ] Backup del workflow actual (Export JSON desde n8n)
- [ ] Copiar código modificado del archivo `*-codigo-de-normalizacion.js`

#### Implementación
- [ ] Abrir workflow en n8n
- [ ] Encontrar el Code Node de normalización
- [ ] Pegar código actualizado
- [ ] Guardar cambios

#### Testing
- [ ] Ejecutar con datos de prueba (5-10 registros)
- [ ] Verificar que version contiene formas normalizadas:
  - ✅ "M-SPORT" (no "M SPORT")
  - ✅ "XDRIVE" (no "X DRIVE")
  - ✅ "URBAN-LINE" (no "URBAN LINE")
- [ ] Verificar que otros campos no se afectaron

#### Validación
- [ ] Procesar batch pequeño (100-500 registros)
- [ ] Revisar resultados en Supabase
- [ ] Comparar hash_comercial y version con batch anterior
- [ ] Verificar match rates

#### Activación
- [ ] Activar workflow en n8n
- [ ] Monitorear primeras ejecuciones
- [ ] Documentar cualquier error

---

## Rollback Plan

Si se detectan problemas:

### Rollback Inmediato (por workflow)

1. **Ir a n8n** workflow afectado
2. **Abrir historial** de versiones (si disponible)
3. **Restaurar versión anterior** del workflow
4. **O:** Pegar código del backup JSON

### Rollback Completo (todas aseguradoras)

1. **Revertir cambios** en archivos `.js` locales:
   ```bash
   git checkout HEAD~1 src/insurers/*/\*-codigo-de-normalizacion.js
   ```

2. **Actualizar workflows n8n** con código revertido

3. **Re-procesar registros afectados** si es necesario

---

## Impacto Esperado

### Métricas de Éxito

**Antes de Implementación (Baseline):**
- Match rate con umbral 0.92 (same insurer): ~85%
- Match rate con umbral 0.50 (cross insurer): ~65%
- Registros con nulls/duplicados: ~75,000

**Después de Implementación (Target):**
- Match rate con umbral 0.92: ~90% (+5%)
- Match rate con umbral 0.50: ~70% (+5%)
- Registros con nulls/duplicados: ~55,000 (-20,000)

### Casos Específicos Mejorados

**BMW 118i URBAN LINE:**
- Tokens antes: ["I", "URBAN", "LINE", "2", "0", "L"] vs ["118I", "URBAN", "LINE", ...]
- Tokens después: ["I", "URBAN-LINE", "2", "0", "L"] vs ["118I", "URBAN-LINE", ...]
- Overlap antes: 0.40
- Overlap después: 0.75
- **Mejora: +87.5%**

**BMW X3 M SPORT XDRIVE:**
- Overlap antes: 0.60
- Overlap después: 0.95
- **Mejora: +58%**

---

## Mantenimiento

### Agregar Nuevos Patterns

Si se identifican nuevos spacing issues:

1. **Agregar al array** `SPACING_NORMALIZATION_PATTERNS` en TODOS los archivos:
   ```javascript
   {
     regex: /\bNUEVO\s+PATTERN\b/gi,
     placeholder: "__NUEVO__",
     canonical: "NUEVO-PATTERN"
   }
   ```

2. **Agregar test case** correspondiente

3. **Validar** con datos reales

4. **Desplegar** siguiendo proceso arriba

### Sincronización entre Archivos

**CRÍTICO:** Como el código es inline en cada archivo, los cambios deben aplicarse a TODOS los 11 archivos manualmente.

**Proceso recomendado:**
1. Mantener un archivo "master" con el código de referencia
2. Al agregar nuevos patterns, actualizar el master primero
3. Copy-paste a los 11 archivos
4. Usar script de validación para asegurar consistencia

---

## Conclusión

La solución de spacing normalization se implementa mediante **código inline en cada archivo** sin dependencias externas:

- ✅ **Compatible con n8n:** Cada workflow es independiente
- ✅ **Sin imports:** Todo el código está en el mismo archivo
- ✅ **Copy-paste ready:** Templates listos para usar
- ✅ **Testeable:** Test cases incluidos en cada archivo
- ✅ **Reversible:** Rollback simple con backups

**Impacto estimado:** 20,000-30,000 registros mejorados, 5-10% reducción en nulls/duplicados.

**Esfuerzo requerido:** ~1-2 horas por aseguradora × 11 = **12-22 horas totales** (desarrollo + testing + despliegue).

**Riesgo:** BAJO - cambios aislados por workflow, fácil rollback individual.

---

## Próximos Pasos

1. ✅ Revisar y aprobar esta solución técnica
2. ⏳ Elegir 1-2 aseguradoras para piloto (recomendado: ANA + HDI)
3. ⏳ Implementar en piloto
4. ⏳ Validar resultados
5. ⏳ Expandir a las 9 aseguradoras restantes
6. ⏳ Monitorear match rates
7. ⏳ Documentar mejoras obtenidas

**¿Listo para comenzar con el piloto?**
