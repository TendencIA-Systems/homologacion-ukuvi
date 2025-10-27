/**
 * Qualitas ETL - Normalization Code Node v2
 *
 * Limpieza alineada con Zurich/Chubb/Atlas:
 * - Preserva trims con guion (A-SPEC, TYPE-S, S-LINE).
 * - Normaliza litros decimales y caballos de fuerza.
 * - Amplía diccionario de transmisiones y elimina tokens irrelevantes.
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
  "BMW MINI": "MINI",

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
  if (!marca || typeof marca !== "string") return "";
  const normalized = marca.toUpperCase().trim();
  return BRAND_CONSOLIDATION_MAP[normalized] || normalized;
}

const QUALITAS_NORMALIZATION_DICTIONARY = {
  irrelevant_comfort_audio: [
    "AA",
    "EE",
    "CD",
    "DVD",
    "GPS",
    "BT",
    "USB",
    "MP3",
    "AM",
    "FM",
    "RA",
    "FX",
    "BOSE",
    "BA",
    "ABS",
    "QC",
    "Q/C",
    "Q.C.",
    "VP",
    "V/P",
    "OC",
    "PIEL",
    "GAMUZA",
    "CA",
    "CE",
    "SQ",
    "CB",
    "SIS/NAV",
    "SIS.NAV.",
    "T.S",
    "T.P.",
    "FBX",
    "AC",
    "ASIST",
    "APARC",
    "NAVI",
    "CAM TRAS",
    "TBO",
    "SENSOR",
    "SENSORES",
    "PARKING",
    "PARK",
    "PARKTRONIC",
    "CLIMA",
    "CLIMATRONIC",
    "CLIMATIZADOR",
    "AIRE ACONDICIONADO",
    "A/A",
    "A A",
    "E/E",
    "E E",
    "B/A",
    "B A",
    "BOLSAS DE AIRE",
    "AIRBAG",
    "AIRBAGS",
    "ALARM",
    "ALARMA",
    "RADIO",
    "STEREO",
    "AUDIO",
    "SOUND",
    "PREMIUM SOUND",
    "HARMAN KARDON",
    "BANG OLUFSEN",
    "MERIDIAN",
    "BURMESTER",
    "MARK LEVINSON",
    "JBL",
    "BEATS",
    "BLUETOOTH",
    "NAV",
    "GPS NAV",
    "NAVEGACION",
    "NAVEGADOR",
    "PANTALLA",
    "TOUCH",
    "TOUCHSCREEN",
    "MONITOR",
    "DISPLAY",
    "LEATHER",
    "PIEL",
    "TELA",
    "VINIL",
    "VINYL",
    "CLOTH",
    "ALCANTARA",
    "SUEDE",
    "CUERO",
    "ALUMINIO",
    "ALUMINUM",
    "MADERA",
    "WOOD",
    "FIBRA DE CARBONO",
    "CARBON FIBER",
    "KEYLESS",
    "PUSH BUTTON",
    "PUSH START",
    "START STOP",
    "BOTON",
    "ENCENDIDO",
    "LLAVE",
    "XENON",
    "HID",
    "LED",
    "HALOGEN",
    "FAROS",
    "LUCES",
    "BI-XENON",
    "BIXENON",
    "SUNROOF",
    "MOONROOF",
    "TECHO",
    "QUEMACOCOS",
    "PANORAMIC",
    "PANORAMICO",
    "CRUISE",
    "CONTROL CRUCERO",
    "VELOCIDAD",
    "LIMITADOR",
    "FRENOS ABS",
    "EBD",
    "ESP",
    "ESC",
    "VSC",
    "VDC",
    "TRACTION CONTROL",
    "CONTROL TRACCION",
    "ASISTENTE",
    "ASSISTANT",
    "HILL",
    "DESCENT",
    "ASCENT",
    "DTC",
    "DSC",
    "CAMARA",
    "CAMERA",
    "REVERSA",
    "REVERSE",
    "TRASERA",
    "REAR VIEW",
    "360",
    "BLIND SPOT",
    "PUNTO CIEGO",
    "LANE",
    "CARRIL",
    "DEPARTURE",
    "KEEP",
    "ASSIST",
    "PADDLE",
    "LEVAS",
    "SHIFTER",
    "VOLANTE MULTIFUNCION",
    "MULTI",
    "CALEFACCION",
    "HEATED",
    "VENTILADOS",
    "VENTILATED",
    "ENFRIADOS",
    "COOLED",
    "MASAJE",
    "MASSAGE",
    "ELECTRICOS",
    "ELECTRIC",
    "POWER",
    "AJUSTABLES",
    "ADJUSTABLE",
    "MEMORIA",
    "MEMORY",
    "SUSPENSION",
    "AMORTIGUACION",
    "ADAPTIVE",
    "ADAPTATIVA",
    "MAGNETICA",
    "MAGNETIC",
    "NEUMATICA",
    "PNEUMATIC",
    "AIR SUSPENSION",
    // Wheel/rim sizes
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
    "RIN",
    "LLANTA",
    "LLANTAS",
    "ALEACION",
    "ALLOY",
    "WHEELS",
    "RINES",
    // Transmission tokens (will be stripped from version)
    "STD",
    "AUT",
    "CVT",
    "DSG",
    "S TRONIC",
    "S-TRONIC",
    "TIPTRONIC",
    "TIPTRNIC",
    "SELESPEED",
    "SALESPEED",
    "SPORTSHIFT",
    "TOUCHTRONIC3",
    "Q-TRONIC",
    "DCT",
    "MULTITRONIC",
    "STEPTRONIC",
    "GEARTRONIC",
    "STRONIC",
    "XTRONIC",
    "SECUENCIAL",
    "DRIVELOGIC",
    "DUALOGIC",
    "SPEEDSHIFT",
    "G-TRONIC",
    "G TRONIC",
    "PDK",
    "MULTITRO",
    "AUTOMATICA",
    "AUTOMATICO",
    "AUTOMATIC",
    "RHYNE",
    "RHYNE SIZE",
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
    SECUENCIAL: "MANUAL",
    DRIVELOGIC: "MANUAL",
    DUALOGIC: "MANUAL",
    TM: "MANUAL",
    ESTANDAR: "MANUAL",
    AUT: "AUTO",
    "AUT.": "AUTO",
    AUTO: "AUTO",
    TA: "AUTO",
    AUTOMATICA: "AUTO",
    AUTOMATICO: "AUTO",
    AUTOMATIC: "AUTO",
    CVT: "AUTO",
    DSG: "AUTO",
    "S TRONIC": "AUTO",
    "S-TRONIC": "AUTO",
    STRONIC: "AUTO",
    XTRONIC: "AUTO",
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
  },
  regex_patterns: {
    year_codes: /\b(20\d{2})\b/g,
    multiple_spaces: /\s+/g,
    trim_spaces: /^\s+|\s+$/g,
  },
};

const PROTECTED_HYPHEN_TOKENS = [
  {
    regex: /\bA[\s-]?SPEC\b/gi,
    placeholder: "__Q_PROTECTED_A_SPEC__",
    canonical: "A-SPEC",
  },
  {
    regex: /\bTYPE[\s-]?S\b/gi,
    placeholder: "__Q_PROTECTED_TYPE_S__",
    canonical: "TYPE-S",
  },
  {
    regex: /\bTYPE[\s-]?R\b/gi,
    placeholder: "__Q_PROTECTED_TYPE_R__",
    canonical: "TYPE-R",
  },
  {
    regex: /\bTYPE[\s-]?F\b/gi,
    placeholder: "__Q_PROTECTED_TYPE_F__",
    canonical: "TYPE-F",
  },
  {
    regex: /\bT5\b/gi,
    placeholder: "__Q_PROTECTED_T5__",
    canonical: "T5",
  },
  {
    regex: /\bT6\b/gi,
    placeholder: "__Q_PROTECTED_T6__",
    canonical: "T6",
  },
  {
    regex: /\bT7\b/gi,
    placeholder: "__Q_PROTECTED_T7__",
    canonical: "T7",
  },
  {
    regex: /\bT8\b/gi,
    placeholder: "__Q_PROTECTED_T8__",
    canonical: "T8",
  },
  {
    regex: /\bT9\b/gi,
    placeholder: "__Q_PROTECTED_T9__",
    canonical: "T9",
  },
  {
    regex: /\bS[\s-]?LINE\b/gi,
    placeholder: "__Q_PROTECTED_S_LINE__",
    canonical: "S-LINE",
  },
  {
    regex: /\bR[\s-]?LINE\b/gi,
    placeholder: "__Q_PROTECTED_R_LINE__",
    canonical: "R-LINE",
  },
  {
    regex: /\bX[\s-]?DRIVE\b/gi,
    placeholder: "__Q_PROTECTED_X_DRIVE__",
    canonical: "X-DRIVE",
  },
];

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

const ENGINE_ALIAS_PATTERNS = [
  { regex: /\bT[\s-]?FSI\b/gi, replacement: "TURBO" },
  { regex: /\bT[\s-]?SI\b/gi, replacement: "TURBO" },
  { regex: /\bFSI\s*TURBO\b/gi, replacement: "TURBO" },
  { regex: /\bFSI\b/gi, replacement: "FSI" },
  { regex: /\bGDI\b/gi, replacement: "GDI" },
];

// ═══════════════════════════════════════════════════════════════════════════
// PROTECTED SPACE-SEPARATED TRIMS (Qualitas - High STRONIC Volume)
// ═══════════════════════════════════════════════════════════════════════════
// Qualitas has high STRONIC count (293 occurrences) and consistent trim usage
const PROTECTED_SPACED_TRIMS_QUALITAS = [
  // M-series (universal)
  "M SPORT",

  // I-series Mazda
  "I GRAND TOURING", // ⭐ CRITICAL - 751 cases across insurers
  "I TOURING",
  "I SPORT",
  "I LUXURY",
  "I PREMIUM",

  // R-series Honda
  "R GRAND TOURING",
  "R TOURING",
  "R SPORT",
  "R LUXURY",

  // S-series Mazda
  "S GRAND TOURING", // ⭐ CRITICAL - 335 cases across insurers
  "S TOURING",
  "S SPORT",

  // D-series (Diesel variants)
  "D GRAND TOURING",
  "D TOURING",

  // Standalone trims (no letter prefix)
  "GRAND TOURING", // ⭐ CRITICAL - 646 cases (standalone)
  "GRAND TOURING PLUS",

  // Letter + PREMIUM
  "A PREMIUM",
  "L PREMIUM",

  // 🔥 v2.13.0 ADDITIONS:
  "MX GRAND TOURING",
  "F SPORT",
  "E SPORT",
  "JOHN COOPER WORKS",
  "COOPER WORKS",
  "COOPER S",
  "KING RANCH",
  "EDDIE BAUER",
  "HIGH COUNTRY",
  "GRAND CHEROKEE",
];

/**
 * Protect space-separated trims by replacing spaces with placeholder
 * Handles multi-space variants (e.g., "M  SPORT", "M   SPORT")
 */
function protectTrims(version) {
  if (!version) return version;
  let protected = version;
  PROTECTED_SPACED_TRIMS_QUALITAS.forEach((trim) => {
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

function normalizeDrivetrain(value = "") {
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

function normalizeEngineDisplacement(value = "") {
  if (!value || typeof value !== "string") return "";
  return (
    value
      // Only add period between 2-digit numbers, not if already part of a decimal (avoid 1.75L → 1.7.5L)
      .replace(/\b(?<!\.)(\d)(\d)L\b/g, "$1.$2L")
      .replace(/\b(?<!\d\.)\d+L\b/g, (match) => `${match.slice(0, -1)}.0L`)
      .replace(/\b(?<!\d\.)\d+\s+L\b/g, (match) => {
        const digits = match.match(/\d+/)[0];
        return `${digits}.0L`;
      })
  );
}

function formatTurboDisplacement(raw = "") {
  const value = parseFloat(raw);
  if (!Number.isFinite(value) || value <= 0 || value > 12) {
    return "";
  }
  return Number.isInteger(value) ? `${value}.0` : value.toString();
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
      return `${formatted}L TURBO`;
    }

    if (hasOtherLiters) {
      return `${formatted} TURBO`;
    }

    return `${formatted}L TURBO`;
  };

  let output = value.replace(
    /\b(\d+(?:\.\d+)?)(L)?[\s-]*T\b/gi,
    applyTurboReplacement
  );
  output = output.replace(
    /(\d+(?:\.\d+)?)(L)?(?:\s|-)?(TFSI|TSI)\b/gi,
    (fullMatch, rawNumber, hasL, _alias, offset) =>
      applyTurboReplacement(fullMatch, rawNumber, hasL, offset)
  );

  return output;
}

function normalizeCylinders(value = "") {
  if (!value || typeof value !== "string") return "";
  let normalized = value;

  // Convert P → PUERTAS before cylinder normalization
  normalized = normalized.replace(/\b(\d+)\s*P\b(?!\s*UERTAS)/gi, "$1PUERTAS");

  Object.entries(
    QUALITAS_NORMALIZATION_DICTIONARY.cylinder_normalization
  ).forEach(([from, to]) => {
    const regex = new RegExp(`\\b${from}\\s*(?=\\d+\\.?\\d*|\\s|$)`, "gi");
    normalized = normalized.replace(regex, to);
    const exact = new RegExp(`\\b${from}\\b`, "gi");
    normalized = normalized.replace(exact, to);
  });
  return normalized;
}

function fixInvalidDoorCounts(text) {
  if (!text || typeof text !== "string") return "";

  // BMW model numbers incorrectly parsed as doors
  const bmwModelNumbers = ["300", "320", "328", "335"];
  bmwModelNumbers.forEach((num) => {
    text = text.replace(new RegExp(`\\b${num}PUERTAS\\b`, "g"), "");
  });

  // Salvageable truck notation
  text = text.replace(/\b3500PUERTAS\b/g, "4PUERTAS");

  // Invalid values: 0PUERTAS, 6-9PUERTAS, 100+PUERTAS
  text = text.replace(/\b[016-9]PUERTAS\b/g, "");
  text = text.replace(/\b\d{3,}PUERTAS\b/g, "");

  return text;
}

function cleanVersionString(versionString, model = "") {
  if (!versionString || typeof versionString !== "string") return "";

  let cleaned = versionString.toUpperCase().trim();

  // NEW FIX 1: Remove escape characters
  cleaned = cleaned.replace(/\\"/g, ""); // Remove escaped quotes
  cleaned = cleaned.replace(/\\\\/g, ""); // Remove backslashes

  // Remove all quote types including straight, curly, and angled quotes
  cleaned = cleaned.replace(
    /[""''\"'\u201C\u201D\u2018\u2019\u00AB\u00BB]/g,
    " "
  );

  // NEW FIX 2: Separate HP from AUT and adjacent letters
  cleaned = cleaned.replace(/(\d+)HPAUT/gi, "$1HP AUT");
  cleaned = cleaned.replace(/(\d+)HP([A-Z])/gi, "$1HP $2");

  // FIX: Remove concatenations BEFORE protecting trims
  cleaned = fixTrimConcatenations(cleaned);

  cleaned = applyProtectedTokens(cleaned);

  // 🔥 v2.13.0 FIX: Normalize multiple spaces BEFORE protecting trims
  // This ensures that trim protection regex can match correctly
  // Fixes: "I  SPORT" (double space) → "I SPORT" (single space) → protected correctly
  cleaned = cleaned.replace(/\s+/g, " ");

  // STAGE 5: TRIM PROTECTION - Protect space-separated trims before hyphen removal
  cleaned = protectTrims(cleaned);
  cleaned = cleaned.replace(/\bRA-?(\d+)\b/g, "R$1");

  // Remove specific patterns with slashes/hyphens BEFORE replacing those characters
  cleaned = cleaned.replace(/\bV[\s\/]P\b/gi, " ");
  cleaned = cleaned.replace(/\bQ[\s\/]C\b/gi, " ");
  cleaned = cleaned.replace(/\bS[\s-]TRONIC\b/gi, " ");
  cleaned = cleaned.replace(/\bSTRONIC\b/gi, " ");

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

  QUALITAS_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach(
    (token) => {
      cleaned = cleaned.replace(new RegExp(`\\b${token}\\b`, "gi"), " ");
    }
  );

  if (model) {
    cleaned = cleaned.replace(
      new RegExp(`\\b${model.toUpperCase()}\\b`, "gi"),
      " "
    );
  }

  cleaned = cleaned
    .replace(/\bHB\b/g, "HATCHBACK")
    .replace(/\bTUR\b/g, "TURBO")
    .replace(/\bGW\b/g, "WAGON")
    .replace(/\bCONV\b/g, "CONVERTIBLE")
    .replace(/\bPICK\s*UP\b/g, "PICKUP");

  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);
  cleaned = cleaned
    .replace(/\b0+(?:\.\d+)?\s*TON(?:ELADAS)?\b/gi, " ")
    .replace(/\bTONELADAS?\b/gi, "TON")
    .replace(/LTON\b/g, "L TON");

  cleaned = cleaned.replace(/(?<!\d)[.,](?!\d)/g, " ");

  Object.values(QUALITAS_NORMALIZATION_DICTIONARY.regex_patterns).forEach(
    (pattern) => {
      if (
        pattern !==
          QUALITAS_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces &&
        pattern !== QUALITAS_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces
      ) {
        cleaned = cleaned.replace(pattern, " ");
      }
    }
  );
  cleaned = cleaned
    .replace(
      QUALITAS_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces,
      " "
    )
    .replace(QUALITAS_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces, "");

  cleaned = restoreProtectedTokens(cleaned);
  // STAGE 8: TRIM RESTORATION - Restore space-separated trims
  cleaned = restoreTrims(cleaned);

  // NEW FIX 3: Remove invalid door counts
  cleaned = fixInvalidDoorCounts(cleaned);

  cleaned = cleaned.replace(/CIL(?=\d)/g, "CIL ");
  cleaned = cleaned.replace(/\b(\d+)\s+O\b/g, "$1OCUP");
  cleaned = cleaned.replace(/\b(\d+)\s+OCU\b/g, "$1OCUP");
  cleaned = cleaned.replace(/\b(\d+)\s+OC\b/g, "$1OCUP");
  cleaned = cleaned.replace(/\b(\d+)\s*HP\b/g, "$1HP");
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
  if (!code || typeof code !== "string") return "";
  const normalized = code.toUpperCase().trim();
  return (
    QUALITAS_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] ||
    normalized
  );
}

function inferTransmissionFromVersion(versionOriginal = "") {
  const version = (versionOriginal || "").toUpperCase();
  for (const token of Object.keys(
    QUALITAS_NORMALIZATION_DICTIONARY.transmission_normalization
  )) {
    if (new RegExp(`\\b${token}\\b`, "i").test(version)) {
      return normalizeTransmission(token);
    }
  }
  return "";
}

function recoverTransmission(record) {
  const transmisionField = (record.transmision || "").toUpperCase().trim();

  // Step 1: Try to extract from contaminated transmision field
  const validPatterns = [
    "AUTO",
    "AUTOMATIC",
    "MANUAL",
    "STD",
    "CVT",
    "DSG",
    "TIPTRONIC",
    "XTRONIC",
    "STRONIC",
    "STEPTRONIC",
    "MULTITRONIC",
    "PDK",
    "ESTANDAR",
    "AUT",
    "MAN",
    "TM",
    "TA",
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
  const inferred = inferTransmissionFromVersion(record.version_original);
  if (inferred === "AUTO" || inferred === "MANUAL") {
    return inferred;
  }

  // Step 3: Cannot recover - return null (record will be discarded)
  return null;
}

const BATCH_SIZE = 5000;

/**
 * Detecta si un token es una especificación con número
 * Ejemplos: "5PUERTAS", "4CIL", "2.0L", "200HP", "7OCUP"
 * @param {string} token - Token a evaluar
 * @returns {boolean} - true si es una especificación numérica
 */
function isNumericSpecification(token) {
  if (!token || typeof token !== "string") return false;
  // Patrones de especificaciones con números
  return /^\d+(\.\d+)?(PUERTAS?|OCUP|CIL|HP|L|KG|TON|PAX)$/i.test(token);
}

/**
 * Deduplica tokens de forma inteligente
 * - Elimina duplicados NO consecutivos (5PUERTAS ... 5PUERTAS)
 * - Preserva números puros (2.0L y 2PUERTAS pueden coexistir)
 * - Mantiene primera ocurrencia de cada especificación
 *
 * PROBLEMA RESUELTO: "TECH 5PUERTAS 6CIL 3.5L AWD 5PUERTAS 7OCUP"
 *                 → "TECH 5PUERTAS 6CIL 3.5L AWD 7OCUP"
 *
 * @param {Array<string>} tokens - Array de tokens a deduplicar
 * @returns {Array<string>} - Array sin duplicados
 */
function deduplicateTokens(tokens) {
  const seen = new Map(); // Usar Map para tracking más sofisticado
  const dedupedTokens = [];

  tokens.forEach((token) => {
    const normalized = token.trim().toUpperCase();
    if (!normalized) return;

    // Caso 1: Especificaciones numéricas (5PUERTAS, 4CIL, etc)
    if (isNumericSpecification(normalized)) {
      // Extraer tipo de especificación (PUERTAS, CIL, OCUP, etc)
      const specType = normalized.replace(/^\d+(\.\d+)?/, "");

      if (seen.has(`spec_${specType}`)) {
        // Ya tenemos una especificación de este tipo, skip duplicado
        return;
      }
      seen.set(`spec_${specType}`, normalized);
      dedupedTokens.push(normalized);
      return;
    }

    // Caso 2: Tokens alfanuméricos normales (no números puros)
    if (!/^\d+(\.\d+)?(L|HP)?$/.test(normalized)) {
      if (seen.has(normalized)) {
        // Duplicado exacto, skip
        return;
      }
      seen.set(normalized, true);
      dedupedTokens.push(normalized);
      return;
    }

    // Caso 3: Números puros o con unidades (2.0L, 200HP)
    // Estos pueden aparecer múltiples veces legítimamente
    // Ejemplo: "2.0L TURBO" y "2PUERTAS" - el "2" es diferente
    dedupedTokens.push(normalized);
  });

  return dedupedTokens;
}

function normalizeQualitasData(records = []) {
  const results = [];
  const errors = [];
  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const batch = records.slice(i, i + BATCH_SIZE);
    for (const record of batch) {
      try {
        results.push(processQualitasRecord(record));
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

function normalizeQualitasRecords(items = []) {
  const rawRecords = items.map((it) => (it && it.json ? it.json : it));
  const { results, errors } = normalizeQualitasData(rawRecords);
  return [
    ...results.map((r) => ({ json: r })),
    ...errors.map((e) => ({ json: e })),
  ];
}

function processQualitasRecord(record) {
  // Use enhanced transmission recovery
  const recoveredTransmission = recoverTransmission(record);
  if (!recoveredTransmission) {
    throw new Error(
      "TRANSMISSION_INFERENCE_FAILED: Cannot recover transmission"
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
  let enhancedVersion = record.version_original || "";
  if (modeloSpecs.length > 0) {
    enhancedVersion = `${modeloSpecs.join(" ")} ${enhancedVersion}`.trim();
  }

  const { doors, occupants } = extractDoorsAndOccupants(enhancedVersion);
  const validation = validateRecord(record);
  if (!validation.isValid) {
    throw new Error(`Validation failed: ${validation.errors.join(", ")}`);
  }

  let versionLimpia = cleanVersionString(enhancedVersion, record.modelo || "");
  versionLimpia = versionLimpia
    .replace(/\b\d\s*P(?:TAS?|TS?|TA)?\.?\b/gi, " ")
    .replace(/\b0?\d+\s*(?:OC|OCU|OCUP|OCUP\.?|O\.?)\b/gi, " ")
    .replace(/\s+[.,](?=\s|$)/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  const rawTokens = versionLimpia.split(" ").filter(Boolean);
  const tokens = [];
  rawTokens.forEach((token, idx, arr) => {
    if (/^[.,]$/.test(token)) return;
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
    }
    tokens.push(token);
  });

  // CRITICAL FIX: Deduplicate tokens intelligently
  // Fixes: "5PUERTAS ... 5PUERTAS" → "5PUERTAS"
  // Preserves: "2.0L" and "2PUERTAS" (different specs)
  const dedupedTokens = deduplicateTokens(tokens);

  versionLimpia = dedupedTokens.join(" ");
  versionLimpia = versionLimpia.replace(/\s+/g, " ").trim();

  // CRITICAL FIX 2: Only append doors/occupants if NOT already present
  // Prevents: "5PUERTAS ... 5PUERTAS" when already in dedupedTokens
  const specsToAppend = [];
  if (doors && !versionLimpia.includes(doors)) {
    specsToAppend.push(doors);
  }
  if (occupants && !versionLimpia.includes(occupants)) {
    specsToAppend.push(occupants);
  }

  if (specsToAppend.length > 0) {
    versionLimpia = [versionLimpia, ...specsToAppend]
      .filter(Boolean)
      .join(" ")
      .trim();
  }

  const consolidatedMarca = consolidateBrand(record.marca);
  if (consolidatedMarca === "INVALID_BRAND") {
    throw new Error("INVALID_BRAND: Brand is invalid or blacklisted");
  }

  const normalized = {
    origen_aseguradora: "QUALITAS",
    id_original: record.id_original,
    marca: consolidatedMarca,
    modelo: normalizeModelo(consolidatedMarca, record.modelo),
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

  // Issue #2: MAZDA brand prefix removal & hyphenation (Qualitas has "CX5" no hyphen)
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

  // Issue #3: VOLKSWAGEN JETTA generation prefix removal
  if (marcaUpper === "VOLKSWAGEN") {
    normalized = normalized.replace(/\s*MK\s*VII?I?/gi, "");
    normalized = normalized.replace(/\s*MKVII?I?/gi, "");
    normalized = normalized.replace(/\s*GEN\.?\s*\d+/gi, "");
    normalized = normalized.replace(/\s*A[4-7]\b/gi, "");
  }

  // 1. Remove NUEVO/NUEVA/NEW prefix
  normalized = normalized.replace(/^(NUEVO|NUEVA|NEW)\s+/gi, "");

  // Remove specs from modelo using MODELO_SPECS_TO_REMOVE
  MODELO_SPECS_TO_REMOVE.forEach((spec) => {
    const pattern = new RegExp(
      `\\b${spec.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`,
      "gi"
    );
    normalized = normalized.replace(pattern, " ");
  });

  // Remove content in parentheses (e.g., "JETTA (DERBY)" -> "JETTA")
  normalized = normalized.replace(/\([^)]+\)/g, " ");

  // 2. Mazda-specific: Remove MAZDA/MA prefix
  if (marcaUpper === "MAZDA") {
    normalized = normalized.replace(/^(MAZDA|MA)\s+/gi, "");
  }

  // 3. Mercedes-specific: Remove MERCEDES prefix and fix KLASSE
  if (marcaUpper === "MERCEDES BENZ" || marcaUpper === "MERCEDES") {
    normalized = normalized.replace(/^MERCEDES\s+(BENZ\s+)?/gi, "");
    normalized = normalized.replace(/\bKLASSE\b/gi, "CLASE");
  }

  // 4. BMW-specific: Fix SERIE X5
  if (marcaUpper === "BMW" && normalized === "SERIE X5") {
    return "X5";
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
  if (!record.marca || record.marca.trim() === "")
    errors.push("marca is required");
  if (!record.modelo || record.modelo.trim() === "")
    errors.push("modelo is required");
  if (!record.anio || record.anio < 2000 || record.anio > 2030)
    errors.push("anio must be between 2000-2030");
  if (!record.version_original || record.version_original.trim() === "")
    errors.push("version is required");
  if (!record.transmision || record.transmision.trim() === "")
    errors.push("transmision is required");
  return { isValid: errors.length === 0, errors };
}

function normalizeText(value) {
  return value ? value.trim().toUpperCase() : "";
}

function categorizeError(error) {
  const message = error.message.toLowerCase();
  if (message.includes("validation")) return "VALIDATION_ERROR";
  if (message.includes("hash")) return "HASH_GENERATION_ERROR";
  return "NORMALIZATION_ERROR";
}

const outputItems = normalizeQualitasRecords(items);
return outputItems;
