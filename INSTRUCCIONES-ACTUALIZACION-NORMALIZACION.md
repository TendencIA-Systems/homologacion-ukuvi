# Instrucciones de Actualización - Normalización Definitiva

**Fecha:** 22 de Octubre, 2025
**Objetivo:** Implementar diccionarios universales de normalización en todas las aseguradoras

---

## Cambios Principales

### 1. Limpieza de Campo MODELO

**Problema identificado:** El campo `modelo` contiene specs que deben estar en `version`

**Ejemplos encontrados:**
- `"GOLF GTI"` → debe ser modelo: `"GOLF"`, version: `"GTI ..."`
- `"JETTA (DERBY)"` → debe ser modelo: `"JETTA"`, version: `"DERBY ..."`
- `"AMAROK PICK UP"` → debe ser modelo: `"AMAROK"`, version: `"PICK UP ..."`
- `"AVEO HATCH BACK"` → debe ser modelo: `"AVEO"`, version: `"HATCH BACK ..."`

**Impacto:** 19,949 registros (5.2%) tienen specs en modelo que serán limpiados

**Specs más comunes a remover:**
1. VAN (6,699 ocurrencias)
2. RS (5,013 ocurrencias)
3. PICK UP (4,300 ocurrencias)
4. GT (1,023 ocurrencias)
5. WAGON (931 ocurrencias)

### 2. Expansión de Tokens Irrelevantes en VERSION

**Problema:** Tokens de navegación, audio, confort contaminan el matching

**Ejemplos encontrados en Zurich:**
- `SIS.NAV.`, `SIS NAV`, `NAVEGACION`, `PAQ.NAVEG`
- `RIN 17`, `R17`, `R18`, `R19`
- `BA`, `ABS`, `VP`, `QC`, `CA`, `CE`

**Impacto:** 143,694 registros (37.3%) tienen tokens irrelevantes en version

**Categorías agregadas:**
1. Navegación: SIS.NAV., PAQ.NAVEG, NAVEGACION, RCD, RNS, etc. (8,361 ocurrencias)
2. Audio: DVD, MP3, USB, BOSE, BLUETOOTH, etc. (5,423 ocurrencias)
3. Confort: PIEL, TELA, QUEMACOCOS, CLIMA DUAL, etc. (52,852 ocurrencias)
4. Safety (abreviaturas): BA, CA, CE, QC, VP, SM, VT, DIS, TAM (110,149 ocurrencias)
5. Ruedas: RIN 17, R17, R18, R19, etc. (11,447 ocurrencias)

---

## Archivos Creados

### `UNIVERSAL_NORMALIZATION_DICTIONARIES.js`

Contiene:
- `MODELO_SPECS_TO_REMOVE`: Array con 50+ specs a remover de modelo
- `IRRELEVANT_VERSION_TOKENS`: Array con 150+ tokens irrelevantes para version
- `PROTECTED_HYPHEN_TOKENS`: Tokens con guión que deben preservarse
- `cleanModeloAndEnhanceVersion()`: Función para limpiar modelo y mover specs a version
- `cleanVersionTokens()`: Función para limpiar version de tokens irrelevantes

---

## Cómo Aplicar los Cambios

### Paso 1: Importar Diccionarios Universales

En cada archivo `src/insurers/[aseguradora]/[aseguradora]-codigo-de-normalizacion.js`:

```javascript
// Al inicio del archivo, agregar:
const {
  MODELO_SPECS_TO_REMOVE,
  IRRELEVANT_VERSION_TOKENS,
  PROTECTED_HYPHEN_TOKENS,
  cleanModeloAndEnhanceVersion,
  cleanVersionTokens
} = require('../UNIVERSAL_NORMALIZATION_DICTIONARIES');
```

### Paso 2: Modificar normalizeModelo()

**ANTES:**
```javascript
function normalizeModelo(marca, modelo) {
  if (!modelo) return modelo;

  let normalized = modelo.toUpperCase().trim();

  // Remover prefijo NUEVO/NUEVA
  normalized = normalized.replace(/^(NUEVO|NUEVA|NEW)\s+/gi, "");

  // ... más lógica específica

  return normalized;
}
```

**DESPUÉS:**
```javascript
function normalizeModelo(marca, modelo) {
  if (!modelo) return modelo;

  let normalized = modelo.toUpperCase().trim();

  // 1. Remover prefijo NUEVO/NUEVA
  normalized = normalized.replace(/^(NUEVO|NUEVA|NEW)\s+/gi, "");

  // 2. Remover specs universales (VAN, RS, GT, PICK UP, etc.)
  MODELO_SPECS_TO_REMOVE.forEach(spec => {
    const specPattern = new RegExp(`\\b${spec.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'gi');
    normalized = normalized.replace(specPattern, ' ');
  });

  // 3. Remover contenido entre paréntesis
  normalized = normalized.replace(/\([^)]+\)/g, ' ');

  // ... resto de lógica específica de la aseguradora

  // 4. Limpiar espacios múltiples
  normalized = normalized.replace(/\s+/g, ' ').trim();

  return normalized;
}
```

### Paso 3: Modificar cleanVersion()

**ANTES:**
```javascript
function cleanVersion(marca, modelo, version) {
  if (!version) return "";

  let cleaned = version.toUpperCase();

  // Proteger tokens con guión
  PROTECTED_HYPHEN_TOKENS.forEach(({ regex, placeholder }) => {
    cleaned = cleaned.replace(regex, placeholder);
  });

  // Remover diccionario local
  [INSURER]_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach(token => {
    const pattern = new RegExp(`\\b${token}\\b`, 'gi');
    cleaned = cleaned.replace(pattern, ' ');
  });

  // ... más lógica

  return cleaned;
}
```

**DESPUÉS:**
```javascript
function cleanVersion(marca, modelo, version) {
  if (!version) return "";

  let cleaned = version.toUpperCase();

  // 1. Proteger tokens con guión (usar universal)
  PROTECTED_HYPHEN_TOKENS.forEach(({ regex, placeholder }) => {
    cleaned = cleaned.replace(regex, placeholder);
  });

  // 2. Remover diccionario UNIVERSAL (reemplaza diccionario local)
  IRRELEVANT_VERSION_TOKENS.forEach(token => {
    const pattern = new RegExp(`\\b${token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'gi');
    cleaned = cleaned.replace(pattern, ' ');
  });

  // 3. Remover body types
  cleaned = cleaned.replace(/\\b(SEDAN|SUV|COUPE|HATCHBACK|PICKUP|VAN|WAGON|CONVERTIBLE)\\b/gi, ' ');

  // 4. Restaurar tokens protegidos
  PROTECTED_HYPHEN_TOKENS.forEach(({ placeholder, canonical }) => {
    cleaned = cleaned.replace(new RegExp(placeholder, 'g'), canonical);
  });

  // ... resto de lógica específica

  // 5. Limpiar espacios múltiples
  cleaned = cleaned.replace(/\\s+/g, ' ').trim();

  return cleaned;
}
```

### Paso 4: Modificar Procesamiento Principal

**IMPORTANTE:** Mover specs de modelo a version **ANTES** de normalizar

```javascript
// En la función principal de procesamiento

for (let item of items) {
  // ✅ NUEVO: Limpiar modelo y mover specs a version PRIMERO
  const { modelo: cleanedModelo, version: enhancedVersion } =
    cleanModeloAndEnhanceVersion(item.marca, item.modelo, item.version_original);

  // Ahora usar los valores limpios/mejorados
  const normalizedModelo = normalizeModelo(item.marca, cleanedModelo);
  const cleanedVersion = cleanVersion(item.marca, normalizedModelo, enhancedVersion);

  // ... resto del procesamiento
}
```

---

## Validación

### Test Cases

Crear archivo `test-normalization.js` en cada aseguradora:

```javascript
const test_cases = [
  {
    input: {
      marca: "VOLKSWAGEN",
      modelo: "GOLF GTI",
      version: "R-LINE SEDAN TIPTRONIC AA EE CD BA QC VP 148HP ABS 1.4L 4CIL 4P 5OCUP"
    },
    expected: {
      modelo: "GOLF",  // GTI removido y movido a version
      version: "GTI R-LINE 148HP 1.4L 4CIL 4PUERTAS 5OCUP"  // Limpio de AA EE CD BA QC VP ABS
    }
  },
  {
    input: {
      marca: "HONDA",
      modelo: "CR-V",
      version: "TOURING SUV AUT AA EE CD BA QC VP SIS.NAV. 190HP ABS 1.5L 4CIL 5P 5OCUP"
    },
    expected: {
      modelo: "CR-V",
      version: "TOURING 190HP 1.5L 4CIL 5PUERTAS 5OCUP"  // Limpio de SUV AUT AA EE CD BA QC VP SIS.NAV. ABS
    }
  },
  {
    input: {
      marca: "MAZDA",
      modelo: "CX-5 CROSS",
      version: "I GRAND TOURING VP QC AUTOMATICA 5PTAS PAQ.NAVEG RIN 19"
    },
    expected: {
      modelo: "CX-5",  // CROSS removido
      version: "CROSS I GRAND TOURING 5PUERTAS"  // CROSS movido de modelo, limpio de VP QC AUTOMATICA PAQ.NAVEG RIN 19
    }
  }
];

// Ejecutar tests
test_cases.forEach((test, i) => {
  const { modelo, version } = cleanModeloAndEnhanceVersion(
    test.input.marca,
    test.input.modelo,
    test.input.version
  );

  const normalizedModelo = normalizeModelo(test.input.marca, modelo);
  const cleanedVersion = cleanVersion(test.input.marca, normalizedModelo, version);

  console.log(`Test ${i + 1}:`);
  console.log(`  Modelo: "${normalizedModelo}" ${normalizedModelo === test.expected.modelo ? '✅' : '❌'}`);
  console.log(`  Version: "${cleanedVersion}" ${cleanedVersion === test.expected.version ? '✅' : '❌'}`);
});
```

---

## Aseguradoras a Actualizar

- [ ] zurich-codigo-de-normalizacion.js
- [ ] hdi-codigo-de-normalizacion.js
- [ ] axa-codigo-de-normalizacion.js
- [ ] atlas-codigo-de-normalizacion.js
- [ ] qualitas-codigo-de-normalizacion-n8n.js
- [ ] gnp-codigo-de-normalizacion.js
- [ ] mapfre-codigo-de-normalizacion.js
- [ ] chubb-codigo-de-normalizacion.js
- [ ] bx-codigo-de-normalizacion.js
- [ ] elpotosi-codigo-de-normalizacion.js
- [ ] ana-codigo-de-normalizacion.js

---

## Impacto Esperado

### Mejoras en Matching

**Antes:**
- Modelo: `"GOLF GTI"` vs `"GOLF"` → ❌ No match (diferentes modelos)
- Version: `"R-LINE AA EE CD BA QC VP 148HP 1.4L"` vs `"R-LINE 148HP 1.4L"` → 🟡 Match parcial (ruido reduce score)

**Después:**
- Modelo: `"GOLF"` vs `"GOLF"` → ✅ Match perfecto
- Version: `"GTI R-LINE 148HP 1.4L 4PUERTAS 5OCUP"` vs `"R-LINE 148HP 1.4L 4PUERTAS 5OCUP"` → ✅ Match alto (specs técnicos limpios)

### Métricas Proyectadas

- **Reducción de nulls en AXA:** 82.4% → ~65-70% (mejora de 12-17 puntos)
- **Reducción de nulls en ATLAS:** 77.6% → ~60-65% (mejora de 12-17 puntos)
- **Mejora general de matching:** +10-15% en score promedio de token overlap

---

## Próximos Pasos

1. **Revisar** este documento y aprobar cambios
2. **Actualizar** archivo de ejemplo (Zurich) como referencia
3. **Aplicar** cambios a las 10 aseguradoras restantes
4. **Regenerar** catálogo homologado completo
5. **Validar** con vehículos del cliente
6. **Deploy** a producción

---

**Autor:** Claude Code
**Basado en:** Análisis de 385,390 registros de 11 aseguradoras
