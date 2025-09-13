// ==========================================
// ETL NORMALIZACIÓN ZURICH - CATÁLOGO MAESTRO DE VEHÍCULOS
// Versión: 2.0 - Con documentación completa
// Fecha: 2025-09-03
// Autor: Sistema ETL Multi-Aseguradora
// ==========================================

/**
 * PROPÓSITO:
 * Este código normaliza los datos de vehículos de la aseguradora ZURICH
 * para integrarlos en un catálogo maestro unificado. El proceso incluye:
 * 1. Limpieza y normalización de marcas/modelos
 * 2. Extracción de versión (trim) eliminando especificaciones técnicas
 * 3. Detección de transmisión desde campo dedicado y validación en texto
 * 4. Extracción de especificaciones técnicas (motor, tracción, etc.)
 * 5. Generación de hashes únicos para deduplicación
 * 
 * IMPORTANTE:
 * - El schema de salida DEBE ser idéntico al del catálogo maestro
 * - Campos vacíos se almacenan como null, no con valores default
 * - La versión vacía se mantiene vacía, no se usa "BASE"
 * - Transmisión desconocida es null, no "DESCONOCIDO" o "AUTO"
 */

// ==========================================
// CONFIGURACIÓN Y DEPENDENCIAS
// ==========================================

const ASEGURADORA = 'ZURICH';
const crypto = require('crypto');

// ==========================================
// FUNCIONES DE UTILIDAD GENERAL
// ==========================================

/**
 * Normaliza cualquier texto eliminando acentos, caracteres especiales
 * y convirtiendo a mayúsculas. Función base para toda normalización.
 * 
 * @param {string} texto - Texto a normalizar
 * @returns {string} Texto normalizado en mayúsculas sin caracteres especiales
 * 
 * Ejemplos:
 * - "Mazda CX-5" → "MAZDA CX-5"
 * - "Volkswagën" → "VOLKSWAGEN"
 * - "PICK-UP  4x4" → "PICK UP 4X4"
 */
function normalizarTexto(texto) {
    if (!texto) return '';
    return texto.toString()
        .toUpperCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '') // Elimina acentos
        .replace(/[^A-Z0-9\s-]/g, ' ')   // Solo permite letras, números, espacios y guiones
        .replace(/\s+/g, ' ')             // Colapsa espacios múltiples
        .trim();
}

/**
 * Genera hash SHA-256 para identificación única de vehículos
 * 
 * @param {...string} componentes - Componentes a hashear
 * @returns {string} Hash SHA-256 en hexadecimal
 */
function generarHash(...componentes) {
    const texto = componentes.filter(c => c).join('|').toUpperCase();
    return crypto.createHash('sha256').update(texto).digest('hex');
}

// ==========================================
// NORMALIZACIÓN DE MARCA
// ==========================================

/**
 * Normaliza nombres de marcas aplicando sinónimos y correcciones comunes.
 * IMPORTANTE: Mantener consistencia entre todas las aseguradoras.
 * 
 * @param {string} marca - Nombre original de la marca
 * @returns {string} Marca normalizada y estandarizada
 * 
 * Casos especiales manejados:
 * - Variaciones ortográficas (VOLKSWAGEN vs VW)
 * - Errores comunes de escritura (MERCEDES vs MERCEDES BENZ)
 * - Marcas con guiones (LAND ROVER vs LAND-ROVER)
 */
function normalizarMarca(marca) {
    if (!marca) return '';
    let marcaNorm = normalizarTexto(marca);
    
    // Diccionario exhaustivo de sinónimos y variaciones
    // MANTENER SINCRONIZADO entre todas las aseguradoras
    const sinonimos = {
        'VOLKSWAGEN': ['VW', 'VOLKSWAGEN', 'VOLKS WAGEN'],
        'MERCEDES BENZ': ['MERCEDES', 'MERCEDES-BENZ', 'MERCEDES BENZ', 'MB', 'MERCEDEZ'],
        'CHEVROLET': ['CHEVROLET', 'CHEVY', 'CHEV'],
        'MINI': ['MINI COOPER', 'MINI', 'COOPER'],
        'LAND ROVER': ['LAND ROVER', 'LANDROVER', 'LAND-ROVER'],
        'ALFA ROMEO': ['ALFA', 'ALFA ROMEO', 'ALFAROMEO'],
        'GMC': ['GMC', 'GM', 'GENERAL MOTORS'],
        'BMW': ['BMW', 'BAYERISCHE MOTOREN WERKE'],
        'MAZDA': ['MAZDA', 'MATSUDA'],
        'KIA': ['KIA', 'KIA MOTORS'],
        'HYUNDAI': ['HYUNDAI', 'HYNDAI', 'HUNDAI'],
        'MITSUBISHI': ['MITSUBISHI', 'MITSIBUSHI', 'MITS'],
        'NISSAN': ['NISSAN', 'NISAN', 'DATSUN'],
        'PEUGEOT': ['PEUGEOT', 'PEUGOT', 'PEUGEOUT'],
        'RENAULT': ['RENAULT', 'RENOLT', 'RENO'],
        'SUBARU': ['SUBARU', 'SUBAROO'],
        'SUZUKI': ['SUZUKI', 'SUSUKI'],
        'TOYOTA': ['TOYOTA', 'TOYOTTA'],
        'VOLVO': ['VOLVO', 'VOLVOO'],
        'ACURA': ['ACURA', 'ACCURA'],
        'AUDI': ['AUDI', 'AUDII'],
        'BUICK': ['BUICK', 'BUIK'],
        'CADILLAC': ['CADILLAC', 'CADILAC'],
        'CHRYSLER': ['CHRYSLER', 'CRYSLER', 'CRISLER'],
        'DODGE': ['DODGE', 'DOGDE'],
        'FERRARI': ['FERRARI', 'FERARI'],
        'FIAT': ['FIAT', 'FIATT'],
        'FORD': ['FORD', 'FORT'],
        'HONDA': ['HONDA', 'JONDA'],
        'INFINITI': ['INFINITI', 'INFINITY'],
        'JAGUAR': ['JAGUAR', 'JAGUARR'],
        'JEEP': ['JEEP', 'JEEEP', 'JEP'],
        'LAMBORGHINI': ['LAMBORGHINI', 'LAMBO'],
        'LEXUS': ['LEXUS', 'LEXUSS'],
        'LINCOLN': ['LINCOLN', 'LINCON'],
        'MASERATI': ['MASERATI', 'MASSERATI'],
        'MCLAREN': ['MCLAREN', 'MC LAREN'],
        'PORSCHE': ['PORSCHE', 'PORCHE', 'PORSHE'],
        'RAM': ['RAM', 'DODGE RAM'],
        'ROLLS ROYCE': ['ROLLS ROYCE', 'ROLLS-ROYCE', 'ROLLS'],
        'SEAT': ['SEAT', 'CEAT'],
        'SKODA': ['SKODA', 'SCODA'],
        'TESLA': ['TESLA', 'TESSLA'],
        'BENTLEY': ['BENTLEY', 'BENTLY'],
        'GENESIS': ['GENESIS', 'GENISIS'],
        'SMART': ['SMART', 'SMAR']
    };
    
    // Buscar coincidencias en el diccionario
    for (const [marcaEstandar, variantes] of Object.entries(sinonimos)) {
        if (variantes.includes(marcaNorm)) {
            return marcaEstandar;
        }
    }
    
    return marcaNorm;
}

// ==========================================
// NORMALIZACIÓN DE MODELO
// ==========================================

/**
 * Normaliza nombres de modelos eliminando redundancias con la marca
 * 
 * @param {string} modelo - Nombre original del modelo
 * @param {string} marca - Marca ya normalizada
 * @returns {string} Modelo limpio sin redundancias
 * 
 * Ejemplos:
 * - ("MAZDA 3", "MAZDA") → "3"
 * - ("SERIE 3", "BMW") → "3 SERIES"
 * - ("CLASE A", "MERCEDES") → "CLASE A"
 */
function normalizarModelo(modelo, marca) {
    if (!modelo) return '';
    let modeloNorm = normalizarTexto(modelo);
    
    // Eliminar marca del inicio del modelo si está presente
    const marcaNorm = normalizarTexto(marca);
    if (modeloNorm.startsWith(marcaNorm + ' ')) {
        modeloNorm = modeloNorm.substring(marcaNorm.length + 1);
    }
    
    // Normalización específica de patrones comunes
    // BMW Serie X → X SERIES
    modeloNorm = modeloNorm.replace(/^SERIE\s+(\d+)/, '$1 SERIES');
    // Mercedes Clase X → CLASE X
    modeloNorm = modeloNorm.replace(/^CLASE\s+([A-Z])/, 'CLASE $1');
    
    return modeloNorm;
}

// ==========================================
// DETECCIÓN Y NORMALIZACIÓN DE TRANSMISIÓN
// ==========================================

/**
 * Determina el tipo de transmisión normalizado.
 * PRIORIDAD: Campo código > Texto de versión > null
 * 
 * @param {number} codigoTransmision - Código numérico (1=Manual, 2=Auto, 0=No especificado)
 * @param {string} textoVersion - Texto completo de versión para validación
 * @returns {string|null} 'MANUAL', 'AUTO' o null si no se puede determinar
 * 
 * IMPORTANTE: CVT y DCT se mapean a 'AUTO' para homologación
 * CVT (Continuously Variable Transmission) = AUTO
 * DCT (Dual Clutch Transmission) = AUTO
 * 
 * Lógica de decisión:
 * 1. Si código es 1 → MANUAL
 * 2. Si código es 2 → AUTO
 * 3. Si código es 0 → Buscar en texto
 * 4. Si no se encuentra → null 
 */
function normalizarTransmision(codigoTransmision, textoVersion) {
    // PRIORIDAD 1: Código numérico del campo dedicado
    if (codigoTransmision === 1) return 'MANUAL';
    if (codigoTransmision === 2) return 'AUTO';
    
    // PRIORIDAD 2: Buscar en texto solo si código es 0 o no especificado
    if (textoVersion) {
        const texto = textoVersion.toUpperCase();
        
        // Patrones de transmisión manual
        if (texto.match(/\b(MANUAL|STD|MAN|MT|ESTANDAR|EST)\b/)) return 'MANUAL';
        
        // Patrones de transmisión automática y sus variantes
        if (texto.match(/\b(AUT|AUTO|AUTOMATICA|AUTOMATIC|AT)\b/)) return 'AUTO';
        if (texto.match(/\b(TIPTRONIC|S[\s-]?TRONIC|STRONIC|STEPTRONIC)\b/)) return 'AUTO';
        if (texto.match(/\b(SPORTMATIC|GEARTRONIC|MULTITRONIC)\b/)) return 'AUTO';
        if (texto.match(/\b(G[\s-]?TRONIC|DRIVELOGIC|XTRONIC)\b/)) return 'AUTO';
        
        // CVT (Variable continua) - Se mapea a AUTO para homologación
        if (texto.match(/\bCVT\b/)) return 'AUTO';
        
        // DCT (Doble embrague) - Se mapea a AUTO para homologación
        if (texto.match(/\b(DCT|DSG|PDK|DUAL)\b/)) return 'AUTO';
    }
    
    // Si no se puede determinar, retornar null 
    return null;
}

// ==========================================
// EXTRACCIÓN DE ESPECIFICACIONES TÉCNICAS
// ==========================================

/**
 * Extrae todas las especificaciones técnicas del texto de versión.
 * Esta información se almacena separada de la versión normalizada.
 * 
 * @param {string} version - Texto completo de versión
 * @returns {Object} Objeto con todas las especificaciones encontradas
 * 
 * Especificaciones extraídas:
 * - cilindrada_l: Motor en litros (1.5, 2.0, etc.)
 * - numero_cilindros: Cantidad de cilindros (4, 6, 8)
 * - potencia_hp: Potencia en caballos de fuerza
 * - traccion: Sistema de tracción (AWD, 4X4, FWD, etc.)
 * - tipo_carroceria: Tipo de vehículo (SEDAN, SUV, PICKUP, etc.)
 * - numero_puertas: Cantidad de puertas (2, 3, 4, 5)
 * - numero_ocupantes: Capacidad de pasajeros
 * - configuracion_motor: Tipo de motor (V6, L4, TURBO, HYBRID, etc.)
 */
function extraerEspecificaciones(version) {
    const specs = {
        cilindrada_l: null,
        numero_cilindros: null,
        potencia_hp: null,
        traccion: null,
        tipo_carroceria: null,
        numero_puertas: null,
        numero_ocupantes: null,
        configuracion_motor: null
    };
    
    if (!version) return specs;
    const versionUpper = version.toUpperCase();
    
    // ===== CILINDRADA =====
    // Buscar patrones como 1.5L, 2.0T, 3.5L
    const cilindradaMatch = versionUpper.match(/(\d+\.?\d*)[LT]/);
    if (cilindradaMatch) {
        const cilindrada = parseFloat(cilindradaMatch[1]);
        // Validar rango razonable (0.5L a 8.0L)
        if (cilindrada >= 0.5 && cilindrada <= 8.0) {
            specs.cilindrada_l = cilindrada;
        }
    }
    
    // ===== NÚMERO DE CILINDROS =====
    // Buscar patrones como 4CIL, 6CIL, 8CIL
    const cilindrosMatch = versionUpper.match(/(\d+)CIL/);
    if (cilindrosMatch) {
        const cilindros = parseInt(cilindrosMatch[1]);
        // Validar rango razonable (2 a 12 cilindros)
        if (cilindros >= 2 && cilindros <= 12) {
            specs.numero_cilindros = cilindros;
        }
    }
    
    // ===== POTENCIA =====
    // Buscar patrones como 190HP, 350HP
    const potenciaMatch = versionUpper.match(/(\d+)HP/);
    if (potenciaMatch) {
        const potencia = parseInt(potenciaMatch[1]);
        // Validar rango razonable (50HP a 1500HP)
        if (potencia >= 50 && potencia <= 1500) {
            specs.potencia_hp = potencia;
        }
    }
    
    // ===== TRACCIÓN =====
    // Orden de prioridad: términos más específicos primero
    if (versionUpper.match(/\b4X4\b/)) specs.traccion = '4X4';
    else if (versionUpper.match(/\b4X2\b/)) specs.traccion = '4X2';
    else if (versionUpper.match(/\bAWD\b/)) specs.traccion = 'AWD';
    else if (versionUpper.match(/\b4WD\b/)) specs.traccion = '4WD';
    else if (versionUpper.match(/\bFWD\b/)) specs.traccion = 'FWD';
    else if (versionUpper.match(/\bRWD\b/)) specs.traccion = 'RWD';
    // Sistemas propietarios que equivalen a AWD
    else if (versionUpper.match(/\bQUATTRO\b/)) specs.traccion = 'AWD';
    else if (versionUpper.match(/\bXDRIVE\b/)) specs.traccion = 'AWD';
    else if (versionUpper.match(/\b4MATIC\b/)) specs.traccion = 'AWD';
    else if (versionUpper.match(/\b4MOTION\b/)) specs.traccion = 'AWD';
    else if (versionUpper.match(/\bALL[\s-]?4\b/)) specs.traccion = 'AWD';
    else if (versionUpper.match(/\bEAWD\b/)) specs.traccion = 'AWD';
    
    // ===== TIPO DE CARROCERÍA =====
    // Detectar el tipo más específico posible
    if (versionUpper.match(/\bSEDAN\b/)) specs.tipo_carroceria = 'SEDAN';
    else if (versionUpper.match(/\bSUV\b/)) specs.tipo_carroceria = 'SUV';
    else if (versionUpper.match(/\bCOUPE\b/)) specs.tipo_carroceria = 'COUPE';
    else if (versionUpper.match(/\bCONV(ERTIBLE)?\b/)) specs.tipo_carroceria = 'CONVERTIBLE';
    else if (versionUpper.match(/\b(HB|HATCHBACK)\b/)) specs.tipo_carroceria = 'HATCHBACK';
    else if (versionUpper.match(/\b(PICK[\s-]?UP|PICKUP)\b/)) specs.tipo_carroceria = 'PICKUP';
    else if (versionUpper.match(/\bVAN\b/)) specs.tipo_carroceria = 'VAN';
    else if (versionUpper.match(/\bWAGON\b/)) specs.tipo_carroceria = 'WAGON';
    else if (versionUpper.match(/\bSPORTBACK\b/)) specs.tipo_carroceria = 'SPORTBACK';
    else if (versionUpper.match(/\bCROSSOVER\b/)) specs.tipo_carroceria = 'CROSSOVER';
    else if (versionUpper.match(/\bMINIVAN\b/)) specs.tipo_carroceria = 'MINIVAN';
    
    // ===== NÚMERO DE PUERTAS =====
    // Buscar patrón XP donde X es el número
    const puertasMatch = versionUpper.match(/(\d+)P\b/);
    if (puertasMatch) {
        const puertas = parseInt(puertasMatch[1]);
        // Validar rango razonable (2 a 5 puertas)
        if (puertas >= 2 && puertas <= 5) {
            specs.numero_puertas = puertas;
        }
    } else {
        // Inferir por tipo de carrocería si no está especificado
        if (specs.tipo_carroceria === 'SEDAN') specs.numero_puertas = 4;
        else if (specs.tipo_carroceria === 'COUPE') specs.numero_puertas = 2;
        else if (specs.tipo_carroceria === 'CONVERTIBLE') specs.numero_puertas = 2;
        else if (specs.tipo_carroceria === 'SUV') specs.numero_puertas = 5;
        else if (specs.tipo_carroceria === 'HATCHBACK') specs.numero_puertas = 5;
        else if (specs.tipo_carroceria === 'PICKUP') specs.numero_puertas = 4;
    }
    
    // ===== NÚMERO DE OCUPANTES =====
    // Buscar patrón XOCUP donde X es el número
    const ocupantesMatch = versionUpper.match(/(\d+)OCUP/);
    if (ocupantesMatch) {
        const ocupantes = parseInt(ocupantesMatch[1]);
        // Validar rango razonable (2 a 23 ocupantes)
        if (ocupantes >= 2 && ocupantes <= 23) {
            specs.numero_ocupantes = ocupantes;
        }
    }
    
    // ===== CONFIGURACIÓN DE MOTOR =====
    // Construir descripción compuesta del motor
    const configMotor = [];
    
    // Tipo de configuración de cilindros
    if (versionUpper.match(/\bV(\d+)\b/)) {
        const vMatch = versionUpper.match(/\bV(\d+)\b/);
        configMotor.push('V' + vMatch[1]);
    } else if (versionUpper.match(/\bL(\d+)\b/)) {
        const lMatch = versionUpper.match(/\bL(\d+)\b/);
        configMotor.push('L' + lMatch[1]);
    } else if (versionUpper.match(/\bI(\d+)\b/)) {
        const iMatch = versionUpper.match(/\bI(\d+)\b/);
        configMotor.push('I' + iMatch[1]);
    } else if (versionUpper.match(/\bH(\d+)\b/)) {
        const hMatch = versionUpper.match(/\bH(\d+)\b/);
        configMotor.push('H' + hMatch[1]); // Motor boxer
    }
    
    // Características adicionales del motor
    if (versionUpper.match(/\bTURBO\b/)) configMotor.push('TURBO');
    if (versionUpper.match(/\b(BITURBO|TWIN[\s-]?TURBO)\b/)) {
        // Reemplazar TURBO si ya existe
        const index = configMotor.indexOf('TURBO');
        if (index > -1) configMotor.splice(index, 1);
        configMotor.push('BITURBO');
    }
    if (versionUpper.match(/\bDIESEL\b/)) configMotor.push('DIESEL');
    if (versionUpper.match(/\b(HYBRID|HIBRIDO)\b/)) configMotor.push('HYBRID');
    if (versionUpper.match(/\bPHEV\b/)) configMotor.push('PHEV');
    if (versionUpper.match(/\bMHEV\b/)) configMotor.push('MHEV');
    if (versionUpper.match(/\bEV\b|\bELECTRICO\b/)) configMotor.push('ELECTRICO');
    
    // Unir configuración si hay elementos
    if (configMotor.length > 0) {
        specs.configuracion_motor = configMotor.join(' ');
    }
    
    return specs;
}

// ==========================================
// NORMALIZACIÓN DE VERSIÓN (TRIM)
// ==========================================

/**
 * Extrae y normaliza la versión (trim level) del vehículo.
 * CRÍTICO: Elimina TODAS las especificaciones técnicas, dejando solo el trim.
 * 
 * @param {string} version - Texto completo de versión del vehículo
 * @param {string} transmisionNormalizada - Transmisión ya detectada (no usado actualmente)
 * @returns {string} Versión limpia solo con trim level o cadena vacía
 * 
 * Proceso:
 * 1. Eliminar códigos al inicio (G5J/1, C20, etc.)
 * 2. Eliminar TODA terminología de transmisión
 * 3. Eliminar especificaciones de motor, tracción, carrocería
 * 4. Eliminar equipamiento y códigos técnicos
 * 5. Preservar solo niveles de trim válidos
 * 
 * IMPORTANTE: Si no hay trim válido, retornar cadena vacía, NO "BASE"
 */
function normalizarVersion(version, transmisionNormalizada) {
    if (!version) return '';
    
    let versionNorm = version.toUpperCase().trim();
    
    // ===== PASO 1: ELIMINAR CÓDIGOS AL INICIO =====
    // Patrones como G5J/1, C20, M4M, etc.
    versionNorm = versionNorm.replace(/^[A-Z0-9]{1,4}[\/\-]?\d?\s+/, '');
    
    // ===== PASO 2: LISTA EXHAUSTIVA DE ELEMENTOS A ELIMINAR =====
    const patronesEliminar = [
        // ----- TRANSMISIONES (TODAS LAS VARIANTES) -----
        // Tipos específicos de transmisión automática
        /\b(TIPTRONIC|S[\s-]?TRONIC|STRONIC|STEPTRONIC|SPORTMATIC|GEARTRONIC)\b/gi,
        /\b(DSG|CVT|CVTF|DCT|PDK|AMT|SMG|XTRONIC|POWERSHIFT)\b/gi,
        /\b(MULTITRONIC|DUALOGIC|EASYTRONIC|DRIVELOGIC|SPORTSHIFT)\b/gi,
        /\b(7[\s-]?G[\s-]?TRONIC|9[\s-]?G[\s-]?TRONIC|G[\s-]?TRONIC)\b/gi,
        // Transmisiones básicas
        /\b(AUTOMATICA|AUTOMATIC|AUTO|AUT)\b/gi,
        /\b(MANUAL|ESTANDAR|STD|EST|MAN)\b/gi,
        /\b(MT|AT)\b/gi,
        // Velocidades
        /\b\d+\s*(VEL|SPEED|VELOCIDADES?|MARCHAS?|CAMBIOS?)\b/gi,
        
        // ----- MOTOR Y CILINDRADA -----
        /\b[VLI]\d+\b/gi,                    // V6, L4, I4
        /\bH\d+\b/gi,                         // H4, H6 (Boxer)
        /\b\d+\.?\d*[LT]\b/gi,                // 2.0L, 1.5T
        /\b\d+\s*CIL\b/gi,                    // 4CIL, 6CIL
        /\b\d+\s*HP\b/gi,                     // 190HP, 350HP
        /\b\d+\s*PS\b/gi,                     // 190PS (caballos métricos)
        /\b\d+\s*KW\b/gi,                     // 140KW (kilowatts)
        // Tecnologías de motor
        /\b(TFSI|TDI|TSI|TBI|GDI|CRDI|CDI|HDI|MHEV|HEV|PHEV|BEV|EV)\b/gi,
        /\b(DIESEL|TURBO|BITURBO|TWIN[\s-]?TURBO|TBO)\b/gi,
        /\b(HIBRIDO|HIBRIDA|HYBRID|ELECTRICO|MILD[\s-]?HYBRID)\b/gi,
        
        // ----- TRACCIÓN -----
        /\b(4X4|4X2|4WD|AWD|FWD|RWD|2WD|ALL4|EAWD)\b/gi,
        /\b(QUATTRO|XDRIVE|4MATIC|4MOTION|ALL[\s-]?WHEEL[\s-]?DRIVE)\b/gi,
        
        // ----- CARROCERÍA (solo si es redundante) -----
        /\b(SEDAN|HATCHBACK|HB|COUPE|CONV|CONVERTIBLE|WAGON|SPORTBACK)\b/gi,
        /\b(SUV|PICKUP|PICK[\s-]?UP|VAN|CROSSOVER|MINIVAN)\b/gi,
        
        // ----- CABINA (PICKUPS) -----
        /\b(CREW[\s.]?CAB|CAB[\s.]?REG|REGULAR[\s-]?CAB|DOUBLE[\s-]?CAB)\b/gi,
        /\b(SINGLE[\s-]?CAB|EXTENDED[\s-]?CAB|DOBLE[\s-]?CABINA)\b/gi,
        
        // ----- EQUIPAMIENTO Y CÓDIGOS -----
        /\b(AA|EE|CD|BA|QC|VP|ABS|EBD|ESP|TCS|VSC|DSC)\b/gi,
        /\b(MP3|USB|GPS|NAVI|DVD|BT|BLUETOOTH|FBX|FX|FN|RA|DH|CB|CE|CA|CQ)\b/gi,
        /\b(ONSTAR|BEDLINER|LEATHERETTE|PIEL|LEATHER|CLOTH|TELA)\b/gi,
        /\b(SIS[\s.]?NAV|SIS[\s.]?ENTRET|CAM[\s.]?VIS[\s.]?TRAS)\b/gi,
        /\b(PAQ[\s.]?ARRAST|PAQ[\s.]?[A-Z])\b/gi,
        /\bR\d{2}\b/gi,                      // R16, R17, R18 (rines)
        /\b(IMP|FBX)\b/gi,
        
        // ----- PUERTAS Y OCUPANTES -----
        /\b\d+\s*P\b/gi,                      // 2P, 3P, 4P, 5P
        /\b\d+\s*PTAS?\b/gi,                  // 2PTAS, 4PTAS
        /\b\d+\s*PUERTAS?\b/gi,
        /\b\d+\s*OCUP\.?\b/gi,                // 5OCUP, 7OCUP
        /\b\d+\s*OCUPANTES?\b/gi,
        /\b\d+\s*PASAJEROS?\b/gi,
        /\b\d+\s*PLAZAS?\b/gi,
        
        // ----- TÉRMINOS ADICIONALES ESPECÍFICOS DE ZURICH -----
        /\b(TA|TB|TC)\b/gi,                  // Códigos de techo
        /\b(DOBLE[\s-]?RODADA|EXTRA[\s-]?LARGA)\b/gi,
        /\b(SIN[\s-]?ASIENTOS[\s-]?TRASEROS)\b/gi,
        /\b(PASAJE[\s-]?(URBANO|PERSONAL)|PRO[\s-]?SUSI)\b/gi,
        /\b(POLYMETAL|BLU[\s-]?RAY|TECHO[\s-]?PANORAMICO)\b/gi,
        /\b(AIR[\s-]?SUSPENSION|WHEELBASE|STANDARD[\s-]?WHEELBASE|LWB|SWB)\b/gi,
        /\b(DARK|EDITION|BLACK[\s-]?EDITION|RECHARGE|ULTIMATE)\b/gi,
        /\b(GEN[\s-]?VI|EDITION[\s-]?CENTENNIAL|ANNIVERSARY|ANIV)\b/gi,
        /\b\d+[\s-]?SEATER\b/gi,             // 7-SEATER, 5 SEATER
        /\b\d+[\s-]?AÑOS?\b/gi,               // 35 AÑOS
        /\b(FRONT|REAR)\b/gi,
        
        // ----- NUMERACIÓN Y CÓDIGOS SUELTOS -----
        /\b\d+PS\b/gi,                        // 250PS
        /\b\d+KWH\b/gi,                       // 75KWH
        /\b(PS|HP|KW|NM|LB-FT)\b/gi,         // Unidades de potencia/torque
        
        // ----- LIMPIAR PUNTUACIÓN -----
        /[,.;:]/g,
        /[?¿!¡]/g,
        /\(|\)/g                              // Paréntesis
    ];
    
    // ===== PASO 3: APLICAR TODAS LAS ELIMINACIONES =====
    for (const patron of patronesEliminar) {
        versionNorm = versionNorm.replace(patron, ' ');
    }
    
    // ===== PASO 4: LIMPIAR ESPACIOS MÚLTIPLES =====
    versionNorm = versionNorm.replace(/\s+/g, ' ').trim();
    
    // ===== PASO 5: IDENTIFICAR TRIM VÁLIDO =====
    // Lista exhaustiva de trims válidos que DEBEN preservarse
    // Ordenados por prioridad (más específicos primero)
    const trimsValidos = [
        // ----- Trims deportivos y premium -----
        'TYPE S', 'TYPE R', 'TYPE A',
        'S LINE', 'M SPORT', 'AMG LINE', 'RS LINE', 'R LINE',
        'M PERFORMANCE', 'AMG', 'RS', 'SS', 'ST', 'GT', 'GTI', 'GTS', 'GTR',
        'JOHN COOPER WORKS', 'JCW', 'NISMO', 'TRD PRO', 'TRD SPORT', 'TRD OFF-ROAD',
        
        // ----- Niveles de equipamiento premium -----
        'A-SPEC', 'EX-L', 'X-LINE', 'GT-LINE', 'E-TRON',
        'SELECT', 'DYNAMIC', 'ADVANCE', 'SPORT', 'LUXURY',
        'PREMIUM', 'ELITE', 'LIMITED', 'EXCLUSIVE', 'ULTIMATE',
        'SIGNATURE', 'AVENIR', 'TITANIUM', 'PLATINUM',
        'COMPETITION', 'VELOCE', 'QUADRIFOGLIO', 'QV',
        'TI', 'SPRINT', 'ESTREMA', 'COMPETIZIONE',
        
        // ----- Trims de pickups -----
        'LARAMIE', 'KING RANCH', 'LARIAT', 'RAPTOR', 'REBEL',
        'SAHARA', 'RUBICON', 'TRAIL BOSS', 'HIGH COUNTRY',
        'Z71', 'ZR2', 'DENALI', 'AT4', 'RST', 'LTZ', 'LT', 'LS',
        'TRADESMAN', 'BIG HORN', 'LONGHORN', 'TEXAS', 'POWER WAGON',
        'TREMOR', 'WILDTRAK', 'BADLANDS',
        
        // ----- Versiones base y medias -----
        'BASE', 'SE', 'SEL', 'SEL PLUS', 'S', 'SV', 'SL', 'SR', 'SR5',
        'LE', 'XLE', 'XSE', 'XL', 'XLT', 'DX', 'LX', 'EX', 'SI',
        'TOURING', 'GRAND TOURING', 'SPORT TOURING',
        'SLE', 'SLT', 'TERRAIN', 'ELEVATION',
        
        // ----- Versiones de lujo -----
        'ESSENCE', 'PREFERRED', 'AVANTGARDE', 'EXCLUSIVE',
        'PROGRESSIVE', 'ACTIVE', 'ALLURE', 'FELINE', 'GRIFFE',
        'TREND', 'STYLE', 'ELEGANCE', 'INTENS', 'ZEN', 'LIFE',
        'EMOTION', 'REFERENCE', 'XCELLENCE', 'FR', 'CUPRA',
        
        // ----- Específicos de marcas -----
        'AUTOBIOGRAPHY', 'VOGUE', 'VELAR', 'EVOQUE', 'DISCOVERY',
        'R-DYNAMIC', 'HSE', 'SVR', 'SVO',
        'QUADRA-TRAC', 'TRAILHAWK', 'OVERLAND', 'SUMMIT',
        'PRO-4X', 'ARMADA',
        'COOPER', 'COUNTRYMAN', 'CLUBMAN', 'ICONIC', 'RESERVE',
        'EXECUTIVE', 'PERFORMANCE', 'EXCELLENCE',
        
        // ----- Nomenclaturas especiales -----
        'SB', 'SBK', // Sportback abreviado
        'S4', 'S5', 'S6', 'S7', 'S8', // Audi S series
        'M3', 'M4', 'M5', 'M6', 'M7', 'M8', // BMW M series
        'X1', 'X2', 'X3', 'X4', 'X5', 'X6', 'X7', // BMW X series
        'Q2', 'Q3', 'Q4', 'Q5', 'Q7', 'Q8', // Audi Q series
        '35', '40', '45', '50', '55', '60', // Nomenclatura Audi TFSI
        
        // ----- Letras sueltas que pueden ser trim -----
        'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
        'N', 'O', 'P', 'Q', 'R', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
    ];
    
    // Buscar el trim válido más relevante
    let trimEncontrado = '';
    
    // Buscar trims compuestos primero (más específicos)
    for (const trim of trimsValidos) {
        if (versionNorm.includes(trim)) {
            trimEncontrado = trim;
            break;
        }
    }
    
    // Si no se encontró trim válido, intentar con la primera palabra significativa
    if (!trimEncontrado) {
        const palabras = versionNorm.split(' ').filter(p => {
            return p.length > 0 && 
                   !p.match(/^\d+$/) &&          // No solo números
                   p.length <= 20;               // No palabras muy largas (probablemente basura)
        });
        
        // Usar la primera palabra si existe y es significativa
        if (palabras.length > 0 && palabras[0].length > 1) {
            trimEncontrado = palabras[0];
        }
    }
    
    // ===== PASO 6: RETORNAR RESULTADO =====
    // IMPORTANTE: Si no hay trim, retornar cadena vacía, NO "BASE"
    if (!trimEncontrado || trimEncontrado.length <= 1) {
        return '';
    }
    
    return trimEncontrado;
}

// ==========================================
// PROCESAMIENTO PRINCIPAL
// ==========================================

/**
 * Procesa todos los registros de entrada y genera el catálogo maestro normalizado
 * 
 * FLUJO DE PROCESAMIENTO:
 * 1. Obtener fecha actual para timestamp
 * 2. Para cada registro de entrada:
 *    a. Normalizar marca y modelo
 *    b. Detectar transmisión
 *    c. Extraer versión limpia (trim)
 *    d. Extraer especificaciones técnicas
 *    e. Generar hashes únicos
 *    f. Crear registro con schema estándar
 * 3. Retornar array de registros procesados
 */

// Obtener fecha actual para el proceso
const fechaProceso = new Date().toISOString();

// Procesar cada registro
const registros = [];
for (const item of $input.all()) {
    const data = item.json;
    
    // ===== NORMALIZACIÓN BÁSICA =====
    const marcaNormalizada = normalizarMarca(data.marca);
    const modeloNormalizado = normalizarModelo(data.modelo, data.marca);
    
    // ===== DETECCIÓN DE TRANSMISIÓN =====
    // Usa campo código como prioridad, texto como validación
    const transmisionNormalizada = normalizarTransmision(
        data.transmision_codigo,
        data.version_completa
    );
    
    // ===== NORMALIZACIÓN DE VERSIÓN =====
    // Extrae solo el trim level, elimina toda especificación técnica
    const versionNormalizada = normalizarVersion(
        data.version_para_normalizar || data.version_completa,
        transmisionNormalizada
    );
    
    // ===== EXTRACCIÓN DE ESPECIFICACIONES =====
    // Toda la información técnica se extrae por separado
    const specs = extraerEspecificaciones(data.version_completa);
    
    // ===== GENERACIÓN DE CONCATENACIONES =====
    // main_specs: Para identificación comercial básica
    const mainSpecs = [
        marcaNormalizada,
        modeloNormalizado,
        data.año,
        transmisionNormalizada
    ].map(v => v || 'null').join('|'); // Usar 'null' como string para campos vacíos
    
    // tech_specs: Para identificación técnica completa
    const techSpecs = [
        versionNormalizada || 'null',
        specs.configuracion_motor || 'null',
        specs.cilindrada_l || 'null',
        specs.traccion || 'null',
        specs.tipo_carroceria || 'null',
        specs.numero_ocupantes || 'null'
    ].join('|');
    
    // ===== GENERACIÓN DE HASHES =====
    // Hash comercial: Para deduplicación básica
    const hashComercial = generarHash(
        mainSpecs
    );
    
    // Hash técnico: Para deduplicación completa incluyendo specs
    const hashTecnico = generarHash(
        mainSpecs,
        techSpecs
    );
    
    // ===== CREAR REGISTRO CON SCHEMA ESTÁNDAR =====
    // IMPORTANTE: Este schema DEBE ser idéntico para todas las aseguradoras
    const registro = {
        // Datos principales
        origen_aseguradora: ASEGURADORA,
        marca: marcaNormalizada,
        modelo: modeloNormalizado,
        anio: data.año,
        transmision: transmisionNormalizada,
        version: versionNormalizada || null, // null si no hay versión
        
        // Especificaciones técnicas (null si no se encontraron)
        motor_config: specs.configuracion_motor,
        cilindrada: specs.cilindrada_l,
        traccion: specs.traccion,
        carroceria: specs.tipo_carroceria,
        numero_ocupantes: specs.numero_ocupantes,
        
        // Concatenaciones para búsqueda y agrupación
        main_specs: mainSpecs,
        tech_specs: techSpecs,
        
        // Hashes únicos para deduplicación
        hash_comercial: hashComercial,
        hash_tecnico: hashTecnico,
        
        // Metadata
        aseguradoras_disponibles: [ASEGURADORA],
        fecha_actualizacion: fechaProceso
    };
    
    registros.push(registro);
}

// Retornar los registros procesados para n8n
return registros.map(item => ({ json: item }));