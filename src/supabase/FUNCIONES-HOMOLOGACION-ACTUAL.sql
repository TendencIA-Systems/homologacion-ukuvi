-- ============================================================================
-- SISTEMA DE HOMOLOGACIÓN DE VEHÍCULOS - VERSIÓN v2.8.0 FINAL
-- ============================================================================

TRUNCATE TABLE catalogo_homologado CASCADE;
ALTER SEQUENCE catalogo_homologado_id_seq RESTART WITH 1;

-- Índices
CREATE INDEX IF NOT EXISTS idx_catalogo_hash_comercial ON catalogo_homologado(hash_comercial);
CREATE INDEX IF NOT EXISTS idx_catalogo_version_tokens ON catalogo_homologado USING gin(version_tokens_array);
CREATE INDEX IF NOT EXISTS idx_catalogo_marca_modelo ON catalogo_homologado(marca, modelo);
CREATE INDEX IF NOT EXISTS idx_catalogo_disponibilidad ON catalogo_homologado USING gin(disponibilidad);
ANALYZE catalogo_homologado;

-- Eliminar funciones existentes (limpiado drops innecesarios)
DROP FUNCTION IF EXISTS procesar_batch_vehiculos(JSONB);
DROP FUNCTION IF EXISTS clean_and_tokenize_version(TEXT);
DROP FUNCTION IF EXISTS deduplicate_tokens_intelligent(TEXT[]);
DROP FUNCTION IF EXISTS calculate_weighted_coverage_with_trim_penalty(TEXT[], TEXT[], BOOLEAN);
DROP FUNCTION IF EXISTS calculate_jaccard_similarity(TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS normalize_token(TEXT);
DROP FUNCTION IF EXISTS is_minimal_version_match(TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS detect_conflicts(TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS has_different_trims(TEXT[], TEXT[]);

-- ============================================================================
-- FUNCIÓN 1: normalize_token
-- ============================================================================
CREATE OR REPLACE FUNCTION normalize_token(token TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
BEGIN
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

        WHEN token IN ('AUT', 'AUT.', 'AUTOMATICA', 'AUTOMÁTICA', 'AUTOMATIC', 'AT', 'A') THEN RETURN 'AUTO';
        WHEN token IN ('STD', 'STANDARD', 'MANUAL', 'MAN', 'MT', 'M') THEN RETURN 'STD';
        WHEN token IN ('CVT', 'CONTINUOUSLY', 'VARIABLE') THEN RETURN 'CVT';
        WHEN token IN ('TIPTRONIC', 'TIP', 'SECUENCIAL') THEN RETURN 'TIPTRONIC';
        WHEN token IN ('DSG', 'PDK', 'DCT') THEN RETURN 'DSG';

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
        WHEN token IN ('LUXURY', 'LUJO', 'LUX') THEN RETURN 'PREMIUM';
        WHEN token IN ('TECHNOLOGY', 'TECNOLOGIA') THEN RETURN 'TECH';
        WHEN token IN ('SPORTLINE', 'S-LINE', 'SLINE', 'DEPORTIVO') THEN RETURN 'SPORT';
        WHEN token IN ('BITURBO', 'BITBO', 'BI-TURBO', 'TWIN-TURBO', 'TWINTURBO') THEN RETURN 'TURBO';
        WHEN token IN ('LIMITED EDITION', 'EDITION', 'EDICION', 'EDICIÓN') THEN RETURN 'LIMITED';
        WHEN token IN ('ADVANCED', 'AVANZADO', 'AVANCE') THEN RETURN 'ADVANCE';
        WHEN token IN ('CONFORT', 'COMFORTLINE', 'CONFORTLINE') THEN RETURN 'COMFORT';
        WHEN token IN ('DINAMICO', 'DINÁMICO', 'DYNAMIQUE') THEN RETURN 'DYNAMIC';
        WHEN token IN ('ELEGANCIA', 'ELEGANT', 'ELEGANTE') THEN RETURN 'ELEGANCE';
        WHEN token IN ('PRESTIGIO', 'PRESTIGIOUS') THEN RETURN 'PRESTIGE';

        WHEN token IN ('XL', 'PLUS', 'L', 'BASE', 'BASICO', 'BÁSICO') THEN RETURN NULL;
        WHEN token IN ('PACK', 'PACKAGE', 'PAQUETE') THEN RETURN NULL;

        ELSE RETURN token;
    END CASE;
END;
$$;

-- ============================================================================
-- FUNCIÓN 2: deduplicate_tokens_intelligent
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
-- FUNCIÓN 3: clean_and_tokenize_version
-- ============================================================================
CREATE OR REPLACE FUNCTION clean_and_tokenize_version(p_version TEXT)
RETURNS TEXT[]
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    noise_tokens TEXT[] := ARRAY['R13', 'R14', 'R15', 'R16', 'R17', 'R18', 'R19', 'R20', 'R21', 'R22', 'NUEVO', 'NEW', 'NUEVA', 'ABS', 'EBD', 'ESP', 'VSC', 'TCS', 'AC', 'A/C', 'AA', 'EE', 'BA', 'CA', 'CE', 'CD', 'VP', 'QC', 'SM', 'VT'];
    known_hyphenated_trims TEXT[] := ARRAY['A-SPEC', 'TYPE-R', 'TYPE-S', 'E-TRON', 'S-LINE', 'R-LINE', 'X-LINE', 'BI-TURBO', 'TWIN-TURBO'];
    cleaned_version TEXT;
    raw_tokens TEXT[];
    final_tokens TEXT[] := ARRAY[]::TEXT[];
    token TEXT;
    normalized_token TEXT;
    trim TEXT;
BEGIN
    IF p_version IS NULL OR trim(p_version) = '' THEN RETURN ARRAY[]::TEXT[]; END IF;
    cleaned_version := upper(trim(p_version));
    FOREACH trim IN ARRAY known_hyphenated_trims LOOP
        cleaned_version := replace(cleaned_version, trim, replace(trim, '-', '§'));
    END LOOP;
    cleaned_version := regexp_replace(cleaned_version, '[,;/|]', ' ', 'g');
    cleaned_version := regexp_replace(cleaned_version, '\s+', ' ', 'g');
    cleaned_version := replace(cleaned_version, '§', '-');
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
-- FUNCIÓN 4: is_minimal_version_match
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
-- FUNCIÓN 5: detect_conflicts 
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
    -- ✅ MANTENER: Verificar drive types (genuinamente diferentes)
    drive_types_a := ARRAY(SELECT t FROM unnest(tokens_a) AS t WHERE t IN ('AWD', '4WD', 'FWD', 'RWD', 'SDRIVE', 'XDRIVE', '2WD'));
    drive_types_b := ARRAY(SELECT t FROM unnest(tokens_b) AS t WHERE t IN ('AWD', '4WD', 'FWD', 'RWD', 'SDRIVE', 'XDRIVE', '2WD'));
    IF array_length(drive_types_a, 1) > 0 AND array_length(drive_types_b, 1) > 0 AND NOT (drive_types_a <@ drive_types_b OR drive_types_b <@ drive_types_a) THEN
        RETURN TRUE;
    END IF;

    -- ✅ MANTENER: Verificar fuel types (genuinamente diferentes)
    fuel_types_a := ARRAY(SELECT t FROM unnest(tokens_a) AS t WHERE t IN ('DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC', 'GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI', 'ELECTRIC', 'HYBRID', 'PHEV', 'MHEV'));
    fuel_types_b := ARRAY(SELECT t FROM unnest(tokens_b) AS t WHERE t IN ('DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC', 'GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI', 'ELECTRIC', 'HYBRID', 'PHEV', 'MHEV'));
    IF array_length(fuel_types_a, 1) > 0 AND array_length(fuel_types_b, 1) > 0 THEN
        IF (EXISTS(SELECT 1 FROM unnest(fuel_types_a) AS t WHERE t IN ('DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC'))
            AND EXISTS(SELECT 1 FROM unnest(fuel_types_b) AS t WHERE t IN ('GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI')))
           OR (EXISTS(SELECT 1 FROM unnest(fuel_types_b) AS t WHERE t IN ('DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC'))
            AND EXISTS(SELECT 1 FROM unnest(fuel_types_a) AS t WHERE t IN ('GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI')))
        THEN RETURN TRUE; END IF;
    END IF;

    -- ✅ MANTENER: Verificar puertas (genuinamente diferentes)
    doors_a := ARRAY(SELECT t FROM unnest(tokens_a) AS t WHERE t IN ('2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS'));
    doors_b := ARRAY(SELECT t FROM unnest(tokens_b) AS t WHERE t IN ('2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS'));
    IF array_length(doors_a, 1) > 0 AND array_length(doors_b, 1) > 0 AND NOT (doors_a = doors_b) THEN
        RETURN TRUE;
    END IF;

    -- ✅ MANTENER: Verificar cilindros (genuinamente diferentes)
    cylinders_a := ARRAY(SELECT t FROM unnest(tokens_a) AS t WHERE t IN ('3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL'));
    cylinders_b := ARRAY(SELECT t FROM unnest(tokens_b) AS t WHERE t IN ('3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL'));
    IF array_length(cylinders_a, 1) > 0 AND array_length(cylinders_b, 1) > 0 AND NOT (cylinders_a = cylinders_b) THEN
        RETURN TRUE;
    END IF;

    -- 🔥 v2.8.0 FIX CRÍTICO: ELIMINADO bloqueo por displacement
    -- ANTES (v2.7.8): Bloqueaba si 2.0L != 2.4L
    -- AHORA (v2.8.0): Removido completamente, dejar que pesos decidan
    -- El peso de displacement (8.0) vs HP (14.0) ya maneja esto correctamente

    -- ✅ MANTENER: Verificar HP tolerance ±8% (diferencias mayores son genuinas)
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
-- FUNCIÓN 6: has_different_trims
-- ============================================================================
CREATE OR REPLACE FUNCTION has_different_trims(tokens_a TEXT[], tokens_b TEXT[])
RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    distinctive_trims TEXT[] := ARRAY[
        'A-SPEC', 'ADVANCE', 'ELITE', 'PREMIUM', 'SPORT', 'TECH',
        'TYPE-R', 'TYPE-S', 'R-LINE', 'S-LINE', 'X-LINE',
        'TOURING', 'LIMITED', 'COMFORT', 'DYNAMIC', 'ELEGANCE', 'PRESTIGE'
    ];
    trim_a TEXT;
    trim_b TEXT;
BEGIN
    SELECT t INTO trim_a FROM unnest(tokens_a) AS t WHERE t = ANY(distinctive_trims) LIMIT 1;
    SELECT t INTO trim_b FROM unnest(tokens_b) AS t WHERE t = ANY(distinctive_trims) LIMIT 1;

    IF trim_a IS NOT NULL AND trim_b IS NOT NULL AND trim_a != trim_b THEN
        RETURN TRUE;
    END IF;

    RETURN FALSE;
END;
$$;

-- ============================================================================
-- FUNCIÓN 7: calculate_weighted_coverage_with_trim_penalty
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
        RETURN QUERY SELECT 0::NUMERIC, 0::NUMERIC, 0::NUMERIC, TRUE, FALSE, 0::NUMERIC;
        RETURN;
    END IF;

    conflicts_detected := detect_conflicts(tokens_a, tokens_b);
    different_trims := has_different_trims(tokens_a, tokens_b);

    -- Pesos optimizados v2.7.8 (mantenidos en v2.8.0)
    FOREACH token IN ARRAY tokens_a LOOP
        token_weight := CASE
            WHEN token ~ '^[0-9]{2,3}HP$' THEN 14.0
            WHEN token ~ '^[0-9]\.[0-9]L$' OR token ~ '^[0-9]L$' THEN 8.0
            WHEN token IN ('AWD', '2WD', 'FWD', 'RWD', 'SDRIVE', 'XDRIVE', 'DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC', 'GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI', 'ELECTRIC', 'HYBRID', 'PHEV', 'MHEV', 'BEV') THEN 10.0
            WHEN token IN ('3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL') THEN 8.0
            WHEN token IN ('TURBO', 'BITURBO', 'SUPERCHARGED') THEN 8.0
            WHEN token IN ('SEDAN', 'SUV', 'COUPE', 'HATCHBACK', 'PICKUP', 'VAN', 'WAGON', 'CONVERTIBLE', '2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS') THEN 5.0
            WHEN token IN ('2OCUP', '3OCUP', '4OCUP', '5OCUP', '6OCUP', '7OCUP', '8OCUP', '9OCUP') THEN 3.0
            WHEN token IN ('PREMIUM', 'TECH', 'SPORT', 'ADVANCE', 'ELITE', 'TOURING', 'LIMITED', 'A-SPEC', 'R-LINE', 'S-LINE', 'X-LINE', 'TYPE-R', 'TYPE-S', 'COMFORT', 'DYNAMIC', 'ELEGANCE', 'PRESTIGE') THEN 1.0
            ELSE 1.0
        END;
        weighted_total_a := weighted_total_a + token_weight;
        IF token = ANY(tokens_b) THEN weighted_intersection := weighted_intersection + token_weight; END IF;
    END LOOP;

    FOREACH token IN ARRAY tokens_b LOOP
        token_weight := CASE
            WHEN token ~ '^[0-9]{2,3}HP$' THEN 14.0
            WHEN token ~ '^[0-9]\.[0-9]L$' OR token ~ '^[0-9]L$' THEN 8.0
            WHEN token IN ('AWD', '2WD', 'FWD', 'RWD', 'SDRIVE', 'XDRIVE', 'DIESEL', 'TDI', 'TDCI', 'CDI', 'CRDI', 'BLUETEC', 'GASOLINA', 'TSI', 'TFSI', 'FSI', 'CGI', 'GDI', 'ELECTRIC', 'HYBRID', 'PHEV', 'MHEV', 'BEV') THEN 10.0
            WHEN token IN ('3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL', 'TURBO', 'BITURBO', 'SUPERCHARGED') THEN 8.0
            WHEN token IN ('SEDAN', 'SUV', 'COUPE', 'HATCHBACK', 'PICKUP', 'VAN', 'WAGON', 'CONVERTIBLE', '2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS') THEN 5.0
            WHEN token IN ('2OCUP', '3OCUP', '4OCUP', '5OCUP', '6OCUP', '7OCUP', '8OCUP', '9OCUP') THEN 3.0
            WHEN token IN ('PREMIUM', 'TECH', 'SPORT', 'ADVANCE', 'ELITE', 'TOURING', 'LIMITED', 'A-SPEC', 'R-LINE', 'S-LINE', 'X-LINE', 'TYPE-R', 'TYPE-S', 'COMFORT', 'DYNAMIC', 'ELEGANCE', 'PRESTIGE') THEN 1.0
            ELSE 1.0
        END;
        weighted_total_b := weighted_total_b + token_weight;
    END LOOP;

    raw_coverage := GREATEST(
        CASE WHEN weighted_total_a > 0 THEN weighted_intersection / weighted_total_a ELSE 0 END,
        CASE WHEN weighted_total_b > 0 THEN weighted_intersection / weighted_total_b ELSE 0 END
    );

    -- Trim penalty (mantenido de v2.7.7)
    IF different_trims THEN
        IF is_same_insurer THEN
            penalized_score := raw_coverage * SAME_INSURER_TRIM_PENALTY;
        ELSE
            penalized_score := raw_coverage * CROSS_INSURER_TRIM_PENALTY;
        END IF;
    ELSE
        penalized_score := raw_coverage;
    END IF;

    RETURN QUERY SELECT
        CASE WHEN weighted_total_a > 0 THEN weighted_intersection / weighted_total_a ELSE 0 END,
        CASE WHEN weighted_total_b > 0 THEN weighted_intersection / weighted_total_b ELSE 0 END,
        raw_coverage,
        conflicts_detected,
        different_trims,
        penalized_score;
END;
$$;

-- ============================================================================
-- FUNCIÓN 8: calculate_jaccard_similarity
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
-- FUNCIÓN PRINCIPAL: procesar_batch_vehiculos v2.8.0 FINAL
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

    v_insurers_permitidos_crear TEXT[] := ARRAY['ZURICH', 'HDI'];

    -- Umbrales optimizados (mantenidos de v2.7.8)
    QUALITAS_TIER2_THRESHOLD CONSTANT NUMERIC := 0.45;
    TIER2_COVERAGE_THRESHOLD CONSTANT NUMERIC := 0.60;
    TIER2_SAME_INSURER_THRESHOLD CONSTANT NUMERIC := 0.88;
    TIER3_COVERAGE_THRESHOLD CONSTANT NUMERIC := 0.35;
    TIER3_JACCARD_THRESHOLD CONSTANT NUMERIC := 0.35;
    SHORT_VERSION_THRESHOLD CONSTANT INT := 4;
    SHORT_VERSION_COVERAGE_THRESHOLD CONSTANT NUMERIC := 0.55;

    is_minimal BOOLEAN; is_short_version BOOLEAN;
    adaptive_threshold NUMERIC; combined_score NUMERIC;
    batch_size INT;
BEGIN
    start_time := clock_timestamp();
    batch_size := jsonb_array_length(vehiculos_json);

    IF batch_size > 500 THEN
        RAISE WARNING 'Batch size % exceeds 500. Reduce batch size to avoid timeout.', batch_size;
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

                IF NOT coverage_result.has_conflicts THEN
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

            IF existing_record.version = v_version THEN
                matches := matches || jsonb_build_object('id', existing_record.id, 'score', 1.0, 'tier', 1, 'method', 'exact_match_cross');
                CONTINUE;
            END IF;

            is_minimal := is_minimal_version_match(v_tokens, existing_record.version_tokens_array);
            IF is_minimal THEN
                matches := matches || jsonb_build_object('id', existing_record.id, 'score', 0.95, 'tier', 2, 'method', 'minimal_version');
                CONTINUE;
            END IF;

            coverage_result := calculate_weighted_coverage_with_trim_penalty(v_tokens, existing_record.version_tokens_array, FALSE);

            IF NOT coverage_result.has_conflicts THEN
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
            IF jsonb_array_length(matches) > 1 THEN multi_match_count := multi_match_count + 1; END IF;

            FOR match_record IN SELECT * FROM jsonb_to_recordset(matches) AS (id BIGINT, score NUMERIC, tier INT, method TEXT)
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

-- ============================================================================
-- FIN - VERSIÓN v2.8.0 FINAL
-- ============================================================================
