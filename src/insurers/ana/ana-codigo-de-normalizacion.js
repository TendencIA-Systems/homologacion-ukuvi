/**
 * Ana ETL - Normalization Code Node
 *
 * Mirrors the insurer normalization pipeline used for Zurich/Qualitas/Chubb.
 * Intended to run inside an n8n Code node: it cleans ANA vehicle records,
 * infers transmissions when missing, extracts door/occupant tokens, and
 * outputs normalized objects ready for Supabase ingestion.
 */

const crypto = require("crypto");

// Specs to remove from MODELO field (should be in VERSION)
const MODELO_SPECS_TO_REMOVE = [
  "VAN",
  "WAGON",
  "SEDAN",
  "HATCHBACK",
  "HATCH BACK",
  "COUPE",
  "CONVERTIBLE",
  "SUV",
  "CROSSOVER",
  "CROSS COUNTRY",
  "PICK UP",
  "PICKUP",
  "RS",
  "GT",
  "GTI",
  "GTS",
  "AMG",
  "SRT",
  "S-LINE",
  // "R-LINE", // R-LINE removido - ahora protegido en PROTECTED_HYPHEN_TOKENS
  "M-SPORT",
  "TYPE-R",
  "TYPE-S",
  "A-SPEC",
  "NISMO",
  "TRD",
  "CROSS",
  "SPORT",
  "LUXURY",
  "LIMITED",
  "EXECUTIVE",
  "PREMIUM",
  "DERBY",
  "NUEVO",
  "NUEVA",
  "NEW",
  "JOYLONG",
  "EDITION",
  "SPECIAL",
  "ANNIVERSARY",
];

/**
 * Fix 1: Remove SERIE prefix from BMW models
 * Critical fix - applies to all insurers
 */
function cleanBMWModelo(marca, modelo) {
  if (!modelo) return modelo;

  // Only apply to BMW marca
  if (marca && marca.toUpperCase().trim() === "BMW") {
    // Remove "SERIE " prefix (case insensitive)
    modelo = modelo.replace(/^SERIE\s+/i, "").trim();
  }

  return modelo;
}

const ANA_NORMALIZATION_DICTIONARY = {
  irrelevant_comfort_audio: [
    // Audio/Navegación
    "AA",
    "A/A",
    "EE",
    "E/E",
    "E.E.",
    "CD",
    "DVD",
    "GPS",
    "BT",
    "USB",
    "MP3",
    "AM",
    "RA",
    "FX",
    "BOSE",
    "HIFI",
    "HARMAN KARDON",
    "HARMAN/KARDON",
    "BEATS",
    "JBL",
    "ALPINE",
    "SONY",
    "SIS/NAV",
    "SIS.NAV.",
    "SIS.NAV",
    "SIS NAV",
    "SIS.NAVEGACION",
    "SIST.NAV",
    "SIST NAV",
    "PAQ.NAVEG",
    "PAQ NAVEG",
    "PAQ.NAVEGACION",
    "PAQ NAV",
    "NAVEGACION",
    "NAVEG",
    "NAV.",
    "NAV",
    "NAVI",
    "NAVIGATOR",
    "RCD",
    "RNS",
    "MIB",
    "MMI",
    "REPRODUCTOR",
    "PANTALLA",
    "TOUCH SCREEN",
    "TOUCHSCREEN",
    "DISPLAY",
    "MONITOR",
    "BLUETOOTH",
    "AUX",
    "RADIO",
    "STEREO",
    "ESTEREO",
    "SOUND SYSTEM",
    "SISTEMA AUDIO",
    "AUDIO PREMIUM",
    "PREMIUM SOUND",
    // Confort
    "PIEL",
    "CUERO",
    "LEATHER",
    "TELA",
    "ALCANTARA",
    "GAMUZA",
    "VINYL",
    "VINIL",
    "ASIENTOS ELECTRICOS",
    "ASIENTOS ELECT",
    "QUEMACOCOS",
    "TECHO SOLAR",
    "SUNROOF",
    "S/ROOF",
    "PANORAMIC",
    "PANORAMICO",
    "CLIMATIZADOR",
    "CLIMA DUAL",
    "BI-ZONA",
    "BIZONA",
    "CALEFACCION",
    "VENTILACION",
    "ASIENTOS CALEFACTABLES",
    "ASIENTO GIRATORIO",
    "CLIMA",
    "KEYLESS",
    "CRUISE",
    "PARKING",
    "PADDLE",
    "SUSPENSION",
    // Safety (abreviaturas)
    "BA",
    "B/A",
    "ABS",
    "QC",
    "Q/C",
    "Q.C.",
    "VP",
    "V/P",
    "CA",
    "C/A",
    "A/C",
    "AC",
    "CE",
    "SQ",
    "CB",
    "CQ",
    "EQ",
    "SM",
    "VT",
    "DIS",
    "TAM",
    "EBD",
    "ESP",
    "VSC",
    "TCS",
    "PARK",
    "PARKTRONIC",
    "ALARM",
    "ALARMA",
    // Luces/Faros
    "XENON",
    "BIXENON",
    "BI-XENON",
    "LED",
    "HALOGENO",
    "HALOGENOS",
    "FOG",
    "HID",
    "LUCES LED",
    "FAROS LED",
    // Ruedas
    "R13",
    "R14",
    "R15",
    "R16",
    "R17",
    "R18",
    "R19",
    "R20",
    "R21",
    "R22",
    "R23",
    "RIN 13",
    "RIN 14",
    "RIN 15",
    "RIN 16",
    "RIN 17",
    "RIN 18",
    "RIN 19",
    "RIN 20",
    "RIN 21",
    "RIN 22",
    "ALEACION",
    "ALUMINIO",
    "LLANTAS ALEACION",
    "RUEDAS ALEACION",
    "RHYNE",
    "RHYNE SIZE",
    // Transmisión (redundantes)
    "STD",
    "STD.",
    "STANDARD",
    "AUT",
    "AUT.",
    "AUTO",
    "AUTOMATICA",
    "AUTOMATICO",
    "AUTOMATIC",
    "CVT",
    "DSG",
    "S TRONIC",
    "S-TRONIC",
    "R TRONIC",
    "TIPTRONIC",
    "TIPTRNIC",
    "SELESPEED",
    "SALESPEED",
    "Q-TRONIC",
    "DCT",
    "MULTITRONIC",
    "STEPTRONIC",
    "GEARTRONIC",
    "STRONIC",
    "SECUENCIAL",
    "DRIVELOGIC",
    "DUALOGIC",
    "SPEEDSHIFT",
    "G-TRONIC",
    "G TRONIC",
    "SPORTSHIFT",
    "TOUCHTRONIC3",
    "PDK",
    "MULTITRO",
    "MANUAL",
    "AUTOMATI",
    "AUTOMA",
    "AUTOM",
    // Paquetes
    "PAQ.",
    "PAQ",
    "PACK",
    "PKG",
    "PACKAGE",
    "KIT",
    "EQUIP.",
    "EQUIP",
    "EQUIPAMIENTO",
    "AS DE",
    "QCC",
    // Otros - ANA específicos
    "IMP",
    "CQ",
    "L.N",
    "VE",
    "FBX",
    "T.S",
    "T.P.",
    "CAM TRAS",
    "SENSOR",
    "CAMARA",
    "TBO",
    "FRENOS CERAM",
    "FRENOS CERAMICA",
    "COMFORT",
    "CONFORT",
  ],
  cylinder_normalization: {
    L3: "3CIL",
    L4: "4CIL",
    L5: "5CIL",
    L6: "6CIL",
    V6: "6CIL",
    V8: "8CIL",
    V10: "10CIL",
    V12: "12CIL",
    W12: "12CIL",
    H4: "4CIL",
    H6: "6CIL",
    I3: "3CIL",
    I4: "4CIL",
    I5: "5CIL",
    I6: "6CIL",
    R3: "3CIL",
    R4: "4CIL",
    R6: "6CIL",
    B4: "4CIL",
    B6: "6CIL",
  },
  transmission_normalization: {
    STD: "MANUAL",
    "STD.": "MANUAL",
    MANUAL: "MANUAL",
    MAN: "MANUAL",
    "MAN.": "MANUAL",
    "M/T": "MANUAL",
    MT: "MANUAL",
    SECUENCIAL: "MANUAL",
    DRIVELOGIC: "MANUAL",
    DUALOGIC: "MANUAL",
    TM: "MANUAL",
    ESTANDAR: "MANUAL",
    MEC: "MANUAL",
    MECANICA: "MANUAL",
    AUT: "AUTO",
    "AUT.": "AUTO",
    AUTO: "AUTO",
    "A/T": "AUTO",
    AT: "AUTO",
    TA: "AUTO",
    AUTOMATICA: "AUTO",
    AUTOMATICO: "AUTO",
    AUTOMATIC: "AUTO",
    AUTOMATI: "AUTO",
    AUTOMA: "AUTO",
    AUTOM: "AUTO",
    CVT: "AUTO",
    CVT7: "AUTO",
    DSG: "AUTO",
    "S TRONIC": "AUTO",
    "R TRONIC": "AUTO",
    "S-TRONIC": "AUTO",
    STRONIC: "AUTO",
    TIPTRONIC: "AUTO",
    TIPTRNIC: "AUTO",
    SELESPEED: "AUTO",
    SALESPEED: "AUTO",
    SPORTSHIFT: "AUTO",
    TOUCHTRONIC3: "AUTO",
    "Q-TRONIC": "AUTO",
    DCT: "AUTO",
    MULTITRONIC: "AUTO",
    STEPTRONIC: "AUTO",
    GEARTRONIC: "AUTO",
    SPEEDSHIFT: "AUTO",
    "G-TRONIC": "AUTO",
    "G TRONIC": "AUTO",
    PDK: "AUTO",
    MULTITRO: "AUTO",
  },
  regex_patterns: {
    year_codes: /\b(20\d{2})\b/g,
    multiple_spaces: /\s+/g,
    trim_spaces: /^\s+|\s+$/g,
  },
};

const RESIDUAL_SINGLE_TOKENS = new Set(["A", "B", "C", "E", "Q", "V", "P"]);

const NUMERIC_CONTEXT_TOKENS = new Set([
  "OCUP",
  "OCUPANTE",
  "OCUPANTES",
  "OCUPACION",
  "PASAJEROS",
  "PASAJERO",
  "PAS",
  "PUERTAS",
  "PUERTA",
  "PAX",
  "HP",
  "CV",
  "KW",
  "TON",
  "TONELADAS",
]);

const ANA_BRAND_ALIASES = {
  IZSUZU: "ISUZU",
  "MERCEDES-BENZ": "MERCEDES BENZ",
  MINI: "MINI", // MINI vehicles must be stored under MINI brand, not BMW
  "BMW MINI": "MINI",
  "MINI COOPER": "MINI",
  MINICOOPER: "MINI",
};

// ═══════════════════════════════════════════════════════════════════════════
// BRAND CONSOLIDATION MAP (Requirement 3.1-3.6)
// ═══════════════════════════════════════════════════════════════════════════
const BRAND_CONSOLIDATION_MAP = {
  // Suffix removal
  "BMW BW": "BMW",
  "VOLKSWAGEN VW": "VOLKSWAGEN",
  "CHEVROLET GM": "CHEVROLET",
  "FORD FR": "FORD",
  "AUDI II": "AUDI",

  // Variant consolidation
  "KIA MOTORS": "KIA",
  "TESLA MOTORS": "TESLA",
  "MERCEDES BENZ II": "MERCEDES BENZ",
  "NISSAN II": "NISSAN",
  "GREAT WALL MOTORS": "GREAT WALL",

  // Typo correction
  BERCEDES: "MERCEDES BENZ",
  BUIK: "BUICK",

  // Invalid brands (flag for deletion)
  AUTOS: "INVALID_BRAND",
  MOTOCICLETAS: "INVALID_BRAND",
  MULTIMARCA: "INVALID_BRAND",
  LEGALIZADO: "INVALID_BRAND",
};

const INVALID_TRANSMISSION_CODES = new Set([
  "",
  "-",
  "NA",
  "N/A",
  "S/D",
  "SD",
  "SIN DATO",
  "SIN INFORMACION",
  "SIN INFORMACIÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“N",
  "NO APLICA",
  "NO APL",
  "NO DEFINIDO",
]);

const NUMERIC_TRANSMISSION_MAP = {
  0: "",
  1: "MANUAL",
  2: "AUTO",
  0: "",
  1: "MANUAL",
  2: "AUTO",
};

const NORMALIZED_TRANSMISSIONS = new Set(["AUTO", "MANUAL"]);

const PROTECTED_HYPHEN_TOKENS = [
  {
    regex: /\bA[\s-]?SPEC\b/gi,
    placeholder: "__PROTECTED_A_SPEC__",
    canonical: "A-SPEC",
  },
  {
    regex: /\bTYPE[\s-]?S\b/gi,
    placeholder: "__PROTECTED_TYPE_S__",
    canonical: "TYPE-S",
  },
  {
    regex: /\bTYPE[\s-]?R\b/gi,
    placeholder: "__PROTECTED_TYPE_R__",
    canonical: "TYPE-R",
  },
  {
    regex: /\bTYPE[\s-]?F\b/gi,
    placeholder: "__PROTECTED_TYPE_F__",
    canonical: "TYPE-F",
  },
  {
    regex: /\bT5\b/gi,
    placeholder: "__PROTECTED_T5__",
    canonical: "T5",
  },
  {
    regex: /\bT6\b/gi,
    placeholder: "__PROTECTED_T6__",
    canonical: "T6",
  },
  {
    regex: /\bT7\b/gi,
    placeholder: "__PROTECTED_T7__",
    canonical: "T7",
  },
  {
    regex: /\bT8\b/gi,
    placeholder: "__PROTECTED_T8__",
    canonical: "T8",
  },
  {
    regex: /\bT9\b/gi,
    placeholder: "__PROTECTED_T9__",
    canonical: "T9",
  },
  {
    regex: /\bS[\s-]?LINE\b/gi,
    placeholder: "__PROTECTED_S_LINE__",
    canonical: "S-LINE",
  },
  {
    regex: /\bR[\s-]?LINE\b/gi,
    placeholder: "__PROTECTED_R_LINE__",
    canonical: "R-LINE",
  },
  {
    regex: /\bX[\s-]?DRIVE\b/gi,
    placeholder: "__PROTECTED_X_DRIVE__",
    canonical: "X-DRIVE",
  },
];

// ═══════════════════════════════════════════════════════════════════════════
// PROTECTED SPACE-SEPARATED TRIMS (ANA - Compact Set)
// ═══════════════════════════════════════════════════════════════════════════
// ANA has a focused trim set with core sport variants
const PROTECTED_SPACED_TRIMS_ANA = [
  // M-series (universal)
  "M SPORT",

  // I-series Mazda (CRÍTICO)
  "I GRAND TOURING", // ⭐ CRITICAL - 751 cases across insurers
  "I TOURING",
  "I SPORT",
  "I LUXURY",
  "I PREMIUM",

  // S-series Mazda
  "S GRAND TOURING", // ⭐ CRITICAL - 335 cases across insurers
  "S TOURING",
  "S SPORT",

  // R-series Mazda/Honda
  "R GRAND TOURING",
  "R TOURING",
  "R SPORT",
  "R LUXURY",

  // D-series (Diesel variants - menos común)
  "D GRAND TOURING",
  "D TOURING",

  // MX-series Mazda
  "MX GRAND TOURING",

  // Standalone (para casos sin prefijo)
  "GRAND TOURING", // ⭐ CRITICAL - 646 cases (standalone)
  "GRAND TOURING PLUS",

  // F-series Lexus
  "F SPORT",

  // E-series BMW
  "E SPORT",

  // MINI Cooper variants
  "JOHN COOPER WORKS",
  "COOPER WORKS",
  "COOPER S",

  // Ford/Chevrolet pickup trims
  "KING RANCH",
  "EDDIE BAUER",
  "HIGH COUNTRY",

  // Jeep
  "GRAND CHEROKEE",
];

/**
 * Protect space-separated trims by replacing spaces with placeholder
 * Handles multi-space variants (e.g., "M  SPORT", "M   SPORT")
 */
function protectTrims(version) {
  if (!version) return version;
  let protected = version;
  PROTECTED_SPACED_TRIMS_ANA.forEach((trim) => {
    const placeholder = trim.replace(/\s+/g, "_SPACE_");
    const pattern = trim.replace(/\s+/g, "\\s+");
    protected = protected.replace(
      new RegExp(`\\b${pattern}\\b`, "gi"),
      placeholder
    );
  });
  return protected;
}

/**
 * Restore space-separated trims by replacing placeholder with space
 */
function restoreTrims(version) {
  if (!version) return version;
  return version.replace(/_SPACE_/g, " ");
}

/**
 * Fixes concatenations where transmission tokens (AUT/STD/MAN) are stuck to trims
 * Example: "I SPORTAUT" → "I SPORT AUT", "S GRAND TOURINGAUT" → "S GRAND TOURING AUT"
 * Critical for El Potosí (16 concatenation cases) but added preventatively to all insurers
 */
function fixTrimConcatenations(version) {
  if (!version) return version;

  return (
    version
      // Mazda I-series concatenations (3-word patterns first)
      .replace(
        /\b(I\s+GRAND\s+TOURING)(AUT|STD|MAN|AUTOMATICA|ESTANDAR|TA|TM)\b/gi,
        "$1 $2"
      )
      // Mazda I-series concatenations (2-word patterns)
      .replace(
        /\b(I\s+(?:TOURING|SPORT|GT|LUXURY|PREMIUM))(AUT|STD|MAN|AUTOMATICA|ESTANDAR|TA|TM)\b/gi,
        "$1 $2"
      )
      // Mazda S-series concatenations (3-word patterns first)
      .replace(/\b(S\s+GRAND\s+TOURING)(AUT|STD|MAN|TA|TM)\b/gi, "$1 $2")
      // Mazda S-series concatenations (2-word patterns)
      .replace(
        /\b(S\s+(?:TOURING|SPORT|GT|HATCHBACK))(AUT|STD|MAN|TA|TM)\b/gi,
        "$1 $2"
      )
      // Other hyphenated trims concatenations
      .replace(/\b([A-Z]-(?:SPEC|LINE|SPORT))(AUT|STD|MAN|TA|TM)\b/gi, "$1 $2")
  );
}

function applyProtectedTokens(value = "") {
  let output = value;
  PROTECTED_HYPHEN_TOKENS.forEach(({ regex, placeholder }) => {
    output = output.replace(regex, placeholder);
  });
  return output;
}

function restoreProtectedTokens(value = "") {
  let output = value;
  PROTECTED_HYPHEN_TOKENS.forEach(({ placeholder, canonical }) => {
    const placeholderRegex = new RegExp(placeholder, "g");
    output = output.replace(placeholderRegex, canonical);
  });
  return output;
}

function expandTurboSuffix(text = "") {
  if (!text || typeof text !== "string") return "";
  return text.replace(/\b(\d+\.\d+)(?:L)?T\b/gi, (_, num) => `${num}L TURBO`);
}

function normalizeStandaloneLiters(value = "") {
  if (!value || typeof value !== "string") return "";
  return value.replace(
    /\b(\d+\.\d+)(?!\s*(?:L\b|TON|TONELADAS|KG|KILOGRAMOS|PUERTAS|OCUP|CIL))/gi,
    (match, _raw, offset, source) => {
      const liters = parseFloat(match);
      if (!Number.isFinite(liters) || liters < 0.5 || liters > 8) {
        return match;
      }
      const before = source
        .substring(Math.max(0, offset - 20), offset)
        .toUpperCase();
      if (/\b(TON|TONELADAS|KG|KILOGRAMOS|PESO|CAB|CHASIS)\b/.test(before)) {
        return match;
      }
      const after = source
        .substring(offset + match.length, offset + match.length + 20)
        .toUpperCase();
      if (/\b(PUERTAS|PTS?|OCUP|PASAJEROS?|PAS|CIL|SERIE)\b/.test(after)) {
        return match;
      }
      return `${match}L`;
    }
  );
}

function normalizeEngineDisplacement(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b(?<!\.)(\d)(\d)L\b/g, "$1.$2L")
    .replace(/\b(?<!\d\.)\d+L\b/g, (match) => `${match.slice(0, -1)}.0L`)
    .replace(/\b(?<!\d\.)\d+\s+L\b/g, (match) => {
      const digits = match.match(/\d+/)[0];
      return `${digits}.0L`;
    });
}

function collapseDisplacementArtifacts(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b(\d+CIL)\.0(?:\.0L)?\b/g, "$1")
    .replace(/\b(\d+CIL)\s+0\.0L\b/g, "$1")
    .replace(/\b(\d+(?:\.\d+)L)(?:\s*\1)+\b/g, "$1")
    .replace(/\b(\d+(?:\.\d+)L)L\b/g, "$1");
}

function normalizeCylinders(value = "") {
  if (!value || typeof value !== "string") return "";
  let normalized = value;
  Object.entries(ANA_NORMALIZATION_DICTIONARY.cylinder_normalization).forEach(
    ([from, to]) => {
      const spacedPattern = new RegExp(
        `\\b${escapeRegex(from)}\\s*(?=\\d+\\.?\\d*|\\s|$)`,
        "gi"
      );
      normalized = normalized.replace(spacedPattern, to);
      const exactPattern = new RegExp(`\\b${escapeRegex(from)}\\b`, "gi");
      normalized = normalized.replace(exactPattern, to);
    }
  );
  return normalized;
}

function normalizeDrivetrain(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\bALL[-\s]?WHEEL DRIVE\b/g, "AWD")
    .replace(/\b4MATIC\b/g, "AWD")
    .replace(/\bQUATTRO\b/g, "AWD")
    .replace(/\bQUARO\b/g, "AWD")
    .replace(/\bTRACCION\s+TOTAL\b/g, "AWD")
    .replace(/\bAWD\b/g, "AWD")
    .replace(/\b4\s*X\s*4\b/g, "4WD")
    .replace(/\b4\s*WD\b/g, "4WD")
    .replace(/\b4\s*WHEEL DRIVE\b/g, "4WD")
    .replace(/\bTRACCION\s+4X4\b/g, "4WD")
    .replace(/\bFRONT[-\s]?WHEEL DRIVE\b/g, "FWD")
    .replace(/\bTRACCION\s+DELANTERA\b/g, "FWD")
    .replace(/\bFWD\b/g, "FWD")
    .replace(/\bREAR[-\s]?WHEEL DRIVE\b/g, "RWD")
    .replace(/\bTRACCION\s+TRASERA\b/g, "RWD")
    .replace(/\b4\s*X\s*2\b/g, "RWD")
    .replace(/\b2WD\b/g, "RWD")
    .replace(/\bRWD\b/g, "RWD");
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * FIX INVALID DOOR COUNTS (Requirement 5.3)
 * ═══════════════════════════════════════════════════════════════════════════
 * Remove invalid door count patterns (BMW model numbers, truck notations, etc.)
 */
function fixInvalidDoorCounts(text) {
  if (!text || typeof text !== "string") return "";

  // BMW model numbers incorrectly parsed as doors
  const bmwModelNumbers = ["300", "320", "328", "335", "340", "350"];
  bmwModelNumbers.forEach((num) => {
    const regex = new RegExp(`\\b${num}PUERTAS\\b`, "g");
    text = text.replace(regex, "");
  });

  // Salvageable truck notation (3500 -> 4PUERTAS for crew cabs)
  text = text.replace(/\b3500PUERTAS\b/g, "4PUERTAS");

  // Invalid door count values (0, 1, 6, 8, 9, or any 3+ digit numbers)
  text = text.replace(/\b[0168-9]PUERTAS\b/g, "");
  text = text.replace(/\b\d{3,}PUERTAS\b/g, "");

  return text;
}

function cleanAnaModel(rawModel = "", marca = "") {
  const normalizedModel = normalizeText(rawModel);
  if (!normalizedModel) return "";

  let cleaned = normalizedModel;
  const normalizedMarca = marca ? marca.toUpperCase().trim() : "";

  if (normalizedMarca) {
    const variants = [normalizedMarca, normalizedMarca.replace(/\s+/g, "")];
    variants.forEach((variant) => {
      if (!variant) return;
      const startRegex = new RegExp(`^${escapeRegex(variant)}\\s*`);
      cleaned = cleaned.replace(startRegex, "");
      const inlineRegex = new RegExp(`\\s+${escapeRegex(variant)}\\b`, "g");
      cleaned = cleaned.replace(inlineRegex, " ");
    });
  }

  cleaned = cleaned
    .replace(/\b(NUEVO|NUEVA|NUEVA LINEA|NUEVALINEA|LINEA NUEVA|NEW)\b/g, " ")
    .replace(/\bPASAJEROS?\b/g, " ")
    .replace(/\bGENERACION\b/g, "GEN")
    .replace(/\bGEN\.?\b/g, "GEN");

  if (normalizedMarca === "FORD") {
    cleaned = cleaned.replace(/[-.]/g, " ");
    cleaned = cleaned.replace(
      /\b([A-Z])\s*(\d{2,4})\b/g,
      (_match, prefix, digits) => `${prefix}${digits}`
    );
  }

  if (/\bJETTA\b/.test(cleaned)) {
    cleaned = "JETTA";
  }

  if (
    (normalizedMarca === "BMW" || normalizedMarca === "MINI") &&
    (/\bMINI\b/.test(cleaned) || /\bCOOPER\b/.test(cleaned))
  ) {
    cleaned = "MINI COOPER";
  }

  // SERIE prefix extraction: If marca is 'BMW' and modelo starts with "SERIE ", extract the number
  if (normalizedMarca === "BMW" && /^SERIE\s+/.test(cleaned)) {
    cleaned = cleaned.replace(/^SERIE\s+/, ""); // "SERIE X5" → "X5"
  }

  // Trailing single-letter trim codes: Remove trailing I/A suffixes (e.g., "SERIE 1 I" → "SERIE 1")
  cleaned = cleaned.replace(/\s+[IA]+$/gi, "");

  cleaned = cleaned.replace(/\s+/g, " ").trim();
  return cleaned;
}

function cleanVersionString(versionString = "", model = "", marca = "") {
  if (!versionString || typeof versionString !== "string") return "";

  let cleaned = versionString.toUpperCase().trim();

  // NEW FIX 1: Remove escape characters (Requirement 5.1)
  cleaned = cleaned.replace(/\\"/g, ""); // Remove escaped quotes
  cleaned = cleaned.replace(/\\\\/g, ""); // Remove backslashes
  cleaned = cleaned.replace(/[""''\"'\u201C\u201D\u2018\u2019]/g, " "); // All quote types

  // FIX: Remove concatenations BEFORE protecting trims
  cleaned = fixTrimConcatenations(cleaned);

  cleaned = applyProtectedTokens(cleaned);

  // 🔥 v2.13.0 FIX: Normalize multiple spaces BEFORE protecting trims
  // This ensures that trim protection regex can match correctly
  // Fixes: "I  SPORT" (double space) → "I SPORT" (single space) → protected correctly
  cleaned = cleaned.replace(/\s+/g, ' ');

  // STAGE 5: TRIM PROTECTION - Protect space-separated trims before hyphen removal
  cleaned = protectTrims(cleaned);

  // 🔥 v2.13.0 FIX: Disabled destructive regex that was removing valid Mazda prefixes
  // This regex was designed to remove irrelevant prefixes like "C " from "C PREMIUM"
  // but was also incorrectly removing "I " from "I TOURING", "S " from "S SPORT"
  // Disabled because:
  // 1. Not essential for normalization
  // 2. High risk of corrupting valid Mazda trims (I, S, R, D prefixes)
  // 3. Protected trim mechanism handles this correctly

  // if (!cleaned.match(/^[A-Z]{1,2}_SPACE_/)) {
  //   cleaned = cleaned.replace(/^[A-Z]{1,2}\s+(?=[A-Z])/g, "");
  // }
  cleaned = cleaned.replace(/\bRA-?(\d+)\b/g, "RA$1");

  // NEW FIX 2: Separate HP from AUT (Requirement 5.2)
  cleaned = cleaned.replace(/(\d+)HPAUT/gi, "$1HP AUT");
  cleaned = cleaned.replace(/(\d+)HP([A-Z])/gi, "$1HP $2");

  cleaned = cleaned.replace(/[\/,]/g, " ");
  cleaned = cleaned.replace(/-/g, " ");
  cleaned = cleaned.replace(/AUT(?=[A-Z0-9])(?!O)/g, "AUT ");
  cleaned = cleaned.replace(/([A-Z0-9])AUT\b/g, "$1 AUT");

  // Remove NUEVO/NUEVA from version (Requirement 4.8)
  cleaned = cleaned.replace(/\b(NUEVO|NUEVA|NEW)\s+/gi, "");

  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeCylinders(cleaned);
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);
  cleaned = collapseDisplacementArtifacts(cleaned);
  cleaned = cleaned
    .replace(/\b0+(?:\.\d+)?\s*TON(?:ELADAS)?\b/gi, " ")
    .replace(/\bTONELADAS?\b/gi, "TON")
    .replace(/LTON\b/g, "L TON");
  cleaned = expandTurboSuffix(cleaned);
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)\s*CP\b/g, "$1HP");
  cleaned = cleaned.replace(/\b(\d+)\s*CC\b/g, "$1CC");
  cleaned = cleaned.replace(/\b(\d+\.\d+)I\b/g, "$1L");

  ANA_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach((token) => {
    const regex = new RegExp(`\\b${escapeRegex(token)}\\b`, "gi");
    cleaned = cleaned.replace(regex, " ");
  });

  // NEW: Remove generation/trim prefixes (A7, MK VII, etc.)
  cleaned = cleaned.replace(
    /\b(A[4-7]|MK\s*VII?I?|MKVII?I?|GEN\s*\d+)\s+/gi,
    ""
  );

  if (model) {
    cleaned = cleaned.replace(
      new RegExp(`\\b${escapeRegex(model.toUpperCase())}\\b`, "gi"),
      " "
    );
  }

  if (marca) {
    const normalizedMarca = marca.toUpperCase();
    const marcaVariants = [
      normalizedMarca,
      normalizedMarca.replace(/\s+/g, ""),
      normalizedMarca.split(" ")[0],
    ].filter(Boolean);
    marcaVariants.forEach((variant) => {
      cleaned = cleaned.replace(
        new RegExp(`\\b${escapeRegex(variant)}\\b`, "gi"),
        " "
      );
    });
  }

  cleaned = cleaned
    .replace(/\bHB\b/g, "HATCHBACK")
    .replace(/\bTUR\b/g, "TURBO")
    .replace(/\bCONV\b/g, "CONVERTIBLE")
    .replace(/\bPICK\s*UP\b/g, "PICKUP");

  // NEW: Remove body types from version
  cleaned = cleaned.replace(
    /\b(SEDAN|HATCHBACK|SUV|COUPE|CONVERTIBLE|PICKUP|VAN|WAGON)\b/gi,
    " "
  );

  // Convert PTAS → PUERTAS before removal (critical for token overlap)
  cleaned = cleaned.replace(/\b(\d+)\s*P(?:TAS?|TS?|TA)?\.?\b/gi, "$1PUERTAS");

  // NEW FIX 3: Remove invalid door counts (Requirement 5.3)
  cleaned = fixInvalidDoorCounts(cleaned);

  cleaned = cleaned
    .replace(/\b\d+\s*PUERTAS?\b/gi, " ")
    .replace(/\bPUERTAS?\b/gi, " ")
    .replace(/\b0?\d+\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX)\b/gi, " ")
    .replace(/\b0?\d+\s*(?:PASAJEROS?|PAS)\b/gi, " ");

  const { year_codes, multiple_spaces, trim_spaces } =
    ANA_NORMALIZATION_DICTIONARY.regex_patterns;
  cleaned = cleaned.replace(year_codes, " ");
  cleaned = cleaned.replace(/(?<!\d)[.,](?!\d)/g, " ");
  cleaned = cleaned.replace(/\bL\b/g, " ");

  cleaned = cleaned.replace(multiple_spaces, " ");
  cleaned = cleaned.replace(trim_spaces, "");

  cleaned = restoreProtectedTokens(cleaned);
  // STAGE 8: TRIM RESTORATION - Restore space-separated trims
  cleaned = restoreTrims(cleaned);
  cleaned = cleaned.replace(/CIL(?=\d)/g, "CIL ");
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)\s*HP\b/g, "$1HP");

  // NEW: Deduplicate tokens (critical for QUALITAS-like issues)
  const tokens = cleaned.split(/\s+/).filter(Boolean);
  const uniqueTokens = [...new Set(tokens)];
  cleaned = uniqueTokens.join(" ");

  cleaned = cleaned.replace(/\s+/g, " ").trim();

  return cleaned;
}

function extractDoorsAndOccupants(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") {
    return { doors: "", occupants: "" };
  }
  const upper = versionOriginal.toUpperCase();
  const doorsMatch = upper.match(
    /\b(\d{1,2})\s*(?:P(?:UERTAS?|TAS?|TS?|TA)?|PUERTAS?|P)\b/
  );
  let doors = "";
  if (doorsMatch) {
    const doorCount = parseInt(doorsMatch[1], 10);
    if ([2, 3, 4, 5, 7].includes(doorCount)) {
      doors = `${doorCount}PUERTAS`;
    }
  }
  const occMatch = upper.match(
    /\b0?(\d{1,2})\s*(?:OCUPANTES?|OCUP|OCU|OC|PAX|PASAJEROS?|PAS)\b/
  );
  let occupants = "";
  if (occMatch) {
    const occCount = parseInt(occMatch[1], 10);
    if (Number.isFinite(occCount) && occCount >= 2 && occCount <= 23) {
      occupants = `${occCount}OCUP`;
    }
  }
  return { doors, occupants };
}

function normalizeTransmission(code) {
  if (code === null || code === undefined) return "";
  if (NUMERIC_TRANSMISSION_MAP.hasOwnProperty(code)) {
    const mapped = NUMERIC_TRANSMISSION_MAP[code];
    return mapped || "";
  }

  const normalized = code.toString().toUpperCase().trim();
  if (!normalized || INVALID_TRANSMISSION_CODES.has(normalized)) return "";
  if (/^\d+$/.test(normalized)) {
    return NUMERIC_TRANSMISSION_MAP[normalized] || "";
  }

  const mapped =
    ANA_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] ||
    normalized;
  if (NORMALIZED_TRANSMISSIONS.has(mapped)) return mapped;
  return "";
}

function inferTransmissionFromVersion(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") return "";
  const version = versionOriginal.toUpperCase();
  for (const code of Object.keys(
    ANA_NORMALIZATION_DICTIONARY.transmission_normalization
  )) {
    const regex = new RegExp(`\\b${escapeRegex(code)}\\b`, "i");
    if (regex.test(version)) {
      const normalized = normalizeTransmission(code);
      if (normalized) return normalized;
    }
  }
  return "";
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * RECOVER TRANSMISSION (Requirement 2.0-2.5)
 * ═══════════════════════════════════════════════════════════════════════════
 * Extract valid transmission from contaminated fields with fallback inference
 */
function recoverTransmission(record) {
  if (!record) return null;

  const transmisionField = (record.transmision || "")
    .toString()
    .toUpperCase()
    .trim();
  const versionOriginal = (record.version_original || "").toString();

  // Step 1: Try to extract from contaminated transmision field
  const validPatterns = [
    "AUTO",
    "AUTOMATIC",
    "AUTOMATICO",
    "AUTOMATICA",
    "MANUAL",
    "STD",
    "STANDARD",
    "CVT",
    "DSG",
    "TIPTRONIC",
    "STEPTRONIC",
    "GEARTRONIC",
    "GEARTR",
    "S-TRONIC",
    "S TRONIC",
    "STRONIC",
    "TRONIC",
    "MULTITRONIC",
    "SPORTSHIFT",
    "POWERSHIFT",
  ];

  for (const pattern of validPatterns) {
    if (transmisionField.includes(pattern)) {
      const normalized = normalizeTransmission(pattern);
      if (normalized === "AUTO" || normalized === "MANUAL") {
        return normalized;
      }
    }
  }

  // Step 2: Infer from version_original
  const inferred = inferTransmissionFromVersion(versionOriginal);
  if (inferred === "AUTO" || inferred === "MANUAL") {
    return inferred;
  }

  // Step 3: Cannot recover - return null (record will be discarded)
  return null;
}

/**
 * Detecta si un token es una especificación con número
 * Ejemplos: "5PUERTAS", "4CIL", "2.0L", "200HP", "7OCUP"
 */
function isNumericSpecification(token) {
  if (!token || typeof token !== "string") return false;
  return /^\d+(\.\d+)?(PUERTAS?|OCUP|CIL|HP|L|KG|TON|PAX)$/i.test(token);
}

/**
 * Deduplica tokens de forma inteligente
 * - Elimina duplicados NO consecutivos (5PUERTAS ... 5PUERTAS)
 * - Preserva números puros (2.0L y 2PUERTAS pueden coexistir)
 * - Mantiene primera ocurrencia de cada especificación
 */
function deduplicateTokens(tokens) {
  const seen = new Map();
  const dedupedTokens = [];

  tokens.forEach((token) => {
    const normalized = token.trim().toUpperCase();
    if (!normalized) return;

    // Caso 1: Especificaciones numéricas (5PUERTAS, 4CIL, etc)
    if (isNumericSpecification(normalized)) {
      const specType = normalized.replace(/^\d+(\.\d+)?/, "");
      if (seen.has(`spec_${specType}`)) return;
      seen.set(`spec_${specType}`, normalized);
      dedupedTokens.push(normalized);
      return;
    }

    // Caso 2: Tokens alfanuméricos normales
    if (!/^\d+(\.\d+)?(L|HP)?$/.test(normalized)) {
      if (seen.has(normalized)) return;
      seen.set(normalized, true);
      dedupedTokens.push(normalized);
      return;
    }

    // Caso 3: Números puros o con unidades
    dedupedTokens.push(normalized);
  });

  return dedupedTokens;
}

/**
 * Elimina tokens duplicados preservando el orden
 * @deprecated Use deduplicateTokens() instead for intelligent deduplication
 */
function dedupeTokens(tokens = []) {
  return deduplicateTokens(tokens);
}

const BATCH_SIZE = 5000;

function normalizeAnaData(records = []) {
  const results = [];
  const errors = [];

  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const batch = records.slice(i, i + BATCH_SIZE);
    for (const record of batch) {
      try {
        const processed = processAnaRecord(record);
        results.push(processed);
      } catch (error) {
        errors.push({
          error: true,
          mensaje: error.message,
          id_original: record.id_original,
          codigo_error: categorizeError(error),
          registro_original: record,
          fecha_error: new Date().toISOString(),
        });
      }
    }
  }

  return { results, errors };
}

function normalizeAnaRecords(items = []) {
  const rawRecords = items.map((item) =>
    item && item.json ? item.json : item
  );
  const { results, errors } = normalizeAnaData(rawRecords);
  const successItems = results.map((record) => ({ json: record }));
  const errorItems = errors.map((error) => ({ json: error }));
  return [...successItems, ...errorItems];
}

function processAnaRecord(record) {
  let marcaNormalizada = normalizeMarca(record.marca);
  marcaNormalizada = consolidateBrand(marcaNormalizada);

  // Skip records with invalid brands (Requirement 3.4)
  if (marcaNormalizada === "INVALID_BRAND") {
    throw new Error(
      "Invalid brand category: AUTOS/MOTOCICLETAS/MULTIMARCA/LEGALIZADO"
    );
  }

  const modeloNormalizado = cleanAnaModel(record.modelo, marcaNormalizada);
  const modeloFinal = modeloNormalizado || normalizeText(record.modelo);

  // Use enhanced transmission recovery function (Requirement 2.0-2.5)
  const recoveredTransmission = recoverTransmission(record);
  if (!recoveredTransmission) {
    throw new Error(
      "TRANSMISSION_INFERENCE_FAILED: Cannot recover transmission from field or version"
    );
  }
  record.transmision = recoveredTransmission;

  // STEP 1: Extract specs from modelo before cleaning
  const modeloSpecs = [];
  const originalModelo = (record.modelo || "").toUpperCase().trim();

  MODELO_SPECS_TO_REMOVE.forEach((spec) => {
    const pattern = new RegExp(
      `\\b${spec.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`,
      "gi"
    );
    const match = originalModelo.match(pattern);
    if (match && match[0]) {
      modeloSpecs.push(match[0]);
    }
  });

  // Also extract content in parentheses
  const parenMatch = originalModelo.match(/\(([^)]+)\)/);
  if (parenMatch && parenMatch[1]) {
    modeloSpecs.push(parenMatch[1]);
  }

  // STEP 2: Enhance version with extracted specs
  const versionOriginal = record.version_original || "";
  let enhancedVersion = versionOriginal;
  if (modeloSpecs.length > 0) {
    enhancedVersion = `${modeloSpecs.join(" ")} ${versionOriginal}`.trim();
  }

  const { doors, occupants } = extractDoorsAndOccupants(versionOriginal);

  const validation = validateRecord({
    ...record,
    marca: marcaNormalizada,
    modelo: modeloFinal,
    transmision: record.transmision,
  });
  if (!validation.isValid) {
    throw new Error(`Validation failed: ${validation.errors.join(", ")}`);
  }

  let versionLimpia = cleanVersionString(
    enhancedVersion,
    modeloFinal || "",
    marcaNormalizada || ""
  );
  versionLimpia = versionLimpia.replace(/\b(\d+\.\d+)L?T\b/g, "$1L TURBO");
  versionLimpia = versionLimpia
    .replace(/\b\d\s*P(?:TAS?|TS?|TA)?\.?\b/gi, " ")
    .replace(/\b\d+\s*PUERTAS?\b/gi, " ")
    .replace(/\b0?\d+\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX)\b/gi, " ")
    .replace(/\b0?\d+\s*(?:PASAJEROS?|PAS)\b/gi, " ")
    .replace(/\s+[.,](?=\s|$)/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  const tokens = versionLimpia.split(" ").filter(Boolean);
  let fallbackDoors = "";
  const sanitizedTokens = [];

  tokens.forEach((token, idx, arr) => {
    if (!token) return;
    if (/^[\.,]$/.test(token)) return;
    if (/^\d+$/.test(token)) {
      const next = (arr[idx + 1] || "").toUpperCase();
      const prev = (arr[idx - 1] || "").toUpperCase();
      if (
        /^\d+OCUP$/i.test(next) ||
        NUMERIC_CONTEXT_TOKENS.has(next) ||
        NUMERIC_CONTEXT_TOKENS.has(prev)
      ) {
        return;
      }
      if (!doors && !fallbackDoors) {
        const numericValue = parseInt(token, 10);
        if ([2, 3, 4, 5, 7].includes(numericValue)) {
          fallbackDoors = `${numericValue}PUERTAS`;
          return;
        }
      }
      sanitizedTokens.push(token);
      return;
    }
    const upperToken = token.toUpperCase();
    if (upperToken.length === 1 && RESIDUAL_SINGLE_TOKENS.has(upperToken))
      return;
    sanitizedTokens.push(token);
  });

  versionLimpia = dedupeTokens(sanitizedTokens)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\bABS\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  const finalDoors = doors || fallbackDoors;
  versionLimpia = [versionLimpia, finalDoors, occupants]
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();

  const normalized = {
    origen_aseguradora: "ANA",
    id_original: record.id_original,
    marca: marcaNormalizada,
    modelo: normalizeModelo(marcaNormalizada, modeloFinal),
    anio: record.anio,
    transmision: record.transmision,
    version_original: record.version_original,
    version_limpia: versionLimpia,
    fecha_procesamiento: new Date().toISOString(),
  };

  normalized.hash_comercial = createCommercialHash(normalized);
  return normalized;
}

/**
 * Normalize modelo field to remove contamination patterns before hash generation
 * ENHANCED VERSION - adds NUEVO prefix, trim levels, body types, and letter spacing fixes
 * ANA-SPECIFIC: Removes "MA" prefix from Mazda models and "CHASIS" from all models
 * Fixes 4,641 cases of modelo contamination identified in analysis
 */
function normalizeModelo(marca, modelo) {
  if (!modelo || typeof modelo !== "string") return "";

  let normalized = modelo.toUpperCase().trim();
  const marcaUpper = (marca || "").toUpperCase().trim();

  // ═══════════════════════════════════════════════════════════════════════════
  // INLINE MODELO NORMALIZATION (Issues #1-4 Fix)
  // ═══════════════════════════════════════════════════════════════════════════

  // Issue #1: HONDA hyphenation normalization
  if (marcaUpper === "HONDA") {
    // Normalize spaces to hyphens first
    normalized = normalized.replace(/\bHR\s+V\b/g, "HR-V");
    normalized = normalized.replace(/\bBR\s+V\b/g, "BR-V");
    normalized = normalized.replace(/\bCR\s+V\b/g, "CR-V");
    // Then normalize no-hyphen to hyphenated
    normalized = normalized.replace(/\bHRV\b/g, "HR-V");
    normalized = normalized.replace(/\bBRV\b/g, "BR-V");
    normalized = normalized.replace(/\bCRV\b/g, "CR-V");
  }

  // Issue #2: MAZDA brand prefix removal & hyphenation (ANA has CX5 no-hyphen)
  if (marcaUpper === "MAZDA") {
    // Remove "MAZDA " prefix
    normalized = normalized.replace(/^MAZDA\s+/gi, "");
    // Normalize spaces to hyphens
    normalized = normalized.replace(/\bCX\s+(\d+)\b/g, "CX-$1");
    normalized = normalized.replace(/\bMX\s+(\d+)\b/g, "MX-$1");
    // Normalize no-hyphen to hyphenated
    normalized = normalized.replace(/\bCX(\d+)\b/g, "CX-$1");
    normalized = normalized.replace(/\bMX(\d+)\b/g, "MX-$1");
  }

  // Issue #3: VOLKSWAGEN JETTA generation prefix removal (ANA has "JETTA MK VII")
  if (marcaUpper === "VOLKSWAGEN") {
    normalized = normalized.replace(/\s*MK\s*VII?I?/gi, "");
    normalized = normalized.replace(/\s*MKVII?I?/gi, "");
    normalized = normalized.replace(/\s*GEN\.?\s*\d+/gi, "");
    normalized = normalized.replace(/\s*A[4-7]\b/gi, "");
  }

  // 1. Remove NUEVO/NUEVA/NEW prefix (1,195 cases) - Requirement 4.8
  normalized = normalized.replace(/^(NUEVO|NUEVA|NEW)\s+/gi, "");

  // Remove specs from modelo using MODELO_SPECS_TO_REMOVE
  MODELO_SPECS_TO_REMOVE.forEach((spec) => {
    const pattern = new RegExp(
      `\\b${spec.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`,
      "gi"
    );
    normalized = normalized.replace(pattern, " ");
  });

  // Remove content in parentheses
  normalized = normalized.replace(/\([^)]+\)/g, " ");

  // 2. ANA-SPECIFIC: Remove "MA" prefix from Mazda models (Requirement 7.4)
  if (marcaUpper === "MAZDA") {
    normalized = normalized.replace(/^MA\s+/gi, "");
  }

  // 3. ANA-SPECIFIC: Remove "CHASIS" from all models (Requirement 7.4)
  normalized = normalized.replace(/\bCHASIS\b/gi, "");

  // 4. Remove generic prefixes (PICK UP, CAMIONETA, VAN, TRUCK)
  normalized = normalized.replace(/^PICK\s*UP\s+/gi, "");
  normalized = normalized.replace(/^PICK-UP\s+/gi, "");
  normalized = normalized.replace(/^CAMIONETA\s+/gi, "");
  normalized = normalized.replace(/^VAN\s+/gi, "");
  normalized = normalized.replace(/^TRUCK\s+/gi, "");

  // 5. Remove brand name if repeated in model field
  if (marcaUpper) {
    const brandPattern = new RegExp(
      `^${marcaUpper.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s+`,
      "gi"
    );
    normalized = normalized.replace(brandPattern, "");
  }

  // 6. Remove trim level/generation from modelo (72 cases) - Requirement 4.6
  normalized = normalized.replace(/\s+(MK\s*VII?I?|MKVII?I?|GEN\s*\d+)$/gi, "");

  // 7. Remove body type from modelo (2,084 cases) - Requirement 4.4
  normalized = normalized.replace(
    /\s+(SEDAN|HATCHBACK|SUV|COUPE|CONVERTIBLE|PICKUP|VAN|WAGON)$/gi,
    ""
  );

  // 8. Collapse spaces in letter+number models (1,290 cases) - Requirement 4.3
  // "A 3" → "A3", "E TRON" → "ETRON", "T T" → "TT"
  normalized = normalized.replace(/^([A-Z])\s+([A-Z0-9])/g, "$1$2");

  // 8b. E-TRON needs hyphen (special case)
  normalized = normalized.replace(/\bETRON\b/g, "E-TRON");

  // 9. Remove single letter trim codes (e.g., "C 1500" → "1500")
  normalized = normalized.replace(/\s+([A-Z])\s+(\d)/g, " $2");

  // 10. Remove cab type and configuration codes
  normalized = normalized.replace(/\s+CAB\.?\s*REG\.?(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+CAB\.?\s*REGULAR(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+CREW\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+QUAD\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+MEGA\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+SUPER\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+KING\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+DOBLE\s+CABINA(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+SENCILLA\s+CABINA(?:\s+|$)/gi, " ");

  // 11. Remove standalone trim codes at end
  normalized = normalized.replace(/\s+(DR|WT|SL|SLE|SLT)$/gi, "");

  // 12. Remove trim level suffixes from end
  normalized = normalized.replace(
    /\s+(CREW|QUAD|MEGA|SUPER|KING)\s+CAB$/gi,
    ""
  );
  normalized = normalized.replace(/\s+(DOBLE|SENCILLA)\s+CABINA$/gi, "");

  // FIX 1: BMW SERIE cleanup (applies to all insurers)
  normalized = cleanBMWModelo(marca, normalized);

  // Final cleanup
  normalized = normalized.replace(/\s+/g, " ").trim();

  return normalized;
}

function createCommercialHash(vehicle) {
  const normalizedModelo = normalizeModelo(vehicle.marca, vehicle.modelo);

  const key = [
    vehicle.marca || "",
    normalizedModelo || "",
    vehicle.anio ? vehicle.anio.toString() : "",
    vehicle.transmision || "",
  ]
    .join("|")
    .toLowerCase()
    .trim();
  return crypto.createHash("sha256").update(key).digest("hex");
}

function validateRecord(record) {
  const errors = [];

  if (!record.marca || record.marca.toString().trim() === "") {
    errors.push("marca is required");
  }
  if (!record.modelo || record.modelo.toString().trim() === "") {
    errors.push("modelo is required");
  }
  if (!record.anio || record.anio < 1990 || record.anio > 2035) {
    errors.push("anio must be between 2000-2030");
  }
  if (
    !record.version_original ||
    record.version_original.toString().trim() === ""
  ) {
    errors.push("version is required");
  }

  const normalizedTransmission = record.transmision
    ? record.transmision.toString().trim().toUpperCase()
    : "";
  if (!NORMALIZED_TRANSMISSIONS.has(normalizedTransmission)) {
    errors.push("transmision is required");
  } else {
    record.transmision = normalizedTransmission;
  }

  return { isValid: errors.length === 0, errors };
}

function normalizeMarca(value) {
  const normalized = normalizeText(value);
  if (!normalized) return "";
  return ANA_BRAND_ALIASES[normalized] || normalized;
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * CONSOLIDATE BRAND (Requirement 3.1-3.6)
 * ═══════════════════════════════════════════════════════════════════════════
 * Apply centralized brand consolidation after initial normalization
 */
function consolidateBrand(marca) {
  if (!marca || typeof marca !== "string") return "";
  const normalized = marca.toUpperCase().trim();
  return BRAND_CONSOLIDATION_MAP[normalized] || normalized;
}

function normalizeText(value) {
  return value ? value.toString().trim().toUpperCase() : "";
}

function categorizeError(error) {
  const message = error.message.toLowerCase();
  if (message.includes("validation")) return "VALIDATION_ERROR";
  if (message.includes("hash")) return "HASH_GENERATION_ERROR";
  return "NORMALIZATION_ERROR";
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const outputItems = normalizeAnaRecords(items);
return outputItems;
