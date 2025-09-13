// ==========================================
// ETL NORMALIZACIÓN HDI - CATÁLOGO MAESTRO DE VEHÍCULOS
// Versión: 2.5 - Corrección completa y limpieza agresiva
// Fecha: 2025-09-07
// Autor: Sistema ETL Multi-Aseguradora
// ==========================================

/**
 * PROPÓSITO:
 * Normalizar datos de vehículos de la aseguradora HDI para integración
 * en catálogo maestro unificado.
 *
 * CAMBIOS v2.5:
 * - Eliminación AGRESIVA de "CP PUERTAS" y todas sus variantes
 * - Eliminación total de "BASE" en cualquier posición
 * - Eliminación completa de transmisiones (SPEEDSHIFT, MULTITRONIC, etc.)
 * - Eliminación completa de carrocerías de la versión
 * - Orden de limpieza optimizado (eliminar problemáticos primero)
 * - Validación estricta de versiones resultantes
 */

const ASEGURADORA = "HDI";
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
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Z0-9\s-]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Limpia texto preservando algunos caracteres necesarios
 */
function limpiarTextoCompleto(texto) {
  if (!texto) return "";

  return texto
    .replace(/["""'''`´¨]/g, "")
    .replace(/["']/g, "")
    .replace(/[\u0022\u0027]/g, "")
    .replace(/[\u201C\u201D\u2018\u2019]/g, "")
    .replace(/[\u00AB\u00BB]/g, "")
    .replace(/\\/g, "/")
    .replace(/[()]/g, " ")
    .replace(/\s+/g, " ")
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
 * Normaliza nombres de marcas aplicando sinónimos
 */
function normalizarMarca(marca) {
  if (!marca) return "";
  let marcaNorm = normalizarTexto(marca);

  const sinonimos = {
    VOLKSWAGEN: ["VW", "VOLKSWAGEN", "VOLKS WAGEN"],
    "MERCEDES BENZ": [
      "MERCEDES",
      "MERCEDES-BENZ",
      "MERCEDES BENZ",
      "MB",
      "MERCEDEZ",
    ],
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
    RAM: ["RAM", "DODGE RAM"],
    SEAT: ["SEAT", "CUPRA"],
  };

  for (const [marcaEstandar, variantes] of Object.entries(sinonimos)) {
    if (variantes.includes(marcaNorm)) {
      return marcaEstandar;
    }
  }

  return marcaNorm;
}

/**
 * Normaliza nombres de modelos eliminando redundancias y equipamiento
 */
function normalizarModelo(modelo, marca) {
  if (!modelo) return "";

  let modeloNorm = normalizarTexto(modelo);
  const marcaNorm = normalizarTexto(marca);

  // Eliminar marca del modelo si está presente
  if (marcaNorm && modeloNorm.startsWith(marcaNorm)) {
    modeloNorm = modeloNorm.substring(marcaNorm.length).trim();
  }

  // Limpiar paréntesis y contenido
  modeloNorm = modeloNorm.replace(/\([^)]*\)/g, "").trim();

  // Eliminar equipamiento que no debería estar en modelo
  modeloNorm = modeloNorm
    .replace(/\b(DVD|CD|GPS|NAV|NAVIGATION|BT|BLUETOOTH)\b/gi, "")
    .trim();
  modeloNorm = modeloNorm.replace(/\b(AA|AC|A\/C|EE|E\/E)\b/gi, "").trim();

  // Limpiar espacios múltiples resultantes
  modeloNorm = modeloNorm.replace(/\s+/g, " ").trim();

  return modeloNorm;
}

// ==========================================
// NORMALIZACIÓN DE TRANSMISIÓN
// ==========================================

/**
 * Normaliza transmisión usando campo dedicado o detección por texto
 */
function normalizarTransmision(codigo, textoTransmision, versionTexto) {
  // Prioridad 1: Campo dedicado de transmisión
  if (textoTransmision) {
    const trans = normalizarTexto(textoTransmision);

    // Automáticas
    if (["AUT", "AUTOMATICA", "AUTO", "AUTOMATIC", "ATD"].includes(trans))
      return "AUTO";
    if (
      ["CVT", "DSG", "PDK", "DCT", "STRONIC", "TRONIC", "9G TRONIC"].includes(
        trans
      )
    )
      return "AUTO";
    if (["TIP", "TIPTRONIC", "S-TRONIC", "DUALOGIC"].includes(trans))
      return "AUTO";
    if (["AUTOMATICA ECVT", "ASG", "HSD"].includes(trans)) return "AUTO";

    // Manuales
    if (["STD", "STANDARD", "ESTANDAR", "MANUAL", "MAN"].includes(trans))
      return "MANUAL";
    if (["SEL", "SELESPEED", "GEA", "MUT", "MUL"].includes(trans))
      return "MANUAL";
    if (trans === "S/A") return "MANUAL"; // Sin Aire = Manual en HDI
  }

  // Prioridad 2: Detectar en texto de versión
  if (versionTexto) {
    const texto = normalizarTexto(versionTexto);

    // Buscar patrones de automática
    if (/\b(AUT|AUTO|AUTOMATIC|CVT|DSG|PDK|DCT|TIPTRONIC)\b/.test(texto))
      return "AUTO";
    if (/\b(STRONIC|TRONIC|DUALOGIC|ASG)\b/.test(texto)) return "AUTO";

    // Buscar patrones de manual
    if (/\b(STD|STANDARD|MANUAL|MAN|ESTANDAR)\b/.test(texto)) return "MANUAL";
    if (/\b(SELESPEED|SEL)\b/.test(texto)) return "MANUAL";
  }

  return null;
}

// ==========================================
// EXTRACCIÓN Y NORMALIZACIÓN DE VERSIÓN
// ==========================================

/**
 * Extrae el trim/versión limpio del campo VersionCorta de HDI
 *
 * CAMBIO v2.5: Limpieza AGRESIVA y orden optimizado
 */
function normalizarVersion(versionCorta) {
  if (!versionCorta) return "";

  let texto = limpiarTextoCompleto(versionCorta);
  texto = normalizarTexto(texto);

  // === PASO 1: ELIMINAR PATRONES PROBLEMÁTICOS PRIMERO ===

  // Eliminar "BASE" y cualquier cosa que le siga
  texto = texto.replace(/\bBASE\s+CP\s+PUERTAS?\b/gi, "");
  texto = texto.replace(/\bBASE\s+CP\b/gi, "");
  texto = texto.replace(/\bBASE\s+\w+/gi, "");
  texto = texto.replace(/\bBASE\b/gi, "");

  // Eliminar "CP PUERTAS" y todas sus variantes
  texto = texto.replace(/\b\d+\s*CP\s+PUERTAS?\b/gi, "");
  texto = texto.replace(/\bCP\s+PUERTAS?\b/gi, "");
  texto = texto.replace(/\b\d+\s*CP\b/gi, "");
  texto = texto.replace(/\bCP\b/gi, "");

  // Eliminar números seguidos de PUERTAS/PTS/P
  texto = texto.replace(/\b\d+\s*PUERTAS?\b/gi, "");
  texto = texto.replace(/\b\d+\s*PTS?\b/gi, "");
  texto = texto.replace(/\b\d+P\b/gi, "");
  texto = texto.replace(/\bSEDAN\s*\d+P/gi, "");
  texto = texto.replace(/\bSEDAN\s*\d+\s*PTS?/gi, "");

  // === PASO 2: ELIMINAR CARROCERÍAS ===
  texto = texto.replace(/\b(SEDAN|COUPE|SUV|HATCHBACK|HB)\b/gi, "");
  texto = texto.replace(/\b(CONVERTIBLE|CABRIO|ROADSTER|SPIDER)\b/gi, "");
  texto = texto.replace(/\b(PICKUP|PICK UP|VAN|WAGON|ESTATE)\b/gi, "");
  texto = texto.replace(/\b(CROSSOVER|MINIVAN|SPORTBACK)\b/gi, "");
  texto = texto.replace(/\b(PANEL|CHASIS|CHASSIS|CARGA)\b/gi, "");

  // === PASO 3: ELIMINAR TRANSMISIONES Y VARIANTES ===
  // Transmisiones específicas primero
  texto = texto.replace(
    /\b(SPEEDSHIFT|MULTITRONIC|TIPTRONIC|STEPTRONIC)\b/gi,
    ""
  );
  texto = texto.replace(
    /\b(S[\s-]?TRONIC|STRONIC|SPORTMATIC|GEARTRONIC)\b/gi,
    ""
  );
  texto = texto.replace(
    /\b(DSG|CVT|CVTF|DCT|PDK|AMT|SMG|XTRONIC|POWERSHIFT)\b/gi,
    ""
  );
  texto = texto.replace(
    /\b(DUALOGIC|EASYTRONIC|DRIVELOGIC|SPORTSHIFT)\b/gi,
    ""
  );
  texto = texto.replace(
    /\b(7[\s-]?G[\s-]?TRONIC|9[\s-]?G[\s-]?TRONIC|G[\s-]?TRONIC)\b/gi,
    ""
  );

  // Transmisiones genéricas
  texto = texto.replace(/\b(AUTOMATICA|AUTOMATIC|AUTO|AUT|AT)\b/gi, "");
  texto = texto.replace(/\b(MANUAL|ESTANDAR|STD|EST|MAN|MT)\b/gi, "");
  texto = texto.replace(/\b(SELESPEED|SEL|GEA|MUT|MUL|ASG|HSD)\b/gi, "");

  // Velocidades
  texto = texto.replace(
    /\b\d+\s*(VEL|VELOCIDADES?|SPEED|SPD|CAMBIOS?|MARCHAS?)\b/gi,
    ""
  );
  texto = texto.replace(/\bAT\d*\b/gi, "");

  // === PASO 4: ELIMINAR ESPECIFICACIONES DE MOTOR ===
  texto = texto.replace(/\b[VIL]?\d+[VIL]?\b/gi, "");
  texto = texto.replace(/\b\d+\.?\d*[LT]\b/gi, "");
  texto = texto.replace(/\b\d+\.?\d*\s*L(ITROS?|TS?)?\b/gi, "");
  texto = texto.replace(/\b\d+\s*(CC|CM3|CILINDROS?|CYL|CIL)\b/gi, "");
  texto = texto.replace(/\b(TURBO|BITURBO|TWINTURBO|TSI|TDI|TFSI|FSI)\b/gi, "");
  texto = texto.replace(/\b(VTEC|VVTI|VVT-I|MIVEC|SKYACTIV)\b/gi, "");

  // === PASO 5: ELIMINAR POTENCIA ===
  texto = texto.replace(/\b\d+\s*(HP|CV|CP|BHP|PS|KW)\b/gi, "");
  texto = texto.replace(/\b\d+\s*(CABALLOS?|HORSES?)\b/gi, "");

  // === PASO 6: ELIMINAR TRACCIÓN ===
  texto = texto.replace(/\b(AWD|4WD|4X4|4X2|FWD|RWD|2WD)\b/gi, "");
  texto = texto.replace(/\b(QUATTRO|XDRIVE|4MATIC|4MOTION|ALL4)\b/gi, "");
  texto = texto.replace(/\b(TRACCION\s*(DELANTERA|TRASERA|INTEGRAL))\b/gi, "");

  // === PASO 7: ELIMINAR COMBUSTIBLE ===
  texto = texto.replace(
    /\b(DIESEL|GASOLINA|HIBRIDO|HYBRID|ELECTRICO|ELECTRIC|EV)\b/gi,
    ""
  );
  texto = texto.replace(/\b(TDI|HDI|CRDI|CDTI|DCI|BLUEHDI)\b/gi, "");

  // === PASO 8: ELIMINAR OCUPANTES ===
  texto = texto.replace(
    /\b\d+\s*(PASAJEROS?|OCUPANTES?|PLAZAS?|ASIENTOS?|PAX|PAS)\b/gi,
    ""
  );
  texto = texto.replace(/\bPASAJEROS?\b/gi, "");

  // === PASO 9: ELIMINAR EQUIPAMIENTO ===
  texto = texto.replace(
    /\b(AA|AC|A\/C|EE|E\/E|BA|CD|DVD|GPS|NAV|BT|BLUETOOTH)\b/gi,
    ""
  );
  texto = texto.replace(/\b(VDC|ABS|EBD|ESP|TCS|VSC|DSC)\b/gi, "");
  texto = texto.replace(/\b(DH|TA|VENTANAS?|QC)\b/gi, "");
  texto = texto.replace(/\bR\d{2}\b/gi, "");

  // === PASO 10: ELIMINAR PALABRAS FUNCIONALES ===
  texto = texto.replace(/\b(AMPLIA|TOLDO\s*ALTO)\b/gi, "");
  texto = texto.replace(/\b(AMBULANCIA)\b/gi, ""); // Mover a carrocería, no versión

  // === LIMPIEZA FINAL ===
  texto = texto.replace(/,/g, " ");
  texto = texto.replace(/\s+/g, " ").trim();

  // === VALIDACIÓN ===

  // Si quedó vacío o es solo números/una letra
  if (!texto || texto.match(/^\d+$/) || texto.match(/^[A-Z]$/)) {
    return "";
  }

  // Si es una palabra sospechosa sola
  const palabrasInvalidas = ["CIL", "CILINDROS", "PASAJEROS", "CARGA"];
  if (palabrasInvalidas.includes(texto)) {
    return "";
  }

  // Lista de trims válidos conocidos (sin BASE)
  const trimsValidos = new Set([
    // Niveles de equipamiento comunes
    "EXCLUSIVE",
    "ADVANCE",
    "SENSE",
    "SR",
    "GL",
    "GLS",
    "GLX",
    "GT",
    "GTI",
    "GTS",
    "SPORT",
    "DEPORTIVO",
    "ELEGANCE",
    "LUXURY",
    "LIMITED",
    "PREMIUM",
    "ULTIMATE",
    "PLATINUM",
    "S",
    "SE",
    "SEL",
    "SL",
    "SLE",
    "SLT",
    "SV",
    "LE",
    "LT",
    "LTZ",
    "LS",
    "LSX",
    "LX",
    "LXI",
    "EX",
    "EXL",
    "DX",
    "DXL",
    "RS",
    "RST",
    // Nombres específicos
    "LATITUDE",
    "LONGITUDE",
    "ALTITUDE",
    "CLASSIC",
    "COMFORT",
    "DYNAMIC",
    "PRESTIGE",
    "ACTIVE",
    "ALLURE",
    "FELINE",
    "GRIFFE",
    "TRENDLINE",
    "COMFORTLINE",
    "HIGHLINE",
    "STYLE",
    "XCELLENCE",
    "FR",
    "LIFE",
    "INTENS",
    "ZEN",
    "INTENSE",
    "ACCESS",
    "PLAY",
    "ICON",
    "TECHNO",
    "ESSENTIAL",
    "EVOLUTION",
    "EXCELLENCE",
    "REFERENCE",
    "STYLE PLUS",
    "XCELLENCE PLUS",
    "AMBITION",
    "ELEGANCE",
    "LAURIN KLEMENT",
    "SCOUT",
    "MONTE CARLO",
    "SPORTLINE",
    "ACTIVE PLUS",
    "AMBITION PLUS",
    "STYLE PLUS",
    "INSPIRE",
    "REFINE",
    // Performance
    "AMG",
    "M",
    "RS",
    "GTI",
    "ST",
    "SRT",
    "SS",
    "R",
    "JOHN COOPER WORKS",
    "JCW",
    "ABARTH",
    // Ediciones especiales
    "ANNIVERSARY",
    "EDITION",
    "SPECIAL",
    "BLACK",
    "WHITE",
  ]);

  // Buscar trim válido
  const palabras = texto.split(" ").filter((p) => p.length > 0);

  // Si es un trim conocido exacto
  if (trimsValidos.has(texto)) {
    return texto;
  }

  // Verificar trims compuestos (2-3 palabras)
  for (let i = 0; i < palabras.length - 2; i++) {
    const compuesto3 = `${palabras[i]} ${palabras[i + 1]} ${palabras[i + 2]}`;
    if (trimsValidos.has(compuesto3)) {
      return compuesto3;
    }
  }

  for (let i = 0; i < palabras.length - 1; i++) {
    const compuesto2 = `${palabras[i]} ${palabras[i + 1]}`;
    if (trimsValidos.has(compuesto2)) {
      return compuesto2;
    }
  }

  // Buscar trim simple válido
  for (const palabra of palabras) {
    if (trimsValidos.has(palabra)) {
      return palabra;
    }
  }

  // Si contiene AMG pero no otras cosas problemáticas
  if (texto.includes("AMG") && !texto.match(/\d/)) {
    return "AMG";
  }

  // Si es una sola palabra razonable (2-15 caracteres)
  if (
    palabras.length === 1 &&
    palabras[0].length >= 2 &&
    palabras[0].length <= 15
  ) {
    // Excluir S sola si no está en la lista de válidos
    if (palabras[0] === "S") return "S";
    if (!palabras[0].match(/^(AT|MT|CVT|DSG)$/)) {
      return palabras[0];
    }
  }

  // Si son 2-3 palabras y parecen un trim compuesto
  if (palabras.length >= 2 && palabras.length <= 3) {
    const trimFinal = palabras.join(" ");
    // Verificar que no contenga palabras problemáticas
    if (!trimFinal.match(/\b(AT|MT|CVT|DSG|SEDAN|COUPE|SUV)\b/)) {
      return trimFinal;
    }
  }

  return "";
}

// ==========================================
// EXTRACCIÓN DE ESPECIFICACIONES TÉCNICAS
// ==========================================

/**
 * Extrae especificaciones técnicas del campo VersionCorta de HDI
 */
function extraerEspecificaciones(versionCorta, numeroOcupantesOriginal) {
  const texto = normalizarTexto(versionCorta || "");
  const specs = {
    configuracion_motor: null,
    cilindrada_l: null,
    traccion: null,
    tipo_carroceria: null,
    numero_ocupantes: null,
  };

  // === Número de ocupantes/pasajeros ===
  const ocupantesMatch = texto.match(
    /(\d+)\s*(PASAJEROS?|OCUPANTES?|PLAZAS?|ASIENTOS?|PAX|PAS)\b/i
  );
  if (ocupantesMatch) {
    const ocupantes = parseInt(ocupantesMatch[1]);
    if (ocupantes >= 2 && ocupantes <= 23) {
      specs.numero_ocupantes = ocupantes;
    }
  }

  // === Configuración de Motor ===
  const motorMatch = texto.match(/\b([VIL]\d+[VILT]?)\b/i);
  if (motorMatch) {
    specs.configuracion_motor = motorMatch[1].toUpperCase();
  }

  if (!specs.configuracion_motor) {
    const motorSimple = texto.match(/\b([LV]\d)\b/i);
    if (motorSimple) {
      specs.configuracion_motor = motorSimple[1].toUpperCase();
    }
  }

  // Detectar turbo
  if (/\b(TURBO|BITURBO|TWINTURBO|TSI|TDI|TFSI)\b/i.test(texto)) {
    specs.configuracion_motor = specs.configuracion_motor
      ? `${specs.configuracion_motor} TURBO`
      : "TURBO";
  }

  // === Cilindrada ===
  const cilindradaMatch = texto.match(/(\d+\.?\d*)\s*[LT]\b/i);
  if (cilindradaMatch) {
    const cilindrada = parseFloat(cilindradaMatch[1]);
    // Validar rango razonable
    if (cilindrada >= 0.5 && cilindrada < 8.0) {
      specs.cilindrada_l = cilindrada;
    } else if (cilindrada === 8.0 && texto.includes("8.0L")) {
      // Solo aceptar 8.0L si está explícitamente escrito
      specs.cilindrada_l = cilindrada;
    }
  }

  // === Tracción ===
  if (/\b(AWD|ALL\s*WHEEL|QUATTRO|XDRIVE|4MATIC)\b/i.test(texto)) {
    specs.traccion = "AWD";
  } else if (/\b(4X4|4WD|FOUR\s*WHEEL)\b/i.test(texto)) {
    specs.traccion = "4X4";
  } else if (/\b(FWD|FRONT\s*WHEEL|TRACCION\s*DELANTERA)\b/i.test(texto)) {
    specs.traccion = "FWD";
  } else if (/\b(RWD|REAR\s*WHEEL|TRACCION\s*TRASERA)\b/i.test(texto)) {
    specs.traccion = "RWD";
  }

  // === Tipo de Carrocería ===
  // Incluir AMBULANCIA como tipo de carrocería especial
  if (/\b(AMBULANCIA)\b/i.test(texto)) {
    specs.tipo_carroceria = "VAN"; // Ambulancia es tipo VAN
  } else if (/\b(PICK\s*UP|TRUCK|CAMIONETA)\b/i.test(texto)) {
    specs.tipo_carroceria = "PICKUP";
  } else if (/\b(CHASIS\s*CABINA|CHASSIS)\b/i.test(texto)) {
    specs.tipo_carroceria = "CHASSIS";
  } else if (/\b(PANEL|CARGO\s*VAN|VAN)\b/i.test(texto)) {
    specs.tipo_carroceria = "VAN";
  } else if (/\b(SUV|SPORT\s*UTILITY|CROSSOVER|CUV)\b/i.test(texto)) {
    specs.tipo_carroceria = "SUV";
  } else if (/\b(SEDAN|BERLINE|SALOON)\b/i.test(texto)) {
    specs.tipo_carroceria = "SEDAN";
  } else if (/\b(HATCHBACK|HB|COMPACTO)\b/i.test(texto)) {
    specs.tipo_carroceria = "HATCHBACK";
  } else if (/\b(COUPE|COUP[EÉ])\b/i.test(texto)) {
    specs.tipo_carroceria = "COUPE";
  } else if (/\b(CONVERTIBLE|CABRIO|ROADSTER)\b/i.test(texto)) {
    specs.tipo_carroceria = "CONVERTIBLE";
  } else if (/\b(WAGON|ESTATE|FAMILIAR|TOURER)\b/i.test(texto)) {
    specs.tipo_carroceria = "WAGON";
  } else {
    // Intentar inferir por número de puertas
    const puertasMatch = texto.match(/(\d+)\s*PUERTAS?/i);
    if (puertasMatch) {
      const puertas = parseInt(puertasMatch[1]);
      if (puertas === 2) {
        specs.tipo_carroceria = "COUPE";
      } else if (puertas === 3) {
        specs.tipo_carroceria = "HATCHBACK";
      } else if (puertas === 4) {
        specs.tipo_carroceria = "SEDAN";
      } else if (puertas === 5) {
        specs.tipo_carroceria = "SUV";
      }
    }
  }

  // === Número de Ocupantes (si no se detectó antes) ===
  if (!specs.numero_ocupantes && numeroOcupantesOriginal) {
    const ocupantes = parseInt(numeroOcupantesOriginal);
    if (ocupantes >= 2 && ocupantes <= 23) {
      specs.numero_ocupantes = ocupantes;
    }
  }

  return specs;
}

// ==========================================
// PROCESAMIENTO PRINCIPAL
// ==========================================

const fechaProceso = new Date().toISOString();
const registros = [];

for (const item of $input.all()) {
  const data = item.json;

  // === PASO 1: NORMALIZACIÓN BÁSICA ===
  const marcaNormalizada = normalizarMarca(data.marca);
  const modeloNormalizado = normalizarModelo(data.modelo, data.marca);

  // === PASO 2: DETECCIÓN DE TRANSMISIÓN ===
  const transmisionNormalizada = normalizarTransmision(
    data.transmision_codigo,
    data.transmision_texto,
    data.version_corta || data.version_original
  );

  // === PASO 3: NORMALIZACIÓN DE VERSIÓN ===
  const versionNormalizada = normalizarVersion(
    data.version_corta || data.version_original
  );

  // === PASO 4: EXTRACCIÓN DE ESPECIFICACIONES ===
  const specs = extraerEspecificaciones(
    data.version_corta || data.version_original,
    data.numero_ocupantes_original
  );

  // === PASO 5: GENERAR CONCATENACIONES (ORDEN CRÍTICO) ===
  const mainSpecs = [
    marcaNormalizada,
    modeloNormalizado,
    data.año,
    transmisionNormalizada,
  ]
    .map((v) => v || "null")
    .join("|");

  const techSpecs = [
    versionNormalizada || "null",
    specs.configuracion_motor || "null",
    specs.cilindrada_l || "null",
    specs.traccion || "null",
    specs.tipo_carroceria || "null",
    specs.numero_ocupantes || "null",
  ].join("|");

  // === PASO 6: GENERAR HASHES ===
  const hashComercial = generarHash(mainSpecs);
  const hashTecnico = generarHash(mainSpecs, techSpecs);

  // === PASO 7: CREAR REGISTRO CON SCHEMA ESTÁNDAR ===
  const registro = {
    // Identificación
    origen_aseguradora: ASEGURADORA,

    // Datos principales
    marca: marcaNormalizada,
    modelo: modeloNormalizado,
    anio: data.año,
    transmision: transmisionNormalizada,
    version: versionNormalizada || null,

    // Especificaciones técnicas
    motor_config: specs.configuracion_motor,
    cilindrada: specs.cilindrada_l,
    traccion: specs.traccion,
    carroceria: specs.tipo_carroceria,
    numero_ocupantes: specs.numero_ocupantes,

    // Concatenaciones
    main_specs: mainSpecs,
    tech_specs: techSpecs,

    // Hashes únicos
    hash_comercial: hashComercial,
    hash_tecnico: hashTecnico,

    // Metadata
    aseguradoras_disponibles: [ASEGURADORA],
    fecha_actualizacion: fechaProceso,
  };

  registros.push(registro);
}

// Retornar para n8n
return registros.map((item) => ({ json: item }));
