// ==========================================
// ETL NORMALIZACIÓN GNP - CATÁLOGO MAESTRO DE VEHÍCULOS
// Versión: 1.0 - Con validación estricta por contaminación de datos
// Fecha: 2025-01-16
// Autor: Sistema ETL Multi-Aseguradora
// ==========================================

/**
 * PROPÓSITO:
 * Este código normaliza los datos de vehículos de la aseguradora GNP
 * para integrarlos en un catálogo maestro unificado.
 *
 * ADVERTENCIA CRÍTICA:
 * - GNP tiene alta contaminación de datos (8% con marcas incorrectas en VersionCorta)
 * - NO existe campo de activo/vigente - se procesan TODOS los registros
 * - Solo ~10% de registros tienen TRIM identificable
 * - Validación estricta requerida para evitar datos incorrectos
 */

// ==========================================
// CONFIGURACIÓN Y DEPENDENCIAS
// ==========================================

const ASEGURADORA = "GNP";
const crypto = require("crypto");

// ==========================================
// FUNCIONES DE UTILIDAD GENERAL
// ==========================================

/**
 * Normaliza cualquier texto eliminando acentos y caracteres especiales
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
    .filter((c) => c)
    .join("|")
    .toUpperCase();
  return crypto.createHash("sha256").update(texto).digest("hex");
}

// ==========================================
// NORMALIZACIÓN DE MARCA
// ==========================================

/**
 * Normaliza marcas de GNP consolidando duplicados conocidos
 */
function normalizarMarca(marca) {
  if (!marca) return "";
  let marcaNorm = normalizarTexto(marca);

  // Consolidación específica de GNP
  const consolidacionGNP = {
    "GENERAL MOTORS": "GMC",
    "GENERAL MOTORS 2": "GMC",
    "JAC SEI": "JAC",
    "MG ROVER": "MG",
    DONGFENG: "DONGFENG",
    "KING LONG": "KING LONG",
    UAZ: "UAZ",
    ZACUA: "ZACUA",
    ZAMARRIPA: "ZAMARRIPA",
    ZEEKR: "ZEEKR",
    ARRA: "ARRA",
    EXEED: "EXEED",
    FOTON: "FOTON",
    GAC: "GAC",
    GEELY: "GEELY",
    OMODA: "OMODA",
    CHIREY: "CHIREY",
    BAIC: "BAIC",
    BYD: "BYD",
    CHANGAN: "CHANGAN",
  };

  // Aplicar consolidación específica de GNP
  if (consolidacionGNP[marcaNorm]) {
    return consolidacionGNP[marcaNorm];
  }

  // Diccionario general de sinónimos
  const sinonimos = {
    VOLKSWAGEN: ["VW", "VOLKSWAGEN", "VOLKS WAGEN"],
    "MERCEDES BENZ": ["MERCEDES", "MERCEDES-BENZ", "MERCEDES BENZ", "MB"],
    CHEVROLET: ["CHEVROLET", "CHEVY", "CHEV"],
    MINI: ["MINI COOPER", "MINI", "COOPER"],
    "LAND ROVER": ["LAND ROVER", "LANDROVER", "LAND-ROVER"],
    "ALFA ROMEO": ["ALFA", "ALFA ROMEO", "ALFAROMEO"],
    BMW: ["BMW", "BAYERISCHE MOTOREN WERKE"],
    CHRYSLER: ["CHRYSLER", "CRYSLER"],
    GMC: ["GMC", "GM", "GENERAL MOTORS"],
    CUPRA: ["CUPRA", "CUPRA RACING"],
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
 * Normaliza modelos eliminando redundancias
 * NOTA: GNP tiene modelos con nombres de otras marcas (ej: "LINCOLN CONTINENTAL" bajo Ford)
 */
function normalizarModelo(modelo, marca) {
  if (!modelo) return "";
  let modeloNorm = normalizarTexto(modelo);

  // Eliminar marca del inicio si está presente
  const marcaNorm = normalizarTexto(marca);
  if (modeloNorm.startsWith(marcaNorm + " ")) {
    modeloNorm = modeloNorm.substring(marcaNorm.length + 1);
  }

  // Casos especiales de GNP
  // Eliminar prefijos de otras marcas cuando están mal clasificados
  modeloNorm = modeloNorm
    .replace(/^LINCOLN\s+/, "")
    .replace(/^DODGE\s+/, "")
    .replace(/^JEEP\s+/, "")
    .replace(/^LEXUS\s+/, "");

  // Normalización de patrones comunes
  modeloNorm = modeloNorm.replace(/^SERIE\s+(\d+)/, "$1 SERIES");
  modeloNorm = modeloNorm.replace(/^CLASE\s+([A-Z])/, "CLASE $1");

  return modeloNorm;
}

// ==========================================
// NORMALIZACIÓN DE TRANSMISIÓN
// ==========================================

/**
 * Normaliza transmisión desde código numérico de GNP
 * GNP usa: 0 = No especificada, 1 = Manual, 2 = Automática
 */
function normalizarTransmision(codigoTransmision, versionCorta) {
  // Prioridad al campo dedicado
  if (codigoTransmision === 1) return "MANUAL";
  if (codigoTransmision === 2) return "AUTO";

  // Si código es 0, intentar extraer del texto
  if (codigoTransmision === 0 && versionCorta) {
    const texto = versionCorta.toUpperCase();

    // Patrones de manual
    if (texto.match(/\b(MANUAL|STD|MAN|MT|ESTANDAR|EST)\b/)) return "MANUAL";

    // Patrones de automática
    if (texto.match(/\b(AUT|AUTO|AUTOMATICA|AUTOMATIC|AT)\b/)) return "AUTO";
    if (texto.match(/\b(CVT|XTRONIC|ECVT)\b/)) return "AUTO";
    if (texto.match(/\b(TIPTRONIC|S-TRONIC|MULTITRONIC|DSG|PDK|DCT)\b/))
      return "AUTO";
    if (texto.match(/\b(IVT|GEARTRONIC|STEPTRONIC)\b/)) return "AUTO";
  }

  // Si no se puede determinar, retornar null
  return null;
}

// ==========================================
// DETECCIÓN Y LIMPIEZA DE CONTAMINACIÓN
// ==========================================

/**
 * Detecta y limpia contaminación de otras marcas en VersionCorta
 * CRÍTICO: GNP tiene ~8% de registros con marcas incorrectas
 */
function limpiarContaminacion(versionCorta, marcaReal, modeloReal) {
  if (!versionCorta) return "";

  let versionLimpia = versionCorta.toUpperCase();

  // Lista de marcas que NO deberían aparecer en VersionCorta
  const marcasContaminantes = [
    "BMW",
    "MERCEDES BENZ",
    "ALFA ROMEO",
    "AUDI",
    "VOLKSWAGEN",
    "TOYOTA",
    "HONDA",
    "NISSAN",
    "MAZDA",
    "MITSUBISHI",
    "FORD",
    "CHEVROLET",
    "GMC",
    "CHRYSLER",
    "DODGE",
    "HYUNDAI",
    "KIA",
    "VOLVO",
    "PORSCHE",
    "JAGUAR",
  ];

  // Verificar si hay contaminación
  const marcaRealNorm = normalizarTexto(marcaReal);
  let esContaminado = false;

  for (const marcaContaminante of marcasContaminantes) {
    if (
      versionLimpia.startsWith(marcaContaminante) &&
      marcaContaminante !== marcaRealNorm
    ) {
      esContaminado = true;
      // Eliminar la marca contaminante y todo lo que le sigue hasta encontrar algo útil
      const regex = new RegExp(`^${marcaContaminante}\\s+[^\\s]+\\s*`, "i");
      versionLimpia = versionLimpia.replace(regex, "");
    }
  }

  // Si está completamente contaminado y queda vacío, retornar cadena vacía
  if (esContaminado && versionLimpia.trim() === "") {
    console.warn(
      `[GNP] Contaminación total detectada: "${versionCorta}" para ${marcaReal} ${modeloReal}`
    );
    return "";
  }

  // Eliminar modelos específicos que aparecen incorrectamente
  versionLimpia = versionLimpia
    .replace(/\b\d{3}[A-Z]{0,2}\s+/g, "") // 325iA, 500CGI, etc.
    .replace(/\bML\s+\d+/g, "") // ML 500, ML 63
    .replace(/\bSERIE\s+[A-Z0-9]/g, ""); // SERIE M, SERIE 3

  return versionLimpia.trim();
}

// ==========================================
// EXTRACCIÓN DE ESPECIFICACIONES TÉCNICAS
// ==========================================

/**
 * Extrae especificaciones técnicas del campo VersionCorta
 */
function extraerEspecificaciones(versionCorta) {
  const specs = {
    motor_config: null,
    cilindrada: null,
    turbo: false,
    traccion: null,
    carroceria: null,
    puertas: null,
  };

  if (!versionCorta) return specs;
  const texto = versionCorta.toUpperCase();

  // Configuración del motor (L4, V6, V8, H4)
  const motorMatch = texto.match(/\b([VLIH])(\d+)\b/);
  if (motorMatch) {
    specs.motor_config = motorMatch[0];
  }

  // Cilindrada (1.5L, 2.0T, 3.5)
  const cilindradaMatch = texto.match(/(\d+\.?\d*)[LT]\b/);
  if (cilindradaMatch) {
    const cilindrada = parseFloat(cilindradaMatch[1]);
    if (cilindrada >= 0.5 && cilindrada <= 8.0) {
      specs.cilindrada = cilindrada;
    }
  }

  // Turbo
  if (/\b(TURBO|BITURBO|TWIN TURBO|TSI|TDI|TFSI|TURB)\b/.test(texto)) {
    specs.turbo = true;
  }

  // Tracción
  if (/\b4X4\b/.test(texto)) specs.traccion = "4X4";
  else if (/\b4X2\b/.test(texto)) specs.traccion = "4X2";
  else if (/\bAWD\b/.test(texto)) specs.traccion = "AWD";
  else if (/\b4WD\b/.test(texto)) specs.traccion = "4WD";
  else if (/\bFWD\b/.test(texto)) specs.traccion = "FWD";
  else if (/\bRWD\b/.test(texto)) specs.traccion = "RWD";
  else if (/\bQUATTRO\b/.test(texto)) specs.traccion = "AWD";

  // Carrocería
  if (/\bSEDAN\b/.test(texto)) specs.carroceria = "SEDAN";
  else if (/\bCOUPE\b/.test(texto)) specs.carroceria = "COUPE";
  else if (/\bCONVERTIBLE\b/.test(texto)) specs.carroceria = "CONVERTIBLE";
  else if (/\bCABRIO\b/.test(texto)) specs.carroceria = "CONVERTIBLE";
  else if (/\bHATCHBACK\b/.test(texto)) specs.carroceria = "HATCHBACK";
  else if (/\bWAGON\b/.test(texto)) specs.carroceria = "WAGON";
  else if (/\bVAN\b/.test(texto)) specs.carroceria = "VAN";
  else if (/\bSUV\b/.test(texto)) specs.carroceria = "SUV";

  // Puertas
  const puertasMatch = texto.match(/\b(\d)[P\s]*(PTAS?|PUERTAS)?\b/);
  if (puertasMatch) {
    const puertas = parseInt(puertasMatch[1]);
    if (puertas >= 2 && puertas <= 5) {
      specs.puertas = puertas;
    }
  }

  return specs;
}

// ==========================================
// EXTRACCIÓN DE TRIM (VERSIÓN)
// ==========================================

/**
 * Extrae el TRIM limpio del campo VersionCorta
 * NOTA: Solo ~10% de registros GNP tienen TRIM identificable
 */
function extraerTrim(versionCorta, marcaReal, modeloReal) {
  if (!versionCorta) return null;

  // Primero limpiar contaminación
  let versionLimpia = limpiarContaminacion(versionCorta, marcaReal, modeloReal);

  // Casos especiales - valores mínimos
  if (
    versionLimpia === "S/D" ||
    versionLimpia === "" ||
    versionLimpia.length <= 2
  ) {
    return null;
  }

  // Eliminar especificaciones técnicas
  versionLimpia = versionLimpia
    // Motor y cilindrada
    .replace(/[VLIH]\d+\s+\d+\.\d+[TL]?\s*/g, "")
    .replace(/\b[VLIH]\d+\b/g, "")
    .replace(/\d+\.\d+[TL]?\s*/g, "")
    .replace(/\b\d+HP\b/g, "")
    .replace(/\b\d+PS\b/g, "")
    // Transmisión
    .replace(
      /\b(STD|AUT|CVT|TIP|TIPTRONIC|XTRONIC|MULTITRONIC|IVT|DCT|DSG|PDK)\b/g,
      ""
    )
    .replace(/\b(MANUAL|AUTOMATICA?|AUTO)\b/g, "")
    // Tracción
    .replace(/\b(4X4|4X2|AWD|FWD|RWD|QUATTRO|4WD)\b/g, "")
    // Turbo
    .replace(/\b(TURBO|BITURBO|TSI|TDI|TFSI|TURB)\b/g, "")
    // Puertas y rines
    .replace(/\b\d+P\b/g, "")
    .replace(/\b\d+\s*(PTAS?|PUERTAS)\b/g, "")
    .replace(/\bRIN\s+\d+\b/g, "")
    // Equipamiento (códigos GNP específicos)
    .replace(/C\/A\.?\s*/g, "")
    .replace(/A\.?C\.?\s*/g, "")
    .replace(/V\.E\.?\s*/g, "")
    .replace(/Q\.C\.?\s*/g, "")
    .replace(/V\.P\.?\s*/g, "")
    // Carrocería
    .replace(
      /\b(SEDAN|COUPE|CONVERTIBLE|CABRIO|HATCHBACK|SUV|VAN|WAGON)\b/g,
      ""
    )
    // Híbrido/Eléctrico
    .replace(/\b(HEV|MHEV|PHEV|EV|HYBRID|ELECTRICO?)\b/g, "");

  // Limpiar espacios múltiples
  versionLimpia = versionLimpia.replace(/\s+/g, " ").trim();

  // Lista de TRIMs válidos para GNP (ordenados por prioridad)
  const TRIMS_VALIDOS_GNP = [
    // Líneas deportivas/premium
    "SPORT LINE",
    "S LINE",
    "GT LINE",
    "FR LINE",
    "R LINE",
    "M SPORT",
    "AMG LINE",
    "RS LINE",
    // Trims compuestos
    "LIMITED PLUS",
    "PREMIUM PLUS",
    "SE PLUS",
    "XLT LIMITED",
    // Trims simples de alta frecuencia
    "SPORT",
    "LIMITED",
    "PREMIUM",
    "EXCLUSIVE",
    "ADVANCE",
    // Niveles de equipamiento
    "REFERENCE",
    "STYLE",
    "ACTIVE",
    "TRENDY",
    "BOLD",
    "LITE",
    // Nomenclaturas estándar
    "SE",
    "SEL",
    "SLE",
    "SR",
    "SV",
    "SL",
    "LX",
    "LXE",
    "LS",
    "LT",
    "LTZ",
    "GL",
    "GLS",
    "GLX",
    "XL",
    "XLE",
    "XLT",
    "GT",
    "GTE",
    "GTI",
    "GTS",
    "FR",
    "RS",
    "ST",
    // Básicos
    "BASE",
    "SIGNO",
    // Especiales
    "TURBO S",
    "CARRERA",
    "TARGA",
    "CONVERTIBLE S",
    "SKY SLIDER",
  ];

  // Buscar el TRIM más relevante
  for (const trim of TRIMS_VALIDOS_GNP) {
    if (versionLimpia.includes(trim)) {
      return trim;
    }
  }

  // Si después de toda la limpieza queda algo significativo (3+ caracteres), considerarlo
  if (versionLimpia.length >= 3 && versionLimpia.length <= 20) {
    // Verificar que no sea solo números o caracteres sin sentido
    if (!/^\d+$/.test(versionLimpia) && !/^[^A-Z]+$/.test(versionLimpia)) {
      return versionLimpia;
    }
  }

  // No se encontró TRIM válido
  return null;
}

// ==========================================
// INFERENCIA DE CARROCERÍA
// ==========================================

/**
 * Infiere el tipo de carrocería basándose en múltiples fuentes
 */
function inferirCarroceria(
  tipoVehiculo,
  esPickup,
  versionCorta,
  modelo,
  puertas
) {
  // Prioridad 1: Campo TipoVehiculo
  if (tipoVehiculo === "CA1" || esPickup === 1) {
    return "PICKUP";
  }

  // Prioridad 2: Especificación extraída de VersionCorta
  const specs = extraerEspecificaciones(versionCorta);
  if (specs.carroceria) {
    return specs.carroceria;
  }

  // Prioridad 3: Por nombre del modelo
  const modeloNorm = normalizarTexto(modelo);

  // SUVs conocidas
  if (
    /\b(CRV|CR-V|RAV4|TUCSON|SPORTAGE|X-TRAIL|TIGUAN|Q[357]|X[13567]|EXPLORER|HIGHLANDER|PILOT)\b/.test(
      modeloNorm
    )
  ) {
    return "SUV";
  }

  // Pickups conocidas
  if (
    /\b(RANGER|F-150|F150|SILVERADO|SIERRA|TACOMA|HILUX|FRONTIER|COLORADO|TUNDRA|TITAN|RIDGELINE|AMAROK|MAVERICK)\b/.test(
      modeloNorm
    )
  ) {
    return "PICKUP";
  }

  // Vans conocidas
  if (
    /\b(TRANSIT|SPRINTER|EXPRESS|SAVANA|PROMASTER|ODYSSEY|SIENNA|PACIFICA|CARNIVAL|SEDONA)\b/.test(
      modeloNorm
    )
  ) {
    return "VAN";
  }

  // Prioridad 4: Por número de puertas
  if (puertas === 2) return "COUPE";
  if (puertas === 5) return "HATCHBACK";
  if (puertas === 4) return "SEDAN";

  // No se puede determinar
  return null;
}

// ==========================================
// PROCESAMIENTO PRINCIPAL
// ==========================================

/**
 * Procesa todos los registros de GNP y genera el catálogo normalizado
 * ADVERTENCIA: No hay campo de activo, se procesan TODOS los registros
 */

// Obtener fecha actual para el proceso
const fechaProceso = new Date().toISOString();

// Procesar cada registro
const registros = [];
let contaminados = 0;
let sinTrim = 0;

for (const item of $input.all()) {
  const data = item.json;

  try {
    // Normalización básica
    const marcaNormalizada = normalizarMarca(data.marca);
    const modeloNormalizado = normalizarModelo(data.modelo, data.marca);

    // Detectar y limpiar contaminación
    const versionLimpia = limpiarContaminacion(
      data.version_completa,
      data.marca,
      data.modelo
    );
    if (versionLimpia !== data.version_completa) {
      contaminados++;
    }

    // Extraer componentes
    const transmisionNormalizada = normalizarTransmision(
      data.transmision_codigo,
      versionLimpia
    );

    const versionNormalizada = extraerTrim(
      versionLimpia,
      data.marca,
      data.modelo
    );
    if (!versionNormalizada) {
      sinTrim++;
    }

    const specs = extraerEspecificaciones(versionLimpia);

    const carroceriaNormalizada = inferirCarroceria(
      data.tipo_vehiculo,
      data.es_pickup,
      versionLimpia,
      data.modelo,
      specs.puertas
    );

    // Generación de identificadores
    const mainSpecs = [
      marcaNormalizada,
      modeloNormalizado,
      data.anio,
      transmisionNormalizada,
    ]
      .map((v) => v || "null")
      .join("|");

    const techSpecs = [
      versionNormalizada || "null",
      specs.motor_config || "null",
      specs.cilindrada || "null",
      specs.traccion || "null",
      carroceriaNormalizada || "null",
      "null", // ocupantes (GNP no proporciona)
    ].join("|");

    const hashComercial = generarHash(mainSpecs);
    const hashTecnico = generarHash(mainSpecs, techSpecs);

    // Crear registro normalizado
    const registro = {
      // Datos principales
      origen_aseguradora: ASEGURADORA,
      marca: marcaNormalizada,
      modelo: modeloNormalizado,
      anio: data.anio,
      transmision: transmisionNormalizada,
      version: versionNormalizada,

      // Especificaciones técnicas
      motor_config: specs.motor_config,
      cilindrada: specs.cilindrada,
      traccion: specs.traccion,
      carroceria: carroceriaNormalizada,
      numero_ocupantes: null, // GNP no proporciona

      // Concatenaciones
      main_specs: mainSpecs,
      tech_specs: techSpecs,

      // Hashes únicos
      hash_comercial: hashComercial,
      hash_tecnico: hashTecnico,

      // Metadata
      aseguradoras_disponibles: [ASEGURADORA],
      fecha_actualizacion: fechaProceso,

      // Datos originales para trazabilidad
      id_original: data.id_original,
      version_original: data.version_completa,
      activo: true, // GNP no tiene campo activo, asumimos todos activos
    };

    registros.push(registro);
  } catch (error) {
    console.error(
      `[GNP] Error procesando registro ${data.id_original}:`,
      error
    );
    // Continuar con el siguiente registro
  }
}

// Log de estadísticas
console.log(`[GNP] Procesados: ${registros.length} registros`);
console.log(
  `[GNP] Contaminados detectados: ${contaminados} (${(
    (contaminados / registros.length) *
    100
  ).toFixed(1)}%)`
);
console.log(
  `[GNP] Sin TRIM identificable: ${sinTrim} (${(
    (sinTrim / registros.length) *
    100
  ).toFixed(1)}%)`
);

// Retornar los registros procesados para n8n
return registros.map((item) => ({ json: item }));
