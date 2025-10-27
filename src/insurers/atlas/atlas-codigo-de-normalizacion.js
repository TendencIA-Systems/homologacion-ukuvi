/**
 * Atlas ETL - Normalization Code Node
 *
 * Mirrors the insurer normalization pipeline used for Zurich/Qualitas/Chubb.
 * Intended to run inside an n8n Code node: it cleans Atlas vehicle records,
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
  MINI: "MINI", // MINI vehicles must be stored under MINI brand, not BMW

  // Typo correction
  BERCEDES: "MERCEDES BENZ",
  BUIK: "BUICK",

  // Invalid brands (flag for deletion)
  AUTOS: "INVALID_BRAND",
  MOTOCICLETAS: "INVALID_BRAND",
  MULTIMARCA: "INVALID_BRAND",
  LEGALIZADO: "INVALID_BRAND",
};

function consolidateBrand(marca) {
  const normalized = marca.toUpperCase().trim();
  return BRAND_CONSOLIDATION_MAP[normalized] || normalized;
}

const ATLAS_NORMALIZATION_DICTIONARY = {
  irrelevant_comfort_audio: [
    // Audio/Navegación
    "AA",
    "EE",
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
    "HARMAN KARDON",
    "HARMAN/KARDON",
    "BEATS",
    "JBL",
    "ALPINE",
    "SONY",
    "SIS/NAV",
    "SIS.NAV.",
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
    // Confort
    "PIEL",
    "CUERO",
    "LEATHER",
    "TELA",
    "ALCANTARA",
    "GAMUZA",
    "VINYL",
    "ASIENTOS ELECTRICOS",
    "ASIENTOS ELECT",
    "QUEMACOCOS",
    "TECHO SOLAR",
    "SUNROOF",
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
    // Safety (abreviaturas)
    "BA",
    "B.A.",
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
    "SM",
    "VT",
    "DIS",
    "TAM",
    "RDC",
    "HUD",
    "EBD",
    "ESP",
    "VSC",
    "TCS",
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
    // Transmisión (redundantes) + Transmission specs for inference then removal
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
    "TIPRONIC",
    "SELESPEED",
    "SALESPEED",
    "Q-TRONIC",
    "DCT",
    "MULTITRONIC",
    "STEPTRONIC",
    "GEARTRONIC",
    "STRONIC", // Audi DSG - for inference (33 occurrences in Atlas) then removal
    "XTRONIC", // Nissan CVT - for inference then removal
    "X-TRONIC", // Nissan CVT hyphenated - for inference then removal
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
    // Otros
    "DH",
    "C",
    "FBX",
    "IMP",
    "T.S",
    "T.P.",
    "CAM TRAS",
    "CAMARA TRASERA",
    "CAMARA",
    "SENSOR",
    "SENSORES",
    "TBO",
    "FRENOS CERAM",
    "FRENOS CERAMICA",
    "XENON",
    "LED",
    "BI-XENON",
    "BIXENON",
    "LUCES LED",
    "FAROS LED",
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
    AUTOMATICO: "AUTO",
    AUTOMATICA: "AUTO",
    AUTOMATIC: "AUTO",
    CVT: "AUTO",
    CVT7: "AUTO",
    DSG: "AUTO",
    "S TRONIC": "AUTO",
    "S-TRONIC": "AUTO",
    STRONIC: "AUTO",
    TIPTRONIC: "AUTO",
    TIPTRNIC: "AUTO",
    TIPRONIC: "AUTO",
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

const INVALID_TRANSMISSION_CODES = new Set([
  "",
  "-",
  "NA",
  "N/A",
  "S/D",
  "SD",
  "SIN DATO",
  "SIN INFORMACION",
  "SIN INFORMACIÓN",
  "NO APLICA",
  "NO APL",
  "NO DEFINIDO",
]);

const NORMALIZED_TRANSMISSIONS = new Set(["AUTO", "MANUAL"]);
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
]);

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

/**
 * Atlas-specific protected space-separated trims (11 unique trims)
 * These trims must be protected from being split during normalization
 * Based on actual data analysis - see CORRECTED-TRIM-LIST.md
 * Note: Atlas has strong I-series Mazda presence
 */
const PROTECTED_SPACED_TRIMS_ATLAS = [
  // M-series (universal - present in ALL insurers)
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

  // Letter + SPORT
  "A SPORT",
  "X SPORT",
  "E SPORT", // BMW

  // F-series Lexus
  "F SPORT",

  // Letter + PREMIUM
  "A PREMIUM",
  "L PREMIUM",
  "K PREMIUM",

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

const ENGINE_ALIAS_PATTERNS = [
  { regex: /\bT[\s-]?FSI\b/gi, replacement: "TURBO" },
  { regex: /\bT[\s-]?SI\b/gi, replacement: "TURBO" },
  { regex: /\bFSI\s*TURBO\b/gi, replacement: "TURBO" },
  { regex: /\bFSI\b/gi, replacement: "FSI" },
  { regex: /\bGDI\b/gi, replacement: "GDI" },
];

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

/**
 * Protects actual vehicle trim levels from being corrupted during normalization
 * Atlas-specific: 11 unique trims with strong I-series Mazda presence
 * Handles multi-space variants (e.g., "M  SPORT" with double/triple spaces)
 */
function protectTrims(version) {
  if (!version) return version;

  let protected = version;

  // Protect space-separated trims (with multi-space handling)
  PROTECTED_SPACED_TRIMS_ATLAS.forEach((trim) => {
    const placeholder = trim.replace(/\s+/g, "_SPACE_");
    // Regex handles "M SPORT", "M  SPORT", "M   SPORT" (multiple spaces)
    const pattern = trim.replace(/\s+/g, "\\s+");
    protected = protected.replace(
      new RegExp(`\\b${pattern}\\b`, "gi"),
      placeholder
    );
  });

  return protected;
}

/**
 * Restores protected trim levels to their canonical format
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

function applyEngineAliases(value = "") {
  if (!value || typeof value !== "string") return "";
  let output = value;
  ENGINE_ALIAS_PATTERNS.forEach(({ regex, replacement }) => {
    output = output.replace(regex, replacement);
  });
  return output;
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
    .replace(/\b(\d+(?:\.\d+)L)L\b/g, "$1")
    .replace(/\b0+(?=\d)/g, "");
}

function formatTurboDisplacement(raw = "") {
  const value = parseFloat(raw);
  if (!Number.isFinite(value) || value <= 0 || value > 12) {
    return "";
  }
  return Number.isInteger(value) ? value.toString() + ".0" : value.toString();
}

function normalizeTurboTokens(value = "") {
  if (!value || typeof value !== "string") return "";

  const explicitLiters = [];
  value.replace(/\b\d+(?:\.\d+)?L\b/gi, (match, offset) => {
    explicitLiters.push({ token: match, offset });
    return match;
  });

  const applyTurboReplacement = (fullMatch, rawNumber, hasL, offset) => {
    const formatted = formatTurboDisplacement(rawNumber);
    if (!formatted) return fullMatch;

    const matchEnd = offset + fullMatch.length;
    const hasOtherLiters = explicitLiters.some(
      ({ token, offset: literOffset }) => {
        const literEnd = literOffset + token.length;
        return literOffset < offset || literOffset >= matchEnd;
      }
    );

    if (hasL) {
      return formatted + "L TURBO";
    }

    if (hasOtherLiters) {
      return formatted + " TURBO";
    }

    return formatted + "L TURBO";
  };

  value = value.replace(
    /\b(\d+(?:\.\d+)?)(L)?[\s-]*T\b/gi,
    applyTurboReplacement
  );
  value = value.replace(
    /(\d+(?:\.\d+)?)(L)?(?:\s|-)?(TFSI|TSI)\b/gi,
    (fullMatch, rawNumber, hasL, _alias, offset) =>
      applyTurboReplacement(fullMatch, rawNumber, hasL, offset)
  );

  return value;
}

function normalizeCylinders(value = "") {
  if (!value || typeof value !== "string") return "";
  let normalized = value;
  Object.entries(ATLAS_NORMALIZATION_DICTIONARY.cylinder_normalization).forEach(
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

function fixInvalidDoorCounts(text) {
  // Atlas-specific: BMW model numbers incorrectly parsed as doors (Req 7.10)
  const bmwModelNumbers = [
    "300",
    "320",
    "328",
    "335",
    "340",
    "350",
    "520",
    "528",
    "530",
    "535",
    "540",
    "550",
    "640",
    "650",
    "740",
    "750",
    "760",
  ];
  bmwModelNumbers.forEach((num) => {
    text = text.replace(new RegExp(`\\b${num}PUERTAS\\b`, "g"), "");
  });

  // Salvageable truck notation
  text = text.replace(/\b3500PUERTAS\b/g, "4PUERTAS");

  // Invalid values (0, 1, 6-9, and 3+ digit numbers)
  text = text.replace(/\b[016-9]PUERTAS\b/g, "");
  text = text.replace(/\b\d{3,}PUERTAS\b/g, "");

  return text;
}

function cleanAtlasModel(rawModel = "", marca = "") {
  const normalizedModel = normalizeText(rawModel);
  if (!normalizedModel) return "";

  let cleaned = normalizedModel;
  const normalizedMarca = normalizeText(marca);

  if (normalizedMarca) {
    const variants = [normalizedMarca, normalizedMarca.replace(/\s+/g, "")];
    variants.forEach((variant) => {
      if (!variant) return;
      const startRegex = new RegExp(`^${escapeRegex(variant)}\s*`);
      cleaned = cleaned.replace(startRegex, "");
      const inlineRegex = new RegExp(`\s+${escapeRegex(variant)}\b`, "g");
      cleaned = cleaned.replace(inlineRegex, "");
    });
  }

  cleaned = cleaned
    .replace(/NUEVA?\s+LINEA/g, "")
    .replace(/NUEV[OA]/g, "")
    .replace(/NEW/g, "")
    .replace(/PASAJEROS/g, "")
    .replace(/F[\s\.-]?(\d{2,3})/g, "F$1");

  if (/JETTA/.test(cleaned)) {
    cleaned = "JETTA";
  }

  // Apply BMW/MINI brand separation
  const { modelo: splitModelo } = splitBmwMini(marca, cleaned);
  cleaned = splitModelo;

  // SERIE prefix extraction: If marca is 'BMW' and modelo starts with "SERIE ", extract the number
  if (normalizedMarca === "BMW" && /^SERIE\s+/.test(cleaned)) {
    cleaned = cleaned.replace(/^SERIE\s+/, ""); // "SERIE X5" → "X5"
  }

  // Trailing single-letter trim codes: Remove trailing I/A suffixes (e.g., "SERIE 1 I" → "SERIE 1")
  cleaned = cleaned.replace(/\s+[IA]+$/gi, "");

  cleaned = cleaned.replace(/\s+/g, " ").trim();
  return cleaned;
}

/**
 * Splits BMW/MINI brand separation logic
 * Handles: BMW MINI alias, BMW marca with MINI modelo, MINI prefix removal
 * Returns: { marca: string, modelo: string, wasSplit: boolean }
 * Used for: Brand-level MINI separation before modelo cleaning
 */
function splitBmwMini(marca = "", modelo = "") {
  try {
    if (!marca || typeof marca !== "string") {
      return { marca: marca || "", modelo: modelo || "", wasSplit: false };
    }

    let cleanMarca = marca.toUpperCase().trim();
    let cleanModelo = (modelo || "").toUpperCase().trim();
    let wasSplit = false;

    // Handle "BMW MINI" alias → normalize to "MINI"
    if (cleanMarca === "BMW MINI") {
      cleanMarca = "MINI";
      wasSplit = true;
    }

    // IF marca is BMW AND modelo contains "MINI" → split to MINI brand
    if (cleanMarca === "BMW" && /\bMINI\b/.test(cleanModelo)) {
      // Extract MINI variant (COOPER, CLUBMAN, CONVERTIBLE, COUNTRYMAN, PACEMAN, CHILI)
      const variantMatch = cleanModelo.match(
        /MINI\s+(COOPER|CLUBMAN|CONVERTIBLE|COUNTRYMAN|PACEMAN|CHILI)/i
      );
      if (variantMatch) {
        cleanMarca = "MINI";
        cleanModelo = variantMatch[1]; // Use the variant (e.g., "COOPER")
        wasSplit = true;
      } else if (/^MINI\s+/i.test(cleanModelo)) {
        // If MINI is at start but variant not recognized, extract what follows
        cleanMarca = "MINI";
        cleanModelo = cleanModelo.replace(/^MINI\s+/i, "").trim() || "COOPER";
        wasSplit = true;
      }
    }

    // IF marca is MINI AND modelo starts with "MINI " → remove prefix
    if (cleanMarca === "MINI" && /^MINI\s+/i.test(cleanModelo)) {
      cleanModelo = cleanModelo.replace(/^MINI\s+/i, "").trim() || "COOPER";
      wasSplit = true;
    }

    // IF modelo is exactly "MINI COOPER" → normalize to modelo="COOPER"
    if (cleanModelo === "MINI COOPER") {
      cleanModelo = "COOPER";
      if (cleanMarca !== "MINI") {
        cleanMarca = "MINI";
        wasSplit = true;
      }
    }

    if (wasSplit) {
      console.log("MINI_SPLIT_INFO:", {
        original_marca: marca,
        new_marca: cleanMarca,
        modelo: cleanModelo,
      });
    }

    return {
      marca: cleanMarca,
      modelo: cleanModelo,
      wasSplit,
    };
  } catch (error) {
    console.error("MINI_SPLIT_ERROR:", error);
    return {
      marca: marca || "",
      modelo: modelo || "",
      wasSplit: false,
    };
  }
}

/**
 * Extracts complete model codes from version field when modelo is single letter
 * Handles: BMW M/X models, AUDI S/R models
 * Returns: { modelo: string, cleanedVersion: string, wasExtracted: boolean }
 * Used for: Completing incomplete single-letter model codes
 */
function extractCompleteModel(marca = "", modelo = "", version = "") {
  try {
    if (!marca || !modelo || !version) {
      return {
        modelo: modelo || "",
        cleanedVersion: version || "",
        wasExtracted: false,
      };
    }

    const cleanMarca = (marca || "").toUpperCase().trim();
    const cleanModelo = (modelo || "").toUpperCase().trim();
    const cleanVersion = (version || "").toUpperCase().trim();

    // Only process single-letter models
    if (cleanModelo.length !== 1) {
      return {
        modelo: cleanModelo,
        cleanedVersion: cleanVersion,
        wasExtracted: false,
      };
    }

    let extractedModel = null;
    let extractionPattern = null;

    // BMW M models: M2, M3, M4, M5, M6, M8
    if (cleanMarca === "BMW" && cleanModelo === "M") {
      const match = cleanVersion.match(/M[2-8]/);
      if (match) {
        extractedModel = match[0];
        extractionPattern = new RegExp(`\\b${extractedModel}\\b`, "g");
      }
    }

    // BMW X models: X1-X7
    if (cleanMarca === "BMW" && cleanModelo === "X") {
      const match = cleanVersion.match(/X[1-7]/);
      if (match) {
        extractedModel = match[0];
        extractionPattern = new RegExp(`\\b${extractedModel}\\b`, "g");
      }
    }

    // AUDI S/R/S models: S1-S8, R8
    if (cleanMarca === "AUDI" && /^[SR]$/.test(cleanModelo)) {
      const match = cleanVersion.match(/[SR][1-8]/);
      if (match) {
        extractedModel = match[0];
        extractionPattern = new RegExp(`\\b${extractedModel}\\b`, "g");
      }
    }

    if (!extractedModel) {
      console.warn(
        "MODEL_EXTRACTION_WARNING: Could not complete single-letter model",
        {
          marca: cleanMarca,
          modelo: cleanModelo,
          version: cleanVersion,
        }
      );
      return {
        modelo: cleanModelo,
        cleanedVersion: cleanVersion,
        wasExtracted: false,
      };
    }

    // Remove extracted model from version to avoid duplication
    const updatedVersion = cleanVersion.replace(extractionPattern, "").trim();

    console.log(
      `MODEL_EXTRACTION_INFO: Completed ${cleanMarca} ${cleanModelo} → ${extractedModel}`
    );

    return {
      modelo: extractedModel,
      cleanedVersion: updatedVersion,
      wasExtracted: true,
    };
  } catch (error) {
    console.error("MODEL_EXTRACTION_ERROR:", error);
    return {
      modelo: modelo || "",
      cleanedVersion: version || "",
      wasExtracted: false,
    };
  }
}

function cleanVersionString(versionString = "", model = "", marca = "") {
  if (!versionString || typeof versionString !== "string") return "";

  let cleaned = versionString.toUpperCase().trim();

  // NEW FIX 1: Remove escape characters
  cleaned = cleaned.replace(/\\"/g, ""); // Remove escaped quotes
  cleaned = cleaned.replace(/\\\\/g, ""); // Remove backslashes
  cleaned = cleaned.replace(/[""''\"'\u201C\u201D\u2018\u2019]/g, " "); // All quote types

  // NEW FIX 2: Separate HP from AUT and adjacent text
  cleaned = cleaned.replace(/(\d+)HPAUT/gi, "$1HP AUT");
  cleaned = cleaned.replace(/(\d+)HP([A-Z])/gi, "$1HP $2");

  cleaned = cleaned.replace(/AUT(?=[A-Z0-9])/g, "AUT ");

  // FIX: Remove concatenations BEFORE protecting trims
  cleaned = fixTrimConcatenations(cleaned);

  // STAGE 5: TRIM PROTECTION - protect hyphenated trims first
  cleaned = applyProtectedTokens(cleaned);

  // 🔥 v2.13.0 FIX: Normalize multiple spaces BEFORE protecting trims
  // This ensures that trim protection regex can match correctly
  // Fixes: "I  SPORT" (double space) → "I SPORT" (single space) → protected correctly
  cleaned = cleaned.replace(/\s+/g, " ");

  // STAGE 5: TRIM PROTECTION - protect space-separated trims
  cleaned = protectTrims(cleaned);

  cleaned = cleaned.replace(/\bRA-?(\d+)\b/g, "R$1");
  cleaned = cleaned.replace(/[\/,]/g, " ");
  cleaned = cleaned.replace(/-/g, " ");

  // NEW: Remove NUEVO/NUEVA from version
  cleaned = cleaned.replace(/\b(NUEVO|NUEVA|NEW)\s+/gi, "");

  // NEW: Remove generation/trim prefixes (A7, MK VII, etc.)
  cleaned = cleaned.replace(
    /\b(A[4-7]|MK\s*VII?I?|MKVII?I?|GEN\s*\d+)\s+/gi,
    ""
  );

  // NEW: Remove body types from version
  cleaned = cleaned.replace(
    /\b(SEDAN|HATCHBACK|SUV|COUPE|CONVERTIBLE|PICKUP|VAN|WAGON)\b/gi,
    " "
  );

  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeTurboTokens(cleaned);
  cleaned = applyEngineAliases(cleaned);
  cleaned = normalizeCylinders(cleaned);
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);
  cleaned = collapseDisplacementArtifacts(cleaned);
  cleaned = cleaned
    .replace(/\b0+(?:\.\d+)?\s*TON(?:ELADAS)?\b/gi, " ")
    .replace(/\bTONELADAS?\b/gi, "TON")
    .replace(/LTON\b/g, "L TON");

  ATLAS_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach((token) => {
    const regex = new RegExp(`\\b${escapeRegex(token)}\\b`, "gi");
    cleaned = cleaned.replace(regex, " ");
  });

  if (model) {
    cleaned = cleaned.replace(
      new RegExp(`\\b${escapeRegex(model.toUpperCase())}\\b`, "gi"),
      " "
    );
  }

  if (marca) {
    cleaned = cleaned.replace(
      new RegExp(`\\b${escapeRegex(marca.toUpperCase())}\\b`, "gi"),
      " "
    );
  }

  cleaned = cleaned
    .replace(/\bHB\b/g, "HATCHBACK")
    .replace(/\bTUR\b/g, "TURBO")
    .replace(/\bCONV\b/g, "CONVERTIBLE")
    .replace(/\bGW\b/g, "WAGON")
    .replace(/\bPICK\s*UP\b/g, "PICKUP");

  // NEW FIX 3: Remove invalid door counts before final cleanup
  cleaned = fixInvalidDoorCounts(cleaned);

  cleaned = cleaned
    .replace(/\b\d+\s*PUERTAS?\b/gi, " ")
    .replace(/\bPUERTAS?\b/gi, " ")
    .replace(/\b0?\d+\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX)\b/gi, " ")
    .replace(/\b0?\d+\s*(?:PASAJEROS?|PAS)\b/gi, " ");

  const { year_codes, multiple_spaces, trim_spaces } =
    ATLAS_NORMALIZATION_DICTIONARY.regex_patterns;
  cleaned = cleaned.replace(year_codes, " ");
  cleaned = cleaned.replace(/(?<!\d)[.,](?!\d)/g, " ");
  cleaned = cleaned.replace(/\bL\b/g, " ");

  cleaned = cleaned.replace(multiple_spaces, " ");
  cleaned = cleaned.replace(trim_spaces, "");

  // STAGE 8: TRIM RESTORATION - restore hyphenated trims first
  cleaned = restoreProtectedTokens(cleaned);
  // STAGE 8: TRIM RESTORATION - restore space-separated trims
  cleaned = restoreTrims(cleaned);

  cleaned = cleaned.replace(/CIL(?=\d)/g, "CIL ");
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)\s*HP\b/g, "$1HP");
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
  if (typeof code === "number") {
    if (code === 1) return "MANUAL";
    if (code === 2) return "AUTO";
    return "";
  }

  const normalized = code.toString().toUpperCase().trim();
  if (!normalized || INVALID_TRANSMISSION_CODES.has(normalized)) return "";

  if (/^[012]$/.test(normalized)) {
    if (normalized === "1") return "MANUAL";
    if (normalized === "2") return "AUTO";
    return "";
  }

  const mapped =
    ATLAS_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] ||
    normalized;
  if (NORMALIZED_TRANSMISSIONS.has(mapped)) return mapped;
  return "";
}

function inferTransmissionFromVersion(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") return "";
  const version = versionOriginal.toUpperCase();
  for (const code of Object.keys(
    ATLAS_NORMALIZATION_DICTIONARY.transmission_normalization
  )) {
    const regex = new RegExp(`\\b${escapeRegex(code)}\\b`, "i");
    if (regex.test(version)) {
      const normalized = normalizeTransmission(code);
      if (normalized) return normalized;
    }
  }
  return "";
}

function recoverTransmission(record) {
  const transmisionField = record.transmision?.toString().toUpperCase().trim();

  // Step 1: Try to extract from contaminated transmision field
  const validPatterns = [
    "AUTO",
    "AUTOMATIC",
    "MANUAL",
    "STD",
    "CVT",
    "DSG",
    "TIPTRONIC",
    "STEPTRONIC",
    "S-TRONIC",
    "STRONIC",
    "MULTITRONIC",
    "GEARTRONIC",
    "PDK",
  ];
  for (const pattern of validPatterns) {
    if (transmisionField?.includes(pattern)) {
      const normalized = normalizeTransmission(pattern);
      if (normalized) return normalized;
    }
  }

  // Step 2: Infer from version_original
  const inferred = inferTransmissionFromVersion(record.version_original);
  if (inferred) {
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

function normalizeAtlasData(records = []) {
  const results = [];
  const errors = [];

  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const batch = records.slice(i, i + BATCH_SIZE);
    for (const record of batch) {
      try {
        const processed = processAtlasRecord(record);
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

function normalizeAtlasRecords(items = []) {
  const rawRecords = items.map((item) =>
    item && item.json ? item.json : item
  );
  const { results, errors } = normalizeAtlasData(rawRecords);
  const successItems = results.map((record) => ({ json: record }));
  const errorItems = errors.map((error) => ({ json: error }));
  return [...successItems, ...errorItems];
}

function processAtlasRecord(record) {
  const marcaNormalizada = consolidateBrand(normalizeText(record.marca));

  if (marcaNormalizada === "INVALID_BRAND") {
    throw new Error("INVALID_BRAND: Brand not valid for catalog");
  }

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
  let enhancedVersion = record.version_original || "";
  if (modeloSpecs.length > 0) {
    enhancedVersion = `${modeloSpecs.join(" ")} ${enhancedVersion}`.trim();
  }

  const modeloNormalizado = cleanAtlasModel(record.modelo, marcaNormalizada);
  let modeloFinal = modeloNormalizado || normalizeText(record.modelo);

  // Complete single-letter models (M, X, S) from version field
  if (modeloFinal.length === 1 && enhancedVersion) {
    const {
      modelo: completeModel,
      cleanedVersion,
      wasExtracted,
    } = extractCompleteModel(marcaNormalizada, modeloFinal, enhancedVersion);
    if (wasExtracted) {
      modeloFinal = completeModel;
      enhancedVersion = cleanedVersion;
      console.log(
        `ATLAS: Completed ${marcaNormalizada} ${modeloFinal} from version`
      );
    }
  }

  const recoveredTransmission = recoverTransmission(record);
  if (!recoveredTransmission) {
    throw new Error(
      "TRANSMISSION_INFERENCE_FAILED: Cannot recover transmission"
    );
  }
  record.transmision = recoveredTransmission;

  const { doors, occupants } = extractDoorsAndOccupants(enhancedVersion);

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
      if (!doors && !fallbackDoors) {
        const numericValue = parseInt(token, 10);
        if ([2, 3, 4, 5, 7].includes(numericValue)) {
          fallbackDoors = `${numericValue}PUERTAS`;
        }
      }
      const next = (arr[idx + 1] || "").toUpperCase();
      const prev = (arr[idx - 1] || "").toUpperCase();
      if (
        /^\d+OCUP$/i.test(next) ||
        NUMERIC_CONTEXT_TOKENS.has(next) ||
        NUMERIC_CONTEXT_TOKENS.has(prev)
      ) {
        return;
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
    .trim();

  const finalDoors = doors || fallbackDoors;
  versionLimpia = [versionLimpia, finalDoors, occupants]
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();

  const normalized = {
    origen_aseguradora: "ATLAS",
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
 * Fixes issue where "PICK UP SILVERADO" vs "SILVERADO" create different hashes
 * Enhanced to remove single-letter trim codes and cab type specifications
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

  // Issue #2: MAZDA brand prefix removal & hyphenation
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

  // Issue #3: VOLKSWAGEN JETTA generation prefix removal (Atlas has "JETTA MKVII")
  if (marcaUpper === "VOLKSWAGEN") {
    normalized = normalized.replace(/\s*MK\s*VII?I?/gi, "");
    normalized = normalized.replace(/\s*MKVII?I?/gi, "");
    normalized = normalized.replace(/\s*GEN\.?\s*\d+/gi, "");
    normalized = normalized.replace(/\s*A[4-7]\b/gi, "");
  }

  // 1. Remove NUEVO/NUEVA/NEW prefix
  normalized = normalized.replace(/^(NUEVO|NUEVA|NEW)\s+/gi, "");

  // 2. Remove specs from modelo using MODELO_SPECS_TO_REMOVE
  MODELO_SPECS_TO_REMOVE.forEach((spec) => {
    const pattern = new RegExp(
      `\\b${spec.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`,
      "gi"
    );
    normalized = normalized.replace(pattern, " ");
  });

  // 3. Remove content in parentheses (e.g., "JETTA (DERBY)" -> "JETTA")
  normalized = normalized.replace(/\([^)]+\)/g, " ");

  // 4. Mazda-specific: Remove MAZDA/MA prefix
  if (marcaUpper === "MAZDA") {
    normalized = normalized.replace(/^(MAZDA|MA)\s+/gi, "");
  }

  // 3. Mercedes-specific: Remove MERCEDES prefix and fix KLASSE
  if (marcaUpper === "MERCEDES BENZ") {
    normalized = normalized.replace(/^MERCEDES\s+(BENZ\s+)?/gi, "");
    normalized = normalized.replace(/\bKLASSE\b/gi, "CLASE");
  }

  // Remove generic prefixes (PICK UP, CAMIONETA, VAN, TRUCK)
  normalized = normalized.replace(/^PICK\s*UP\s+/gi, "");
  normalized = normalized.replace(/^PICK-UP\s+/gi, "");
  normalized = normalized.replace(/^CAMIONETA\s+/gi, "");
  normalized = normalized.replace(/^VAN\s+/gi, "");
  normalized = normalized.replace(/^TRUCK\s+/gi, "");

  // Remove brand name if repeated in model field
  if (marcaUpper) {
    const brandPattern = new RegExp(
      `^${marcaUpper.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s+`,
      "gi"
    );
    normalized = normalized.replace(brandPattern, "");
  }

  // 2. Remove trim level/generation from modelo (MK VII, GEN 4)
  normalized = normalized.replace(/\s+(MK\s*VII?I?|MKVII?I?|GEN\s*\d+)$/gi, "");

  // 3. Remove body type from modelo (SEDAN, SUV, etc.)
  normalized = normalized.replace(
    /\s+(SEDAN|HATCHBACK|SUV|COUPE|CONVERTIBLE|PICKUP|VAN|WAGON)$/gi,
    ""
  );

  // 4. Collapse spaces in letter+number models (A 3 → A3, E TRON → E-TRON)
  normalized = normalized.replace(/^([A-Z])\s+([A-Z0-9])/g, "$1$2");

  // 4b. E-TRON needs hyphen (special case)
  normalized = normalized.replace(/\bETRON\b/g, "E-TRON");

  // Remove single letter trim codes (e.g., "C 1500" → "1500", "M 350" → "350")
  // Only when followed by numbers to preserve legitimate model codes
  normalized = normalized.replace(/\s+([A-Z])\s+(\d)/g, " $2");

  // Remove cab type and configuration codes from middle
  normalized = normalized.replace(/\s+CAB\.?\s*REG\.?(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+CAB\.?\s*REGULAR(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+CREW\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+QUAD\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+MEGA\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+SUPER\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+KING\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+DOBLE\s+CABINA(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+SENCILLA\s+CABINA(?:\s+|$)/gi, " ");

  // Remove standalone trim codes at end (DR, WT, SL, SLE, SLT)
  normalized = normalized.replace(/\s+(DR|WT|SL|SLE|SLT)$/gi, "");

  // Remove trim level suffixes from end
  normalized = normalized.replace(
    /\s+(CREW|QUAD|MEGA|SUPER|KING)\s+CAB$/gi,
    ""
  );
  normalized = normalized.replace(/\s+(DOBLE|SENCILLA)\s+CABINA$/gi, "");

  // FIX 1: BMW SERIE cleanup (applies to all insurers)
  normalized = cleanBMWModelo(marca, normalized);

  // Clean up multiple spaces and trim
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
  if (!record.anio || record.anio < 2000 || record.anio > 2030) {
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

const outputItems = normalizeAtlasRecords(items);
return outputItems;
