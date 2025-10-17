-- ============================================================================
-- SISTEMA DE HOMOLOGACIÓN DE VEHÍCULOS - VERSIÓN 1.3.1
-- ============================================================================
-- Proyecto: Ukuvi - Catálogo Unificado de Vehículos
-- Propósito: Homologar versiones de vehículos de múltiples aseguradoras
-- Base: PostgreSQL con extensiones plpgsql
-- ============================================================================

TRUNCATE TABLE catalogo_homologado CASCADE;
ALTER SEQUENCE catalogo_homologado_id_seq RESTART WITH 1;

DROP FUNCTION IF EXISTS procesar_batch_vehiculos(JSONB);
DROP FUNCTION IF EXISTS clean_and_tokenize_version(TEXT);
DROP FUNCTION IF EXISTS calculate_weighted_coverage(TEXT[], TEXT[]);
DROP FUNCTION IF EXISTS normalize_token(TEXT);
DROP FUNCTION IF EXISTS is_minimal_version_match(TEXT[], TEXT[]);

-- ============================================================================
-- FUNCIÓN 1: normalize_token
-- ============================================================================
-- Propósito:
--   Normalizar tokens individuales a sus formas canónicas para garantizar
--   consistencia en la comparación de versiones entre aseguradoras.
--
-- Funcionamiento:
--   - Recibe un token (palabra) en cualquier formato
--   - Lo compara contra un catálogo de sinónimos conocidos
--   - Retorna la forma canónica estandarizada
--
-- Ejemplos:
--   'SED' → 'SEDAN'
--   '4CIL' → '4CIL' (ya está normalizado)
--   '495H' → '495HP' (normaliza unidades de potencia)
--   'AUTOMATICA' → 'AUTO'
--
-- Categorías normalizadas:
--   - Body styles (SEDAN, COUPE, SUV, etc.)
--   - Tipos de tracción (4WD, FWD, RWD, AWD)
--   - Tipos de propulsión (ELECTRIC, HYBRID, DIESEL, GASOLINA)
--   - Transmisión (AUTO, STD, CVT, DSG)
--   - Conteos (puertas, ocupantes, cilindros)
--   - Niveles de trim (SPORT, LUXURY, PREMIUM, etc.)
--   - Tecnología de motor (FSI, TSI, VTEC, TURBO)
--   - Ediciones especiales (GT, RS, AMG, NISMO)
-- ============================================================================
CREATE OR REPLACE FUNCTION normalize_token(token TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    CASE
        -- Body Styles
        WHEN token IN ('SED', 'SEDAN', 'SEDÁN') THEN RETURN 'SEDAN';
        WHEN token IN ('CP', 'COUPE', 'COUPÉ') THEN RETURN 'COUPE';
        WHEN token IN ('SW', 'STATION', 'WAGON', 'STATIONWAGON') THEN RETURN 'WAGON';
        WHEN token IN ('VAN', 'MINIVAN', 'MINIVÁN') THEN RETURN 'VAN';
        WHEN token IN ('CABRIO', 'CABRIOLET', 'CONVERTIBLE', 'DESCAPOTABLE') THEN RETURN 'CONVERTIBLE';
        WHEN token IN ('HB', 'HATCH', 'HATCHBACK') THEN RETURN 'HATCHBACK';
        WHEN token IN ('PICKUP', 'PICK-UP', 'PU') THEN RETURN 'PICKUP';
        WHEN token IN ('SUV', 'CROSSOVER') THEN RETURN 'SUV';
        
        -- Drive Types
        WHEN token IN ('4X4', '4WD', '4X2') THEN RETURN '4WD';
        WHEN token IN ('FWD', 'DELANTERA', 'TRACCIÓN DELANTERA') THEN RETURN 'FWD';
        WHEN token IN ('RWD', 'TRASERA', 'TRACCIÓN TRASERA') THEN RETURN 'RWD';
        WHEN token IN ('AWD', 'ALLWHEELDRIVE', 'TRACCIÓN INTEGRAL') THEN RETURN 'AWD';
        WHEN token IN ('2WD', '2X4') THEN RETURN '2WD';
        
        -- Propulsion Types
        WHEN token IN ('ELECTRIC', 'ELECTRICO', 'ELÉCTRICO', 'EV', 'BEV') THEN RETURN 'ELECTRIC';
        WHEN token IN ('HYBRID', 'HIBRIDO', 'HÍBRIDO', 'HEV', 'HYBRIDE') THEN RETURN 'HYBRID';
        WHEN token IN ('PHEV', 'PLUG-IN', 'PLUGIN') THEN RETURN 'PHEV';
        WHEN token IN ('MHEV', 'MILD', 'MILDHYBRID') THEN RETURN 'MHEV';
        WHEN token IN ('DIESEL', 'DSL', 'DIÉSEL', 'TDI', 'TDCI', 'CRDI', 'BLUETEC') THEN RETURN 'DIESEL';
        WHEN token IN ('GASOLINA', 'GASOLINE', 'GAS', 'PETROL', 'NAFTA') THEN RETURN 'GASOLINA';
        WHEN token IN ('GNV', 'GNC', 'CNG') THEN RETURN 'GNV';
        WHEN token IN ('GLP', 'LPG') THEN RETURN 'GLP';
        
        -- Transmission
        WHEN token IN ('AUT', 'AUT.', 'AUTOMATICA', 'AUTOMÁTICA', 'AUTOMATIC', 'AT', 'A') THEN RETURN 'AUTO';
        WHEN token IN ('STD', 'STANDARD', 'MANUAL', 'MAN', 'MT', 'M') THEN RETURN 'STD';
        WHEN token IN ('CVT', 'CONTINUOUSLY', 'VARIABLE') THEN RETURN 'CVT';
        WHEN token IN ('TIPTRONIC', 'TIP', 'SECUENCIAL') THEN RETURN 'TIPTRONIC';
        WHEN token IN ('DSG', 'PDK', 'DCT') THEN RETURN 'DSG';
        
        -- Door counts
        WHEN token IN ('2PTAS', '2P', '2-PUERTAS', '2 PUERTAS') THEN RETURN '2PUERTAS';
        WHEN token IN ('3PTAS', '3P', '3-PUERTAS', '3 PUERTAS') THEN RETURN '3PUERTAS';
        WHEN token IN ('4PTAS', '4P', '4-PUERTAS', '4 PUERTAS') THEN RETURN '4PUERTAS';
        WHEN token IN ('5PTAS', '5P', '5-PUERTAS', '5 PUERTAS') THEN RETURN '5PUERTAS';
        
        -- Occupancy
        WHEN token IN ('2OCUP', '2 OCUP', '2OCUPANTES', '2 OCUPANTES') THEN RETURN '2OCUP';
        WHEN token IN ('3OCUP', '3 OCUP', '3OCUPANTES', '3 OCUPANTES') THEN RETURN '3OCUP';
        WHEN token IN ('4OCUP', '4 OCUP', '4OCUPANTES', '4 OCUPANTES') THEN RETURN '4OCUP';
        WHEN token IN ('5OCUP', '5 OCUP', '5OCUPANTES', '5 OCUPANTES', '05 OCUP', '05OCUP') THEN RETURN '5OCUP';
        WHEN token IN ('6OCUP', '6 OCUP', '6OCUPANTES', '6 OCUPANTES') THEN RETURN '6OCUP';
        WHEN token IN ('7OCUP', '7 OCUP', '7OCUPANTES', '7 OCUPANTES', '07 OCUP', '07OCUP') THEN RETURN '7OCUP';
        WHEN token IN ('8OCUP', '8 OCUP', '8OCUPANTES', '8 OCUPANTES') THEN RETURN '8OCUP';
        
        -- Cylinder counts
        WHEN token IN ('3CIL', '3 CIL', 'L3', '3-CIL') THEN RETURN '3CIL';
        WHEN token IN ('4CIL', '4 CIL', 'L4', '4-CIL', 'I4') THEN RETURN '4CIL';
        WHEN token IN ('5CIL', '5 CIL', 'L5', '5-CIL') THEN RETURN '5CIL';
        WHEN token IN ('6CIL', '6 CIL', 'V6', '6-CIL', 'L6', 'H6') THEN RETURN '6CIL';
        WHEN token IN ('8CIL', '8 CIL', 'V8', '8-CIL') THEN RETURN '8CIL';
        WHEN token IN ('10CIL', '10 CIL', 'V10', '10-CIL') THEN RETURN '10CIL';
        WHEN token IN ('12CIL', '12 CIL', 'V12', '12-CIL', 'W12') THEN RETURN '12CIL';
        
        -- Trim Levels
        WHEN token IN ('ST', 'SPORT', 'DEPORTIVO', 'SPORTIVE') THEN RETURN 'SPORT';
        WHEN token IN ('LUX', 'LUXURY', 'LUJO', 'LUXE') THEN RETURN 'LUXURY';
        WHEN token IN ('BASE', 'ENTRY', 'BÁSICO') THEN RETURN 'BASE';
        WHEN token IN ('PREM', 'PREMIUM', 'PREMIUN') THEN RETURN 'PREMIUM';
        WHEN token IN ('PLATINUM', 'PLAT', 'PLATINO') THEN RETURN 'PLATINUM';
        WHEN token IN ('T', 'TOURING', 'TOUR') THEN RETURN 'TOURING';
        WHEN token IN ('ADVANCE', 'ADV', 'AVANZADO') THEN RETURN 'ADVANCE';
        WHEN token IN ('EXCL', 'EXCLUSIVE', 'EXCLUSIVO') THEN RETURN 'EXCLUSIVE';
        WHEN token IN ('SENSE', 'SENSING') THEN RETURN 'SENSE';
        WHEN token IN ('LTD', 'LIMITED', 'LIMITADO') THEN RETURN 'LIMITED';
        WHEN token IN ('SR', 'SUPER') THEN RETURN 'SR';
        WHEN token IN ('ELITE', 'ÉLITE') THEN RETURN 'ELITE';
        WHEN token IN ('ELEGANCE', 'ELEGANCIA') THEN RETURN 'ELEGANCE';
        WHEN token IN ('COMFORT', 'CONFORT') THEN RETURN 'COMFORT';
        WHEN token IN ('HIGHLINE', 'HIGH-LINE', 'HL') THEN RETURN 'HIGHLINE';
        WHEN token IN ('TRENDLINE', 'TREND-LINE', 'TL') THEN RETURN 'TRENDLINE';
        WHEN token IN ('COMFORTLINE', 'COMFORT-LINE', 'CL') THEN RETURN 'COMFORTLINE';
        
        -- Engine Technology
        WHEN token IN ('FSI', 'FUELSTRATIFIEDINJECTION') THEN RETURN 'FSI';
        WHEN token IN ('TSI', 'TURBOSTRATIFIEDINJECTION', 'TFSI', 'TURBOFSI') THEN RETURN 'TSI';
        WHEN token IN ('TDI', 'TURBODIESEL') THEN RETURN 'TDI';
        WHEN token IN ('CGI', 'CHARGEDGASOLINE') THEN RETURN 'CGI';
        WHEN token IN ('VTEC', 'V-TEC') THEN RETURN 'VTEC';
        WHEN token IN ('TURBO', 'TURBOCHARGED') THEN RETURN 'TURBO';
        WHEN token IN ('BITURBO', 'BI-TURBO', 'TWIN-TURBO', 'TWINTURBO') THEN RETURN 'BITURBO';
        WHEN token IN ('SUPERCHARGED', 'SUPER', 'SC') THEN RETURN 'SUPERCHARGED';
        
        -- Performance/Special Editions
        WHEN token IN ('GT', 'GRAN TURISMO') THEN RETURN 'GT';
        WHEN token IN ('GTS', 'GRAN TURISMO SPORT') THEN RETURN 'GTS';
        WHEN token IN ('RS', 'RENNSPORT') THEN RETURN 'RS';
        WHEN token IN ('AMG', 'AUFRECHT MELCHER GROẞASPACH') THEN RETURN 'AMG';
        WHEN token IN ('M', 'MOTORSPORT') THEN RETURN 'M';
        WHEN token IN ('NISMO', 'NISSAN MOTORSPORT') THEN RETURN 'NISMO';
        WHEN token IN ('TRD', 'TOYOTA RACING DEVELOPMENT') THEN RETURN 'TRD';
        WHEN token IN ('STI', 'SUBARU TECNICA INTERNATIONAL') THEN RETURN 'STI';
        WHEN token IN ('TYPE-R', 'TYPER', 'TYPE R') THEN RETURN 'TYPER';
        
        -- HP/Power notation - normaliza diferentes formatos a HP estándar
        WHEN token SIMILAR TO '[0-9]+H$' THEN RETURN REPLACE(token, 'H', 'HP');
        WHEN token SIMILAR TO '[0-9]+CP$' THEN RETURN REPLACE(token, 'CP', 'HP');
        WHEN token SIMILAR TO '[0-9]+CV$' THEN RETURN REPLACE(token, 'CV', 'HP');
        WHEN token SIMILAR TO '[0-9]+ HP$' THEN RETURN REPLACE(token, ' HP', 'HP');
        WHEN token SIMILAR TO '[0-9]+ H$' THEN RETURN REPLACE(REPLACE(token, ' H', 'HP'), 'H', 'HP');
        
        -- Engine displacement - preserva decimales significativos
        WHEN token SIMILAR TO '[0-9]+\.[0-9]+ L$' THEN RETURN REPLACE(token, ' L', 'L');
        WHEN token SIMILAR TO '[0-9]+\.[0-9]+LT$' THEN RETURN REPLACE(token, 'LT', 'L');
        WHEN token ~ '^[0-9]+\.0L$' THEN RETURN token;
        
        ELSE RETURN token;
    END CASE;
END;
$$;

-- ============================================================================
-- FUNCIÓN 2: clean_and_tokenize_version
-- ============================================================================
-- Propósito:
--   Convertir una cadena de versión cruda en un array limpio de tokens
--   normalizados, listos para comparación y matching.
--
-- Proceso de limpieza:
--   1. Conversión a mayúsculas para consistencia
--   2. Preservación de guiones en trims conocidos (A-SPEC, TYPE-R)
--   3. Eliminación de caracteres especiales y delimitadores
--   4. Rejunción de designaciones separadas (M 50 IA → M50IA)
--   5. Tokenización por espacios
--   6. Normalización de cada token individual
--   7. Validación de números de puertas realistas (2-10)
--   8. Filtrado de tokens de ruido (features genéricos)
--   9. Eliminación de duplicados
--
-- Tokens de ruido eliminados:
--   - Tamaños de rueda (R13-R25, RA13-RA25)
--   - Descriptores temporales (NUEVO, NEW)
--   - Sistemas de seguridad estándar (ABS, EBD, ESP)
--   - Features genéricos (AC, DH, DA, SD, VP, VT)
--   - Números sueltos menores a 100
--   - Preposiciones y artículos
--   - Materiales genéricos (MADERA, LEATHER)
--
-- Ejemplo:
--   Input:  "NUEVO A-SPEC SUV 190HP EBD 5 PUERTAS"
--   Output: ['A-SPEC', 'SUV', '190HP', '5PUERTAS']
-- ============================================================================
CREATE OR REPLACE FUNCTION clean_and_tokenize_version(p_version TEXT)
RETURNS TEXT[]
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
    noise_tokens TEXT[] := ARRAY[
        'R13', 'R14', 'R15', 'R16', 'R17', 'R18', 'R19', 'R20', 'R21', 'R22', 'R23', 'R24', 'R25',
        'RA13', 'RA14', 'RA15', 'RA16', 'RA17', 'RA18', 'RA19', 'RA20', 'RA21', 'RA22', 'RA23', 'RA24', 'RA25',
        'RA-13', 'RA-14', 'RA-15', 'RA-16', 'RA-17', 'RA-18', 'RA-19', 'RA-20',
        '0TON', '0.5TON', '1TON', '1.5TON', '2TON', '2.5TON', '3TON', '3.5TON', '4TON',
        '0 TON', '1 TON', '2 TON', '3 TON',
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 
        'DE', 'LA', 'EL', 'LOS', 'LAS', 'CON', 'SIN', 'PARA', 'EN', 'AL',
        'THE', 'OF', 'WITH', 'WITHOUT', 'FOR', 'IN', 'AT',
        'NUEVO', 'NEW', 'NUEVA',
        'ABS', 'EBD', 'ESP', 'VSC', 'TCS', 'DSC',
        'AIRBAG', 'CLIMATIZADOR',
        'AC', 'A/C', 'AIRE', 'AA',
        'DH', 'DA', 'VE', 'VP', 'EE',
        'SD', 'V', 'P', 'T',
        'MADERA', 'WOOD', 'LEATHER', 'CUERO', 'PIEL',
        'BA', 'CA', 'CE', 'CD', 'RA',
        'PAQ', 'PKG', 'PACKAGE', 'PAQUETE', 'LINE', 'LINEA', 'PLUS',
        'LT', 'LTR', 'MTR', 'MT'
    ];
    
    known_hyphenated_trims TEXT[] := ARRAY[
        'A-SPEC', 'TYPE-R', 'E-TRON', 'I-PACE', 'X-LINE', 'S-LINE'
    ];
    
    cleaned_version TEXT;
    raw_tokens TEXT[];
    final_tokens TEXT[] := ARRAY[]::TEXT[];
    token TEXT;
    normalized_token TEXT;
    door_number INT;
    trim TEXT;
BEGIN
    IF p_version IS NULL OR trim(p_version) = '' THEN
        RETURN ARRAY[]::TEXT[];
    END IF;
    
    cleaned_version := upper(trim(p_version));
    
    -- Preservar guiones en trims conocidos usando marcador temporal
    FOREACH trim IN ARRAY known_hyphenated_trims LOOP
        cleaned_version := replace(cleaned_version, trim, replace(trim, '-', '§'));
    END LOOP;
    
    -- Limpiar delimitadores y espacios múltiples
    cleaned_version := regexp_replace(cleaned_version, '[,;/|]', ' ', 'g');
    cleaned_version := regexp_replace(cleaned_version, '\s+', ' ', 'g');
    
    -- Rejuntar designaciones BMW/Mustang: "M 50 IA" → "M50IA"
    cleaned_version := regexp_replace(cleaned_version, 
        '([A-Z])\s+(\d{2,3})\s*([A-Z]*)', '\1\2\3', 'g');
    
    -- Eliminar guiones entre alfanuméricos
    cleaned_version := regexp_replace(cleaned_version, '(\d+)-([A-Z]+)', '\1\2', 'g');
    cleaned_version := regexp_replace(cleaned_version, '([A-Z]+)-([A-Z]+)', '\1\2', 'g');
    
    -- Restaurar guiones en trims preservados
    cleaned_version := replace(cleaned_version, '§', '-');
    
    -- Tokenizar por espacios
    raw_tokens := string_to_array(cleaned_version, ' ');
    
    -- Normalizar y filtrar cada token
    FOREACH token IN ARRAY raw_tokens LOOP
        IF token IS NOT NULL AND length(token) > 0 THEN
            -- Validar números de puertas (solo 2-10 son realistas)
            IF token SIMILAR TO '[0-9]+PUERTAS' THEN
                door_number := substring(token FROM '^([0-9]+)')::INT;
                IF door_number NOT BETWEEN 2 AND 10 THEN
                    CONTINUE;
                END IF;
            END IF;
            
            normalized_token := normalize_token(token);
            
            IF NOT (normalized_token = ANY(noise_tokens)) THEN
                final_tokens := array_append(final_tokens, normalized_token);
            END IF;
        END IF;
    END LOOP;
    
    -- Eliminar duplicados preservando orden
    final_tokens := ARRAY(SELECT DISTINCT unnest(final_tokens));
    
    RETURN final_tokens;
END;
$$;

-- ============================================================================
-- FUNCIÓN 3: is_minimal_version_match
-- ============================================================================
-- Propósito:
--   Detectar si dos versiones son compatibles cuando una es versión mínima
--   (≤3 tokens) y debe matchear con una versión más completa.
--
-- Funcionamiento:
--   1. Identifica si alguna versión tiene ≤3 tokens (versión mínima)
--   2. Si ninguna es mínima, no aplica esta lógica (retorna FALSE)
--   3. Si ambas son mínimas, deben ser idénticas
--   4. Si solo una es mínima:
--      a. Filtra body styles opcionales (SEDAN, SUV, COUPE, etc.)
--      b. Verifica que TODOS los tokens de la mínima estén en la completa
--      c. Valida que no haya conflictos críticos (tracción/propulsión)
--
-- Tokens opcionales (ignorados en comparación):
--   - Body styles: SEDAN, SUV, COUPE, HATCHBACK, WAGON, etc.
--   Estos no afectan el match porque son descriptivos, no diferenciadores
--
-- Tokens críticos (deben ser consistentes):
--   - Tracción: AWD, 4WD, 2WD, FWD, RWD
--   - Propulsión: ELECTRIC, DIESEL, GASOLINA, GNV, GLP
--   Si hay conflicto en estos tokens, NO hay match
--
-- Ejemplos de matching:
--   ["5PUERTAS"] vs ["5PUERTAS", "4CIL", "2.0L", "SEDAN"] → MATCH
--   ["A-SPEC"] vs ["A-SPEC", "SUV", "190HP", "1.5L"] → MATCH
--   ["A-SPEC", "2.0L"] vs ["A-SPEC", "2.0L", "4CIL", "AUTO"] → MATCH
--   ["PREMIUM"] vs ["PREMIUM", "SEDAN", "150HP"] → MATCH
--   ["4WD"] vs ["FWD", "SEDAN"] → NO MATCH (conflicto tracción)
--
-- Retorna:
--   TRUE si es un match válido de versión mínima
--   FALSE si no aplica esta lógica o hay conflictos
-- ============================================================================
CREATE OR REPLACE FUNCTION is_minimal_version_match(
    tokens_a TEXT[],
    tokens_b TEXT[]
)
RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
    -- Tokens que pueden generar conflictos críticos
    critical_conflict_tokens TEXT[] := ARRAY[
        'AWD', '4WD', '2WD', 'FWD', 'RWD',
        'ELECTRIC', 'DIESEL', 'GASOLINA', 'GNV', 'GLP'
    ];
    
    is_a_minimal BOOLEAN;
    is_b_minimal BOOLEAN;
    tokens_a_filtered TEXT[];
    tokens_b_filtered TEXT[];
    tokens_a_critical TEXT[];
    tokens_b_critical TEXT[];
    minimal_tokens TEXT[];
    complete_tokens TEXT[];
    token TEXT;
BEGIN
    -- Determinar si alguna versión es mínima (≤3 tokens)
    is_a_minimal := (array_length(tokens_a, 1) <= 3);
    is_b_minimal := (array_length(tokens_b, 1) <= 3);
    
    -- Si ninguna es mínima, no aplica esta lógica
    IF NOT (is_a_minimal OR is_b_minimal) THEN
        RETURN FALSE;
    END IF;
    
    -- Si ambas son mínimas, deben ser idénticas
    IF is_a_minimal AND is_b_minimal THEN
        RETURN tokens_a = tokens_b;
    END IF;
    
    -- Identificar cuál es la versión mínima
    IF is_a_minimal THEN
        minimal_tokens := tokens_a;
        complete_tokens := tokens_b;
    ELSE
        minimal_tokens := tokens_b;
        complete_tokens := tokens_a;
    END IF;
    
    tokens_a_filtered := ARRAY(
        SELECT unnest(tokens_a) 
    );
    tokens_b_filtered := ARRAY(
        SELECT unnest(tokens_b) 
    );
    
    -- Validar que TODOS los tokens relevantes de la mínima estén en la completa
    IF is_a_minimal THEN
        FOREACH token IN ARRAY tokens_a_filtered LOOP
            IF NOT (token = ANY(tokens_b_filtered)) THEN
                RETURN FALSE;
            END IF;
        END LOOP;
    ELSE
        FOREACH token IN ARRAY tokens_b_filtered LOOP
            IF NOT (token = ANY(tokens_a_filtered)) THEN
                RETURN FALSE;
            END IF;
        END LOOP;
    END IF;
    
    -- Verificar que no haya conflictos en tokens críticos
    tokens_a_critical := ARRAY(
        SELECT unnest(tokens_a) INTERSECT SELECT unnest(critical_conflict_tokens)
    );
    tokens_b_critical := ARRAY(
        SELECT unnest(tokens_b) INTERSECT SELECT unnest(critical_conflict_tokens)
    );
    
    -- Si ambos tienen critical tokens y no son compatibles, hay conflicto
    IF array_length(tokens_a_critical, 1) > 0 AND array_length(tokens_b_critical, 1) > 0 THEN
        IF NOT (tokens_a_critical <@ tokens_b_critical OR tokens_b_critical <@ tokens_a_critical) THEN
            RETURN FALSE;
        END IF;
    END IF;
    
    RETURN TRUE;
END;
$$;

-- ============================================================================
-- FUNCIÓN 4: calculate_weighted_coverage
-- ============================================================================
-- Propósito:
--   Calcular la similitud entre dos versiones usando pesos diferenciados
--   para tokens según su importancia en la diferenciación de vehículos.
--
-- Sistema de pesos:
--   - Critical tokens (peso 5.0): Tracción, body style, propulsión
--     Estos definen características fundamentales del vehículo
--   - High impact tokens (peso 2.0): Cilindros, ocupantes, trims principales
--     Estos distinguen claramente entre versiones
--   - Moderate tokens (peso 1.5): Tecnología de motor, trims secundarios
--     Agregan especificidad pero no son críticos
--   - Normal tokens (peso 1.0): Resto de especificaciones
--
-- Cálculo de cobertura:
--   1. Para cada token en A, suma su peso al total_a
--   2. Si el token también está en B, suma su peso a la intersección
--   3. Repite para tokens en B
--   4. Calcula coverage_a_in_b = intersección / total_a
--   5. Calcula coverage_b_in_a = intersección / total_b
--   6. max_coverage = máximo de ambas coberturas
--
-- Detección de conflictos:
--   Se marca has_conflicts = TRUE si:
--   - Ambas versiones tienen critical tokens diferentes
--   - Por ejemplo: una tiene 4WD y la otra FWD (incompatible)
--   - O una tiene DIESEL y la otra GASOLINA (incompatible)
--
-- Retorna:
--   - coverage_a_in_b: porcentaje de A que está en B
--   - coverage_b_in_a: porcentaje de B que está en A
--   - max_coverage: cobertura máxima entre ambas
--   - has_conflicts: TRUE si hay tokens críticos contradictorios
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_weighted_coverage(
    tokens_a TEXT[],
    tokens_b TEXT[]
)
RETURNS TABLE(
    coverage_a_in_b NUMERIC,
    coverage_b_in_a NUMERIC,
    max_coverage NUMERIC,
    has_conflicts BOOLEAN
)
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
    critical_tokens TEXT[] := ARRAY[
        -- Drivetrain
        'AWD', '4WD', '2WD', 'FWD', 'RWD', 'XDRIVE', 'SDRIVE', 'QUATTRO',
        -- Door count
        '2PUERTAS', '3PUERTAS', '4PUERTAS', '5PUERTAS', '6PUERTAS', '7PUERTAS', '8PUERTAS',
        -- Body style
        'SEDAN', 'SUV', 'COUPE', 'CONVERTIBLE', 'CABRIOLET', 'ROADSTER',
        'WAGON', 'PICKUP', 'MINIVAN', 'HATCHBACK', 'VAN', 'SPORTBACK',
        -- Propulsion type
        'ELECTRIC', 'ELECTRICO', 'EV', 'BEV',
        'HYBRID', 'HIBRIDO', 'HEV', 'PHEV', 'MHEV', 'MILD',
        'DIESEL', 'TDI', 'TDCI', 'CRDI', 'BLUETEC',
        'GAS', 'GASOLINA', 'GNV', 'GLP',
        'TURBO', 'BITURBO', 'TRITURBO', 'SUPERCHARGED',
        -- Trim levels 
        'PREMIUM', 'LUXURY', 'SPORT', 'LIMITED', 'ELITE', 'EXCLUSIVE', 'LUJO',
        'TECH', 'TECHNOLOGY', 'A-SPEC', 'TYPE-S', 'TYPE-R', 'TYPE-F', 'S-LINE', 'R-LINE', 'R-DESIGN',
        'ADVANCE', 'TOURING', 'EX-L', 'LX', 'EX', 'SX', 'SEL', 'SE', 'SLT', 'SXT',
        'BASE', 'COMFORT', 'ELEGANCE', 'TITANIUM', 'PLATINIUM', 'PLATINUM',
        'GT', 'GTI', 'GTS', 'RS', 'AMG', 'M', 'SS', 'RT', 'SRT',
        'LARAMIE', 'DENALI', 'REBEL', 'RAPTOR', 'TRD', 'RUBICON', 'WRANGLER',
        'NISMO', 'STI', 'WRX', 'F-SPORT', 'FSPORT',
        'HIGHLINE', 'COMFORTLINE', 'TRENDLINE', 'SPORTLINE', 'TRENDY',
        'COSMOPOLITAN', 'COSMOPOLITA', 'ESPECIAL', 'SPECIAL', 'EDITION',
        'ANNIVERSARY', 'ANIVERSARIO', 'SIGNATURE', 'RESERVE',
        'PRESTIGE', 'PROGRESSIVE', 'ESSENTIAL', 'EXCELLENCE',
        'XL', 'XLT', 'LS', 'LT', 'LTZ', 'GL', 'CLASSIC', 'CUSTOM',
        'ADVENTURE', 'UNLIMITED', 'GRAND', 'CHEROKEE',
        'DYNAMIC', 'SELECT', 'COMPETITION', 'AMBIENTE', 'COUNTRY'
    ];

    high_impact_tokens TEXT[] := ARRAY[
        '3CIL', '4CIL', '5CIL', '6CIL', '8CIL', '10CIL', '12CIL', '16CIL',
        '2OCUP', '3OCUP', '4OCUP', '5OCUP', '6OCUP', '7OCUP', '8OCUP',
        '9OCUP', '10OCUP', '11OCUP', '12OCUP', '13OCUP', '14OCUP', '15OCUP'
    ];
    
    moderate_tokens TEXT[] := ARRAY[
        'CGI', 'FSI', 'TSI', 'TFSI', 'VTEC',
        'LINE', 'PLUS'
    ];
    
    propulsion_tokens TEXT[] := ARRAY[
        'ELECTRIC', 'ELECTRICO', 'EV', 'BEV', 
        'HYBRID', 'HIBRIDO', 'HEV', 'PHEV', 'MHEV', 
        'DIESEL', 'TDI', 'TDCI', 'CRDI', 'BLUETEC', 
        'GAS', 'GASOLINA', 'GNV', 'GLP'
    ];
    
    weighted_intersection NUMERIC := 0;
    weighted_total_a NUMERIC := 0;
    weighted_total_b NUMERIC := 0;
    critical_in_a TEXT[];
    critical_in_b TEXT[];
    propulsion_in_a TEXT[];
    propulsion_in_b TEXT[];
    token TEXT;
    token_weight NUMERIC;
BEGIN
    IF tokens_a IS NULL OR tokens_b IS NULL OR 
       array_length(tokens_a, 1) IS NULL OR array_length(tokens_b, 1) IS NULL THEN
        RETURN QUERY SELECT 0::NUMERIC, 0::NUMERIC, 0::NUMERIC, TRUE;
        RETURN;
    END IF;

    -- Calcular peso total de A y su intersección con B
    FOREACH token IN ARRAY tokens_a LOOP
        IF token = ANY(critical_tokens) THEN
            token_weight := 5.0;
        ELSIF token = ANY(high_impact_tokens) THEN
            token_weight := 2.0;
        ELSIF token = ANY(moderate_tokens) THEN
            token_weight := 1.5;
        ELSE
            token_weight := 1.0;
        END IF;
        
        weighted_total_a := weighted_total_a + token_weight;
        
        IF token = ANY(tokens_b) THEN
            weighted_intersection := weighted_intersection + token_weight;
        END IF;
    END LOOP;
    
    -- Calcular peso total de B
    FOREACH token IN ARRAY tokens_b LOOP
        IF token = ANY(critical_tokens) THEN
            token_weight := 5.0;
        ELSIF token = ANY(high_impact_tokens) THEN
            token_weight := 2.0;
        ELSIF token = ANY(moderate_tokens) THEN
            token_weight := 1.5;
        ELSE
            token_weight := 1.0;
        END IF;
        
        weighted_total_b := weighted_total_b + token_weight;
    END LOOP;
    
    -- Calcular coberturas
    coverage_a_in_b := CASE 
        WHEN weighted_total_a > 0 THEN weighted_intersection / weighted_total_a 
        ELSE 0 
    END;
    
    coverage_b_in_a := CASE 
        WHEN weighted_total_b > 0 THEN weighted_intersection / weighted_total_b 
        ELSE 0 
    END;
    
    max_coverage := GREATEST(coverage_a_in_b, coverage_b_in_a);
    
    -- Detectar conflictos en tokens críticos
    critical_in_a := ARRAY(SELECT unnest(tokens_a) INTERSECT SELECT unnest(critical_tokens));
    critical_in_b := ARRAY(SELECT unnest(tokens_b) INTERSECT SELECT unnest(critical_tokens));
    
    has_conflicts := (
        array_length(critical_in_a, 1) > 0 AND
        array_length(critical_in_b, 1) > 0 AND
        NOT (critical_in_a <@ critical_in_b OR critical_in_b <@ critical_in_a)
    );
    
    -- Validar conflictos específicos de propulsión
    IF NOT has_conflicts THEN
        propulsion_in_a := ARRAY(SELECT unnest(tokens_a) INTERSECT SELECT unnest(propulsion_tokens));
        propulsion_in_b := ARRAY(SELECT unnest(tokens_b) INTERSECT SELECT unnest(propulsion_tokens));
        
        IF array_length(propulsion_in_a, 1) > 0 AND array_length(propulsion_in_b, 1) > 0 THEN
            has_conflicts := NOT (
                propulsion_in_a <@ propulsion_in_b OR 
                propulsion_in_b <@ propulsion_in_a OR
                ('HYBRID' = ANY(propulsion_in_a) AND 'HEV' = ANY(propulsion_in_b)) OR
                ('HYBRID' = ANY(propulsion_in_b) AND 'HEV' = ANY(propulsion_in_a)) OR
                ('PHEV' = ANY(propulsion_in_a) AND 'HYBRID' = ANY(propulsion_in_b)) OR
                ('PHEV' = ANY(propulsion_in_b) AND 'HYBRID' = ANY(propulsion_in_a)) OR
                ('MHEV' = ANY(propulsion_in_a) AND 'HYBRID' = ANY(propulsion_in_b)) OR
                ('MHEV' = ANY(propulsion_in_b) AND 'HYBRID' = ANY(propulsion_in_a))
            );
        END IF;
    END IF;
    
    RETURN QUERY SELECT coverage_a_in_b, coverage_b_in_a, max_coverage, has_conflicts;
END;
$$;

-- ============================================================================
-- FUNCIÓN 5: procesar_batch_vehiculos (Función Principal RPC)
-- ============================================================================
-- Propósito:
--   Procesar un batch de vehículos en formato JSON y homologarlos contra
--   el catálogo existente usando múltiples estrategias de matching.
--
-- Estrategias de matching (en orden de evaluación):
--
--   TIER 1 - Exact Match (score 1.0):
--   - La versión es idéntica carácter por carácter
--   - Aplicable tanto same_insurer como cross_insurer
--
--   TIER 2 - Minimal Version Match (score 0.95):
--   - Una versión tiene ≤3 tokens (versión mínima)
--   - Todos los tokens de la mínima están en la completa
--   - No hay conflictos críticos (tracción/propulsión)
--   - Se evalúa PRIMERO antes que weighted coverage
--   - Ejemplos: "A-SPEC" matchea con "A-SPEC SUV 190HP..."
--              "5PUERTAS" matchea con "5PUERTAS 4CIL 2.0L..."
--
--   TIER 2 - Subset Match (score = max_coverage):
--   - Una versión es subconjunto puro de la otra (coverage 100%)
--   - Al menos una tiene ≤5 tokens
--   - No hay conflictos críticos
--
--   TIER 2 - Weighted Coverage (score = max_coverage):
--   - Cobertura ponderada >= threshold
--   - Same insurer: 75% threshold
--   - Cross insurer: 70% threshold
--   - No hay conflictos críticos
--
--   TIER 3 - Hybrid Coverage + Jaccard (score = promedio):
--   - Solo para cross_insurer
--   - Coverage >= 50% + Jaccard >= 40%
--   - Score final es el promedio de ambos
--
-- Manejo de "origin":
--   - origin = TRUE: solo para el insurer que INSERTÓ el vehículo (primer registro)
--   - origin = FALSE: para todos los insurers que MATCHEAN después
--
-- Umbrales configurables:
--   - TIER1_COVERAGE_THRESHOLD: 90%
--   - TIER2_SAME_INSURER_THRESHOLD: 75%
--   - TIER2_COVERAGE_THRESHOLD: 70%
--   - TIER3_COVERAGE_THRESHOLD: 50%
--   - TIER3_JACCARD_THRESHOLD: 40%
--
-- Input (JSON):
--   Array de objetos con: hash_comercial, marca, modelo, anio, transmision,
--   version_limpia, version_original, origen_aseguradora, id_original
--
-- Output (TABLE):
--   - insertados: nuevos registros creados
--   - actualizados: registros existentes actualizados
--   - tier1_matches: matches exactos
--   - tier2_matches: matches por coverage/subset/minimal
--   - tier3_matches: matches híbridos
--   - tier4_flagged: (reservado para uso futuro)
--   - processing_time_ms: tiempo de procesamiento en milisegundos
-- ============================================================================
CREATE OR REPLACE FUNCTION procesar_batch_vehiculos(
    vehiculos_json JSONB
)
RETURNS TABLE(
    insertados INT,
    actualizados INT,
    tier1_matches INT,
    tier2_matches INT,
    tier3_matches INT,
    tier4_flagged INT,
    processing_time_ms NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_record JSONB;
    v_hash TEXT;
    v_version TEXT;
    v_tokens TEXT[];
    v_origen TEXT;
    existing_record RECORD;
    match_tier INT;
    coverage_result RECORD;
    jaccard_score NUMERIC;
    start_time TIMESTAMP;

    insert_count INT := 0;
    update_count INT := 0;
    tier1_count INT := 0;
    tier2_count INT := 0;
    tier3_count INT := 0;
    tier4_count INT := 0;

    matches JSONB := '[]'::JSONB;
    matchinfo JSONB;
    match_rec RECORD;

    TIER1_COVERAGE_THRESHOLD CONSTANT NUMERIC := 0.90;
    TIER2_SAME_INSURER_THRESHOLD CONSTANT NUMERIC := 0.80;
    TIER2_COVERAGE_THRESHOLD CONSTANT NUMERIC := 0.70;
    TIER3_COVERAGE_THRESHOLD CONSTANT NUMERIC := 0.40;
    TIER3_JACCARD_THRESHOLD CONSTANT NUMERIC := 0.40;
    
    is_subset_match BOOLEAN;
    is_minimal_version BOOLEAN;
    is_minimal_match BOOLEAN;
BEGIN
    start_time := clock_timestamp();
    
    FOR v_record IN SELECT * FROM jsonb_array_elements(vehiculos_json)
    LOOP
        v_hash := v_record->>'hash_comercial';
        v_version := v_record->>'version_limpia';
        v_origen := v_record->>'origen_aseguradora';
        v_tokens := clean_and_tokenize_version(v_version);
        matches := '[]'::jsonb;

        FOR existing_record IN
            SELECT
                id,
                version,
                version_tokens_array,
                disponibilidad,
                (disponibilidad ? v_origen) AS same_insurer
            FROM catalogo_homologado
            WHERE hash_comercial = v_hash
        LOOP
            IF existing_record.same_insurer THEN
                -- Same Insurer
                IF existing_record.version = v_version THEN
                    matchinfo := jsonb_build_object(
                        'id', existing_record.id,
                        'aseguradora', v_origen,
                        'score', 1.0,
                        'tier', 1,
                        'same_insurer', TRUE,
                        'metodo_match', 'exact_match_same_insurer'
                    );
                    matches := matches || to_jsonb(matchinfo);
                    tier1_count := tier1_count + 1;
                    CONTINUE;
                END IF;
                
                is_minimal_match := is_minimal_version_match(
                    v_tokens, 
                    existing_record.version_tokens_array
                );
                
                IF is_minimal_match THEN
                    matchinfo := jsonb_build_object(
                        'id', existing_record.id,
                        'aseguradora', v_origen,
                        'score', 0.95,
                        'tier', 2,
                        'same_insurer', TRUE,
                        'metodo_match', 'minimal_version_same_insurer'
                    );
                    matches := matches || to_jsonb(matchinfo);
                    tier2_count := tier2_count + 1;
                    CONTINUE;
                END IF;
                
                coverage_result := calculate_weighted_coverage(
                    v_tokens,
                    existing_record.version_tokens_array
                );
                
                is_subset_match := (
                    coverage_result.coverage_a_in_b = 1.0 OR
                    coverage_result.coverage_b_in_a = 1.0
                );
                
                is_minimal_version := (
                    array_length(v_tokens, 1) <= 5 OR 
                    array_length(existing_record.version_tokens_array, 1) <= 5
                );
                
                IF is_subset_match AND is_minimal_version AND NOT coverage_result.has_conflicts THEN
                    matchinfo := jsonb_build_object(
                        'id', existing_record.id,
                        'aseguradora', v_origen,
                        'score', coverage_result.max_coverage,
                        'tier', 2,
                        'same_insurer', TRUE,
                        'metodo_match', 'subset_match_same_insurer'
                    );
                    matches := matches || to_jsonb(matchinfo);
                    tier2_count := tier2_count + 1;
                    CONTINUE;
                END IF;
                
                IF coverage_result.max_coverage >= TIER2_SAME_INSURER_THRESHOLD
                   AND NOT coverage_result.has_conflicts
                THEN
                    matchinfo := jsonb_build_object(
                        'id', existing_record.id,
                        'aseguradora', v_origen,
                        'score', coverage_result.max_coverage,
                        'tier', 2,
                        'same_insurer', TRUE,
                        'metodo_match', 'weighted_coverage_same_insurer'
                    );
                    matches := matches || to_jsonb(matchinfo);
                    tier2_count := tier2_count + 1;
                    CONTINUE;
                END IF;
                
            ELSE
                -- Cross Insurer
                IF existing_record.version = v_version THEN
                    matchinfo := jsonb_build_object(
                        'id', existing_record.id,
                        'aseguradora', v_origen,
                        'score', 1.0,
                        'tier', 1,
                        'same_insurer', FALSE,
                        'metodo_match', 'exact_match_cross_insurer'
                    );
                    matches := matches || to_jsonb(matchinfo);
                    tier1_count := tier1_count + 1;
                    CONTINUE;
                END IF;
                
                is_minimal_match := is_minimal_version_match(
                    v_tokens, 
                    existing_record.version_tokens_array
                );
                
                IF is_minimal_match THEN
                    matchinfo := jsonb_build_object(
                        'id', existing_record.id,
                        'aseguradora', v_origen,
                        'score', 0.95,
                        'tier', 2,
                        'same_insurer', FALSE,
                        'metodo_match', 'minimal_version_cross_insurer'
                    );
                    matches := matches || to_jsonb(matchinfo);
                    tier2_count := tier2_count + 1;
                    CONTINUE;
                END IF;
                
                coverage_result := calculate_weighted_coverage(
                    v_tokens,
                    existing_record.version_tokens_array
                );
                
                is_subset_match := (
                    coverage_result.coverage_a_in_b = 1.0 OR
                    coverage_result.coverage_b_in_a = 1.0
                );
                
                is_minimal_version := (
                    array_length(v_tokens, 1) <= 5 OR 
                    array_length(existing_record.version_tokens_array, 1) <= 5
                );
                
                IF is_subset_match AND is_minimal_version AND NOT coverage_result.has_conflicts THEN
                    matchinfo := jsonb_build_object(
                        'id', existing_record.id,
                        'aseguradora', v_origen,
                        'score', coverage_result.max_coverage,
                        'tier', 2,
                        'same_insurer', FALSE,
                        'metodo_match', 'subset_match_cross_insurer'
                    );
                    matches := matches || to_jsonb(matchinfo);
                    tier2_count := tier2_count + 1;
                    CONTINUE;
                END IF;
                
                IF coverage_result.max_coverage >= TIER2_COVERAGE_THRESHOLD
                   AND NOT coverage_result.has_conflicts
                THEN
                    matchinfo := jsonb_build_object(
                        'id', existing_record.id,
                        'aseguradora', v_origen,
                        'score', coverage_result.max_coverage,
                        'tier', 2,
                        'same_insurer', FALSE,
                        'metodo_match', 'weighted_coverage_cross_insurer'
                    );
                    matches := matches || to_jsonb(matchinfo);
                    tier2_count := tier2_count + 1;
                    CONTINUE;
                END IF;
                
                IF coverage_result.max_coverage >= TIER3_COVERAGE_THRESHOLD 
                   AND NOT coverage_result.has_conflicts 
                THEN
                    jaccard_score := (
                        SELECT
                            COUNT(*)::NUMERIC / (
                                array_length(v_tokens, 1) +
                                array_length(existing_record.version_tokens_array, 1) -
                                COUNT(*)
                            )
                        FROM unnest(v_tokens) t
                        WHERE t = ANY(existing_record.version_tokens_array)
                    );
                    
                    IF jaccard_score >= TIER3_JACCARD_THRESHOLD THEN
                        matchinfo := jsonb_build_object(
                            'id', existing_record.id,
                            'aseguradora', v_origen,
                            'score', (coverage_result.max_coverage + jaccard_score) / 2,
                            'tier', 3,
                            'same_insurer', FALSE,
                            'metodo_match', 'hybrid_coverage_jaccard_cross_insurer'
                        );
                        matches := matches || to_jsonb(matchinfo);
                        tier3_count := tier3_count + 1;
                        CONTINUE;
                    END IF;
                END IF;
            END IF;
        END LOOP;

        IF jsonb_array_length(matches) > 0 THEN
            FOR match_rec IN SELECT * FROM jsonb_to_recordset(matches) AS (
                id BIGINT, 
                aseguradora TEXT, 
                score NUMERIC, 
                tier INT, 
                same_insurer BOOLEAN, 
                metodo_match TEXT
            )
            LOOP
                UPDATE catalogo_homologado
                SET
                    disponibilidad = jsonb_set(
                        COALESCE(disponibilidad, '{}'::jsonb),
                        ARRAY[v_origen],
                        jsonb_build_object(
                            -- Si ya existe entrada para esta aseguradora con origen=true, preservarlo
                            -- Si no existe o era false, mantener false
                            'origen', COALESCE(
                                (disponibilidad->v_origen->>'origen')::boolean,
                                FALSE
                            ),
                            'disponible', TRUE,
                            'aseguradora', v_origen,
                            'id_original', v_record->>'id_original',
                            'version_original', v_record->>'version_original',
                            'confianza_score', match_rec.score,
                            'fecha_actualizacion', NOW(),
                            'metodo_match', match_rec.metodo_match
                        ),
                        TRUE
                    ),
                    fecha_actualizacion = NOW()
                WHERE id = match_rec.id;
                
                update_count := update_count + 1;
            END LOOP;
        ELSE
            INSERT INTO catalogo_homologado (
                hash_comercial,
                marca,
                modelo,
                anio,
                transmision,
                version,
                version_tokens_array,
                disponibilidad
            ) VALUES (
                v_hash,
                v_record->>'marca',
                v_record->>'modelo',
                (v_record->>'anio')::INT,
                v_record->>'transmision',
                v_version,
                v_tokens,
                jsonb_build_object(
                    v_origen,
                    jsonb_build_object(
                        'origen', TRUE,
                        'disponible', TRUE,
                        'aseguradora', v_origen,
                        'id_original', v_record->>'id_original',
                        'version_original', v_record->>'version_original',
                        'metodo_match', 'original_entry',
                        'confianza_score', 1.0,
                        'fecha_actualizacion', NOW()
                    )
                )
            )
            ON CONFLICT (hash_comercial, version) DO NOTHING;
            
            insert_count := insert_count + 1;
        END IF;
    END LOOP;

    RETURN QUERY SELECT
        insert_count,
        update_count,
        tier1_count,
        tier2_count,
        tier3_count,
        tier4_count,
        EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
END;
$$;

-- ============================================================================
-- FIN DEL SCRIPT - VERSIÓN 1.3.1
-- ============================================================================