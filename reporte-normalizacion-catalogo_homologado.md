# Reporte de recomendaciones de normalización — catalogo_homologado (Ukuvi)

Fecha: 2025-09-28
Proyecto Supabase: "Ukuvi" (id: zsyapaddgdrnqfdxxzjw)
Tabla analizada: public.catalogo_homologado (242,656 filas)

---

## 1) Resumen ejecutivo

Se identificaron oportunidades adicionales de normalización, más allá de las ya documentadas, principalmente en:
- Marca en el modelo (no sólo Mazda): múltiples marcas con el modelo iniciando con la marca.
- Variantes de marca a consolidar: "LAND ROVER" vs "LANDROVER".
- Transmisión contaminada: valores de `transmision` que incluyen trims/paquetes o specs que deberían migrar a `version`.

Se confirmó además que varias anomalías previamente señaladas ya no aparecen en este catálogo homologado: rines (R16/RIN 16/ARO 16), "0TON", puertas inválidas (p.ej. 320PUERTAS), tokens de carrocería en `modelo` o `version` (SEDAN/HATCHBACK/…), trims compuestos sin guion y drift por `hash_comercial`.

---

## 2) Hallazgos detallados

### 2.1 Marca en el modelo (limpieza generalizada)
Consulta aplicada detectó registros donde `modelo` inicia con `marca` (ignorando espacios). Principales casos:
- MAZDA: 2,042
- MINI: 1,604
- PEUGEOT: 722
- PORSCHE: 586
- VOLKSWAGEN: 245
- CADILLAC: 242
- BMW: 223
- MERCEDES BENZ: 153 (ver también sección 2.4)
- MG: 145 · NISSAN: 105 · JAC: 92 · SUBARU: 90 · JAGUAR: 68 · SAAB: 57 · LINCOLN: 51 · LEXUS: 48 · SMART: 34 · ALFA ROMEO: 34 · HYUNDAI: 33 · LAND ROVER: 30 · HUMMER: 27 · ROVER: 22 …

Recomendación:
- Aplicar regla genérica: si `modelo` comienza con `marca` (comparación sin espacios/guiones y case-insensitive), remover el prefijo.
- Casos prioritarios por volumen: MAZDA, MINI, PEUGEOT, PORSCHE, VOLKSWAGEN, CADILLAC, BMW, MERCEDES BENZ.

### 2.2 Variantes de marca a consolidar
Se identificó una familia con variantes:
- LAND ROVER vs LANDROVER → total combinado: 3,591 filas.

Recomendación:
- Consolidar ambas a "LAND ROVER" (preferida). Evaluar si "ROVER" debería mapearse a "LAND ROVER" (requiere validación de negocio).

### 2.3 Transmisión con valores de versión/trim incrustados
`transmision` contiene mezclas de transmisión real con trims/paquetes o specs. Ejemplos representativos y conteos:
- "GLI DSG" (20), "COMFORTLSLINE DSG" (16), "LATITUDE" (15), "CX LEATHEREE" (10), "S GT AT SD/HB" (9), "INSPIRATION" (9), "DSG 1.4 RIN 16 TURBO" (8), "GLX BOOSTERJET 6AT" (8), "STYLE 1.4TSI DSG" (7), "PEPPER AT" (7), "SALT AT" (7), "CHILI AT" (7), "TDI DSG 4PTAS" (7), etc.

Recomendación:
- Normalizar `transmision` sólo a {AUTO, MANUAL}.
- Mapear alias a tipo base (ej.: AT/Tiptronic/Steptronic/CVT/DSG/DCT/E‑CVT → AUTO; MT/STD/MAN → MANUAL).
- Mover tokens de trim/paquete (p.ej. S‑LINE, R‑LINE, HOT CHILI/PEPPER/SALT, INSPIRATION, LATITUDE) y specs (RIN 16, 4PTAS, TURBO) a `version` (u otros campos específicos si existen).

### 2.4 MERCEDES: prefijo redundante en modelo
- Se detectaron 674 filas con `modelo` que inicia con "MERCEDES ", bajo marca "MERCEDES BENZ" (p.ej., "MERCEDES CLASE E").

Recomendación:
- Remover prefijo "MERCEDES " del campo `modelo` cuando `marca` = "MERCEDES BENZ".

### 2.5 MINI como marca independiente
- 1,604 filas con `marca` = "MINI" y `modelo` que inicia con "MINI ".

Recomendación:
- Si `marca` = "MINI", eliminar el prefijo "MINI " del `modelo` y estandarizar nombres de modelo (p.ej., "COOPER", "COUNTRYMAN", "CLUBMAN").

---

## 3) Confirmaciones de limpieza (no detectadas en este catálogo)
- Puertas anómalas ("320PUERTAS"/"335PUERTAS" o fuera de 2–5): 0 casos.
- Rines/aros (R16/RIN 16/ARO 16): 0 casos en `version`.
- "0TON"/"TON" en `version`: 0 casos.
- Trims compuestos sin guion ("SPORT LINE", "S LINE", "R LINE", "F SPORT", "AMG LINE", etc.): 0 casos.
- Tokens de carrocería en `modelo`/`version` (HATCHBACK/SEDAN/COUPE/…): 0 casos.
- Inconsistencia por `hash_comercial` (múltiples marcas/modelos/transmisiones en un mismo hash): 0 casos.
- Minúsculas/espacios sobrantes en `marca`/`modelo`/`version`: no detectados.

---

## 4) Reglas de normalización propuestas (ETL)

1) Regla genérica marca→modelo
- Si `normalize(marca)` es prefijo de `normalize(modelo)`, entonces `modelo := modelo` sin ese prefijo.
- `normalize(x)`: quitar espacios/guiones, pasar a upper.

2) Consolidación de marcas
- Mapear `LANDROVER` → `LAND ROVER`. Revisar si `ROVER` debe integrarse (validación de negocio requerida).

3) Transmisión
- Derivar `transmision_base ∈ {AUTO, MANUAL}` a partir de alias: {AT, AUT, ATX, CVT, DSG, DCT, E‑CVT, TIPTRONIC, STEPTRONIC → AUTO} · {MT, MAN, STD → MANUAL}.
- Remover tokens residuales (trims/paquetes/specs) del campo `transmision` y moverlos a `version`.

4) Casos específicos
- MERCEDES BENZ: eliminar prefijo "MERCEDES " en `modelo`.
- MINI: eliminar prefijo "MINI " en `modelo` al tener `marca` = "MINI".

---

## 5) Consultas SQL reproducibles

A) Variantes de marca (familias por normalización):
```sql
WITH counts AS (
  SELECT marca, COUNT(*) AS cnt,
         REGEXP_REPLACE(UPPER(marca), '[^A-Z0-9]', '', 'g') AS base
  FROM public.catalogo_homologado
  GROUP BY marca
),
 grouped AS (
  SELECT base,
         ARRAY_AGG(DISTINCT marca ORDER BY marca) AS variants,
         SUM(cnt) AS total,
         COUNT(DISTINCT marca) AS variant_count
  FROM counts
  GROUP BY base
)
SELECT base, variants, total, variant_count
FROM grouped
WHERE variant_count > 1
ORDER BY variant_count DESC, total DESC
LIMIT 200;
```

B) Marca presente al inicio del modelo:
```sql
SELECT marca, COUNT(*) AS casos
FROM public.catalogo_homologado
WHERE UPPER(REGEXP_REPLACE(modelo, '\s+', '', 'g'))
      LIKE UPPER(REGEXP_REPLACE(marca, '\s+', '', 'g')) || '%'
GROUP BY marca
ORDER BY casos DESC
LIMIT 50;
```

C) Tokens de transmisión no normalizados (mezclados con trims/specs):
```sql
SELECT UPPER(TRIM(transmision)) AS tx, COUNT(*) AS c
FROM public.catalogo_homologado
WHERE transmision IS NOT NULL
GROUP BY tx
HAVING UPPER(TRIM(transmision)) NOT IN ('AUTO', 'MANUAL')
ORDER BY c DESC
LIMIT 100;
```

D) Mercedes con prefijo en modelo:
```sql
SELECT SUM(CASE WHEN marca ~* 'MERCEDES' AND modelo ~* '^MERCEDES\\s' THEN 1 ELSE 0 END) AS modelo_con_prefijo_mercedes
FROM public.catalogo_homologado;
```

E) MINI como marca con modelo duplicando prefijo:
```sql
SELECT SUM(CASE WHEN marca='MINI' AND modelo ~* '^MINI\\s' THEN 1 ELSE 0 END) AS mini_con_prefijo
FROM public.catalogo_homologado;
```

---

## 6) Siguientes pasos sugeridos

1. Implementar regla genérica "marca en modelo" en el pipeline ETL (impacto en miles de filas; priorizar MAZDA, MINI, PEUGEOT, PORSCHE, VOLKSWAGEN, CADILLAC, BMW, MERCEDES).
2. Consolidar LAND ROVER vs LANDROVER; evaluar ROVER.
3. Reescribir la normalización de `transmision` (AUTO/MANUAL + subtipos opcionales) y migrar trims/specs a `version`.
4. Casos específicos: prefijo MERCEDES y MINI en `modelo`.
5. Añadir validaciones: `transmision` ∈ {AUTO, MANUAL}; `modelo` sin prefijos de marca; catálogo de marcas con lista blanca/aliases.

---

## 7) Notas
- Varias anomalías históricas (rines, 0TON, puertas, trims sin guion, AWD/4x4 en modelo/version) no aparecen en este catálogo, lo que sugiere que ya fueron corregidas en el flujo de homologación.
- Recomendado monitorear periódicamente con las consultas anteriores para prevenir regresiones.
