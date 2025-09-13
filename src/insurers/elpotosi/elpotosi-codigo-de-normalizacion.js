// ==========================================
// ETL NORMALIZACIÓN EL POTOSÍ - CATÁLOGO MAESTRO DE VEHÍCULOS
// Versión: 1.0 - Implementación inicial
// Fecha: 2025-01-15
// Autor: Sistema ETL Multi-Aseguradora
// ==========================================

/**
 * PROPÓSITO:
 * Este código normaliza los datos de vehículos de la aseguradora EL POTOSÍ
 * para integrarlos en un catálogo maestro unificado. El proceso incluye:
 * 1. Limpieza y normalización de marcas/modelos
 * 2. Mapeo de transmisión desde campo numérico
 * 3. Extracción de versión (trim) del campo VersionCorta/Descripcion
 * 4. Detección de configuración motor, carrocería y tracción
 * 5. Generación de hashes únicos para deduplicación
 *
 * IMPORTANTE:
 * - Solo procesar registros con Activo = 1
 * - El campo VersionCorta puede estar vacío, usar Descripcion como fallback
 * - Hay inconsistencias graves en mapeo marca-modelo que requieren validación
 * - No inventar TRIMs, si no existe retornar null
 */

// ==========================================
// CONFIGURACIÓN Y DEPENDENCIAS
// ==========================================

const ASEGURADORA = "EL_POTOSI";
const crypto = require("crypto");

// ==========================================
// FUNCIONES DE UTILIDAD GENERAL
// ==========================================

/**
 * Normaliza cualquier texto eliminando acentos, caracteres especiales
 * y convirtiendo a mayúsculas.
 */
function normalizarTexto(texto) {
  if (!texto) return "";
  return texto
    .toString()
    .toUpperCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "") // Elimina acentos
    .replace(/[^A-Z0-9\s-]/g, " ") // Solo permite letras, números, espacios y guiones
    .replace(/\s+/g, " ") // Colapsa espacios múltiples
    .trim();
}

/**
 * Genera hash SHA-256 para identificación única
 */
function generarHash(...componentes) {
  const texto = componentes
    .filter((c) => c !== undefined && c !== null && c !== "")
    .join("|")
    .toUpperCase();
  return crypto.createHash("sha256").update(texto).digest("hex");
}

// ==========================================
// NORMALIZACIÓN DE MARCA
// ==========================================

/**
 * Normaliza nombres de marcas aplicando sinónimos y correcciones
 */
function normalizarMarca(marca) {
  if (!marca) return "";
  let marcaNorm = normalizarTexto(marca);

  // Diccionario de sinónimos y variaciones
  const sinonimos = {
    VOLKSWAGEN: ["VW", "VOLKSWAGEN", "VOLKS WAGEN"],
    "MERCEDES BENZ": ["MERCEDES", "MERCEDES-BENZ", "MERCEDES BENZ", "MB"],
    CHEVROLET: ["CHEVROLET", "CHEVY", "CHEV"],
    MINI: ["MINI COOPER", "MINI", "COOPER"],
    "LAND ROVER": ["LAND ROVER", "LANDROVER", "LAND-ROVER"],
    "ALFA ROMEO": ["ALFA", "ALFA ROMEO", "ALFAROMEO"],
    GMC: ["GMC", "GM", "GENERAL MOTORS"],
    BMW: ["BMW", "BAYERISCHE MOTOREN WERKE"],
    MAZDA: ["MAZDA", "MATSUDA"],
    KIA: ["KIA", "KIA MOTORS"],
    HYUNDAI: ["HYUNDAI", "HYNDAI", "HUNDAI"],
    MITSUBISHI: ["MITSUBISHI", "MITSIBUSHI", "MITS"],
    NISSAN: ["NISSAN", "NISAN", "DATSUN"],
    PEUGEOT: ["PEUGEOT", "PEUGOT", "PEUGEOUT"],
    RENAULT: ["RENAULT", "RENOLT", "RENO"],
    SUBARU: ["SUBARU", "SUBAROO"],
    SUZUKI: ["SUZUKI", "SUSUKI"],
    TOYOTA: ["TOYOTA", "TOYOTTA"],
    VOLVO: ["VOLVO", "VOLVOO"],
    FIAT: ["FIAT", "FIATT"],
    SEAT: ["SEAT", "CEAT"],
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
 */
function normalizarModelo(modelo, marca) {
  if (!modelo) return "";
  let modeloNorm = normalizarTexto(modelo);

  // Eliminar marca del inicio del modelo si está presente
  const marcaNorm = normalizarTexto(marca);
  if (modeloNorm.startsWith(marcaNorm + " ")) {
    modeloNorm = modeloNorm.substring(marcaNorm.length + 1);
  }

  return modeloNorm;
}

// ==========================================
// MAPEO DE TRANSMISIÓN
// ==========================================

/**
 * Mapea el código numérico de transmisión a valores estándar
 */
function normalizarTransmision(codigoTransmision) {
  // El Potosí usa códigos numéricos
  // 1 = Manual/STD
  // 2 = Automática/AUT
  // 0 = No especificado

  const transmision = parseInt(codigoTransmision);

  switch (transmision) {
    case 1:
      return "MANUAL";
    case 2:
      return "AUTO";
    case 0:
    default:
      return null;
  }
}

// ==========================================
// PREPARACIÓN DEL CAMPO VERSION
// ==========================================

/**
 * Prepara el texto de versión para procesamiento
 */
function prepararVersion(registro) {
  // Usar VersionCorta si existe, sino usar Descripcion
  let versionRaw = registro.version_corta || registro.descripcion || "";

  // Convertir a mayúsculas
  versionRaw = versionRaw.toUpperCase();

  // Limpiar prefijos de marca/modelo si están presentes
  // Ejemplo: "NISSAN SENTRA SR BITONO..." → "SR BITONO..."
  const marca = normalizarTexto(registro.marca_descripcion);
  const modelo = normalizarTexto(registro.modelo_descripcion);

  // Eliminar marca del inicio
  if (versionRaw.startsWith(marca + " ")) {
    versionRaw = versionRaw.substring(marca.length + 1);
  }

  // Eliminar modelo del inicio (si queda después de eliminar marca)
  if (versionRaw.startsWith(modelo + " ")) {
    versionRaw = versionRaw.substring(modelo.length + 1);
  }

  // Limpiar "Año: XXXX" del final si existe
  versionRaw = versionRaw.replace(/\s*AÑO:\s*\d{4}\s*$/i, "");

  return versionRaw.trim();
}

// ==========================================
// EXTRACCIÓN DE TRIM (VERSION)
// ==========================================

/**
 * Extrae el TRIM/versión limpio del texto
 */
function extraerTrim(versionText) {
  if (!versionText) return null;

  // Lista de TRIMs válidos identificados en El Potosí
  const TRIMS_VALIDOS = [
    // Premium/Lujo
    "LIMITED",
    "EXCLUSIVE",
    "PLATINUM",
    "SIGNATURE",
    "RESERVE",

    // Niveles medios-altos
    "ADVANCE",
    "ACTIVE",
    "ALLURE",
    "DYNAMIC",
    "PREMIUM",

    // Niveles estándar
    "GLS",
    "GLX",
    "GLE",
    "GL",
    "GT",
    "GTI",
    "GTS",
    "LT",
    "LE",
    "LX",
    "LS",
    "LTZ",
    "SE",
    "SEL",
    "SR",
    "SV",
    "SL",
    "S",
    "EX",
    "EX-L",

    // Deportivos
    "SPORT",
    "RS",
    "ST",
    "TYPE R",
    "TYPE S",
    "R-DESIGN",
    "FR",
    "CUPRA",
    "JOHN COOPER WORKS",
    "JCW",

    // Específicos VW Group
    "COMFORTLINE",
    "TRENDLINE",
    "HIGHLINE",
    "R-LINE",

    // SEAT
    "STYLE",
    "REFERENCE",
    "XCELLENCE",

    // Renault/Nissan
    "SENSE",
    "INTENS",
    "ZEN",
    "ICONIC",

    // Peugeot
    "ACCESS",
    "ACTIVE",
    "ALLURE",
    "GT LINE",

    // Mazda
    "I",
    "I SPORT",
    "I TOURING",
    "I GRAND TOURING",

    // BMW
    "SPORT LINE",
    "LUXURY LINE",
    "M SPORT",

    // Mercedes
    "AVANTGARDE",
    "ELEGANCE",
    "AMG LINE",

    // Pickups
    "PRO",
    "PRO-4X",
    "TRADESMAN",
    "BIG HORN",
    "LARAMIE",
    "REBEL",
    "KING RANCH",
    "LARIAT",
    "RAPTOR",

    // Híbridos/Eléctricos
    "E-POWER",
    "HYBRID",
    "PHEV",
    "EV",

    // Básicos
    "BASE",
    "CORE",
    "ESSENTIAL",

    // Ediciones especiales
    "ANNIVERSARY",
    "BLACK EDITION",
    "NIGHT EDITION",
  ];

  // Limpiar el texto inicial
  let cleanText = versionText
    .replace(/,.*$/, "") // Eliminar todo después de la primera coma
    .replace(/\s*(AUT|AUTO|STD|MANUAL|CVT|DSG)\s+/gi, " ") // Eliminar transmisión
    .replace(/\s*\d+\s*(PTAS?|PUERTAS)\s*/gi, " ") // Eliminar puertas
    .replace(/\s*\d+\s*OCUP\s*/gi, " ") // Eliminar ocupantes
    .replace(/\s*\d+(\.\d+)?\s*TON\s*/gi, " ") // Eliminar tonelaje
    .replace(/\s*\d+\.\d+[LT]?\s*/gi, " ") // Eliminar cilindrada
    .replace(/\s+/g, " ")
    .trim();

  // Dividir en palabras
  const parts = cleanText.split(" ").filter((p) => p.length > 0);

  // Buscar TRIMs compuestos primero (más específicos)
  for (let i = 0; i < parts.length - 1; i++) {
    // Verificar combinaciones de 3 palabras
    if (i < parts.length - 2) {
      const triple = `${parts[i]} ${parts[i + 1]} ${parts[i + 2]}`;
      if (TRIMS_VALIDOS.includes(triple)) {
        return triple;
      }
    }

    // Verificar combinaciones de 2 palabras
    const compound = `${parts[i]} ${parts[i + 1]}`;
    if (TRIMS_VALIDOS.includes(compound)) {
      return compound;
    }
  }

  // Buscar TRIMs simples
  for (const part of parts) {
    if (TRIMS_VALIDOS.includes(part)) {
      return part;
    }
  }

  // No inventar "BASE" si no se encuentra TRIM
  return null;
}

// ==========================================
// EXTRACCIÓN DE CONFIGURACIÓN DE MOTOR
// ==========================================

/**
 * Extrae la configuración del motor del texto
 */
function extraerMotorConfig(versionText) {
  if (!versionText) return null;

  const texto = versionText.toUpperCase();

  // Buscar configuración específica (L4, V6, etc.)
  const motorMatch = texto.match(/\b([LVI])([3468])\b/);
  if (motorMatch) {
    return `${motorMatch[1]}${motorMatch[2]}`;
  }

  // Detectar híbridos/eléctricos
  if (texto.match(/\b(HYBRID|HEV|HV|HIBRIDO)\b/)) {
    return "HYBRID";
  }
  if (texto.match(/\b(E-POWER|ELECTRIC|EV)\b/) && !texto.match(/\bHEV\b/)) {
    return "ELECTRIC";
  }
  if (texto.match(/\bPHEV\b/)) {
    return "PHEV";
  }
  if (texto.match(/\bMHEV\b/)) {
    return "MHEV";
  }

  // Detectar por número de cilindros
  const cilMatch = texto.match(/(\d+)\s*CIL/);
  if (cilMatch) {
    const numCil = parseInt(cilMatch[1]);
    switch (numCil) {
      case 3:
        return "L3";
      case 4:
        return "L4";
      case 6:
        return "V6";
      case 8:
        return "V8";
    }
  }

  // Detectar diesel
  if (texto.match(/\b(DIESEL|TDI|CDI|CRDI)\b/)) {
    return "DIESEL";
  }

  return null;
}

// ==========================================
// INFERENCIA DE CARROCERÍA
// ==========================================

/**
 * Infiere el tipo de carrocería basado en diversos indicadores
 */
function inferirCarroceria(versionText, tipoVehiculo, modelo) {
  // Si es pickup según tipo de vehículo
  if (tipoVehiculo === "PIC") {
    return "PICKUP";
  }

  const texto = versionText.toUpperCase();

  // Buscar carrocería explícita en el texto
  if (texto.match(/\bSEDAN\b/)) return "SEDAN";
  if (texto.match(/\b(HATCHBACK|HB)\b/)) return "HATCHBACK";
  if (texto.match(/\bSUV\b/)) return "SUV";
  if (texto.match(/\b(COUPE|CUPE)\b/)) return "COUPE";
  if (texto.match(/\b(CONVERTIBLE|CABRIO|ROADSTER)\b/)) return "CONVERTIBLE";
  if (texto.match(/\b(VAN|MINIVAN)\b/)) return "VAN";
  if (texto.match(/\b(WAGON|SPORTWAGEN|ESTATE)\b/)) return "WAGON";
  if (texto.match(/\b(PICKUP|PICK[\s-]?UP)\b/)) return "PICKUP";
  if (texto.match(/\bCHASIS\s+CABINA\b/)) return "PICKUP";

  // Inferir por número de puertas
  const puertasMatch = texto.match(/(\d+)\s*(?:PTAS|PUERTAS|P\b)/);
  if (puertasMatch) {
    const numPuertas = parseInt(puertasMatch[1]);
    switch (numPuertas) {
      case 2:
        return "COUPE";
      case 3:
        return "HATCHBACK";
      case 4:
        // Necesita más contexto, por defecto SEDAN
        return "SEDAN";
      case 5:
        // Podría ser HATCHBACK o SUV
        // Verificar por modelo conocido o contexto
        if (modelo && modelo.match(/\b(CX-|CR-V|RAV4|TUCSON|SPORTAGE)\b/)) {
          return "SUV";
        }
        return "HATCHBACK";
    }
  }

  return null;
}

// ==========================================
// EXTRACCIÓN DE TRACCIÓN
// ==========================================

/**
 * Extrae el sistema de tracción del texto
 */
function extraerTraccion(versionText) {
  if (!versionText) return null;

  const texto = versionText.toUpperCase();

  // Buscar patrones de tracción (orden de prioridad)
  if (texto.match(/\b4X4\b/i)) return "4X4";
  if (texto.match(/\b4X2\b/i)) return "4X2";
  if (texto.match(/\bAWD\b/)) return "AWD";
  if (texto.match(/\b4WD\b/)) return "4WD";
  if (texto.match(/\bFWD\b/)) return "FWD";
  if (texto.match(/\bRWD\b/)) return "RWD";

  // Sistemas propietarios que equivalen a AWD
  if (texto.match(/\b(XDRIVE|QUATTRO|4MATIC|4MOTION|ALL4)\b/)) {
    return "AWD";
  }

  return null;
}

// ==========================================
// PROCESAMIENTO PRINCIPAL
// ==========================================

/**
 * Procesa un registro de El Potosí y lo normaliza al formato canónico
 */
function procesarRegistro(registro) {
  // Validar que el registro esté activo
  if (!registro.activo || registro.activo !== 1) {
    return null; // No procesar registros inactivos
  }

  // Normalización básica
  const marcaNormalizada = normalizarMarca(registro.marca_descripcion);
  const modeloNormalizado = normalizarModelo(
    registro.modelo_descripcion,
    marcaNormalizada
  );
  const anio = parseInt(registro.anio);
  const transmisionNormalizada = normalizarTransmision(registro.transmision);

  // Preparar texto de versión
  const versionPreparada = prepararVersion(registro);

  // Extraer especificaciones
  const versionTrim = extraerTrim(versionPreparada);
  const motorConfig = extraerMotorConfig(versionPreparada);
  const carroceria = inferirCarroceria(
    versionPreparada,
    registro.tipo_vehiculo,
    modeloNormalizado
  );
  const traccion = extraerTraccion(versionPreparada);

  // Construir strings de identificación
  const stringComercial = [
    marcaNormalizada || "NULL",
    modeloNormalizado || "NULL",
    anio || "NULL",
    transmisionNormalizada || "NULL",
  ].join("|");

  const stringTecnico = [
    marcaNormalizada || "NULL",
    modeloNormalizado || "NULL",
    anio || "NULL",
    transmisionNormalizada || "NULL",
    versionTrim || "NULL",
    motorConfig || "NULL",
    carroceria || "NULL",
    traccion || "NULL",
  ].join("|");

  // Generar hashes
  const hashComercial = generarHash(
    marcaNormalizada,
    modeloNormalizado,
    anio,
    transmisionNormalizada
  );

  const idCanonico = generarHash(
    marcaNormalizada,
    modeloNormalizado,
    anio,
    transmisionNormalizada,
    versionTrim,
    motorConfig,
    carroceria,
    traccion
  );

  // Construir objeto de salida
  return {
    // Identificadores
    id_canonico: idCanonico,
    hash_comercial: hashComercial,
    string_comercial: stringComercial,
    string_tecnico: stringTecnico,

    // Datos normalizados
    marca: marcaNormalizada,
    modelo: modeloNormalizado,
    anio: anio,
    transmision: transmisionNormalizada,
    version: versionTrim,
    motor_config: motorConfig,
    carroceria: carroceria,
    traccion: traccion,

    // Metadata
    origen_aseguradora: ASEGURADORA,
    id_original: String(registro.id_version),
    version_original: registro.version_corta || registro.descripcion,
    activo: true, // Solo procesamos activos
  };
}

// ==========================================
// PUNTO DE ENTRADA PARA N8N
// ==========================================

// Para n8n - Function node
const registrosProcesados = [];

for (const item of $input.all()) {
  try {
    const registroNormalizado = procesarRegistro(item.json);

    // Solo agregar si se procesó exitosamente (no es null)
    if (registroNormalizado) {
      registrosProcesados.push({
        json: registroNormalizado,
      });
    }
  } catch (error) {
    // Registrar error pero continuar con otros registros
    console.error("Error procesando registro:", error);
    registrosProcesados.push({
      json: {
        error: true,
        mensaje: error.message,
        registro_original: item.json,
      },
    });
  }
}

return registrosProcesados;
