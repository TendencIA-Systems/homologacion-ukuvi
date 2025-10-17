# Análisis y Correcciones - Sistema de Normalización de Aseguradoras

## 📋 Contexto del Proyecto

Este documento identifica issues, correcciones y mejoras para los códigos de normalización de 11 aseguradoras. Cada aseguradora tiene su propio código de normalización en n8n que debe ser corregido para maximizar la tasa de efectividad en la homologación de datos vehiculares.

### Estructura de Archivos

```
/data/origin/
├── ana-origin.csv
├── mapfre-origin.csv
├── zurich-origin.csv
├── elpotosi-origin.csv
├── qualitas-origin.csv
├── chubb-origin.csv
├── atlas-origin.csv
├── axa-origin.csv
├── bx-origin.csv
├── hdi-origin.csv
└── gnp-origin.csv

/src/insurers/
├── ana/
│   └── ana-codigo-de-normalizacion.js
├── mapfre/
│   └── mapfre-codigo-de-normalizacion.js
├── zurich/
│   └── zurich-codigo-de-normalizacion.js
├── elpotosi/
│   └── elpotosi-codigo-de-normalizacion.js
├── qualitas/
│   └── qualitas-codigo-de-normalizacion.js
├── chubb/
│   └── chubb-codigo-de-normalizacion.js
├── atlas/
│   └── atlas-codigo-de-normalizacion.js
├── axa/
│   └── axa-codigo-de-normalizacion.js
├── bx/
│   └── bx-codigo-de-normalizacion.js
├── hdi/
│   └── hdi-codigo-de-normalizacion.js
└── gnp/
    └── gnp-codigo-de-normalizacion.js
```

---

## 🔴 ISSUES CRÍTICOS GLOBALES

### 1. **Espacios Incorrectos en Tokens Protegidos** 🚨

**Problema:**
Los tokens protegidos están generando espacios donde no deberían existir, especialmente en trims con letras y números.

**Ejemplo:**

- **Original:** `T5 INSPIRATION GEARTRONIC`
- **Actual (incorrecto):** `__MAPFRE_PROTECTED_T 5__ INSPIRATION`
- **Esperado:** `__MAPFRE_PROTECTED_T5__ INSPIRATION` → `T5 INSPIRATION`

**Causa raíz:**
El código está aplicando transformaciones que separan números de letras ANTES de proteger los tokens:

```javascript
cleaned = cleaned.replace(/(\d)([A-Z])/g, "$1 $2"); // Separa dígito + letra
cleaned = cleaned.replace(/([A-Z])(\d)/g, "$1 $2"); // Separa letra + dígito
```

**Afecta a:**

- MAPFRE ✅ (confirmado)
- Potencialmente: ANA, ZURICH, QUALITAS, HDI, BX, ATLAS, AXA, GNP, CHUBB, EL POTOSI

**Solución:**

1. Aplicar `applyProtectedTokens()` ANTES de cualquier transformación que separe caracteres
2. Asegurar que los tokens protegidos incluyan el formato completo (T5, T6, T7, T8, T9, etc.)
3. Restaurar tokens DESPUÉS de todas las transformaciones

---

### 2. **Agregación Incorrecta de "L" (Litros)** 🚨

**Problema:**
Se está agregando "L" a números que no son cilindradas, creando datos incorrectos.

**Ejemplos de ANA:**

- `9.150L` (debería ser `9.150` sin L - es tonelaje o peso)
- `15.190L` (debería ser `15.190` sin L)
- `17.230L` (debería ser `17.230` sin L)

**Causa raíz:**
La función `normalizeStandaloneLiters()` es demasiado agresiva y no valida el contexto:

```javascript
return versionString.replace(/\b(\d+\.\d+)(?!L\b)(?!\d)(?![A-Z])/g, (match) => {
  const liters = parseFloat(match);
  if (!Number.isFinite(liters) || liters <= 0 || liters > 10) return match;
  return `${match}L`;
});
```

**Problema:** El rango `> 10` no captura casos como 15.190, 17.230, etc.

**Solución:**

1. Cambiar el rango máximo de litros de `10` a `8.0` (motores reales no pasan de 8L típicamente)
2. Agregar validación de contexto para detectar si el número está asociado con:
   - TON/TONELADAS (peso)
   - KG/KILOGRAMOS (peso)
   - PUERTAS (número de puertas)
   - Números de serie o identificadores
3. Solo aplicar "L" si:
   - El número está entre 0.5 y 8.0
   - No está precedido por TON, KG, o contexto de peso
   - No está seguido por PUERTAS, OCUP, CIL

---

### 3. **Extracción Errónea de Puertas** 🚨

**Problema:**
Se están extrayendo números de puertas de contextos incorrectos.

**Ejemplos de ANA:**

```
Original: CHASIS CABINA ESTAND 17PUERTAS
Extraído: 17PUERTAS (INCORRECTO - un vehículo no tiene 17 puertas)

Original: 17.230 RWD MAN D0834 CAB OV
Versión: 17.230 4X2 MAN D0834 CAB OV (el 4 no son puertas)
```

**Causa raíz:**
El regex de extracción no valida rangos razonables:

```javascript
const doorsMatch = versionOriginal.match(
  /\b(\d)\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/
);
```

Solo captura 1 dígito, pero no valida que sea 2, 3, 4, 5, o 7.

**Solución:**

1. Validar que el número de puertas esté en el rango válido: [2, 3, 4, 5, 7]
2. Ignorar extracciones fuera de este rango
3. Mejorar el regex para ser más restrictivo:

```javascript
const doorsMatch = versionOriginal.match(
  /\b([2-5]|7)\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/i
);
```

---

## 🔍 ANÁLISIS POR ASEGURADORA

### **ANA** 🔴

**Issues identificados:**

1. ✅ Agregación incorrecta de "L" a números grandes (9.150L, 15.190L, 17.230L)
2. ✅ Extracción errónea de puertas de contextos numéricos
3. ⚠️ Probable: Espacios incorrectos en trims protegidos

**Correcciones necesarias:**

- Ajustar `normalizeStandaloneLiters()` con rango máximo de 8.0L
- Validar contexto de números antes de agregar "L"
- Validar rango de puertas [2,3,4,5,7]
- Verificar que tokens protegidos se apliquen ANTES de separar caracteres

**Archivos a revisar:**

- `/data/origin/ana-origin.csv` - Analizar estructura de datos original
- `/src/insurers/ana/ana-codigo-de-normalizacion.js` - Aplicar correcciones

---

### **MAPFRE** 🟡

**Issues identificados:**

1. ✅ Espacios incorrectos en tokens protegidos (T5 → T 5)
2. ✅ Código actualizado a v2.4 pero aún tiene el issue de espacios

**Correcciones ya aplicadas en v2.4:**

- ✅ Brand aliases (CHRYSLER-DODGE, BMW BW, CHEVROLET GM)
- ✅ Mercedes Benz modelo+número (C + 200 → C-200)
- ✅ Protección de T5, T6, T7, T8, T9
- ✅ Agregado AM, FM, RIN a tokens irrelevantes
- ✅ GEARTR → AUTO
- ✅ PLAZAS, PASAJEROS → OCUPANTES

**Correcciones pendientes:**

- ⚠️ Aplicar `applyProtectedTokens()` ANTES de las líneas que separan caracteres:
  ```javascript
  // ESTO DEBE HACERSE DESPUÉS DE PROTEGER:
  cleaned = cleaned.replace(/(\d)([A-Z])/g, "$1 $2");
  cleaned = cleaned.replace(/([A-Z])(\d)/g, "$1 $2");
  ```

**Orden correcto:**

```javascript
// 1. Proteger tokens PRIMERO
cleaned = applyProtectedTokens(cleaned);

// 2. Luego hacer otras transformaciones
cleaned = cleaned.replace(/[,/]/g, " ");
cleaned = cleaned.replace(/-/g, " ");

// 3. NO separar dígitos de letras si no es necesario
// O hacerlo de forma más inteligente

// 4. Al final restaurar
cleaned = restoreProtectedTokens(cleaned);
```

---

### **ZURICH** 🟢

**Correcciones ya aplicadas:**

- ✅ MINI → BMW
- ✅ Mazda - eliminar MAZDA del modelo
- ✅ VW VAN - eliminar (DERBY)
- ✅ VW - eliminar PASAJEROS
- ✅ ISUZU ELF - crear espacio (ELF200 → ELF 200)
- ✅ Ford - normalizar (F-150 → F150)
- ✅ Separar AUT pegado

**Issues potenciales:**

- ⚠️ Verificar si tiene el mismo problema de espacios en tokens protegidos
- ⚠️ Validar extracción de litros y puertas

---

### **EL POTOSI** 🟢

**Correcciones ya aplicadas:**

- ✅ MINI → BMW
- ✅ Volvo - eliminar espacios (XC 60 → XC60)
- ✅ Mazda - eliminar MAZDA
- ✅ Jaguar - eliminar JAGUAR
- ✅ Mercedes Benz - eliminar MERCEDES
- ✅ Separar AUT pegado
- ✅ NUEVO/NEW - eliminar
- ✅ PASAJEROS - eliminar

**Issues potenciales:**

- ⚠️ Verificar espacios en tokens protegidos
- ⚠️ Validar extracción de litros y puertas

---

### **QUALITAS** ⚪ (Pendiente de análisis)

### **CHUBB** ⚪ (Pendiente de análisis)

### **ATLAS** ⚪ (Pendiente de análisis)

### **AXA** ⚪ (Pendiente de análisis)

### **BX** ⚪ (Pendiente de análisis)

### **HDI** ⚪ (Pendiente de análisis)

### **GNP** ⚪ (Pendiente de análisis)

---

## 🛠️ CORRECCIONES TÉCNICAS DETALLADAS

### Corrección 1: Orden de Protección de Tokens

**Problema:**

```javascript
// MAL - Proteger después de separar
cleaned = cleaned.replace(/(\d)([A-Z])/g, "$1 $2"); // T5 → T 5
cleaned = applyProtectedTokens(cleaned); // __PROTECTED_T 5__
```

**Solución:**

```javascript
// BIEN - Proteger antes de separar
cleaned = applyProtectedTokens(cleaned); // T5 → __PROTECTED_T5__
cleaned = cleaned.replace(/(\d)([A-Z])/g, "$1 $2"); // No afecta a protegidos
```

**Aplicar a:** Todas las aseguradoras

---

### Corrección 2: Validación de Litros

**Código actual (problemático):**

```javascript
function normalizeStandaloneLiters(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString.replace(
    /\b(\d+\.\d+)(?!L\b)(?!\d)(?![A-Z])/g,
    (match) => {
      const liters = parseFloat(match);
      if (!Number.isFinite(liters) || liters <= 0 || liters > 10) return match;
      return `${match}L`;
    }
  );
}
```

**Código corregido:**

```javascript
function normalizeStandaloneLiters(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";

  return versionString.replace(
    /\b(\d+\.\d+)(?!\s*(?:L\b|TON|KG|PUERTAS|OCUP|CIL))/gi,
    (match, p1, offset, string) => {
      const liters = parseFloat(match);

      // Validar rango razonable para motores (0.5L - 8.0L)
      if (!Number.isFinite(liters) || liters < 0.5 || liters > 8.0) {
        return match;
      }

      // Validar contexto previo - no agregar L si hay palabras de peso/puertas
      const before = string
        .substring(Math.max(0, offset - 20), offset)
        .toUpperCase();
      if (/TON|TONELADAS|KG|KILOGRAMOS|PESO|CAB|CHASIS/i.test(before)) {
        return match;
      }

      // Validar contexto posterior
      const after = string
        .substring(offset + match.length, offset + match.length + 20)
        .toUpperCase();
      if (/PUERTAS|OCUP|TON|KG/i.test(after)) {
        return match;
      }

      return `${match}L`;
    }
  );
}
```

**Aplicar a:** Todas las aseguradoras

---

### Corrección 3: Validación de Puertas

**Código actual (problemático):**

```javascript
const doorsMatch = versionOriginal.match(
  /\b(\d)\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/i
);
```

**Código corregido:**

```javascript
function extractDoorsAndOccupants(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") {
    return { doors: "", occupants: "" };
  }

  const normalized = versionOriginal
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/[,/]/g, " ");

  // Mejorado: Solo capturar 2, 3, 4, 5, o 7 puertas (valores válidos)
  const doorsMatch = normalized.match(
    /\b([2-5]|7)\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/i
  );

  // Validar que el número capturado es razonable
  let doors = "";
  if (doorsMatch) {
    const doorCount = parseInt(doorsMatch[1], 10);
    // Solo aceptar 2, 3, 4, 5, o 7 puertas
    if ([2, 3, 4, 5, 7].includes(doorCount)) {
      doors = `${doorCount}PUERTAS`;
    }
  }

  // Ocupantes sin cambios (ya incluye PLAZAS, PASAJEROS, etc.)
  const occMatch = normalized.match(
    /\b0?(\d+)\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX|PASAJ(?:ERO)?S?|PAS|PLAZAS?)\b/
  );

  const occupants =
    occMatch && !Number.isNaN(parseInt(occMatch[1], 10))
      ? `${parseInt(occMatch[1], 10)}OCUP`
      : "";

  return { doors, occupants };
}
```

**Aplicar a:** Todas las aseguradoras

---

## 📊 METODOLOGÍA DE ANÁLISIS

Para analizar cada aseguradora de forma sistemática:

1. **Cargar datos de origen:**

   ```bash
   head -50 /data/origin/{aseguradora}-origin.csv
   ```

2. **Identificar patrones:**

   - ¿Cómo vienen los datos de modelo?
   - ¿Cómo vienen los datos de versión?
   - ¿Qué campos están contaminados?
   - ¿Hay patrones únicos de esta aseguradora?

3. **Verificar código de normalización:**

   ```bash
   cat /src/insurers/{aseguradora}/{aseguradora}-codigo-de-normalizacion.js
   ```

4. **Buscar issues específicos:**

   - ¿Aplica `applyProtectedTokens()` antes de separar caracteres?
   - ¿Tiene validación de litros mejorada?
   - ¿Tiene validación de puertas mejorada?
   - ¿Tiene brand aliases correctos?
   - ¿Tiene modelo base extraction?

5. **Comparar con datos homologados:**
   - Ver si hay L incorrectos
   - Ver si hay puertas incorrectas
   - Ver si hay espacios en trims
   - Ver si hay modelos contaminados

---

## 🎯 PLAN DE ACCIÓN

### Fase 1: Correcciones Críticas (Todas las Aseguradoras)

1. ✅ Reordenar protección de tokens ANTES de separar caracteres
2. ✅ Implementar validación mejorada de litros (rango 0.5-8.0L)
3. ✅ Implementar validación mejorada de puertas ([2,3,4,5,7])

### Fase 2: Análisis Individual (Por Aseguradora)

Para cada una de las 11 aseguradoras:

1. Analizar datos de origen
2. Identificar patterns únicos
3. Aplicar correcciones específicas
4. Validar resultados

### Fase 3: Validación y Testing

1. Ejecutar normalización en todas las aseguradoras
2. Comparar resultados antes/después
3. Validar homologación
4. Ajustar según sea necesario

---

## 📝 CHECKLIST DE CORRECCIONES

### Todas las Aseguradoras:

- [ ] ANA
  - [ ] Orden de protección de tokens
  - [ ] Validación de litros (0.5-8.0L)
  - [ ] Validación de puertas ([2,3,4,5,7])
  - [ ] Análisis de datos origen
- [ ] MAPFRE
  - [ ] Orden de protección de tokens ⚠️ CRÍTICO
  - [ ] Validación de litros (0.5-8.0L)
  - [ ] Validación de puertas ([2,3,4,5,7])
- [ ] ZURICH
  - [ ] Orden de protección de tokens
  - [ ] Validación de litros (0.5-8.0L)
  - [ ] Validación de puertas ([2,3,4,5,7])
- [ ] EL POTOSI
  - [ ] Orden de protección de tokens
  - [ ] Validación de litros (0.5-8.0L)
  - [ ] Validación de puertas ([2,3,4,5,7])
- [ ] QUALITAS
  - [ ] Análisis completo de datos origen
  - [ ] Todas las correcciones críticas
- [ ] CHUBB
  - [ ] Análisis completo de datos origen
  - [ ] Todas las correcciones críticas
- [ ] ATLAS
  - [ ] Análisis completo de datos origen
  - [ ] Todas las correcciones críticas
- [ ] AXA
  - [ ] Análisis completo de datos origen
  - [ ] Todas las correcciones críticas
- [ ] BX
  - [ ] Análisis completo de datos origen
  - [ ] Todas las correcciones críticas
- [ ] HDI
  - [ ] Análisis completo de datos origen
  - [ ] Todas las correcciones críticas
- [ ] GNP
  - [ ] Análisis completo de datos origen
  - [ ] Todas las correcciones críticas

---

## 🤖 PROMPT PARA AGENTE

Eres un agente especializado en normalización de datos vehiculares para un sistema ETL de 11 aseguradoras mexicanas. Tu tarea es aplicar correcciones críticas a los códigos de normalización JavaScript que se ejecutan en n8n.

### Contexto del Proyecto

Cada aseguradora proporciona datos vehiculares en formatos diferentes. Tenemos códigos de normalización hechos a mano para cada una que transforman estos datos a un formato estándar, pero se han identificado issues críticos que afectan la tasa de homologación.

### Ubicación de Archivos

**Datos de origen (CSV):**

```
/data/origin/{aseguradora}-origin.csv
```

Aseguradoras: ana, mapfre, zurich, elpotosi, qualitas, chubb, atlas, axa, bx, hdi, gnp

**Códigos de normalización (JavaScript para n8n):**

```
/src/insurers/{aseguradora}/{aseguradora}-codigo-de-normalizacion.js
```

### Issues Críticos Identificados

#### 1. Espacios Incorrectos en Tokens Protegidos

**Ejemplo:** `T5 INSPIRATION` se convierte en `T 5 INSPIRATION`
**Causa:** `applyProtectedTokens()` se llama DESPUÉS de separar dígitos y letras
**Solución:** Llamar `applyProtectedTokens()` ANTES de cualquier transformación

#### 2. Agregación Incorrecta de "L" (Litros)

**Ejemplo:** `17.230` se convierte en `17.230L` (es peso, no cilindrada)
**Causa:** Rango de validación demasiado amplio (> 10L)
**Solución:** Limitar a 0.5-8.0L y validar contexto (TON, KG, PUERTAS)

#### 3. Extracción Errónea de Puertas

**Ejemplo:** Extrae `17PUERTAS` de contextos numéricos incorrectos
**Causa:** No valida rango razonable [2, 3, 4, 5, 7]
**Solución:** Regex más restrictivo que solo capture valores válidos

### Tu Tarea

Para cada aseguradora:

1. **Analizar datos de origen:**

   - Ejecuta: `head -50 /data/origin/{aseguradora}-origin.csv`
   - Identifica estructura de datos
   - Documenta patrones únicos

2. **Cargar código de normalización:**

   - Lee: `/src/insurers/{aseguradora}/{aseguradora}-codigo-de-normalizacion.js`
   - Busca las funciones críticas

3. **Aplicar correcciones críticas:**

   - **Corrección 1:** Mover `applyProtectedTokens()` ANTES de separar caracteres
   - **Corrección 2:** Actualizar `normalizeStandaloneLiters()` con rango 0.5-8.0L
   - **Corrección 3:** Actualizar `extractDoorsAndOccupants()` con validación [2,3,4,5,7]

4. **Guardar código corregido:**
   - Crear backup del original
   - Guardar versión corregida
   - Documentar cambios realizados

### Código de Referencia

**Corrección 1: Orden de Protección**

```javascript
// ANTES (MAL):
cleaned = cleaned.replace(/(\d)([A-Z])/g, "$1 $2");
cleaned = applyProtectedTokens(cleaned);

// DESPUÉS (BIEN):
cleaned = applyProtectedTokens(cleaned);
cleaned = cleaned.replace(/(\d)([A-Z])/g, "$1 $2");
```

**Corrección 2: Validación de Litros**

```javascript
function normalizeStandaloneLiters(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";

  return versionString.replace(
    /\b(\d+\.\d+)(?!\s*(?:L\b|TON|KG|PUERTAS|OCUP|CIL))/gi,
    (match, p1, offset, string) => {
      const liters = parseFloat(match);

      // CRÍTICO: Rango 0.5-8.0L para motores reales
      if (!Number.isFinite(liters) || liters < 0.5 || liters > 8.0) {
        return match;
      }

      // Validar contexto
      const before = string
        .substring(Math.max(0, offset - 20), offset)
        .toUpperCase();
      if (/TON|TONELADAS|KG|KILOGRAMOS|PESO|CAB|CHASIS/i.test(before)) {
        return match;
      }

      return `${match}L`;
    }
  );
}
```

**Corrección 3: Validación de Puertas**

```javascript
// Solo capturar 2, 3, 4, 5, o 7 puertas
const doorsMatch = normalized.match(
  /\b([2-5]|7)\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/i
);

if (doorsMatch) {
  const doorCount = parseInt(doorsMatch[1], 10);
  if ([2, 3, 4, 5, 7].includes(doorCount)) {
    doors = `${doorCount}PUERTAS`;
  }
}
```

### Orden de Prioridad

1. **CRÍTICO:** MAPFRE (espacios en T5, T6, etc.)
2. **CRÍTICO:** ANA (L incorrectos, puertas incorrectas)
3. **ALTO:** ZURICH, EL POTOSI (verificar mismos issues)
4. **MEDIO:** Resto de aseguradoras

### Formato de Reporte

Para cada aseguradora, proporciona:

```markdown
## {ASEGURADORA}

### Análisis de Datos Origen

- Estructura identificada: ...
- Patrones únicos: ...
- Issues específicos: ...

### Correcciones Aplicadas

- [x] Corrección 1: Orden de protección de tokens
- [x] Corrección 2: Validación de litros
- [x] Corrección 3: Validación de puertas
- [x] Correcciones específicas: ...

### Código Modificado

Archivo: /src/insurers/{aseguradora}/{aseguradora}-codigo-de-normalizacion-CORREGIDO.js
Cambios: {descripción detallada}

### Resultados Esperados

- Reducción de L incorrectos: {porcentaje}
- Mejora en extracción de puertas: {porcentaje}
- Trims protegidos correctamente: {sí/no}
```

### Notas Importantes

- **SIEMPRE** documenta cada cambio realizado
- **SIEMPRE** valida que el código siga funcionando en n8n
- **NUNCA** elimines funcionalidad existente que funcione correctamente
- Si encuentras otros issues, documéntalos pero no los corrijas sin confirmación
