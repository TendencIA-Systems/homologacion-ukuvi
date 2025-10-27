/**
 * HDI ETL - Normalization Code Node
 *
 * Harmonizes HDI records with the shared homologation contract.
 * - Canonicalizes AUTO/MANUAL transmissions (numeric + textual) and strips aliases from trims.
 * - Normalizes drivetrain, engine specs, comfort tokens (COMFORT/CONFORT), and compact turbo/ton strings.
 * - Preserves trim tokens while removing door/occupant noise via numeric-context guards.
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
  // R-LINE removido - ahora protegido en PROTECTED_HYPHEN_TOKENS
  // "R-LINE",
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

const BATCH_SIZE = 5000;

const CANONICAL_TRANSMISSIONS = new Set(["AUTO", "MANUAL"]);

const TRANSMISSION_DEFINITIONS = [
  {
    canonical: "MANUAL",
    tokens: [
      "MANUAL",
      "MAN",
      "MAN.",
      "STD",
      "STD.",
      "TM",
      "ESTANDAR",
      "MECANICO",
      "MECANICA",
      "MECA",
      "MECHANICO",
      "SECUENCIAL",
      "DRIVELOGIC",
      "DUALOGIC",
      "SMG",
      "SEMI AUTOMATICO",
      "SEMI AUTOMATICA",
    ],
  },
  {
    canonical: "AUTO",
    tokens: [
      "AUTO",
      "AUT",
      "AUT.",
      "AT",
      "AT.",
      "AUTOMATICO",
      "AUTOMATICA",
      "AUTOMATIC",
      "AUTOMATIZADO",
      "AUTOMATIZADA",
      "AUTOTRANS",
      "AUTOM",
      "CVT",
      "E CVT",
      "E-CVT",
      "ECVT",
      "IVT",
      "I CVT",
      "DSG",
      "DCT",
      "TIPTRONIC",
      "TIPTRNIC",
      "STEPTRONIC",
      "GEARTRONIC",
      "MULTITRONIC",
      "S TRONIC",
      "S-TRONIC",
      "STRONIC",
      "S.TRONIC",
      "Q TRONIC",
      "Q-TRONIC",
      "TOUCHTRONIC",
      "TOUCHTRONIC3",
      "POWERSHIFT",
      "PDK",
      "SPORTSHIFT",
      "SELESPEED",
      "SALESPEED",
      "SPEEDSHIFT",
      "TORQUEFLITE",
      "DUAL CLUTCH",
      "DUAL-CLUTCH",
      "HYDROMATIC",
      "XTRONIC",
      "X-TRONIC",
      "X TRONIC",
      "MULTIDRIVE",
    ],
  },
];

const BRAND_ALIASES = {
  "GENERAL MOTORS": "GMC",
  "GENERAL MOTORS 2": "GMC",
  "GENERAL MOTORS COMPANY": "GMC",
  "GENERAL MOTORS CORPORATION": "GMC",
  GMC: "GMC",
  "JAC SEI": "JAC",
  "MG ROVER": "MG",
  MINI: "BMW",
  "BMW MINI": "BMW",
  "MINI COOPER": "BMW",
};

const HDI_NORMALIZATION_DICTIONARY = {
  irrelevant_comfort_audio: [
    // Audio/Navegación
    "AA",
    "EE",
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
    "CP", // HDI-specific addition
    "SQ",
    "CB",
    "CQ",
    "SM",
    "VT",
    "DIS",
    "TAM",
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
    "SELESPEED",
    "SALESPEED",
    "Q-TRONIC",
    "DCT",
    "MULTITRONIC",
    "STEPTRONIC",
    "GEARTRONIC",
    "STRONIC", // Audi DSG - for inference (118 occurrences in HDI) then removal
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
    // HDI specific tokens (preserved from original)
    "EQ",
    "A/A",
    "A A",
    "E/E",
    "E E",
    "B/A",
    "B A",
    "Q C",
    "VINIL",
    "ALARM",
    "ALARMA",
    "CAM",
    "CAMARA",
    "PARK",
    "PARKTRONIC",
    "CLIMA",
    "CLIMATRONIC",
    "D/T",
    "D T",
    "D/V",
    "D V",
    "PADDLE",
    "KEYLESS",
    "PUSH",
    "START",
    "BOTON",
    "ENCENDIDO",
    "VE",
    "V.E.",
    "S/D",
  ],
  cylinder_normalization: {
    L3: "3CIL",
    L4: "4CIL",
    L5: "5CIL",
    L6: "6CIL",
    L8: "8CIL",
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
    R5: "5CIL",
    R6: "6CIL",
    B4: "4CIL",
    B6: "6CIL",
  },
  regex_patterns: {
    decimal_comma: /(\d),(\d)/g,
    multiple_spaces: /\s+/g,
    trim_spaces: /^\s+|\s+$/g,
    stray_punctuation: /(?<!\d)[\.,;]|[\.,;](?!\d)/g,
  },
};

const PROTECTED_HYPHEN_TOKENS = [
  {
    regex: /\bA[\s-]?SPEC\b/gi,
    placeholder: "__HDI_PROTECTED_A_SPEC__",
    canonical: "A-SPEC",
  },
  {
    regex: /\bTYPE[\s-]?S\b/gi,
    placeholder: "__HDI_PROTECTED_TYPE_S__",
    canonical: "TYPE-S",
  },
  {
    regex: /\bTYPE[\s-]?R\b/gi,
    placeholder: "__HDI_PROTECTED_TYPE_R__",
    canonical: "TYPE-R",
  },
  {
    regex: /\bTYPE[\s-]?F\b/gi,
    placeholder: "__HDI_PROTECTED_TYPE_F__",
    canonical: "TYPE-F",
  },
  {
    regex: /\bS[\s-]?LINE\b/gi,
    placeholder: "__HDI_PROTECTED_S_LINE__",
    canonical: "S-LINE",
  },
  {
    regex: /\bR[\s-]?LINE\b/gi,
    placeholder: "__HDI_PROTECTED_R_LINE__",
    canonical: "R-LINE",
  },
  {
    regex: /\bX[\s-]?DRIVE\b/gi,
    placeholder: "__HDI_PROTECTED_X_DRIVE__",
    canonical: "X-DRIVE",
  },
];

/**
 * HDI-specific protected space-separated trims (24 unique trims)
 * These trims must be protected from being split during normalization
 * Based on actual data analysis - see CORRECTED-TRIM-LIST.md
 */
const PROTECTED_SPACED_TRIMS_HDI = [
  // M-series (universal - present in ALL insurers)
  "M SPORT",

  // I-series Mazda (HDI, AXA, Atlas, El Potosí, GNP, Zurich)
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

  // Letter + SPORT
  "E SPORT",

  // Letter + ELEGANCE
  "F ELEGANCE",

  // TYPE variants (already protected by PROTECTED_HYPHEN_TOKENS but listing for completeness)
  // TYPE S (handled as hyphenated TYPE-S)

  // 🔥 v2.13.0 ADDITIONS:
  "MX GRAND TOURING",
  "F SPORT",
  "JOHN COOPER WORKS",
  "COOPER WORKS",
  "COOPER S",
  "KING RANCH",
  "EDDIE BAUER",
  "HIGH COUNTRY",
  "GRAND CHEROKEE",
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

const VALID_DOOR_COUNTS = new Set([2, 3, 4, 5, 7]);

const RESIDUAL_SINGLE_TOKENS = new Set(["A", "B", "C", "E", "Q"]);

const ENGINE_ALIAS_PATTERNS = [
  { regex: /\bT[\s-]?FSI\b/gi, replacement: "TURBO" },
  { regex: /\bT[\s-]?SI\b/gi, replacement: "TURBO" },
  { regex: /\bFSI\s*TURBO\b/gi, replacement: "TURBO" },
  { regex: /\bECOBOOST\b/gi, replacement: "TURBO" },
  { regex: /\bT[\s-]?JET\b/gi, replacement: "TURBO" },
  { regex: /\bBI[\s-]?TURBO\b/gi, replacement: "BITURBO" },
  { regex: /\bTURBO DIESEL\b/gi, replacement: "DIESEL_TURBO" },
  { regex: /\bDIESEL TURBO\b/gi, replacement: "DIESEL_TURBO" },
  { regex: /\bTDI\b/gi, replacement: "DIESEL_TURBO" },
  { regex: /\bCDI\b/gi, replacement: "DIESEL_TURBO" },
  { regex: /\bTDCI\b/gi, replacement: "DIESEL_TURBO" },
  { regex: /\bHDI\b/gi, replacement: "DIESEL_TURBO" },
  { regex: /\bBLUETEC\b/gi, replacement: "DIESEL_TURBO" },
  { regex: /\bHEMI\b/gi, replacement: "HEMI" },
];

function escapeRegExp(value = "") {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function sanitizeTransmissionToken(value = "") {
  return value
    .toString()
    .toUpperCase()
    .replace(/[^\w\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function generateTransmissionTokenVariants(token = "") {
  const variants = new Set();
  const upper = token.toString().toUpperCase();
  variants.add(upper);
  variants.add(upper.replace(/-/g, " "));
  variants.add(upper.replace(/\./g, ""));
  variants.add(upper.replace(/[.\-]/g, " "));
  variants.add(upper.replace(/\s+/g, " ").trim());
  variants.add(upper.replace(/\s+/g, ""));
  const sanitized = sanitizeTransmissionToken(token);
  if (sanitized) {
    variants.add(sanitized);
    variants.add(sanitized.replace(/\s+/g, ""));
  }
  return Array.from(variants)
    .map((variant) => variant.trim())
    .filter(Boolean);
}

const TRANSMISSION_TOKEN_MAP = new Map();
const TRANSMISSION_SEARCH_PATTERNS = [];
const TRANSMISSION_TOKEN_VARIANTS = new Set();

TRANSMISSION_DEFINITIONS.forEach(({ canonical, tokens }) => {
  const variantSet = new Set();
  tokens.forEach((token) => {
    const normalizedToken = sanitizeTransmissionToken(token);
    if (normalizedToken && !TRANSMISSION_TOKEN_MAP.has(normalizedToken)) {
      TRANSMISSION_TOKEN_MAP.set(normalizedToken, canonical);
    }
    generateTransmissionTokenVariants(token).forEach((variant) => {
      variantSet.add(variant);
      TRANSMISSION_TOKEN_VARIANTS.add(variant);
    });
  });
  TRANSMISSION_SEARCH_PATTERNS.push({
    canonical,
    patterns: Array.from(variantSet)
      .map((variant) => {
        const trimmed = variant.trim();
        if (!trimmed) return null;
        const useWordBoundary = /^[A-Z0-9 ]+$/.test(trimmed);
        const source = useWordBoundary
          ? `\\b${escapeRegExp(trimmed)}\\b`
          : escapeRegExp(trimmed);
        return new RegExp(source, "i");
      })
      .filter(Boolean),
  });
});

HDI_NORMALIZATION_DICTIONARY.transmission_tokens = Array.from(
  new Set(
    Array.from(TRANSMISSION_TOKEN_VARIANTS)
      .flatMap((token) => {
        const spaced = token.toUpperCase().replace(/\s+/g, " ").trim();
        const compact = spaced.replace(/\s+/g, "");
        return [spaced, compact];
      })
      .filter(Boolean)
  )
);

HDI_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio = Array.from(
  new Set(
    HDI_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.map((token) =>
      token
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .toUpperCase()
        .replace(/\s+/g, " ")
        .trim()
    )
  )
);

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
 * HDI-specific: 7 unique trims with multi-space handling
 * Handles multi-space variants (e.g., "M  SPORT" with double/triple spaces)
 */
function protectTrims(version) {
  if (!version) return version;

  let protected = version;

  // Protect space-separated trims (with multi-space handling)
  PROTECTED_SPACED_TRIMS_HDI.forEach((trim) => {
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

function stripTokens(text = "", tokens = []) {
  if (!text || typeof text !== "string") return "";
  let output = text;
  tokens.forEach((token) => {
    const trimmed = token.trim();
    if (!trimmed) return;
    const useWordBoundary = /^[A-Z0-9 ]+$/.test(trimmed);
    const pattern = useWordBoundary
      ? new RegExp(`\\b${escapeRegExp(trimmed)}\\b`, "gi")
      : new RegExp(escapeRegExp(trimmed), "gi");
    output = output.replace(pattern, " ");
  });
  return output;
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

function normalizeCylinders(value = "") {
  if (!value || typeof value !== "string") return "";
  let output = value;
  Object.entries(HDI_NORMALIZATION_DICTIONARY.cylinder_normalization).forEach(
    ([from, to]) => {
      const pattern = new RegExp(`\\b${escapeRegExp(from)}\\b`, "gi");
      output = output.replace(pattern, to);
    }
  );
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

function normalizeStandaloneLiters(value = "") {
  if (!value || typeof value !== "string") return "";
  const compacted = value.replace(/\b(\d+\.\d+)\s+L\b/g, "$1L");
  return compacted.replace(
    /\b(\d+\.\d+)(?!\s*(?:L\b|TON|TONELADAS|KG|KILOGRAMOS|PUERTAS|OCUP|CIL|SERIE))/gi,
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
      if (/\b(PUERTAS?|PTS?|OCUP|PASAJEROS?|PAS|CIL|SERIE)\b/.test(after)) {
        return match;
      }

      return `${match}L`;
    }
  );
}

function normalizeHorsepower(value = "") {
  if (!value || typeof value !== "string") return "";
  return (
    value
      // Convert CP (Caballos de Potencia) → HP
      .replace(/\b(\d+)\s*C\.P\.?\b/gi, "$1HP")
      .replace(/\b(\d+)\s*CP\b/gi, "$1HP")
      .replace(/\b(\d+)\s*H\.P\.?\b/gi, "$1HP")
      .replace(/\b(\d+)\s*HP\b/gi, "$1HP")
  );
}

function collapseDisplacementArtifacts(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b(\d+CIL)\.0(?:\.0L)?\b/g, "$1")
    .replace(/\b(\d+CIL)\s+0\.0L\b/g, "$1")
    .replace(/\b(\d+(?:\.\d+)L)(?:\s*\1)+\b/g, "$1")
    .replace(/\b(\d+(?:\.\d+)L)L\b/g, "$1");
}

function formatTurboDisplacement(raw = "") {
  const value = parseFloat(raw);
  if (!Number.isFinite(value) || value <= 0 || value > 12) {
    return "";
  }
  return Number.isInteger(value) ? `${value}.0` : value.toString();
}

function normalizeTurboSuffix(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b(\d+\.\d+)T\b/gi, "$1L TURBO")
    .replace(/\b(\d+\.\d+)\s*T\b/gi, "$1L TURBO");
}

function normalizeTonCapacity(value = "") {
  if (!value || typeof value !== "string") return "";
  return value.replace(/\b(\d+(?:\.\d+)?)\s*TON\b/gi, (_match, ton) => {
    const parsed = parseFloat(ton);
    if (!Number.isFinite(parsed) || parsed <= 0) return "";
    return `${parsed.toString()}TON`;
  });
}

function applyEngineAliases(value = "") {
  if (!value || typeof value !== "string") return "";
  let output = value;
  ENGINE_ALIAS_PATTERNS.forEach(({ regex, replacement }) => {
    output = output.replace(regex, replacement);
  });
  return output;
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

  output = output
    .replace(/\bTBO\b/gi, "TURBO")
    .replace(/\bBI[\s-]?TURBO\b/gi, "BITURBO")
    .replace(/\bTWIN[\s-]?TURBO\b/gi, "TWIN TURBO")
    .replace(/\bT\/T\b/gi, "TWIN TURBO");

  return output;
}

function normalizeBrand(value = "") {
  if (!value || typeof value !== "string") return "";
  const normalized = value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toUpperCase();
  return BRAND_ALIASES[normalized] || normalized;
}

function normalizeText(value = "") {
  return value
    ? value
        .toString()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .trim()
        .toUpperCase()
    : "";
}

function cleanHdiModel(rawModel = "", brand = "") {
  const normalizedModel = normalizeText(rawModel);
  if (!normalizedModel) {
    return { model: "", extras: "" };
  }

  let cleaned = normalizedModel;
  const extras = [];
  const normalizedBrand = normalizeBrand(brand || "");
  if (normalizedBrand) {
    const variants = [
      normalizedBrand,
      normalizedBrand.replace(/\s+/g, ""),
      normalizedBrand.split(" ")[0],
    ].filter(Boolean);
    variants.forEach((variant) => {
      const startRegex = new RegExp(`^${escapeRegExp(variant)}\s*`);
      cleaned = cleaned.replace(startRegex, "");
      const inlineRegex = new RegExp(`\s+${escapeRegExp(variant)}\b`, "g");
      cleaned = cleaned.replace(inlineRegex, " ");
    });
  }

  cleaned = cleaned
    .replace(/\b(NUEVO|NUEVA|NUEVA LINEA|NUEVALINEA|LINEA NUEVA|NEW)\b/g, " ")
    .replace(/\bPASAJEROS?\b/g, " ");

  cleaned = cleaned
    .replace(/\bGENERACION\b/g, "GEN")
    .replace(/\bGEN\.?\b/g, "GEN");

  if (normalizedBrand === "VOLVO") {
    cleaned = cleaned
      .replace(/\bXC-(\d+)\b/g, "XC$1")
      .replace(/\bV-(\d+)\b/g, "V$1")
      .replace(/\bS-(\d+)\b/g, "S$1")
      .replace(/\bC-(\d+)\b/g, "C$1");
  }

  if (normalizedBrand === "MAZDA") {
    cleaned = cleaned.replace(/^MAZDA\s*/, "");
  }

  if (normalizedBrand === "VOLKSWAGEN") {
    cleaned = cleaned.replace(/^TRANSPORTER\s+PASAJEROS\b/, "TRANSPORTER");
  }

  const bodyTypes = /\b(HATCHBACK|SEDAN|WAGON|COUPE|CONVERTIBLE|SUV)\b/;
  if (bodyTypes.test(cleaned)) {
    const match = cleaned.match(bodyTypes);
    if (match) {
      extras.push(match[1]);
      cleaned = cleaned.replace(bodyTypes, " ");
    }
  }

  if (/\bJETTA\b/.test(cleaned)) {
    const tokens = cleaned.split(/\s+/).filter(Boolean);
    const leftovers = tokens.filter((token) => token !== "JETTA");
    if (leftovers.length) {
      extras.push(leftovers.join(" "));
    }
    cleaned = "JETTA";
  }

  if (
    (normalizedBrand === "BMW" || normalizedBrand === "MINI") &&
    (/\bMINI\b/.test(cleaned) || /\bCOOPER\b/.test(cleaned))
  ) {
    cleaned = "MINI COOPER";
  }

  if (normalizedBrand === "FORD") {
    cleaned = cleaned.replace(/[-.]/g, " ");
    cleaned = cleaned.replace(
      /\b([A-Z])\s*(\d{2,4})\b/g,
      (_match, prefix, digits) => `${prefix}${digits}`
    );
  }

  cleaned = cleaned.replace(/\s+/g, " ").trim();

  return {
    model: cleaned,
    extras: extras.filter(Boolean).join(" "),
  };
}

function cleanVersionString(versionString = "", brand = "", model = "") {
  if (!versionString || typeof versionString !== "string") return "";

  let cleaned = versionString
    .toString()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/"/g, " ")
    .trim();

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

  cleaned = cleaned.replace(
    HDI_NORMALIZATION_DICTIONARY.regex_patterns.decimal_comma,
    "$1.$2"
  );
  cleaned = cleaned.replace(/[\\/]/g, " ");
  cleaned = cleaned.replace(/\s*&\s*/g, " ");
  cleaned = cleaned.replace(/-/g, " ");
  cleaned = cleaned.replace(/AUT(?=[A-Z0-9])(?!O)/g, "AUT ");
  cleaned = cleaned.replace(/([A-Z0-9])AUT\b/g, "$1 AUT");
  cleaned = cleaned.replace(/(\d)([A-Z])/g, "$1 $2");
  cleaned = cleaned.replace(/([A-Z])(\d)/g, "$1 $2");
  cleaned = cleaned.replace(
    /\b([A-Z0-9]+)(AUT|MAN|STD|CVT|DSG|DCT|IVT|TIPTRONIC)\b/g,
    "$1 $2"
  );
  cleaned = cleaned.replace(/\bHB\b/g, "HATCHBACK");
  cleaned = cleaned.replace(/\bSW\b/g, "WAGON");
  cleaned = cleaned.replace(/\bPICK\s*UP\b/g, "PICKUP");
  cleaned = cleaned.replace(/\b(V|L|R|H|I|B)\s+(\d{1,2})\b/g, "$1$2");
  cleaned = cleaned.replace(/\b(\d{1,2})\s+CIL\b/g, "$1CIL");
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)\s+L\b/g, "$1L");

  cleaned = normalizeTonCapacity(cleaned);
  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeCylinders(cleaned);
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);
  cleaned = collapseDisplacementArtifacts(cleaned);
  cleaned = normalizeTurboSuffix(cleaned);
  cleaned = normalizeHorsepower(cleaned);
  cleaned = normalizeTurboTokens(cleaned);
  cleaned = applyEngineAliases(cleaned);

  cleaned = stripTokens(
    cleaned,
    HDI_NORMALIZATION_DICTIONARY.transmission_tokens
  );
  cleaned = stripTokens(
    cleaned,
    HDI_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio
  );

  cleaned = cleaned
    .replace(/\b0\s*TON(?:ELADAS|S)?\b/gi, " ")
    .replace(/\b0TON\b/gi, " ")
    .replace(/\b0\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/gi, " ")
    .replace(/\b0(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/gi, " ");

  if (brand) {
    const normalizedBrand = normalizeBrand(brand);
    if (normalizedBrand) {
      const variants = [
        normalizedBrand,
        normalizedBrand.replace(/\s+/g, ""),
        normalizedBrand.split(" ")[0],
      ].filter(Boolean);
      variants.forEach((variant) => {
        cleaned = cleaned.replace(
          new RegExp(`\b${escapeRegExp(variant)}\b`, "gi"),
          " "
        );
      });
    }
  }

  if (model) {
    const normalizedModel = normalizeText(model);
    if (normalizedModel) {
      const modelVariants = [
        normalizedModel,
        normalizedModel.replace(/[-\s]+/g, ""),
        normalizedModel.replace(/-/g, " "),
      ].filter(Boolean);
      modelVariants.forEach((variant) => {
        cleaned = cleaned.replace(
          new RegExp(`\b${escapeRegExp(variant)}\b`, "gi"),
          " "
        );
      });
    }
  }

  cleaned = cleaned.replace(
    HDI_NORMALIZATION_DICTIONARY.regex_patterns.stray_punctuation,
    " "
  );
  // STAGE 8: TRIM RESTORATION - restore hyphenated trims first
  cleaned = restoreProtectedTokens(cleaned);
  // STAGE 8: TRIM RESTORATION - restore space-separated trims
  cleaned = restoreTrims(cleaned);

  cleaned = cleaned.replace(
    HDI_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces,
    " "
  );
  cleaned = cleaned.replace(
    HDI_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces,
    ""
  );

  return cleaned;
}

function extractDoorsAndOccupants(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") {
    return { doors: "", occupants: "" };
  }

  const normalized = versionOriginal
    .toString()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/[-,/]/g, " ");

  const doorMatch = normalized.match(
    /\b(\d{1,2})\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/
  );
  let doors = "";
  if (doorMatch) {
    const doorCount = parseInt(doorMatch[1], 10);
    if (VALID_DOOR_COUNTS.has(doorCount)) {
      doors = `${doorCount}PUERTAS`;
    }
  }

  const occMatch = normalized.match(
    /\b0?(\d{1,2})\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX|PASAJEROS?|PAS)\b/
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

function normalizeTransmission(value) {
  if (value === null || value === undefined) return "";
  if (typeof value === "number") {
    if (value === 1) return "MANUAL";
    if (value === 2) return "AUTO";
    return "";
  }
  const asString = value.toString().trim();
  if (!asString) return "";
  if (/^[12]$/.test(asString)) {
    return asString === "1" ? "MANUAL" : "AUTO";
  }
  const normalizedToken = sanitizeTransmissionToken(asString);
  if (!normalizedToken) return "";
  if (CANONICAL_TRANSMISSIONS.has(normalizedToken)) {
    return normalizedToken;
  }
  if (TRANSMISSION_TOKEN_MAP.has(normalizedToken)) {
    return TRANSMISSION_TOKEN_MAP.get(normalizedToken);
  }
  return "";
}

function inferTransmissionFromVersion(versionOriginal = "") {
  if (!versionOriginal) return "";
  const normalizedVersion = versionOriginal
    .toString()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/-/g, " ");
  for (const { canonical, patterns } of TRANSMISSION_SEARCH_PATTERNS) {
    for (const pattern of patterns) {
      if (pattern.test(normalizedVersion)) {
        return canonical;
      }
    }
  }
  return "";
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

function validateRecord(record) {
  const errors = [];
  const year = Number(record.anio);

  if (!record.marca || record.marca.toString().trim() === "") {
    errors.push("marca is required");
  }
  if (!record.modelo || record.modelo.toString().trim() === "") {
    errors.push("modelo is required");
  }
  if (!Number.isInteger(year) || year < 2000 || year > 2030) {
    errors.push("anio must be between 2000-2030");
  } else {
    record.anio = year;
  }
  if (
    !record.version_original ||
    record.version_original.toString().trim() === ""
  ) {
    errors.push("version is required");
  }
  const transmission = record.transmision
    ? record.transmision.toString().trim().toUpperCase()
    : "";
  if (!CANONICAL_TRANSMISSIONS.has(transmission)) {
    errors.push("transmision is required");
  } else {
    record.transmision = transmission;
  }

  return { isValid: errors.length === 0, errors };
}

function categorizeError(error) {
  const message = (error.message || "").toLowerCase();
  if (message.includes("validation")) return "VALIDATION_ERROR";
  if (message.includes("hash")) return "HASH_GENERATION_ERROR";
  return "NORMALIZATION_ERROR";
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

function processHdiRecord(record) {
  const versionOriginal = record.version_original
    ? record.version_original.toString()
    : "";
  const derivedTransmission =
    normalizeTransmission(record.transmision) ||
    inferTransmissionFromVersion(versionOriginal);

  record.transmision = derivedTransmission;

  const marcaNormalizada = normalizeBrand(record.marca || "");
  const rawModelNormalized = normalizeText(record.modelo || "");
  const { model: modeloNormalizado, extras: modeloExtras } = cleanHdiModel(
    record.modelo || "",
    marcaNormalizada
  );
  const modeloFinal = modeloNormalizado || rawModelNormalized;

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
  let enhancedVersion = versionOriginal || "";
  if (modeloSpecs.length > 0) {
    enhancedVersion = `${modeloSpecs.join(" ")} ${enhancedVersion}`.trim();
  }

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

  const versionSeed = modeloExtras
    ? `${modeloExtras} ${enhancedVersion}`.trim()
    : enhancedVersion;

  let versionLimpia = cleanVersionString(
    versionSeed,
    marcaNormalizada,
    modeloFinal
  );

  versionLimpia = versionLimpia
    .replace(/\b\d\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/gi, " ")
    .replace(
      /\b0?\d+\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX|PASAJEROS?|PAS)\b/gi,
      " "
    )
    .replace(/\s+[.,](?=\s|$)/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  const tokens = versionLimpia.split(" ").filter(Boolean);
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
      return;
    }

    const upperToken = token.toUpperCase();
    if (upperToken === (modeloFinal || "").toUpperCase()) return;
    if (
      upperToken === "CIL" &&
      sanitizedTokens.length &&
      sanitizedTokens[sanitizedTokens.length - 1].toUpperCase().endsWith("CIL")
    )
      return;
    if (upperToken.length === 1 && RESIDUAL_SINGLE_TOKENS.has(upperToken)) {
      return;
    }
    sanitizedTokens.push(token);
  });

  versionLimpia = dedupeTokens(sanitizedTokens)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();

  const finalDoors = doors;
  versionLimpia = [versionLimpia, finalDoors, occupants]
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();

  if (!versionLimpia) {
    throw new Error("Normalization produced empty version_limpia");
  }

  const normalized = {
    origen_aseguradora: "HDI",
    id_original: record.id_original,
    marca: marcaNormalizada,
    modelo: normalizeModelo(marcaNormalizada, modeloFinal),
    anio: record.anio,
    transmision: record.transmision,
    version_original: versionOriginal,
    version_limpia: versionLimpia,
    fecha_procesamiento: new Date().toISOString(),
  };

  normalized.hash_comercial = createCommercialHash(normalized);
  return normalized;
}

function normalizeHdiData(records = []) {
  const results = [];
  const errors = [];

  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const batch = records.slice(i, i + BATCH_SIZE);
    for (const record of batch) {
      try {
        results.push(processHdiRecord(record));
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

function normalizeHdiRecords(items = []) {
  const rawRecords = items.map((it) => (it && it.json ? it.json : it));
  const { results, errors } = normalizeHdiData(rawRecords);
  const successItems = results.map((record) => ({ json: record }));
  const errorItems = errors.map((error) => ({ json: error }));
  return [...successItems, ...errorItems];
}

const outputItems = normalizeHdiRecords(items);
return outputItems;
