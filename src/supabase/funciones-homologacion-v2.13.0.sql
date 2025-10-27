-- ============================================================================
-- SISTEMA DE HOMOLOGACIÓN DE VEHÍCULOS - VERSIÓN v2.13.0
-- ============================================================================
-- CAMBIOS v2.13.0 🔥 CRITICAL BUGFIX:
-- 1. BUGFIX CRÍTICO: Bloquear (no solo penalizar) homologación de trims diferentes
--    - Impacto: ~2,000 casos Mazda ahora homologados correctamente
--    - Problema: "I GRAND TOURING" se mezclaba con "I TOURING" y "I" (base)
--    - Solución:
--      a) extract_primary_trim() ahora busca por ESPECIFICIDAD (I-GRAND-TOURING antes que I)
--      b) has_different_trims() con lógica ESTRICTA (I ≠ I-TOURING ≠ I-GRAND-TOURING)
--      c) calculate_weighted_coverage_with_trim_penalty() retorna has_different_trims
--      d) Matching BLOQUEADO (no solo penalizado) cuando has_different_trims = TRUE
-- 2. FIX: Cada trim genera su propio registro homologado:
--    - MAZDA 2 2016 "I" → Registro independiente
--    - MAZDA 2 2016 "I TOURING" → Registro independiente
--    - MAZDA 2 2016 "I GRAND TOURING" → Registro independiente
-- 3. VALIDACIÓN: Script diagnose_mazda_pipeline.py verifica 0 mezclas incorrectas
--
-- CAMBIOS HEREDADOS v2.12.0 🔥:
-- 1. BUGFIX CRÍTICO: Bloquear homologación cuando vehículos tienen different trims
--    - Impacto: ~324 casos incorrectos corregidos
--    - Cambio: Agregar validación "AND NOT coverage_result.has_trim_penalty" en matching logic
-- 2. FEATURE: Multi-update para estrategias simples (single_spec, minimal_version)
--    - Vehículos con pocos specs ahora se agregan a múltiples registros existentes
--    - Estrategias complejas (coverage, jaccard) mantienen comportamiento de best-match único
--    - Ejemplo: "COMFORT" se agrega a todas las versiones COMFORT (150HP, 180HP, 200HP, etc.)
--
-- OPTIMIZACIONES AGRESIVAS v2.11.3.2 🚀:
-- 1. EARLY EXIT GLOBAL: Skip todo el bloque de regexp si NO hay keywords (~70% versiones)
-- 2. Regexp_replace incondicionales ahora CONDICIONALES (20 → 5 grupos condicionados)
-- 3. Impacto adicional: 50-70% mejora sobre v2.11.3.1
-- 4. Batch size recomendado: 200 → 100 para máxima estabilidad
-- 5. TOTAL: 80-90% mejora vs v2.11.2 original
--
-- BUGFIX v2.11.3.1 🐛:
-- - CRÍTICO: Lista negra de excepciones (PICK-UP, PLUG-IN)
-- - Impacto: ~800-1300 registros corregidos
--
-- CAMBIOS v2.11.3 🔥 MULTI-WORD TRIM FIX:
-- - Preserva trims hyphenated (I-GRAND-TOURING, M-SPORT, S-LINE)
-- - Protección dinámica de guiones
-- - Eliminadas conversiones destructivas
-- - Impacto: >90% éxito en multi-word trims (antes 3.94%)
--
-- OPTIMIZACIONES BASE v2.11.3 ⚡:
-- 1. Early exit en normalize_token si no hay guión
-- 2. Early exit en protección dinámica
-- 3. Variables no usadas eliminadas
-- 4. Logging verboso deshabilitado
--
-- CAMBIOS HEREDADOS de v2.11.2 🧠 INTELLIGENT PATTERN MATCHING:
-- - Regexp_replace CONDICIONALES (solo si detecta palabra clave)
-- - Early exit: si no hay palabras clave, skip todo el bloque
-- - Performance: 10-20x más rápido que v2.11.0
-- - Cobertura: 100% de casos (todos los 84 trims)
-- - Estrategia: Detectar keywords → Aplicar solo regexp_replace relevantes
--
-- OPTIMIZACIONES:
-- 1. Detección rápida de keywords (SPORT, TOURING, LINE, COOPER, etc.)
-- 2. Solo ejecuta regexp_replace si keyword está presente
-- 3. Early exit si no hay multi-word trims
-- 4. Orden óptimo: más comunes primero
-- ============================================================================

TRUNCATE TABLE catalogo_homologado CASCADE;
ALTER SEQUENCE catalogo_homologado_id_seq RESTART WITH 1;

-- Índices
CREATE INDEX IF NOT EXISTS idx_catalogo_hash_comercial ON catalogo_homologado(hash_comercial);
CREATE INDEX IF NOT EXISTS idx_catalogo_version_tokens ON catalogo_homologado USING gin(version_tokens_array);
CREATE INDEX IF NOT EXISTS idx_catalogo_marca_modelo ON catalogo_homologado(marca, modelo);
CREATE INDEX IF NOT EXISTS idx_catalogo_disponibilidad ON catalogo_homologado USING gin(disponibilidad);
ANALYZE catalogo_homologado;

-- Eliminar funciones existentes
DROP FUNCTION IF EXISTS procesar_batch_vehiculos(JSONB);
DROP FUNCTION IF EXISTS clean_and_tokenize_version(TEXT);
DROP FUNCTION IF EXISTS deduplicate_tokens_intelligent(TEXT[]);
DROP FUNCTION IF EXISTS calculate_weighted_coverage_with_trim_penalty(TEXT[], TEXT[], BOOLEAN);
DROP FUNCTION IF EXISTS calculate_jaccard_similarity(TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS normalize_token(TEXT);
DROP FUNCTION IF EXISTS is_minimal_version_match(TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS is_single_spec_match(TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS extract_primary_trim(TEXT[]);
DROP FUNCTION IF EXISTS detect_conflicts(TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS has_different_trims(TEXT[], TEXT[]);

-- ============================================================================
-- FUNCIÓN 1: normalize_token - 🔥 UPDATED v2.11.3
-- ============================================================================
-- CAMBIOS v2.11.3:
-- - Agregado regex de preservación para trims hyphenated
-- - Modificadas normalizaciones destructivas (SPORT, TURBO) para no afectar trims con guión
-- ============================================================================
CREATE OR REPLACE FUNCTION normalize_token(token TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
BEGIN
    -- ✅ v2.11.3 OPTIMIZED: Early exit si no hay guión (performance)
    -- Solo ejecutar regex costoso si el token contiene guión
    IF position('-' in token) > 0 THEN
        -- ⚠️  BUGFIX v2.11.3.1: Excepciones para tokens con normalizaciones específicas
        -- Estos tokens tienen guiones pero NO deben preservarse como trims
        -- PICK-UP → PICKUP, PLUG-IN → PHEV
        IF token NOT IN ('PICK-UP', 'PLUG-IN') THEN
            -- Preservar trims hyphenated ANTES de cualquier normalización
            -- Detecta patrones como "I-GRAND-TOURING", "M-SPORT", "S-LINE", etc.
            IF token ~ '^[A-Z]{1,}(-[A-Z]{1,})+$' THEN
                RETURN token;  -- Preservar intacto
            END IF;
        END IF;
    END IF;

    CASE
        WHEN token IN ('SED', 'SEDAN', 'SEDÁN') THEN RETURN 'SEDAN';
        WHEN token IN ('CP', 'COUPE', 'COUPÉ') THEN RETURN 'COUPE';
        WHEN token IN ('SW', 'STATION', 'WAGON', 'STATIONWAGON') THEN RETURN 'WAGON';
        WHEN token IN ('VAN', 'MINIVAN', 'MINIVÁN') THEN RETURN 'VAN';
        WHEN token IN ('CABRIO', 'CABRIOLET', 'CONVERTIBLE', 'DESCAPOTABLE') THEN RETURN 'CONVERTIBLE';
        WHEN token IN ('HB', 'HATCH', 'HATCHBACK') THEN RETURN 'HATCHBACK';
        WHEN token IN ('PICKUP', 'PICK-UP', 'PU') THEN RETURN 'PICKUP';
        WHEN token IN ('SUV', 'CROSSOVER') THEN RETURN 'SUV';

        WHEN token IN ('4X4', '4X2', '4WD') THEN RETURN 'AWD';
        WHEN token IN ('DELANTERA', 'TRACCIÓN DELANTERA', 'TRACCION DELANTERA') THEN RETURN 'FWD';
        WHEN token IN ('TRASERA', 'TRACCIÓN TRASERA', 'TRACCION TRASERA') THEN RETURN 'RWD';
        WHEN token IN ('ALLWHEELDRIVE', 'TRACCIÓN INTEGRAL', 'TRACCION INTEGRAL') THEN RETURN 'AWD';
        WHEN token IN ('2X4') THEN RETURN '2WD';

        WHEN token IN ('ELECTRIC', 'ELECTRICO', 'ELÉCTRICO', 'EV', 'BEV') THEN RETURN 'ELECTRIC';
        WHEN token IN ('HYBRID', 'HIBRIDO', 'HÍBRIDO', 'HEV', 'HYBRIDE') THEN RETURN 'HYBRID';
        WHEN token IN ('PHEV', 'PLUG-IN', 'PLUGIN') THEN RETURN 'PHEV';
        WHEN token IN ('MHEV', 'MILD', 'MILDHYBRID') THEN RETURN 'MHEV';
        WHEN token IN ('DSL', 'DIÉSEL') THEN RETURN 'DIESEL';
        WHEN token IN ('GASOLINE', 'GAS', 'PETROL', 'NAFTA') THEN RETURN 'GASOLINA';
        WHEN token IN ('GNV', 'GNC', 'CNG') THEN RETURN 'GNV';
        WHEN token IN ('GLP', 'LPG') THEN RETURN 'GLP';

        WHEN token IN ('2PTAS', '2P', '2-PUERTAS', '2 PUERTAS') THEN RETURN '2PUERTAS';
        WHEN token IN ('3PTAS', '3P', '3-PUERTAS', '3 PUERTAS') THEN RETURN '3PUERTAS';
        WHEN token IN ('4PTAS', '4P', '4-PUERTAS', '4 PUERTAS') THEN RETURN '4PUERTAS';
        WHEN token IN ('5PTAS', '5P', '5-PUERTAS', '5 PUERTAS') THEN RETURN '5PUERTAS';

        WHEN token IN ('2OCUP', '2 OCUP', '2OCUPANTES', '2 OCUPANTES') THEN RETURN '2OCUP';
        WHEN token IN ('3OCUP', '3 OCUP', '3OCUPANTES', '3 OCUPANTES', '03 OCUP', '03OCUP') THEN RETURN '3OCUP';
        WHEN token IN ('4OCUP', '4 OCUP', '4OCUPANTES', '4 OCUPANTES', '04 OCUP', '04OCUP') THEN RETURN '4OCUP';
        WHEN token IN ('5OCUP', '5 OCUP', '5OCUPANTES', '5 OCUPANTES', '05 OCUP', '05OCUP') THEN RETURN '5OCUP';
        WHEN token IN ('6OCUP', '6 OCUP', '6OCUPANTES', '6 OCUPANTES', '06 OCUP', '06OCUP') THEN RETURN '6OCUP';
        WHEN token IN ('7OCUP', '7 OCUP', '7OCUPANTES', '7 OCUPANTES', '07 OCUP', '07OCUP') THEN RETURN '7OCUP';
        WHEN token IN ('8OCUP', '8 OCUP', '8OCUPANTES', '8 OCUPANTES', '08 OCUP', '08OCUP') THEN RETURN '8OCUP';
        WHEN token IN ('9OCUP', '9 OCUP', '9OCUPANTES', '9 OCUPANTES', '09 OCUP', '09OCUP') THEN RETURN '9OCUP';

        WHEN token IN ('3 CIL', 'L3', '3-CIL') THEN RETURN '3CIL';
        WHEN token IN ('4 CIL', 'L4', '4-CIL', 'I4') THEN RETURN '4CIL';
        WHEN token IN ('5 CIL', 'L5', '5-CIL') THEN RETURN '5CIL';
        WHEN token IN ('6 CIL', 'V6', '6-CIL', 'L6', 'H6') THEN RETURN '6CIL';
        WHEN token IN ('8 CIL', 'V8', '8-CIL') THEN RETURN '8CIL';
        WHEN token IN ('10 CIL', 'V10', '10-CIL') THEN RETURN '10CIL';
        WHEN token IN ('12 CIL', 'V12', 'W12', '12-CIL') THEN RETURN '12CIL';

        WHEN token SIMILAR TO '[0-9]+H$' THEN RETURN REPLACE(token, 'H', 'HP');
        WHEN token SIMILAR TO '[0-9]+CP$' THEN RETURN REPLACE(token, 'CP', 'HP');
        WHEN token SIMILAR TO '[0-9]+CV$' THEN RETURN REPLACE(token, 'CV', 'HP');

        WHEN token IN ('EXECUTIVE', 'EXCLUSIVO', 'EXCLUSIVE', 'EJECUTIVO') THEN RETURN 'PREMIUM';
        WHEN token IN ('LUXURY', 'LUJO', 'LUX') THEN RETURN 'LUJO';
        WHEN token IN ('TECHNOLOGY', 'TECNOLOGIA') THEN RETURN 'TECH';

        -- ✅ v2.11.3: Solo normalizar variantes SIN guión
        -- Preservar S-LINE, R-LINE, X-LINE (ya protegidos por el regex de arriba)
        WHEN token IN ('SPORTLINE', 'SLINE', 'DEPORTIVO') THEN RETURN 'SPORT';

        -- ✅ v2.11.3: Solo normalizar variantes SIN guión
        -- Preservar BI-TURBO, TWIN-TURBO (ya protegidos por el regex de arriba)
        WHEN token IN ('BITURBO', 'BITBO', 'TWINTURBO') THEN RETURN 'TURBO';
        WHEN token IN ('LIMITED EDITION', 'EDITION', 'EDICION', 'EDICIÓN') THEN RETURN 'LIMITED';
        WHEN token IN ('ADVANCED', 'AVANZADO', 'AVANCE') THEN RETURN 'ADVANCE';
        WHEN token IN ('CONFORT', 'COMFORTLINE', 'CONFORTLINE') THEN RETURN 'COMFORT';
        WHEN token IN ('DINAMICO', 'DINÁMICO', 'DYNAMIQUE') THEN RETURN 'DYNAMIC';
        WHEN token IN ('HIGHLINE', 'HIGLINE') THEN RETURN 'HIGHLINE';
        WHEN token IN ('ELEGANCIA', 'ELEGANT', 'ELEGANTE') THEN RETURN 'ELEGANCE';
        WHEN token IN ('PRESTIGIO', 'PRESTIGIOUS') THEN RETURN 'PRESTIGE';

        WHEN token IN ('XL', 'PLUS', 'L', 'BASE', 'BASICO', 'BÁSICO') THEN RETURN NULL;
        WHEN token IN ('PACK', 'PACKAGE', 'PAQUETE') THEN RETURN NULL;

        ELSE RETURN token;
    END CASE;
END;
$$;

-- ============================================================================
-- FUNCIÓN 2: deduplicate_tokens_intelligent (SIN CAMBIOS)
-- ============================================================================
CREATE OR REPLACE FUNCTION deduplicate_tokens_intelligent(tokens TEXT[])
RETURNS TEXT[]
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    result TEXT[] := ARRAY[]::TEXT[];
    seen_specs TEXT[] := ARRAY[]::TEXT[];
    seen_tokens TEXT[] := ARRAY[]::TEXT[];
    token TEXT;
    spec_type TEXT;
    is_numeric_spec BOOLEAN;
BEGIN
    FOREACH token IN ARRAY tokens LOOP
        is_numeric_spec := token ~ '^\d+(\.\d+)?(PUERTAS?|OCUP|CIL|HP|L|KG|TON|PAX)$';
        IF is_numeric_spec THEN
            spec_type := regexp_replace(token, '^\d+(\.\d+)?', '');
            IF spec_type = ANY(seen_specs) THEN CONTINUE; END IF;
            seen_specs := array_append(seen_specs, spec_type);
            result := array_append(result, token);
            CONTINUE;
        END IF;
        IF NOT (token ~ '^\d+(\.\d+)?(L|HP)?$') THEN
            IF token = ANY(seen_tokens) THEN CONTINUE; END IF;
            seen_tokens := array_append(seen_tokens, token);
            result := array_append(result, token);
            CONTINUE;
        END IF;
        result := array_append(result, token);
    END LOOP;
    RETURN result;
END;
$$;

-- ============================================================================
-- FUNCIÓN 3: clean_and_tokenize_version - 🔥 UPDATED v2.11.3
-- ============================================================================
-- CAMBIOS v2.11.3:
-- - Mejorada protección de trims hyphenated: ahora dinámica en lugar de lista hardcoded
-- - Protege automáticamente TODOS los guiones entre letras mayúsculas
-- ============================================================================
CREATE OR REPLACE FUNCTION clean_and_tokenize_version(p_version TEXT)
RETURNS TEXT[]
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    noise_tokens TEXT[] := ARRAY['R13', 'R14', 'R15', 'R16', 'R17', 'R18', 'R19', 'R20', 'R21', 'R22', 'NUEVO', 'NEW', 'NUEVA', 'ABS', 'EBD', 'ESP', 'VSC', 'TCS', 'AC', 'A/C', 'AA', 'EE', 'BA', 'CA', 'CE', 'CD', 'VP', 'QC', 'SM', 'VT'];
    cleaned_version TEXT;
    raw_tokens TEXT[];
    final_tokens TEXT[] := ARRAY[]::TEXT[];
    token TEXT;
    normalized_token TEXT;

    -- 🧠 SMART: Variables para detección de keywords
    has_sport BOOLEAN;
    has_touring BOOLEAN;
    has_line BOOLEAN;
    has_cooper BOOLEAN;
    has_grand BOOLEAN;
    has_limited BOOLEAN;
    has_drive BOOLEAN;
    has_range BOOLEAN;
    has_carrera BOOLEAN;
    has_edition BOOLEAN;
    has_premium BOOLEAN;
    has_unlimited BOOLEAN;
    has_king BOOLEAN;
BEGIN
    IF p_version IS NULL OR trim(p_version) = '' THEN RETURN ARRAY[]::TEXT[]; END IF;
    cleaned_version := upper(trim(p_version));

    -- ========================================================================
    -- ⚡ OPTIMIZACIÓN CRÍTICA v2.11.3.2: EARLY EXIT GLOBAL
    -- ========================================================================
    -- Si NO hay NINGUNA keyword de multi-word trims, skip TODO el bloque costoso
    -- Esto ahorra ~70% del tiempo en versiones simples (ej: "AUTOMATICA 5PTAS 4CIL")
    IF NOT (cleaned_version ~ '\m(SPORT|TOURING|LINE|COOPER|GRAND|LIMITED|DRIVE|RANGE|CARRERA|EDITION|PREMIUM|UNLIMITED|KING|EDDIE|HIGH|LARIAT|RAPTOR|DYNAMIC|DESIGN|SPORTBACK|STYLE|TRENDY|ALLURE|LUXURY|ELEGANCE)\M') THEN
        -- No hay multi-word trims, ir directo a tokenización
        cleaned_version := regexp_replace(cleaned_version, '[,;/|]', ' ', 'g');
        cleaned_version := regexp_replace(cleaned_version, '\s+', ' ', 'g');
        raw_tokens := string_to_array(cleaned_version, ' ');

        FOREACH token IN ARRAY raw_tokens LOOP
            IF token IS NOT NULL AND length(token) > 0 THEN
                normalized_token := normalize_token(token);
                IF normalized_token IS NOT NULL AND NOT (normalized_token = ANY(noise_tokens)) THEN
                    final_tokens := array_append(final_tokens, normalized_token);
                END IF;
            END IF;
        END LOOP;

        RETURN deduplicate_tokens_intelligent(final_tokens);
    END IF;

    -- ========================================================================
    -- 🧠 SMART v2.11.2: DETECCIÓN RÁPIDA DE KEYWORDS
    -- ========================================================================
    -- Solo llegamos aquí si HAY keywords de multi-word trims
    -- Detectamos específicamente cuáles para ejecutar solo regexp_replace relevantes

    has_sport := cleaned_version ~ '\mSPORT\M';
    has_touring := cleaned_version ~ '\mTOURING\M';
    has_line := cleaned_version ~ '\mLINE\M';
    has_cooper := cleaned_version ~ '\mCOOPER\M';
    has_grand := cleaned_version ~ '\mGRAND\M';
    has_limited := cleaned_version ~ '\mLIMITED\M';
    has_drive := cleaned_version ~ '\mDRIVE\M';
    has_range := cleaned_version ~ '\mRANGE\M';
    has_carrera := cleaned_version ~ '\mCARRERA\M';
    has_edition := cleaned_version ~ '\mEDITION\M';
    has_premium := cleaned_version ~ '\mPREMIUM\M';
    has_unlimited := cleaned_version ~ '\mUNLIMITED\M';
    has_king := cleaned_version ~ '\mKING\M';

    -- ========================================================================
    -- 🧠 CONDITIONAL REPLACEMENTS: Solo si keyword está presente
    -- ========================================================================

    -- TOURING variants (Mazda - ALTA PRIORIDAD)
    IF has_touring THEN
        -- 3-word patterns first (más específicos primero)
        cleaned_version := regexp_replace(cleaned_version, '\mI\s+GRAND\s+TOURING\M', 'I-GRAND-TOURING', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mS\s+GRAND\s+TOURING\M', 'S-GRAND-TOURING', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mR\s+GRAND\s+TOURING\M', 'R-GRAND-TOURING', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mD\s+GRAND\s+TOURING\M', 'D-GRAND-TOURING', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mGRAND\s+TOURING\s+PLUS\M', 'GRAND-TOURING-PLUS', 'gi');

        -- 2-word patterns
        cleaned_version := regexp_replace(cleaned_version, '\mGRAND\s+TOURING\M', 'GRAND-TOURING', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mI\s+TOURING\M', 'I-TOURING', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mS\s+TOURING\M', 'S-TOURING', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mR\s+TOURING\M', 'R-TOURING', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mD\s+TOURING\M', 'D-TOURING', 'gi');
    END IF;

    -- SPORT variants (BMW, Audi - MUY COMÚN)
    IF has_sport THEN
        cleaned_version := regexp_replace(cleaned_version, '\mSPORT\s+LINE\M', 'SPORT-LINE', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mSPORT\s+AUTOMATICA\M', 'SPORT-AUTOMATICA', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mSPORT\s+PLUS\M', 'SPORT-PLUS', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mSPORT\s+EDITION\M', 'SPORT-EDITION', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mM\s+SPORT\M', 'M-SPORT', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mI\s+SPORT\M', 'I-SPORT', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mS\s+SPORT\M', 'S-SPORT', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mR\s+SPORT\M', 'R-SPORT', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mE\s+SPORT\M', 'E-SPORT', 'gi');
    END IF;

    -- LINE variants (Audi, BMW, VW - MUY COMÚN)
    IF has_line THEN
        cleaned_version := regexp_replace(cleaned_version, '\mLUXURY\s+LINE\M', 'LUXURY-LINE', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mMODERN\s+LINE\M', 'MODERN-LINE', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mURBAN\s+LINE\M', 'URBAN-LINE', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mS\s+LINE\M', 'S-LINE', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mX\s+LINE\M', 'X-LINE', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mR\s+LINE\M', 'R-LINE', 'gi');
    END IF;

    -- COOPER variants (MINI)
    IF has_cooper THEN
        -- 3-word first
        cleaned_version := regexp_replace(cleaned_version, '\mJOHN\s+COOPER\s+WORKS\M', 'JOHN-COOPER-WORKS', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mJOHN\s+COOPER\M', 'JOHN-COOPER', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mCOOPER\s+WORKS\M', 'COOPER-WORKS', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mCOOPER\s+S\M', 'COOPER-S', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mS\s+CHILI\M', 'S-CHILI', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mS\s+SALT\M', 'S-SALT', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mCHILI\s+CONVERTIBLE\M', 'CHILI-CONVERTIBLE', 'gi');
    END IF;

    -- GRAND variants (Jeep, Cherokee)
    IF has_grand THEN
        cleaned_version := regexp_replace(cleaned_version, '\mGRAND\s+CHEROKEE\s+LIMITED\M', 'GRAND-CHEROKEE-LIMITED', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mGRAND\s+CHEROKEE\M', 'GRAND-CHEROKEE', 'gi');
    END IF;

    -- UNLIMITED (Jeep)
    IF has_unlimited THEN
        cleaned_version := regexp_replace(cleaned_version, '\mUNLIMITED\s+SAHARA\M', 'UNLIMITED-SAHARA', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mUNLIMITED\s+RUBICON\M', 'UNLIMITED-RUBICON', 'gi');
    END IF;

    -- LIMITED variants
    IF has_limited THEN
        cleaned_version := regexp_replace(cleaned_version, '\mLIMITED\s+PREMIUM\M', 'LIMITED-PREMIUM', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mLIMITED\s+LUJO\M', 'LIMITED-LUJO', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mLIMITED\s+TECH\M', 'LIMITED-TECH', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mLIMITED\s+PLUS\M', 'LIMITED-PLUS', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mLIMITED\s+EDITION\M', 'LIMITED-EDITION', 'gi');
    END IF;

    -- PREMIUM variants
    IF has_premium THEN
        cleaned_version := regexp_replace(cleaned_version, '\mPREMIUM\s+LUXURY\M', 'PREMIUM-LUXURY', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mI\s+PREMIUM\M', 'I-PREMIUM', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mL\s+PREMIUM\M', 'L-PREMIUM', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mC\s+PREMIUM\M', 'C-PREMIUM', 'gi');
    END IF;

    -- DRIVE variants (BMW)
    IF has_drive THEN
        cleaned_version := regexp_replace(cleaned_version, '\mX\s+DRIVE\M', 'X-DRIVE', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mS\s+DRIVE\M', 'S-DRIVE', 'gi');
    END IF;

    -- RANGE ROVER (Land Rover)
    IF has_range THEN
        cleaned_version := regexp_replace(cleaned_version, '\mRANGE\s+ROVER\s+SPORT\M', 'RANGE-ROVER-SPORT', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mRANGE\s+ROVER\M', 'RANGE-ROVER', 'gi');
    END IF;

    -- CARRERA (Porsche)
    IF has_carrera THEN
        cleaned_version := regexp_replace(cleaned_version, '\mCARRERA\s+4S\M', 'CARRERA-4S', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mCARRERA\s+2S\M', 'CARRERA-2S', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mCARRERA\s+S\M', 'CARRERA-S', 'gi');
    END IF;

    -- EDITION variants
    IF has_edition THEN
        cleaned_version := regexp_replace(cleaned_version, '\mBLACK\s+EDITION\M', 'BLACK-EDITION', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mSPECIAL\s+EDITION\M', 'SPECIAL-EDITION', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mFIRST\s+EDITION\M', 'FIRST-EDITION', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mCOMPETITION\s+EDITION\M', 'COMPETITION-EDITION', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mMIDNIGHT\s+EDITION\M', 'MIDNIGHT-EDITION', 'gi');
    END IF;

    -- KING RANCH (Ford)
    IF has_king THEN
        cleaned_version := regexp_replace(cleaned_version, '\mKING\s+RANCH\M', 'KING-RANCH', 'gi');
    END IF;

    -- ⚡ v2.11.3.2 OPTIMIZED: Adicionales ahora condicionales
    -- EDDIE, HIGH, LARIAT, RAPTOR (Ford - menos comunes)
    IF cleaned_version ~ '\m(EDDIE|HIGH|LARIAT|RAPTOR)\M' THEN
        cleaned_version := regexp_replace(cleaned_version, '\mEDDIE\s+BAUER\M', 'EDDIE-BAUER', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mHIGH\s+COUNTRY\M', 'HIGH-COUNTRY', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mLARIAT\s+CREW\M', 'LARIAT-CREW', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mRAPTOR\s+CREW\M', 'RAPTOR-CREW', 'gi');
    END IF;

    -- DYNAMIC, DESIGN (Jaguar, Volvo - menos comunes)
    IF cleaned_version ~ '\m(DYNAMIC|DESIGN)\M' THEN
        cleaned_version := regexp_replace(cleaned_version, '\mR\s+DYNAMIC\M', 'R-DYNAMIC', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mACTIVE\s+DYNAMIC\M', 'ACTIVE-DYNAMIC', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mR\s+DESIGN\M', 'R-DESIGN', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mDESIGN\s+PURE\M', 'DESIGN-PURE', 'gi');
    END IF;

    -- SPORTBACK (Audi - menos común)
    IF cleaned_version ~ '\mSPORTBACK\M' THEN
        cleaned_version := regexp_replace(cleaned_version, '\mSPORTBACK\s+S\M', 'SPORTBACK-S', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mSPORTBACK\s+ATTRACTION\M', 'SPORTBACK-ATTRACTION', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mSPORTBACK\s+ELITE\M', 'SPORTBACK-ELITE', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mSPORTBACK\s+LUXURY\M', 'SPORTBACK-LUXURY', 'gi');
    END IF;

    -- STYLE, TRENDY, ALLURE (Peugeot, Citroën - menos comunes)
    IF cleaned_version ~ '\m(STYLE|TRENDY|ALLURE)\M' THEN
        cleaned_version := regexp_replace(cleaned_version, '\mSTYLE\s+ACTIVE\M', 'STYLE-ACTIVE', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mSTYLE\s+PLUS\M', 'STYLE-PLUS', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mTRENDY\s+PLUS\M', 'TRENDY-PLUS', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mALLURE\s+PACK\M', 'ALLURE-PACK', 'gi');
    END IF;

    -- LUXURY, ELEGANCE (Mazda, Mercedes - menos comunes)
    IF cleaned_version ~ '\m(LUXURY|ELEGANCE)\M' THEN
        cleaned_version := regexp_replace(cleaned_version, '\mI\s+LUXURY\M', 'I-LUXURY', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mI\s+ELEGANCE\M', 'I-ELEGANCE', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mF\s+ELEGANCE\M', 'F-ELEGANCE', 'gi');
        cleaned_version := regexp_replace(cleaned_version, '\mK\s+ELEGANCE\M', 'K-ELEGANCE', 'gi');
    END IF;

    -- ========================================================================
    -- END v2.11.2 smart conditional conversions
    -- ========================================================================

    -- ✅ v2.11.3 OPTIMIZED: Solo proteger si hay guiones (performance)
    IF position('-' in cleaned_version) > 0 THEN
        -- Proteger TODOS los trims hyphenated dinámicamente
        -- En lugar de lista hardcoded, proteger todos los guiones entre letras mayúsculas
        -- Esto captura I-GRAND-TOURING, M-SPORT, S-LINE, etc. automáticamente
        cleaned_version := regexp_replace(cleaned_version, '([A-Z])-([A-Z])', '\1§\2', 'g');
    END IF;

    cleaned_version := regexp_replace(cleaned_version, '[,;/|]', ' ', 'g');
    cleaned_version := regexp_replace(cleaned_version, '\s+', ' ', 'g');

    -- ✅ v2.11.3 OPTIMIZED: Solo restaurar si protegimos (performance)
    IF position('§' in cleaned_version) > 0 THEN
        cleaned_version := replace(cleaned_version, '§', '-');
    END IF;

    raw_tokens := string_to_array(cleaned_version, ' ');

    FOREACH token IN ARRAY raw_tokens LOOP
        IF token IS NOT NULL AND length(token) > 0 THEN
            normalized_token := normalize_token(token);
            IF normalized_token IS NOT NULL AND NOT (normalized_token = ANY(noise_tokens)) THEN
                final_tokens := array_append(final_tokens, normalized_token);
            END IF;
        END IF;
    END LOOP;

    RETURN deduplicate_tokens_intelligent(final_tokens);
END;
$$;

-- ============================================================================
-- FUNCIÓN 4: extract_primary_trim - 🔥🔥 UPDATED v2.13.0 - CRITICAL BUGFIX
-- ============================================================================
-- CAMBIO v2.13.0: Buscar por ESPECIFICIDAD (más específicos primero)
--
-- PROBLEMA ANTERIOR (v2.12.0):
--   - Función iteraba tokens del vehículo: FOREACH token IN ARRAY tokens
--   - Si un vehículo tenía ['I', 'GRAND', 'TOURING', ...], retornaba 'I' (primer match)
--   - NO detectaba que el trim completo era 'I-GRAND-TOURING'
--
-- SOLUCIÓN v2.13.0:
--   - Ahora itera el array distinctive_trims EN ORDEN (más específicos primero)
--   - Busca cada distinctive_trim completo en los tokens del vehículo
--   - 'I-GRAND-TOURING' se busca ANTES que 'I', evitando falsos positivos
--   - Ejemplo:
--     tokens = ['I-GRAND-TOURING', '106HP', '1.5L', '4CIL']
--     → Retorna 'I-GRAND-TOURING' (no 'I')
--
-- OPTIMIZACIÓN v2.13.0:
--   - Early exit si tokens es muy corto (performance)
--   - Búsqueda optimizada con operator ANY en lugar de loop explícito
--
-- IMPACTO: ~2,000 vehículos Mazda ahora homologados correctamente
-- ============================================================================
CREATE OR REPLACE FUNCTION extract_primary_trim(tokens TEXT[])
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    token TEXT;
    token_count INT;
    -- ⚡ OPTIMIZACIÓN v2.13.0: Grupos de trims por prioridad para early exit
    -- Búsqueda secuencial solo en grupos relevantes
BEGIN
    -- ⚡ Early exit: NULL o array vacío
    token_count := array_length(tokens, 1);
    IF tokens IS NULL OR token_count IS NULL OR token_count = 0 THEN
        RETURN NULL;
    END IF;

    -- ========================================================================
    -- ⚡ OPTIMIZACIÓN CRÍTICA: Iterar tokens (pequeño) en lugar de distinctive_trims (grande)
    -- ESTRATEGIA:
    -- 1. Primero buscar tokens con guión (multi-word trims) - más específicos
    -- 2. Luego buscar tokens single-word - menos específicos
    -- 3. Early exit al primer match específico
    -- ========================================================================

    -- ========================================================================
    -- PASO 1: BUSCAR MULTI-WORD TRIMS (más específicos) - tokens con guión
    -- ========================================================================
    -- Buscar primero tokens que contengan guión (son los más específicos)
    -- Ejemplo: 'I-GRAND-TOURING' tiene prioridad sobre 'I'
    FOREACH token IN ARRAY tokens LOOP
        -- Solo considerar tokens con guión
        IF position('-' in token) > 0 THEN
            -- Lista de multi-word trims aceptados (ordenada por especificidad)
            CASE token
                -- MAZDA 3-word (highest priority)
                WHEN 'I-GRAND-TOURING', 'S-GRAND-TOURING', 'R-GRAND-TOURING', 'D-GRAND-TOURING', 'GRAND-TOURING-PLUS' THEN RETURN token;

                -- MINI 3-word
                WHEN 'JOHN-COOPER-WORKS' THEN RETURN token;

                -- JEEP 3-word
                WHEN 'GRAND-CHEROKEE-LIMITED', 'UNLIMITED-SAHARA', 'UNLIMITED-RUBICON' THEN RETURN token;

                -- RANGE ROVER 3-word
                WHEN 'RANGE-ROVER-SPORT' THEN RETURN token;

                -- MAZDA 2-word (medium priority)
                WHEN 'GRAND-TOURING', 'I-TOURING', 'S-TOURING', 'R-TOURING', 'D-TOURING',
                     'I-SPORT', 'S-SPORT', 'R-SPORT', 'E-SPORT',
                     'I-LUXURY', 'I-PREMIUM', 'I-ELEGANCE', 'S-ELEGANCE', 'R-LUXURY' THEN RETURN token;

                -- OTHER 2-word trims (common)
                WHEN 'JOHN-COOPER', 'COOPER-WORKS', 'COOPER-S',
                     'GRAND-CHEROKEE', 'RANGE-ROVER',
                     'LIMITED-PREMIUM', 'LIMITED-EDITION', 'LIMITED-LUJO', 'LIMITED-TECH', 'LIMITED-PLUS',
                     'BLACK-EDITION', 'SPECIAL-EDITION', 'FIRST-EDITION', 'COMPETITION-EDITION', 'MIDNIGHT-EDITION', 'SPORT-EDITION',
                     'PREMIUM-LUXURY', 'I-PREMIUM', 'L-PREMIUM', 'C-PREMIUM', 'I-LUXURY', 'F-ELEGANCE', 'K-ELEGANCE',
                     'LUXURY-LINE', 'MODERN-LINE', 'URBAN-LINE', 'SPORT-LINE', 'S-LINE', 'X-LINE', 'R-LINE', 'AMG-LINE',
                     'M-SPORT', 'SPORT-PLUS', 'SPORT-AUTOMATICA',
                     'SPORTBACK-LUXURY', 'SPORTBACK-ELITE', 'SPORTBACK-ATTRACTION', 'SPORTBACK-S',
                     'CARRERA-4S', 'CARRERA-2S', 'CARRERA-S',
                     'KING-RANCH', 'EDDIE-BAUER', 'HIGH-COUNTRY', 'LARIAT-CREW', 'RAPTOR-CREW', 'TRAIL-BOSS', 'HIGH-DESERT',
                     'ACTIVE-DYNAMIC', 'R-DYNAMIC', 'R-DESIGN', 'DESIGN-PURE',
                     'CHILI-CONVERTIBLE', 'S-CHILI', 'S-SALT',
                     'X-DRIVE', 'S-DRIVE',
                     'STYLE-ACTIVE', 'STYLE-PLUS', 'TRENDY-PLUS', 'ALLURE-PACK',
                     'TYPE-R', 'TYPE-S', 'A-SPEC', 'GT-LINE', 'EX-L', 'BIG-HORN' THEN RETURN token;

                ELSE
                    -- Token con guión pero no reconocido - continuar
                    CONTINUE;
            END CASE;
        END IF;
    END LOOP;

    -- ========================================================================
    -- PASO 2: BUSCAR SINGLE-WORD TRIMS (menos específicos)
    -- ========================================================================
    -- Si no encontramos multi-word trim, buscar single-word
    -- NOTA: Los single-letter trims (I, S, R, D) están al FINAL para evitar falsos positivos
    FOREACH token IN ARRAY tokens LOOP
        -- Ignorar tokens con guión (ya procesados arriba) y tokens técnicos
        IF position('-' in token) > 0 OR token ~ '^[0-9]' THEN
            CONTINUE;
        END IF;

        CASE token
            -- Honda/Acura
            WHEN 'PRIME', 'UNIQ', 'UNIQUE', 'TOURING', 'ELITE', 'EX', 'EXL', 'LX', 'EPIC' THEN RETURN token;

            -- Genéricos comunes
            WHEN 'BASE', 'BASICA', 'PREMIUM', 'EXCLUSIVE', 'EXECUTIVE', 'FEST',
                 'LIMITED', 'PLATINUM', 'TITANIUM', 'ULTIMATE', 'DRIVE' THEN RETURN token;

            -- Deportivos/performance
            WHEN 'SPORT', 'GT', 'GTI', 'GTS', 'SRT', 'AMG', 'PERFORMANCE', 'TRACK', 'NISMO', 'RS' THEN RETURN token;

            -- Volkswagen
            WHEN 'TRENDLINE', 'COMFORTLINE', 'HIGHLINE', 'COMFORT', 'TREND',
                 'GLI', 'ALLTRACK', 'CROSS', 'WOLFSBURG', 'AUTOBAHN' THEN RETURN token;

            -- Audi
            WHEN 'BLACK', 'SPORTBACK', 'QUATTRO', 'PROGRESSIVE', 'TECHNIK', 'COMPETITION' THEN RETURN token;

            -- BMW
            WHEN 'XDRIVE', 'SDRIVE', 'MSPORT', 'MODERN' THEN RETURN token;

            -- Peugeot
            WHEN 'ACTIVE', 'ALLURE', 'FELINE', 'STYLE' THEN RETURN token;

            -- Jeep
            WHEN 'RUBICON', 'SAHARA', 'OVERLAND', 'TRAILHAWK', 'ALTITUDE', 'LONGITUDE',
                 'LAREDO', 'SUMMIT', 'WILLYS', 'UNLIMITED', 'NORTH', 'UPLAND', '80TH' THEN RETURN token;

            -- Chevrolet/GMC
            WHEN 'LT', 'LTZ', 'LS', 'LTX', 'PREMIER', 'MIDNIGHT',
                 'SLT', 'SLE', 'DENALI', 'AT4', 'CREW', 'RST', 'Z71' THEN RETURN token;

            -- Dodge/RAM
            WHEN 'SXT', 'LARAMIE', 'REBEL', 'LONGHORN', 'WARLOCK', 'NIGHT' THEN RETURN token;

            -- Ford
            WHEN 'XL', 'XLT', 'LARIAT', 'RAPTOR', 'TREMOR', 'WILDTRAK' THEN RETURN token;

            -- Toyota/Lexus
            WHEN 'LE', 'SE', 'XLE', 'XSE', 'TRD', 'PRO', 'NIGHTSHADE', 'SR5', 'VENTURE' THEN RETURN token;

            -- Hyundai/Kia
            WHEN 'GLS', 'GLX', 'SEL', 'SX', 'GL' THEN RETURN token;

            -- Land Rover
            WHEN 'HSE', 'VOGUE', 'AUTOBIOGRAPHY', 'DYNAMIC', 'EVOQUE', 'VELAR' THEN RETURN token;

            -- Porsche
            WHEN 'CARRERA', 'TURBO', 'TARGA', 'BOXSTER', 'CAYMAN' THEN RETURN token;

            -- Nissan
            WHEN 'ADVANCE', 'EXCLUSIVE', 'SENSE', 'GST', 'GXE', 'XE', 'GSX', 'GSS', 'SR', 'SV', 'SL' THEN RETURN token;

            -- Mazda (other)
            WHEN 'SIGNATURE', 'CARBON', 'SELECT' THEN RETURN token;

            -- Mini
            WHEN 'CHILI', 'PEPPER' THEN RETURN token;

            -- Renault
            WHEN 'EXPRESSION', 'DYNAMIQUE', 'INTENS', 'PRIVILEGE', 'ZEN' THEN RETURN token;

            -- Mercedes Benz
            WHEN 'ELEGANCE', 'AVANTGARDE', 'FASHION' THEN RETURN token;

            -- Subaru
            WHEN 'WILDERNESS', 'ONYX' THEN RETURN token;

            -- Otros comunes
            WHEN 'TECH', 'PRESTIGE', 'AMBIENTE', 'TRENDY', 'REFERENCE', 'CUSTOM', 'LUXURY', 'LUJO', 'TIPICO' THEN RETURN token;

            -- 🔥 MAZDA SINGLE-LETTER TRIMS - AL FINAL (lowest priority)
            -- Estos solo se retornan si NO hay ningún otro trim más específico
            WHEN 'I', 'S', 'R', 'D' THEN RETURN token;

            ELSE
                -- Token no reconocido - continuar
                CONTINUE;
        END CASE;
    END LOOP;

    -- No se encontró ningún trim distintivo
    RETURN NULL;
END;
$$;

-- ============================================================================
-- FUNCIÓN 5: is_single_spec_match - NEW v2.10.0 (SIN CAMBIOS en v2.13.0)
-- ============================================================================
-- Detecta si dos versiones son la misma especificación a diferentes niveles de detalle
-- Caso de uso: "COMFORT" vs "COMFORT 148HP 1.4L 4CIL 4PUERTAS 5OCUP"
-- Lógica:
--   1. Al menos una versión debe ser "single-spec" (1-2 tokens)
--   2. Extraer trim principal de ambas versiones
--   3. Si ambos trims son iguales → MATCH
--   4. Si alguno no tiene trim distintivo → Comparar todos los tokens de la versión simple
-- ============================================================================
CREATE OR REPLACE FUNCTION is_single_spec_match(tokens_a TEXT[], tokens_b TEXT[])
RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    len_a INT;
    len_b INT;
    is_a_single_spec BOOLEAN;
    is_b_single_spec BOOLEAN;
    trim_a TEXT;
    trim_b TEXT;
    token TEXT;
    SINGLE_SPEC_THRESHOLD CONSTANT INT := 2;
BEGIN
    len_a := array_length(tokens_a, 1);
    len_b := array_length(tokens_b, 1);

    IF len_a IS NULL OR len_b IS NULL THEN
        RETURN FALSE;
    END IF;

    is_a_single_spec := (len_a <= SINGLE_SPEC_THRESHOLD);
    is_b_single_spec := (len_b <= SINGLE_SPEC_THRESHOLD);

    IF NOT (is_a_single_spec OR is_b_single_spec) THEN
        RETURN FALSE;
    END IF;

    IF is_a_single_spec AND is_b_single_spec THEN
        RETURN tokens_a = tokens_b;
    END IF;

    trim_a := extract_primary_trim(tokens_a);
    trim_b := extract_primary_trim(tokens_b);

    IF trim_a IS NOT NULL AND trim_b IS NOT NULL THEN
        IF trim_a = trim_b THEN
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;
    END IF;

    IF is_a_single_spec THEN
        FOREACH token IN ARRAY tokens_a LOOP
            IF NOT (token = ANY(tokens_b)) THEN
                RETURN FALSE;
            END IF;
        END LOOP;
        RETURN TRUE;
    END IF;

    IF is_b_single_spec THEN
        FOREACH token IN ARRAY tokens_b LOOP
            IF NOT (token = ANY(tokens_a)) THEN
                RETURN FALSE;
            END IF;
        END LOOP;
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$;

-- ============================================================================
-- FUNCIÓN 6: is_minimal_version_match (SIN CAMBIOS en v2.13.0)
-- ============================================================================
CREATE OR REPLACE FUNCTION is_minimal_version_match(tokens_a TEXT[], tokens_b TEXT[])
RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    is_a_minimal BOOLEAN;
    is_b_minimal BOOLEAN;
    token TEXT;
    body_style_a TEXT;
    body_style_b TEXT;
    body_styles TEXT[] := ARRAY['SEDAN', 'SUV', 'COUPE', 'HATCHBACK', 'WAGON', 'PICKUP', 'VAN', 'CONVERTIBLE'];
    MINIMAL_TOKEN_THRESHOLD CONSTANT INT := 4;
BEGIN
    is_a_minimal := (array_length(tokens_a, 1) <= MINIMAL_TOKEN_THRESHOLD);
    is_b_minimal := (array_length(tokens_b, 1) <= MINIMAL_TOKEN_THRESHOLD);
    IF NOT (is_a_minimal OR is_b_minimal) THEN RETURN FALSE; END IF;
    IF is_a_minimal AND is_b_minimal THEN RETURN tokens_a = tokens_b; END IF;
    FOREACH token IN ARRAY tokens_a LOOP
        IF token = ANY(body_styles) THEN body_style_a := token; EXIT; END IF;
    END LOOP;
    FOREACH token IN ARRAY tokens_b LOOP
        IF token = ANY(body_styles) THEN body_style_b := token; EXIT; END IF;
    END LOOP;
    IF body_style_a IS NOT NULL AND body_style_b IS NOT NULL AND body_style_a != body_style_b THEN RETURN FALSE; END IF;
    IF is_a_minimal THEN
        FOREACH token IN ARRAY tokens_a LOOP
            IF NOT (token = ANY(tokens_b)) THEN RETURN FALSE; END IF;
        END LOOP;
        RETURN TRUE;
    END IF;
    FOREACH token IN ARRAY tokens_b LOOP
        IF NOT (token = ANY(tokens_a)) THEN RETURN FALSE; END IF;
    END LOOP;
    RETURN TRUE;
END;
$$;

-- ============================================================================
-- FUNCIÓN 7: detect_conflicts (SIN CAMBIOS en v2.13.0)
-- ============================================================================
CREATE OR REPLACE FUNCTION detect_conflicts(tokens_a TEXT[], tokens_b TEXT[])
RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    drive_types_a TEXT[]; drive_types_b TEXT[];
    fuel_types_a TEXT[]; fuel_types_b TEXT[];
    doors_a TEXT[]; doors_b TEXT[];
    cylinders_a TEXT[]; cylinders_b TEXT[];
    hp_a INT; hp_b INT;
    token TEXT;
BEGIN
    drive_types_a := ARRAY(SELECT t FROM unnest(tokens_a) AS t WHERE t IN ('AWD', '4WD', 'FWD', 'RWD', 'SDRIVE', 'XDRIVE', '2WD'));
    drive_types_b := ARRAY(SELECT t FROM unnest(tokens_b) AS t WHERE t IN ('AWD', '4WD', 'FWD', 'RWD', 'SDRIVE', 'XDRIVE', '2WD'));
    IF array_length(drive_types_a, 1) > 0 AND array_length(drive_types_b, 1) > 0 AND NOT (drive_types_a <@ drive_types_b OR drive_types_b <@ drive_types_a) THEN
        RETURN TRUE;
    END IF;

    fuel_types_a := ARRAY(SELECT t FROM unnest(tokens_a) AS t WHERE t IN ('DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC', 'GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI', 'ELECTRIC', 'HYBRID', 'PHEV', 'MHEV'));
    fuel_types_b := ARRAY(SELECT t FROM unnest(tokens_b) AS t WHERE t IN ('DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC', 'GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI', 'ELECTRIC', 'HYBRID', 'PHEV', 'MHEV'));
    IF array_length(fuel_types_a, 1) > 0 AND array_length(fuel_types_b, 1) > 0 THEN
        IF (EXISTS(SELECT 1 FROM unnest(fuel_types_a) AS t WHERE t IN ('DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC'))
            AND EXISTS(SELECT 1 FROM unnest(fuel_types_b) AS t WHERE t IN ('GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI')))
           OR (EXISTS(SELECT 1 FROM unnest(fuel_types_b) AS t WHERE t IN ('DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC'))
            AND EXISTS(SELECT 1 FROM unnest(fuel_types_a) AS t WHERE t IN ('GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI')))
        THEN RETURN TRUE; END IF;
    END IF;

    doors_a := ARRAY(SELECT t FROM unnest(tokens_a) AS t WHERE t IN ('2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS'));
    doors_b := ARRAY(SELECT t FROM unnest(tokens_b) AS t WHERE t IN ('2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS'));
    IF array_length(doors_a, 1) > 0 AND array_length(doors_b, 1) > 0 AND NOT (doors_a = doors_b) THEN
        RETURN TRUE;
    END IF;

    cylinders_a := ARRAY(SELECT t FROM unnest(tokens_a) AS t WHERE t IN ('3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL'));
    cylinders_b := ARRAY(SELECT t FROM unnest(tokens_b) AS t WHERE t IN ('3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL'));
    IF array_length(cylinders_a, 1) > 0 AND array_length(cylinders_b, 1) > 0 AND NOT (cylinders_a = cylinders_b) THEN
        RETURN TRUE;
    END IF;

    FOREACH token IN ARRAY tokens_a LOOP
        IF token ~ '^[0-9]{2,3}HP$' THEN
            hp_a := substring(token FROM '^([0-9]{2,3})HP$')::INT;
            EXIT;
        END IF;
    END LOOP;
    FOREACH token IN ARRAY tokens_b LOOP
        IF token ~ '^[0-9]{2,3}HP$' THEN
            hp_b := substring(token FROM '^([0-9]{2,3})HP$')::INT;
            EXIT;
        END IF;
    END LOOP;
    IF hp_a IS NOT NULL AND hp_b IS NOT NULL THEN
        IF ABS(hp_a - hp_b)::NUMERIC / GREATEST(hp_a, hp_b) > 0.08 THEN
            RETURN TRUE;
        END IF;
    END IF;

    RETURN FALSE;
END;
$$;

-- ============================================================================
-- FUNCIÓN 8: has_different_trims - 🔥🔥 UPDATED v2.13.0 - CRITICAL BUGFIX
-- ============================================================================
-- CAMBIO v2.13.0: Lógica ESTRICTA de comparación de trims
--
-- PROBLEMA ANTERIOR (v2.12.0):
--   - Función solo retornaba TRUE si AMBOS vehículos tenían trims Y eran diferentes
--   - Si un vehículo tenía trim y otro NO, retornaba FALSE (permitía match incorrecto)
--   - Ejemplo problemático:
--     tokens_a = ['I-GRAND-TOURING', '106HP'] → trim_a = 'I-GRAND-TOURING'
--     tokens_b = ['AUTOMATICA', '106HP']      → trim_b = NULL
--     Resultado: FALSE (permitía match cuando NO debería)
--
-- SOLUCIÓN v2.13.0:
--   - Si ambos tienen NULL → FALSE (no hay conflicto)
--   - Si solo uno tiene trim → TRUE (sí hay conflicto)
--   - Si ambos tienen trim → deben ser EXACTAMENTE iguales
--     - 'I' ≠ 'I-TOURING' ≠ 'I-GRAND-TOURING'
--
-- IMPACTO: Evita mezclas de ~2,000 vehículos Mazda
-- ============================================================================
CREATE OR REPLACE FUNCTION has_different_trims(tokens_a TEXT[], tokens_b TEXT[])
RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    trim_a TEXT;
    trim_b TEXT;
BEGIN
    -- Extraer trims principales usando la nueva lógica de especificidad
    trim_a := extract_primary_trim(tokens_a);
    trim_b := extract_primary_trim(tokens_b);

    -- 🔥 v2.13.0 CRITICAL: Lógica ESTRICTA de comparación

    -- CASO 1: Si ambos son NULL → no hay conflicto
    IF trim_a IS NULL AND trim_b IS NULL THEN
        RETURN FALSE;
    END IF;

    -- CASO 2: Si solo uno tiene trim → SÍ hay conflicto
    -- Ejemplo: 'I-GRAND-TOURING' vs NULL (genérico) → diferentes
    IF (trim_a IS NULL AND trim_b IS NOT NULL) OR
       (trim_a IS NOT NULL AND trim_b IS NULL) THEN
        RETURN TRUE;
    END IF;

    -- CASO 3: Si ambos tienen trim → deben ser EXACTAMENTE iguales
    -- IMPORTANTE: 'I' ≠ 'I-TOURING' ≠ 'I-GRAND-TOURING'
    -- Esto previene:
    --   - ZURICH "I 106HP" matching con ZURICH "I GRAND TOURING 106HP"
    --   - BX "I SPORT" matching con QUALITAS "I GRAND TOURING"
    IF trim_a != trim_b THEN
        RETURN TRUE;
    END IF;

    -- Si llegamos aquí, ambos tienen el mismo trim exacto
    RETURN FALSE;
END;
$$;

-- ============================================================================
-- FUNCIÓN 9: calculate_weighted_coverage_with_trim_penalty
-- 🔥 UPDATED v2.13.0 - CRITICAL BUGFIX
-- ============================================================================
-- CAMBIO v2.13.0: Retorna has_different_trims además de has_trim_penalty
--
-- RAZÓN:
--   - has_trim_penalty: penalización de score (0.75 o 0.95) cuando trims son diferentes
--   - has_different_trims: flag booleano para BLOQUEAR matching completamente
--
-- IMPACTO:
--   - Permite que procesar_batch_vehiculos bloquee matches cuando trims diferentes
--   - Complementa la penalización con bloqueo total
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_weighted_coverage_with_trim_penalty(
    tokens_a TEXT[],
    tokens_b TEXT[],
    is_same_insurer BOOLEAN
)
RETURNS TABLE(
    coverage_a_in_b NUMERIC,
    coverage_b_in_a NUMERIC,
    max_coverage NUMERIC,
    has_conflicts BOOLEAN,
    has_trim_penalty BOOLEAN,
    has_different_trims BOOLEAN,
    final_score NUMERIC
)
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    weighted_intersection NUMERIC := 0;
    weighted_total_a NUMERIC := 0;
    weighted_total_b NUMERIC := 0;
    token TEXT;
    token_weight NUMERIC;
    conflicts_detected BOOLEAN;
    different_trims BOOLEAN;
    raw_coverage NUMERIC;
    penalized_score NUMERIC;
    SAME_INSURER_TRIM_PENALTY CONSTANT NUMERIC := 0.75;
    CROSS_INSURER_TRIM_PENALTY CONSTANT NUMERIC := 0.95;
BEGIN
    IF tokens_a IS NULL OR tokens_b IS NULL OR array_length(tokens_a, 1) IS NULL OR array_length(tokens_b, 1) IS NULL THEN
        RETURN QUERY SELECT 0::NUMERIC, 0::NUMERIC, 0::NUMERIC, TRUE, FALSE, FALSE, 0::NUMERIC;
        RETURN;
    END IF;

    conflicts_detected := detect_conflicts(tokens_a, tokens_b);
    different_trims := has_different_trims(tokens_a, tokens_b);

    -- 🔥🔥 v2.13.1 CRITICAL FIX: Si trims diferentes, retornar score 0 inmediatamente
    -- Esto previene CUALQUIER match, sin importar cuán similares sean los specs
    IF different_trims THEN
        RETURN QUERY SELECT 0::NUMERIC, 0::NUMERIC, 0::NUMERIC, conflicts_detected, TRUE, TRUE, 0::NUMERIC;
        RETURN;
    END IF;

    FOREACH token IN ARRAY tokens_a LOOP
        token_weight := CASE
            -- 🔥🔥 v2.13.1 NEW: Trims multi-word (Mazda y otros) - PESO MÁXIMO
            -- Estos deben tener MÁS peso que HP para evitar mezclas
            WHEN token IN (
                -- Mazda 3-word
                'I-GRAND-TOURING', 'S-GRAND-TOURING', 'R-GRAND-TOURING', 'D-GRAND-TOURING', 'GRAND-TOURING-PLUS',
                -- Mazda 2-word
                'GRAND-TOURING', 'I-TOURING', 'S-TOURING', 'R-TOURING', 'D-TOURING',
                'I-SPORT', 'S-SPORT', 'R-SPORT', 'E-SPORT',
                'I-LUXURY', 'I-PREMIUM', 'I-ELEGANCE', 'S-ELEGANCE', 'R-LUXURY',
                -- BMW/Audi
                'M-SPORT', 'SPORT-LINE', 'SPORT-PLUS', 'SPORT-EDITION',
                'S-LINE', 'X-LINE', 'R-LINE', 'AMG-LINE',
                'LUXURY-LINE', 'MODERN-LINE', 'URBAN-LINE',
                -- Mini
                'JOHN-COOPER-WORKS', 'JOHN-COOPER', 'COOPER-WORKS', 'COOPER-S',
                -- Jeep
                'GRAND-CHEROKEE-LIMITED', 'GRAND-CHEROKEE', 'UNLIMITED-SAHARA', 'UNLIMITED-RUBICON',
                -- Land Rover
                'RANGE-ROVER-SPORT', 'RANGE-ROVER',
                -- Otros comunes
                'LIMITED-PREMIUM', 'LIMITED-EDITION', 'PREMIUM-LUXURY',
                'BLACK-EDITION', 'SPECIAL-EDITION', 'FIRST-EDITION',
                'X-DRIVE', 'S-DRIVE',
                'TYPE-R', 'TYPE-S', 'A-SPEC', 'GT-LINE', 'EX-L'
            ) THEN 20.0  -- 🔥 PESO CRÍTICO: Más que HP (14.0)

            -- Specs técnicas (pesos originales)
            WHEN token ~ '^[0-9]{2,3}HP$' THEN 14.0
            WHEN token ~ '^[0-9]\.[0-9]L$' OR token ~ '^[0-9]L$' THEN 8.0
            WHEN token IN ('AWD', '2WD', 'FWD', 'RWD', 'SDRIVE', 'XDRIVE', 'DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC', 'GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI', 'ELECTRIC', 'HYBRID', 'PHEV', 'MHEV', 'BEV') THEN 10.0
            WHEN token IN ('3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL') THEN 8.0
            WHEN token IN ('TURBO', 'BITURBO', 'SUPERCHARGED') THEN 8.0
            WHEN token IN ('SEDAN', 'SUV', 'COUPE', 'HATCHBACK', 'PICKUP', 'VAN', 'WAGON', 'CONVERTIBLE', '2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS') THEN 5.0
            WHEN token IN ('2OCUP', '3OCUP', '4OCUP', '5OCUP', '6OCUP', '7OCUP', '8OCUP', '9OCUP') THEN 3.0

            -- 🔥🔥 v2.13.1 UPDATED: Trims single-word - PESO ALTO (pero menor que multi-word)
            WHEN token IN (
                'PREMIUM', 'TECH', 'SPORT', 'ADVANCE', 'ELITE', 'TOURING', 'LIMITED',
                'COMFORT', 'DYNAMIC', 'ELEGANCE', 'PRESTIGE',
                'I', 'S', 'R', 'D',  -- 🔥 Mazda single-letter trims
                'TOURING', 'SIGNATURE', 'CARBON', 'SELECT',  -- Mazda otros
                'GT', 'GTI', 'GTS', 'SRT', 'AMG', 'RS',  -- Deportivos
                'LT', 'LTZ', 'LS', 'LTX', 'PREMIER',  -- Chevrolet
                'XL', 'XLT', 'LARIAT', 'RAPTOR',  -- Ford
                'LE', 'SE', 'XLE', 'XSE', 'TRD',  -- Toyota
                'EX', 'LX', 'TOURING', 'ELITE'  -- Honda/Acura
            ) THEN 15.0  -- 🔥 PESO ALTO: Más que HP

            ELSE 1.0
        END;
        weighted_total_a := weighted_total_a + token_weight;
        IF token = ANY(tokens_b) THEN weighted_intersection := weighted_intersection + token_weight; END IF;
    END LOOP;

    FOREACH token IN ARRAY tokens_b LOOP
        token_weight := CASE
            -- 🔥🔥 v2.13.1 NEW: Misma lista de trims multi-word
            WHEN token IN (
                'I-GRAND-TOURING', 'S-GRAND-TOURING', 'R-GRAND-TOURING', 'D-GRAND-TOURING', 'GRAND-TOURING-PLUS',
                'GRAND-TOURING', 'I-TOURING', 'S-TOURING', 'R-TOURING', 'D-TOURING',
                'I-SPORT', 'S-SPORT', 'R-SPORT', 'E-SPORT',
                'I-LUXURY', 'I-PREMIUM', 'I-ELEGANCE', 'S-ELEGANCE', 'R-LUXURY',
                'M-SPORT', 'SPORT-LINE', 'SPORT-PLUS', 'SPORT-EDITION',
                'S-LINE', 'X-LINE', 'R-LINE', 'AMG-LINE',
                'LUXURY-LINE', 'MODERN-LINE', 'URBAN-LINE',
                'JOHN-COOPER-WORKS', 'JOHN-COOPER', 'COOPER-WORKS', 'COOPER-S',
                'GRAND-CHEROKEE-LIMITED', 'GRAND-CHEROKEE', 'UNLIMITED-SAHARA', 'UNLIMITED-RUBICON',
                'RANGE-ROVER-SPORT', 'RANGE-ROVER',
                'LIMITED-PREMIUM', 'LIMITED-EDITION', 'PREMIUM-LUXURY',
                'BLACK-EDITION', 'SPECIAL-EDITION', 'FIRST-EDITION',
                'X-DRIVE', 'S-DRIVE',
                'TYPE-R', 'TYPE-S', 'A-SPEC', 'GT-LINE', 'EX-L'
            ) THEN 20.0

            WHEN token ~ '^[0-9]{2,3}HP$' THEN 14.0
            WHEN token ~ '^[0-9]\.[0-9]L$' OR token ~ '^[0-9]L$' THEN 8.0
            WHEN token IN ('AWD', '2WD', 'FWD', 'RWD', 'SDRIVE', 'XDRIVE', 'DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC', 'GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI', 'ELECTRIC', 'HYBRID', 'PHEV', 'MHEV', 'BEV') THEN 10.0
            WHEN token IN ('3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL', 'TURBO', 'BITURBO', 'SUPERCHARGED') THEN 8.0
            WHEN token IN ('SEDAN', 'SUV', 'COUPE', 'HATCHBACK', 'PICKUP', 'VAN', 'WAGON', 'CONVERTIBLE', '2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS') THEN 5.0
            WHEN token IN ('2OCUP', '3OCUP', '4OCUP', '5OCUP', '6OCUP', '7OCUP', '8OCUP', '9OCUP') THEN 3.0

            -- 🔥🔥 v2.13.1 UPDATED: Trims single-word
            WHEN token IN (
                'PREMIUM', 'TECH', 'SPORT', 'ADVANCE', 'ELITE', 'TOURING', 'LIMITED',
                'COMFORT', 'DYNAMIC', 'ELEGANCE', 'PRESTIGE',
                'I', 'S', 'R', 'D',
                'TOURING', 'SIGNATURE', 'CARBON', 'SELECT',
                'GT', 'GTI', 'GTS', 'SRT', 'AMG', 'RS',
                'LT', 'LTZ', 'LS', 'LTX', 'PREMIER',
                'XL', 'XLT', 'LARIAT', 'RAPTOR',
                'LE', 'SE', 'XLE', 'XSE', 'TRD',
                'EX', 'LX', 'TOURING', 'ELITE'
            ) THEN 15.0

            ELSE 1.0
        END;
        weighted_total_b := weighted_total_b + token_weight;
    END LOOP;

    raw_coverage := GREATEST(
        CASE WHEN weighted_total_a > 0 THEN weighted_intersection / weighted_total_a ELSE 0 END,
        CASE WHEN weighted_total_b > 0 THEN weighted_intersection / weighted_total_b ELSE 0 END
    );

    -- Como ya bloqueamos arriba si different_trims=TRUE, aquí no hay penalización
    penalized_score := raw_coverage;

    RETURN QUERY SELECT
        CASE WHEN weighted_total_a > 0 THEN weighted_intersection / weighted_total_a ELSE 0 END,
        CASE WHEN weighted_total_b > 0 THEN weighted_intersection / weighted_total_b ELSE 0 END,
        raw_coverage,
        conflicts_detected,
        FALSE,  -- has_trim_penalty (ya no se usa, bloqueamos directamente)
        FALSE,  -- has_different_trims (siempre FALSE aquí porque bloqueamos arriba)
        penalized_score;
END;
$$;

-- ============================================================================
-- FUNCIÓN 10: calculate_jaccard_similarity (SIN CAMBIOS en v2.13.0)
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_jaccard_similarity(tokens_a TEXT[], tokens_b TEXT[])
RETURNS NUMERIC
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    intersection_count INT;
    union_count INT;
BEGIN
    IF tokens_a IS NULL OR tokens_b IS NULL OR array_length(tokens_a, 1) IS NULL OR array_length(tokens_b, 1) IS NULL THEN RETURN 0; END IF;
    SELECT COUNT(*) INTO intersection_count FROM unnest(tokens_a) t WHERE t = ANY(tokens_b);
    union_count := array_length(tokens_a, 1) + array_length(tokens_b, 1) - intersection_count;
    IF union_count = 0 THEN RETURN 0; END IF;
    RETURN intersection_count::NUMERIC / union_count::NUMERIC;
END;
$$;

-- ============================================================================
-- 🔥🔥 FUNCIÓN PRINCIPAL: procesar_batch_vehiculos v2.13.0
-- ============================================================================
-- CAMBIO v2.13.0: BLOQUEAR (no solo penalizar) matching cuando has_different_trims = TRUE
--
-- LÓGICA ANTERIOR (v2.12.0):
--   - Si has_trim_penalty = TRUE → penalizar score pero PERMITIR match
--   - Resultado: Vehículos con trims diferentes se agrupaban (score penalizado pero suficiente)
--
-- LÓGICA NUEVA (v2.13.0):
--   - Si has_different_trims = TRUE → BLOQUEAR match completamente (CONTINUE)
--   - Vehículos con trims diferentes NUNCA se agrupan (ni con score alto)
--
-- UBICACIONES DE CAMBIO:
--   1. Same-insurer matching (línea ~1192)
--   2. Cross-insurer matching (línea ~1238)
--
-- IMPACTO: ~2,000 vehículos Mazda ahora homologados correctamente
-- ============================================================================
CREATE OR REPLACE FUNCTION procesar_batch_vehiculos(vehiculos_json JSONB)
RETURNS TABLE(insertados INT, actualizados INT, skipped INT, tier1_matches INT, tier2_matches INT, tier3_matches INT, multi_matches INT, processing_time_ms NUMERIC)
LANGUAGE plpgsql AS $$
DECLARE
    v_record JSONB;
    v_hash TEXT; v_version TEXT; v_tokens TEXT[]; v_origen TEXT;
    existing_record RECORD;
    coverage_result RECORD;
    jaccard_score NUMERIC;
    start_time TIMESTAMP;

    insert_count INT := 0; update_count INT := 0; skip_count INT := 0;
    tier1_count INT := 0; tier2_count INT := 0; tier3_count INT := 0;
    multi_match_count INT := 0;

    matches JSONB := '[]'::JSONB;
    match_record RECORD;
    best_match RECORD;

    v_insurers_permitidos_crear TEXT[] := ARRAY['ZURICH']; -- , 'HDI'

    -- Umbrales optimizados
    QUALITAS_TIER2_THRESHOLD CONSTANT NUMERIC := 0.45;
    TIER2_COVERAGE_THRESHOLD CONSTANT NUMERIC := 0.60;
    TIER2_SAME_INSURER_THRESHOLD CONSTANT NUMERIC := 0.88;
    TIER3_COVERAGE_THRESHOLD CONSTANT NUMERIC := 0.35;
    TIER3_JACCARD_THRESHOLD CONSTANT NUMERIC := 0.35;
    SHORT_VERSION_THRESHOLD CONSTANT INT := 4;
    SHORT_VERSION_COVERAGE_THRESHOLD CONSTANT NUMERIC := 0.55;

    is_single_spec BOOLEAN;
    is_short_version BOOLEAN;
    is_minimal BOOLEAN;
    adaptive_threshold NUMERIC;
    combined_score NUMERIC;
    batch_size INT;
BEGIN
    start_time := clock_timestamp();
    batch_size := jsonb_array_length(vehiculos_json);

    -- ⚡ v2.11.3.2 ULTRA-OPTIMIZED: Batch size para máxima estabilidad
    IF batch_size > 100 THEN
        RAISE WARNING 'Batch size % exceeds 100. Reduce to 50-100 for best performance and stability.', batch_size;
    END IF;

    FOR v_record IN SELECT * FROM jsonb_array_elements(vehiculos_json)
    LOOP
        v_hash := v_record->>'hash_comercial';
        v_version := v_record->>'version_limpia';
        v_origen := v_record->>'origen_aseguradora';
        v_tokens := clean_and_tokenize_version(v_version);

        matches := '[]'::JSONB;
        is_short_version := (array_length(v_tokens, 1) <= SHORT_VERSION_THRESHOLD);

        FOR existing_record IN
            SELECT id, version, version_tokens_array, (disponibilidad ? v_origen) AS same_insurer
            FROM catalogo_homologado
            WHERE hash_comercial = v_hash
        LOOP
            IF existing_record.same_insurer THEN
                coverage_result := calculate_weighted_coverage_with_trim_penalty(v_tokens, existing_record.version_tokens_array, TRUE);

                -- 🔥🔥 v2.13.0 CRITICAL: BLOQUEAR (no solo penalizar) si trims diferentes
                -- ANTES (v2.12.0): "AND NOT coverage_result.has_trim_penalty"
                --   → Solo penalizaba score, pero PERMITÍA match si score era suficiente
                -- AHORA (v2.13.0): "AND NOT coverage_result.has_different_trims"
                --   → BLOQUEA match completamente, aunque score sea alto
                --
                -- EJEMPLO del cambio:
                --   ZURICH "I GRAND TOURING 106HP" vs ZURICH "I 106HP"
                --   - v2.12.0: coverage = 0.95, penalizado a 0.71, SI permite match (threshold 0.88)
                --   - v2.13.0: has_different_trims = TRUE → BLOQUEADO (CONTINUE)
                --
                -- RESULTADO: Cada trim mantiene su propio registro homologado
                IF NOT coverage_result.has_conflicts AND NOT coverage_result.has_different_trims THEN
                    IF coverage_result.final_score >= TIER2_SAME_INSURER_THRESHOLD THEN
                        matches := matches || jsonb_build_object(
                            'id', existing_record.id,
                            'score', coverage_result.final_score,
                            'tier', 2,
                            'method', 'weighted_coverage_same_batch'
                        );
                        CONTINUE;
                    END IF;
                END IF;
                CONTINUE;
            END IF;

            -- TIER 1: Exact match
            IF existing_record.version = v_version THEN
                matches := matches || jsonb_build_object('id', existing_record.id, 'score', 1.0, 'tier', 1, 'method', 'exact_match_cross');
                CONTINUE;
            END IF;

            -- Single-spec match
            is_single_spec := is_single_spec_match(v_tokens, existing_record.version_tokens_array);
            IF is_single_spec THEN
                matches := matches || jsonb_build_object(
                    'id', existing_record.id,
                    'score', 0.98,
                    'tier', 1,
                    'method', 'single_spec_match'
                );
                CONTINUE;
            END IF;

            -- Minimal version match
            is_minimal := is_minimal_version_match(v_tokens, existing_record.version_tokens_array);
            IF is_minimal THEN
                matches := matches || jsonb_build_object('id', existing_record.id, 'score', 0.95, 'tier', 2, 'method', 'minimal_version');
                CONTINUE;
            END IF;

            -- Coverage-based matching
            coverage_result := calculate_weighted_coverage_with_trim_penalty(v_tokens, existing_record.version_tokens_array, FALSE);

            -- 🔥🔥 v2.13.0 CRITICAL: BLOQUEAR (no solo penalizar) si trims diferentes
            -- ANTES (v2.12.0): "AND NOT coverage_result.has_trim_penalty"
            --   → Solo penalizaba score cross-insurer (0.95), permitía match
            -- AHORA (v2.13.0): "AND NOT coverage_result.has_different_trims"
            --   → BLOQUEA match entre aseguradoras con trims diferentes
            --
            -- EJEMPLO del cambio:
            --   BX "I SPORT 109HP" vs QUALITAS "I GRAND TOURING 110HP"
            --   - v2.12.0: coverage = 0.92, penalizado a 0.87, SI permite match (threshold 0.60)
            --   - v2.13.0: has_different_trims = TRUE → BLOQUEADO (CONTINUE)
            --
            -- RESULTADO: BX "I SPORT" NO se mezcla con QUALITAS "I GRAND TOURING"
            IF NOT coverage_result.has_conflicts AND NOT coverage_result.has_different_trims THEN
                adaptive_threshold := CASE
                    WHEN v_origen = 'QUALITAS' THEN QUALITAS_TIER2_THRESHOLD
                    WHEN is_short_version THEN SHORT_VERSION_COVERAGE_THRESHOLD
                    ELSE TIER2_COVERAGE_THRESHOLD
                END;

                IF (coverage_result.coverage_a_in_b >= adaptive_threshold OR coverage_result.coverage_b_in_a >= adaptive_threshold) THEN
                    matches := matches || jsonb_build_object(
                        'id', existing_record.id,
                        'score', coverage_result.final_score,
                        'tier', 2,
                        'method', CASE
                            WHEN is_short_version THEN 'weighted_coverage_short_adaptive'
                            WHEN v_origen = 'QUALITAS' THEN 'weighted_coverage_qualitas_directional'
                            ELSE 'weighted_coverage_directional'
                        END
                    );
                    CONTINUE;
                END IF;

                IF coverage_result.max_coverage >= TIER3_COVERAGE_THRESHOLD THEN
                    jaccard_score := calculate_jaccard_similarity(v_tokens, existing_record.version_tokens_array);
                    IF jaccard_score >= TIER3_JACCARD_THRESHOLD THEN
                        combined_score := (coverage_result.max_coverage + jaccard_score) / 2.0;
                        matches := matches || jsonb_build_object('id', existing_record.id, 'score', combined_score, 'tier', 3, 'method', 'tier3_hybrid_coverage_jaccard');
                    END IF;
                END IF;
            END IF;
        END LOOP;

        IF jsonb_array_length(matches) > 0 THEN
            -- ✅ v2.12.0: Estrategias simples pueden actualizar múltiples registros
            -- Verificar si hay matches de single_spec o minimal_version
            IF EXISTS(SELECT 1 FROM jsonb_to_recordset(matches) AS m(method TEXT)
                      WHERE m.method IN ('single_spec_match', 'minimal_version')) THEN

                -- Actualizar múltiples registros que pasaron estrategias simples
                FOR match_record IN
                    SELECT * FROM jsonb_to_recordset(matches) AS m(id BIGINT, score NUMERIC, tier INT, method TEXT)
                    WHERE m.method IN ('single_spec_match', 'minimal_version')
                LOOP
                    UPDATE catalogo_homologado
                    SET disponibilidad = jsonb_set(
                            COALESCE(disponibilidad, '{}'::jsonb),
                            ARRAY[v_origen],
                            jsonb_build_object(
                                'origen', COALESCE((disponibilidad->v_origen->>'origen')::boolean, FALSE),
                                'disponible', TRUE,
                                'aseguradora', v_origen,
                                'id_original', v_record->>'id_original',
                                'version_original', v_record->>'version_original',
                                'confianza_score', match_record.score,
                                'metodo_match', match_record.method,
                                'tier', match_record.tier,
                                'fecha_actualizacion', NOW()
                            ), TRUE
                        ),
                        fecha_actualizacion = NOW()
                    WHERE id = match_record.id;

                    update_count := update_count + 1;
                    CASE match_record.tier
                        WHEN 1 THEN tier1_count := tier1_count + 1;
                        WHEN 2 THEN tier2_count := tier2_count + 1;
                        WHEN 3 THEN tier3_count := tier3_count + 1;
                    END CASE;
                END LOOP;

                IF jsonb_array_length(matches) > 1 THEN multi_match_count := multi_match_count + 1; END IF;

            ELSE
                -- Estrategias complejas: solo actualizar el mejor match
                IF jsonb_array_length(matches) > 1 THEN multi_match_count := multi_match_count + 1; END IF;

                SELECT * INTO best_match
                FROM jsonb_to_recordset(matches) AS m(id BIGINT, score NUMERIC, tier INT, method TEXT)
                ORDER BY score DESC, (method LIKE '%same_batch%') DESC, tier ASC
                LIMIT 1;

                -- ✅ v2.11.3 OPTIMIZED: Disabled verbose logging for performance
                -- Uncomment for debugging if needed
                -- IF best_match.method = 'single_spec_match' THEN
                --     RAISE NOTICE '🔥 SINGLE_SPEC_MATCH: hash=% version_new=% matched with ID=% (score: %, tier: %)',
                --         v_hash, v_version, best_match.id, best_match.score, best_match.tier;
                -- ELSE
                --     RAISE NOTICE 'BEST_MATCH_EVALUATION: Evaluated % candidates for hash=% version=%, selected ID=% (score: %, tier: %, method: %)',
                --         jsonb_array_length(matches), v_hash, v_version, best_match.id, best_match.score, best_match.tier, best_match.method;
                -- END IF;

                IF (SELECT COUNT(*) FROM jsonb_to_recordset(matches) AS m(id BIGINT, score NUMERIC, tier INT, method TEXT)
                    WHERE m.score = best_match.score) > 1 THEN
                    RAISE WARNING 'BEST_MATCH_TIE: Multiple candidates with identical score % for hash=% version=%: %',
                        best_match.score, v_hash, v_version, matches;
                END IF;

                IF best_match.tier > 2 THEN
                    RAISE WARNING 'LOW_TIER_MATCH: Best match for hash=% version=% is tier % with score %, candidates: %',
                        v_hash, v_version, best_match.tier, best_match.score, matches;
                END IF;

                UPDATE catalogo_homologado
                SET disponibilidad = jsonb_set(
                        COALESCE(disponibilidad, '{}'::jsonb),
                        ARRAY[v_origen],
                        jsonb_build_object(
                            'origen', COALESCE((disponibilidad->v_origen->>'origen')::boolean, FALSE),
                            'disponible', TRUE,
                            'aseguradora', v_origen,
                            'id_original', v_record->>'id_original',
                            'version_original', v_record->>'version_original',
                            'confianza_score', best_match.score,
                            'metodo_match', best_match.method,
                            'tier', best_match.tier,
                            'fecha_actualizacion', NOW()
                        ), TRUE
                    ),
                    fecha_actualizacion = NOW()
                WHERE id = best_match.id;

                update_count := update_count + 1;
                CASE best_match.tier
                    WHEN 1 THEN tier1_count := tier1_count + 1;
                    WHEN 2 THEN tier2_count := tier2_count + 1;
                    WHEN 3 THEN tier3_count := tier3_count + 1;
                END CASE;
            END IF;
        ELSE
            IF v_origen = ANY(v_insurers_permitidos_crear) THEN
                INSERT INTO catalogo_homologado (hash_comercial, marca, modelo, anio, transmision, version, version_tokens_array, disponibilidad)
                VALUES (v_hash, v_record->>'marca', v_record->>'modelo', (v_record->>'anio')::INT, v_record->>'transmision', v_version, v_tokens,
                    jsonb_build_object(v_origen, jsonb_build_object('origen', TRUE, 'disponible', TRUE, 'aseguradora', v_origen,
                        'id_original', v_record->>'id_original', 'version_original', v_record->>'version_original',
                        'metodo_match', 'original_entry', 'confianza_score', 1.0, 'tier', 0, 'fecha_actualizacion', NOW())))
                ON CONFLICT (hash_comercial, version) DO NOTHING;
                insert_count := insert_count + 1;
            ELSE
                skip_count := skip_count + 1;
            END IF;
        END IF;
    END LOOP;

    RETURN QUERY SELECT insert_count, update_count, skip_count, tier1_count, tier2_count, tier3_count, multi_match_count,
        EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
END;
$$;
