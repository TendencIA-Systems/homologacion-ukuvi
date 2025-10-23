/**
 * Chubb ETL - Normalization Code Node (updated: drop floating numbers used for doors)
 *
 * Mirrors the insurer normalization pipeline used for Zurich/Qualitas/Atlas.
 * Intended for execution inside an n8n Code node: it cleans Chubb vehicle
 * records, infers transmissions when missing, extracts door/occupant tokens,
 * and outputs normalized objects ready for Supabase ingestion.
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
  "R-LINE",
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

function cleanBMWModelo(marca, modelo) {
  if (!modelo) return modelo;

  if (marca && marca.toUpperCase().trim() === "BMW") {
    modelo = modelo.replace(/^SERIE\s+/i, "").trim();
  }

  return modelo;
}

/**
 * Fix: BMW/MINI brand separation (CHUBB-specific)
 * CHUBB stores MINI vehicles under BMW brand with modelo="MINI COOPER"
 * This function separates them to marca="MINI", modelo="COOPER"
 */
function fixChubbMINIBrand(marca, modelo) {
  if (!marca || !modelo) return { marca, modelo };

  if (
    marca.toUpperCase().trim() === "BMW" &&
    modelo.toUpperCase().includes("MINI")
  ) {
    marca = "MINI";
    modelo = modelo.replace(/^MINI\s+/i, "").trim();
  }

  return { marca, modelo };
}

/**
 * Fix: Remove space before BMW trim codes (e.g., "118 I" → "118I")
 */
function fixChubbTrimSpacing(marca, modelo) {
  if (!marca || !modelo) return modelo;

  if (marca.toUpperCase().trim() === "BMW") {
    // Remove space before I or IA suffix at end of string
    modelo = modelo.replace(/(\d+)\s+(I[A]?)\s*$/i, "$1$2").trim();
  }

  return modelo;
}

/**
 * Fix: Move SDRIVE/XDRIVE from modelo to version (CHUBB-specific)
 */
function cleanChubbDriveSuffix(marca, modelo, version) {
  if (!marca || !modelo) return { modelo, version };

  // Only apply to BMW
  if (marca.toUpperCase().trim() === "BMW") {
    // Check for SDRIVE/XDRIVE suffix
    const driveMatch = modelo.match(/\s+(SDRIVE|XDRIVE)\s*$/i);
    if (driveMatch) {
      const driveType = driveMatch[1].toUpperCase();

      // Remove from modelo
      modelo = modelo.replace(/\s+(SDRIVE|XDRIVE)\s*$/i, "").trim();

      // Add to version if not already there
      version = version || "";
      if (!version.toUpperCase().includes(driveType)) {
        version = `${driveType} ${version}`.trim();
      }
    }
  }

  return { modelo, version };
}

const CHUBB_NORMALIZATION_DICTIONARY = {
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
    "IEC",
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
    "IMO",
    "DIS",
    "CQ",
    "TELA",
    "CT",
    "IEM",
    "SMP",
    "SM",
    "IPC",
    "HDS",
    "NAVI",
    "CAM TRAS",
    "SENSOR",
    "CAMARA",
    "IMP",
    "ISM",
    "BTU",
    "TBO",
    "STD",
    "STD.",
    "AUT",
    "AUT.",
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
    CVT: "AUTO",
    CVT7: "AUTO",
    DSG: "AUTO",
    "S TRONIC": "AUTO",
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

const INVALID_TRANSMISSION_CODES = new Set([
  "",
  "-",
  "NA",
  "N/A",
  "S/D",
  "SD",
  "SIN DATO",
  "SIN INFORMACION",
  "SIN INFORMACI�N",
  "NO APLICA",
  "NO APL",
  "NO DEFINIDO",
]);

const NORMALIZED_TRANSMISSIONS = new Set(["AUTO", "MANUAL"]);
const NUMERIC_CONTEXT_TOKENS = new Set([
  "O",
  "OC",
  "OCU",
  "OCUP",
  "OCUPANTE",
  "OCUPANTES",
  "PASAJEROS",
  "PASAJERO",
  "PAS",
  "PUERTAS",
  "PUERTA",
  "PAX",
]);

const VALID_DOOR_COUNTS = new Set([2, 3, 4, 5, 7]);

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
    regex: /\bS[\s-]?LINE\b/gi,
    placeholder: "__PROTECTED_S_LINE__",
    canonical: "S-LINE",
  },
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

function normalizeStandaloneLiters(value = "") {
  if (!value || typeof value !== "string") return "";

  // First, compact spaced liters like "2.3 L" → "2.3L"
  const compacted = value.replace(/\b(\d+\.\d+)\s+L\b/g, "$1L");

  // Then add L to standalone decimal numbers that look like liters
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
      if (/\b(PUERTAS|PTS?|OCUP|PASAJEROS?|PAS|CIL|SERIE)\b/.test(after)) {
        return match;
      }
      return `${match}L`;
    }
  );
}
function collapseDisplacementArtifacts(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b(\d+CIL)\.0(?:\.0L)?\b/g, "$1")
    .replace(/\b(\d+CIL)\s+0\.0L\b/g, "$1")
    .replace(/\b(\d+(?:\.\d+)L)(?:\s*\1)+\b/g, "$1");
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
  Object.entries(CHUBB_NORMALIZATION_DICTIONARY.cylinder_normalization).forEach(
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
  if (!text || typeof text !== "string") return "";

  // BMW model numbers incorrectly parsed as doors
  const bmwModelNumbers = ["300", "320", "328", "335"];
  bmwModelNumbers.forEach((num) => {
    text = text.replace(new RegExp(`\\b${num}PUERTAS\\b`, "g"), "");
  });

  // Salvageable truck notation
  text = text.replace(/\b3500PUERTAS\b/g, "4PUERTAS");

  // Invalid values
  text = text.replace(/\b0PUERTAS\b/g, "");
  text = text.replace(/\b[6-9]PUERTAS\b/g, "");
  text = text.replace(/\b\d{3,}PUERTAS\b/g, "");

  return text;
}

function cleanVersionString(versionString = "", model = "", marca = "") {
  if (!versionString || typeof versionString !== "string") return "";

  let cleaned = versionString
    .toString()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .trim();

  // ENHANCED: Remove escape characters (Requirement 5.1)
  cleaned = cleaned.replace(/\\"/g, ""); // Remove escaped quotes
  cleaned = cleaned.replace(/\\\\/g, ""); // Remove backslashes
  cleaned = cleaned.replace(/[""''\"'\u201C\u201D\u2018\u2019]/g, " "); // All quote types

  // ENHANCED: Separate HP from AUT (Requirement 5.2)
  cleaned = cleaned.replace(/(\d+)HPAUT/gi, "$1HP AUT");
  cleaned = cleaned.replace(/(\d+)HP([A-Z])/gi, "$1HP $2");

  // CHUBB-SPECIFIC: Separate liters from adjacent text (Requirement 7.9)
  cleaned = cleaned.replace(/(\d+\.?\d*)L([A-Z])/gi, "$1L $2");

  cleaned = cleaned.replace(/AUT(?=[A-Z0-9])/g, "AUT ");
  cleaned = applyProtectedTokens(cleaned);
  cleaned = cleaned.replace(/\bRA-?(\d+)\b/g, "R$1");
  cleaned = cleaned.replace(/[\/,]/g, " ");
  cleaned = cleaned.replace(/-/g, " ");

  // NEW: Remove generation/trim prefixes (A7, MK VII, etc.) - NUEVO already handled in lines 447-449
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
  cleaned = cleaned
    .replace(/\b0+(?:\.\d+)?\s*TON(?:ELADAS)?\b/gi, " ")
    .replace(/\bTONELADAS?\b/gi, "TON")
    .replace(/LTON\b/g, "L TON");
  cleaned = collapseDisplacementArtifacts(cleaned);

  CHUBB_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach((token) => {
    const regex = new RegExp(`\\b${escapeRegex(token)}\\b`, "gi");
    cleaned = cleaned.replace(regex, " ");
  });

  if (model) {
    cleaned = cleaned.replace(
      new RegExp(`\b${escapeRegex(model.toUpperCase())}\b`, "gi"),
      " "
    );
    cleaned = cleaned.replace(/\bNUEVA?\s+LINEA\b/g, "");
    cleaned = cleaned.replace(/\bNUEV[OA]\b/g, "");
    cleaned = cleaned.replace(/\bNEW\b/g, "");
    cleaned = cleaned.replace(/\bPASAJEROS\b/g, "");
    cleaned = cleaned.replace(/\bMINI\s+COOPER\b.*/g, "MINI COOPER");
    cleaned = cleaned.replace(/\bMINICOOPER\b/g, "MINI COOPER");
    cleaned = cleaned.replace(/\bF[\s.-]?(\d{2,3})\b/g, "F$1");
    cleaned = cleaned.replace(/\bGENERACION\b/g, "GEN");
    cleaned = cleaned.replace(/\bGEN\./g, "GEN");
    if (/\bJETTA\b/.test(cleaned)) {
      cleaned = cleaned.replace(/\bJETTA\b.*/, "JETTA");
    }
  }

  if (marca) {
    cleaned = cleaned.replace(
      new RegExp(`\b${escapeRegex(marca.toUpperCase())}\b`, "gi"),
      " "
    );
  }

  cleaned = cleaned
    .replace(/\bHB\b/g, "HATCHBACK")
    .replace(/\bTUR\b/g, "TURBO")
    .replace(/\bCONV\b/g, "CONVERTIBLE")
    .replace(/\bPICK\s*UP\b/g, "PICKUP");

  cleaned = cleaned
    .replace(/\b\d+\s*PUERTAS?\b/gi, " ")
    .replace(/\bPUERTAS?\b/gi, " ")
    .replace(/\b0?\d+\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX)\b/gi, " ")
    .replace(/\b0?\d+\s*(?:PASAJEROS?|PAS)\b/gi, " ");

  const { year_codes, multiple_spaces, trim_spaces } =
    CHUBB_NORMALIZATION_DICTIONARY.regex_patterns;
  cleaned = cleaned.replace(year_codes, " ");
  cleaned = cleaned.replace(/(?<!\d)[.,](?!\d)/g, " ");
  cleaned = cleaned.replace(/\bL\b/g, " ");

  // ENHANCED: Fix invalid door counts (Requirement 5.3)
  cleaned = fixInvalidDoorCounts(cleaned);

  cleaned = cleaned.replace(multiple_spaces, " ");
  cleaned = cleaned.replace(trim_spaces, "");

  cleaned = restoreProtectedTokens(cleaned);
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
  const doorMatch = upper.match(
    /\b(\d{1,2})\s*(?:P(?:UERTAS?|TAS?|TS?|TA)?|PUERTAS?|P)\b/
  );
  let doors = "";
  if (doorMatch) {
    const doorCount = parseInt(doorMatch[1], 10);
    if (VALID_DOOR_COUNTS.has(doorCount)) {
      doors = `${doorCount}PUERTAS`;
    }
  }

  // Extract doors from "4 ABS" pattern (common in CHUBB data)
  if (!doors) {
    const absDoorsMatch = upper.match(/\b([2-7])\s+ABS\b/);
    if (absDoorsMatch) {
      const absCount = parseInt(absDoorsMatch[1], 10);
      if (VALID_DOOR_COUNTS.has(absCount)) {
        doors = `${absCount}PUERTAS`;
      }
    }
  }

  const occMatch = upper.match(
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

function consolidateBrand(marca) {
  if (!marca || typeof marca !== "string") return "";
  const normalized = marca.toUpperCase().trim();
  return BRAND_CONSOLIDATION_MAP[normalized] || normalized;
}

function normalizeTransmission(code) {
  if (!code || typeof code !== "string") return "";
  const normalized = code.toUpperCase().trim();
  if (!normalized || INVALID_TRANSMISSION_CODES.has(normalized)) return "";
  if (/^\d+$/.test(normalized)) return "";
  const mapped =
    CHUBB_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] ||
    normalized;
  if (NORMALIZED_TRANSMISSIONS.has(mapped)) return mapped;
  return "";
}

function inferTransmissionFromVersion(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") return "";
  const version = versionOriginal.toUpperCase();
  for (const code of Object.keys(
    CHUBB_NORMALIZATION_DICTIONARY.transmission_normalization
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
  if (transmisionField) {
    const validPatterns = [
      "AUTO",
      "AUTOMATIC",
      "AUTOMATICA",
      "AUTOMATICO",
      "MANUAL",
      "STD",
      "CVT",
      "DSG",
      "TIPTRONIC",
      "AUT",
      "MAN",
      "MT",
      "AT",
    ];
    for (const pattern of validPatterns) {
      if (transmisionField.includes(pattern)) {
        const normalized = normalizeTransmission(pattern);
        if (normalized) return normalized;
      }
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

function normalizeChubbData(records = []) {
  const results = [];
  const errors = [];

  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const batch = records.slice(i, i + BATCH_SIZE);
    for (const record of batch) {
      try {
        const processed = processChubbRecord(record);
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

function normalizeChubbRecords(items = []) {
  const rawRecords = items.map((item) =>
    item && item.json ? item.json : item
  );
  const { results, errors } = normalizeChubbData(rawRecords);
  const successItems = results.map((record) => ({ json: record }));
  const errorItems = errors.map((error) => ({ json: error }));
  return [...successItems, ...errorItems];
}

function processChubbRecord(record) {
  // Use new transmission recovery function
  const recoveredTransmission = recoverTransmission(record);
  if (!recoveredTransmission) {
    throw new Error(
      "TRANSMISSION_INFERENCE_FAILED: Cannot recover transmission"
    );
  }
  record.transmision = recoveredTransmission;

  // CHUBB-SPECIFIC FIXES - Apply BEFORE other normalization
  // Fix 1: BMW/MINI brand separation
  const brandFix = fixChubbMINIBrand(record.marca || "", record.modelo || "");
  record.marca = brandFix.marca;
  record.modelo = brandFix.modelo;

  // Fix 2: SDRIVE/XDRIVE removal from modelo to version
  const driveFix = cleanChubbDriveSuffix(
    record.marca || "",
    record.modelo || "",
    record.version_original || ""
  );
  record.modelo = driveFix.modelo;
  let versionForProcessing = driveFix.version;

  // Fix 3: Trim code spacing (e.g., "118 I" → "118I")
  record.modelo = fixChubbTrimSpacing(record.marca, record.modelo);

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
  let enhancedVersion = versionForProcessing;
  if (modeloSpecs.length > 0) {
    enhancedVersion = `${modeloSpecs.join(" ")} ${enhancedVersion}`.trim();
  }

  const { doors, occupants } = extractDoorsAndOccupants(enhancedVersion);

  const validation = validateRecord(record);
  if (!validation.isValid) {
    throw new Error(`Validation failed: ${validation.errors.join(", ")}`);
  }

  let versionLimpia = cleanVersionString(
    enhancedVersion,
    record.modelo || "",
    record.marca || ""
  );

  versionLimpia = versionLimpia
    .replace(/\b\d\s*P(?:TAS?|TS?|TA)?\.?\b/gi, " ")
    .replace(/\b\d+\s*PUERTAS?\b/gi, " ")
    .replace(/\b0?\d+\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX)\b/gi, " ")
    .replace(/\b0?\d+\s*(?:PASAJEROS?|PAS)\b/gi, " ")
    .replace(/\s+[.,](?=\s|$)/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  // FIX: Never let a bare number linger if used for doors (or if it's context-free noise)
  const tokens = versionLimpia.split(" ").filter(Boolean);
  const sanitizedTokens = [];

  tokens.forEach((token, idx, arr) => {
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

  const marcaConsolidada = consolidateBrand(normalizeText(record.marca));

  const normalized = {
    origen_aseguradora: "CHUBB",
    id_original: record.id_original,
    marca: marcaConsolidada,
    modelo: normalizeModelo(marcaConsolidada, record.modelo),
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

  // Issue #3: VOLKSWAGEN JETTA generation prefix removal
  if (marcaUpper === "VOLKSWAGEN") {
    normalized = normalized.replace(/\s*MK\s*VII?I?/gi, "");
    normalized = normalized.replace(/\s*MKVII?I?/gi, "");
    normalized = normalized.replace(/\s*GEN\.?\s*\d+/gi, "");
    normalized = normalized.replace(/\s*A[4-7]\b/gi, "");
  }

  // 1. Remove NUEVO/NUEVA/NEW prefix (ENHANCED - Requirement 4.1)
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

  // 2. Mazda-specific: Remove MAZDA/MA prefix (ENHANCED - Requirement 4.2)
  if (marcaUpper === "MAZDA") {
    normalized = normalized.replace(/^(MAZDA|MA)\s+/gi, "");
  }

  // 3. Mercedes-specific: Remove MERCEDES prefix and fix KLASSE (ENHANCED - Requirement 4.2)
  if (marcaUpper === "MERCEDES BENZ" || marcaUpper === "MERCEDES") {
    normalized = normalized.replace(/^MERCEDES\s+(BENZ\s+)?/gi, "");
    normalized = normalized.replace(/\bKLASSE\b/gi, "CLASE");
  }

  // 4. BMW-specific: SERIE prefix extraction (ENHANCED - Requirement 4.2)
  if (marcaUpper === "BMW" && /^SERIE\s+/.test(normalized)) {
    normalized = normalized.replace(/^SERIE\s+/, ""); // "SERIE X5" → "X5"
  }

  // 5. Remove trim level/generation from modelo (MK VII, GEN 4)
  normalized = normalized.replace(/\s+(MK\s*VII?I?|MKVII?I?|GEN\s*\d+)$/gi, "");

  // 6. Remove body type from modelo (SEDAN, SUV, etc.) (Requirement 4.3)
  normalized = normalized.replace(
    /\s+(SEDAN|HATCHBACK|SUV|COUPE|CONVERTIBLE|PICKUP|VAN|WAGON)$/gi,
    ""
  );

  // 7. Collapse spaces in letter+number models (A 3 → A3, E TRON → E-TRON)
  normalized = normalized.replace(/^([A-Z])\s+([A-Z0-9])/g, "$1$2");

  // 7b. E-TRON needs hyphen (special case)
  normalized = normalized.replace(/\bETRON\b/g, "E-TRON");

  // Remove single letter trim codes (e.g., "C 1500" → "1500", "M 350" → "350")
  // Only when followed by numbers to preserve legitimate model codes
  normalized = normalized.replace(/\s+([A-Z])\s+(\d)/g, " $2");

  // Remove cab type and configuration codes from middle (Requirement 4.4)
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

  // Trailing single-letter trim codes: Remove trailing I/A suffixes (e.g., "SERIE 1 I" → "SERIE 1")
  normalized = normalized.replace(/\s+[IA]+$/gi, "");

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

const outputItems = normalizeChubbRecords(items);
return outputItems;
