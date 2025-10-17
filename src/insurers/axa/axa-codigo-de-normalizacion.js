/**
 * AXA ETL - Normalization Code Node
 *
 * Mirrors the insurer normalization pipeline used for Zurich/Qualitas/Chubb.
 * Intended for execution inside an n8n Code node: it cleans AXA vehicle
 * records, infers transmissions when missing, and outputs normalized objects
 * ready for Supabase ingestion.
 */

const crypto = require("crypto");

const AXA_NORMALIZATION_DICTIONARY = {
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
    "PIEL",
    "GAMUZA",
    "TELA",
    "ALCANTARA",
    "CUERO",
    "XENON",
    "LED",
    "BI-XENON",
    "CA",
    "C/A",
    "A/C",
    "AC",
    "CE",
    "SQ",
    "CB",
    "SIS/NAV",
    "SIS.NAV.",
    "NAV",
    "NAVEG",
    "NAVEGACION",
    "NAVEGADOR",
    "T.S",
    "T.P.",
    "FBX",
    "CAM TRAS",
    "TBO",
    "SENSOR",
    "CAMARA",
    "FRENOS CERAM",
    "FRENOS CERAMICA",
    "COMFORT",
    "CONFORT",
    "STD",
    "STD.",
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
    "MANUAL",
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
    1: "MANUAL",
    2: "AUTO",
    1: "MANUAL",
    2: "AUTO",
    STD: "MANUAL",
    "STD.": "MANUAL",
    MANUAL: "MANUAL",
    "M/T": "MANUAL",
    MT: "MANUAL",
    MEC: "MANUAL",
    MECANICA: "MANUAL",
    SECUENCIAL: "MANUAL",
    DRIVELOGIC: "MANUAL",
    DUALOGIC: "MANUAL",
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
    "R TRONIC": "AUTO",
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
    year_codes: /\b(19\d{2}|20\d{2})\b/g,
    multiple_spaces: /\s+/g,
    trim_spaces: /^\s+|\s+$/g,
  },
};

const AXA_BRAND_ALIASES = {
  IZSUZU: "ISUZU",
  "MERCEDES-BENZ": "MERCEDES BENZ",
  MINI: "BMW",
  "BMW MINI": "BMW",
  "MINI COOPER": "BMW",
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

const NUMERIC_TRANSMISSION_MAP = {
  0: "",
  1: "MANUAL",
  2: "AUTO",
  0: "",
  1: "MANUAL",
  2: "AUTO",
};

const NORMALIZED_TRANSMISSIONS = new Set(["AUTO", "MANUAL"]);
const RESIDUAL_SINGLE_TOKENS = new Set(["A", "B", "C", "E", "Q"]);

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

const LEGITIMATE_TRIM_TOKENS = new Set([
  "TECH",
  "ADVANCE",
  "BASE",
  "LUXURY",
  "PREMIUM",
  "SPORT",
  "ELEGANCE",
  "EXCLUSIVE",
  "LIMITED",
  "EDITION",
  "SPECIAL",
  "ANNIVERSARY",
  "GT",
  "GTS",
  "RS",
  "AMG",
  "M",
  "S",
  "SL",
  "SLK",
  "SLS",
]);

const ENGINE_ALIAS_PATTERNS = [
  { regex: /\bT[\s-]?FSI\b/gi, replacement: "TURBO" },
  { regex: /\bT[\s-]?SI\b/gi, replacement: "TURBO" },
  { regex: /\bFSI\s*TURBO\b/gi, replacement: "TURBO" },
  { regex: /\bFSI\b/gi, replacement: "FSI" },
  { regex: /\bGDI\b/gi, replacement: "GDI" },
];

function escapeRegex(text = "") {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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

function normalizeCylinders(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  let normalized = versionString;
  Object.entries(AXA_NORMALIZATION_DICTIONARY.cylinder_normalization).forEach(
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

function normalizeDrivetrain(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString
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

function normalizeEngineDisplacement(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString
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

function collapseDisplacementArtifacts(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b(\d+CIL)\.0(?:\.0L)?\b/g, "$1")
    .replace(/\b(\d+CIL)\s+0\.0L\b/g, "$1")
    .replace(/\b(\d+(?:\.\d+)L)(?:\s*\1)+\b/g, "$1")
    .replace(/\b(\d+(?:\.\d+)L)L\b/g, "$1");
}

function applyEngineAliases(value = "") {
  if (!value || typeof value !== "string") return "";
  let output = value;
  ENGINE_ALIAS_PATTERNS.forEach(({ regex, replacement }) => {
    output = output.replace(regex, replacement);
  });
  return output;
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

function cleanAxaModel(rawModel = "", marca = "") {
  const normalizedModel = normalizeText(rawModel);
  if (!normalizedModel) {
    return { model: "", extras: "" };
  }

  let cleaned = normalizedModel;
  const extras = [];
  const normalizedMarca = marca ? marca.toUpperCase() : "";
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
    .replace(/\bPASAJEROS?\b/g, " ");

  cleaned = cleaned
    .replace(/\bGENERACION\b/g, "GEN")
    .replace(/\bGEN\.?\b/g, "GEN");

  if (/\bJETTA\b/.test(cleaned)) {
    const tokens = cleaned.split(/\s+/).filter(Boolean);
    const residualTokens = tokens.filter((token) => token !== "JETTA");
    if (residualTokens.length) {
      extras.push(residualTokens.join(" "));
    }
    cleaned = "JETTA";
  }

  if (
    (normalizedMarca === "BMW" || normalizedMarca === "MINI") &&
    (/\bMINI\b/.test(cleaned) || /\bCOOPER\b/.test(cleaned))
  ) {
    cleaned = "MINI COOPER";
  }

  if (normalizedMarca === "FORD") {
    cleaned = cleaned.replace(/[-.]/g, " ");
    cleaned = cleaned.replace(
      /\b([A-Z])\s*(\d{2,4})\b/g,
      (_match, prefix, digits) => `${prefix}${digits}`
    );
  }

  // Normalize T CROSS to T-CROSS for Volkswagen
  if (normalizedMarca === "VOLKSWAGEN" || normalizedMarca === "VW") {
    cleaned = cleaned.replace(/\bT\s+CROSS\b/g, "T-CROSS");
  }

  cleaned = cleaned.replace(/\s+/g, " ").trim();

  return {
    model: cleaned,
    extras: extras.filter(Boolean).join(" "),
  };
}

function cleanVersionString(versionString = "", model = "", marca = "") {
  if (!versionString || typeof versionString !== "string") return "";

  let cleaned = versionString.toUpperCase().trim();
  cleaned = applyProtectedTokens(cleaned);
  cleaned = cleaned.replace(/[\/,]/g, " ");
  cleaned = cleaned.replace(/-/g, " ");
  cleaned = cleaned.replace(/AUT(?=[A-Z0-9])(?!O)/g, "AUT ");
  cleaned = cleaned.replace(/([A-Z0-9])AUT\b/g, "$1 AUT");

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
  cleaned = cleaned.replace(/\bGENERACION\b/g, "GEN");
  cleaned = cleaned.replace(/\bGEN\.?\b/g, "GEN");
  // Convert P → PUERTAS before removal
  cleaned = cleaned.replace(/\b(\d+)\s*P\b(?!\s*UERTAS)/gi, "$1PUERTAS");

  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)\s*CP\b/g, "$1HP");
  cleaned = cleaned.replace(/\b(\d+)\s*CC\b/g, "$1CC");
  cleaned = cleaned.replace(/\b(\d+\.\d+)I\b/g, "$1L");

  AXA_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach((spec) => {
    const regex = new RegExp(`\\b${escapeRegex(spec)}\\b`, "gi");
    cleaned = cleaned.replace(regex, " ");
  });

  if (model) {
    cleaned = cleaned.replace(
      new RegExp(`\\b${escapeRegex(model.toUpperCase())}\\b`, "gi"),
      " "
    );
  }

  if (marca) {
    const normalizedMarca = marca.toUpperCase();
    const variants = [
      normalizedMarca,
      normalizedMarca.replace(/\s+/g, ""),
      normalizedMarca.split(" ")[0],
    ].filter(Boolean);
    variants.forEach((variant) => {
      cleaned = cleaned.replace(
        new RegExp(`\\b${escapeRegex(variant)}\\b`, "gi"),
        " "
      );
    });
  }

  cleaned = cleaned
    .replace(/\bHBK\b/g, "HATCHBACK")
    .replace(/\bHB\b/g, "HATCHBACK")
    .replace(/\bTUR\b/g, "TURBO")
    .replace(/\bCONV\b/g, "CONVERTIBLE")
    .replace(/\bCP\b/g, "COUPE")
    .replace(/\bPICK\s*UP\b/g, "PICKUP");

  cleaned = cleaned
    .replace(/\b\d+\s*PUERTAS?\b/gi, " ")
    .replace(/\bPUERTAS?\b/gi, " ")
    .replace(/\b0?\d+\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX)\b/gi, " ")
    .replace(/\b0?\d+\s*(?:PASAJEROS?|PAS)\b/gi, " ");

  const { year_codes, multiple_spaces, trim_spaces } =
    AXA_NORMALIZATION_DICTIONARY.regex_patterns;
  cleaned = cleaned.replace(year_codes, " ");
  cleaned = cleaned.replace(/(?<!\d)[.,](?!\d)/g, " ");
  cleaned = cleaned.replace(/\bL\b/g, " ");

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
    AXA_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] ||
    normalized;
  if (NORMALIZED_TRANSMISSIONS.has(mapped)) return mapped;
  return "";
}

function inferTransmissionFromVersion(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") return "";
  const version = versionOriginal.toUpperCase();
  for (const code of Object.keys(
    AXA_NORMALIZATION_DICTIONARY.transmission_normalization
  )) {
    if (!code) continue;
    const regex = new RegExp(`\\b${escapeRegex(code)}\\b`, "i");
    if (regex.test(version)) {
      const normalized = normalizeTransmission(code);
      if (normalized) return normalized;
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

const BATCH_SIZE = 5000;

function normalizeAxaData(records = []) {
  const results = [];
  const errors = [];
  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const batch = records.slice(i, i + BATCH_SIZE);
    for (const record of batch) {
      try {
        const processed = processAxaRecord(record);
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

function normalizeAxaRecords(items = []) {
  const rawRecords = items.map((item) =>
    item && item.json ? item.json : item
  );
  const { results, errors } = normalizeAxaData(rawRecords);
  const successItems = results.map((record) => ({ json: record }));
  const errorItems = errors.map((error) => ({ json: error }));
  return [...successItems, ...errorItems];
}

function processAxaRecord(record) {
  const isActive = normalizeActiveFlag(record.activo);
  if (isActive === false) {
    throw new Error("Validation failed: registro inactivo");
  }

  const marcaNormalizada = normalizeMarca(record.marca);
  const { model: modeloNormalizado, extras: modeloExtras } = cleanAxaModel(
    record.modelo,
    marcaNormalizada
  );
  const modeloFinal = modeloNormalizado || normalizeText(record.modelo);

  const derivedTransmission =
    normalizeTransmission(record.transmision) ||
    normalizeTransmission(record.transmision_codigo) ||
    inferTransmissionFromVersion(record.version_original || "");
  record.transmision = derivedTransmission;

  const { doors, occupants } = extractDoorsAndOccupants(
    record.version_original || ""
  );

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
    ? `${modeloExtras} ${record.version_original || ""}`.trim()
    : record.version_original || "";

  let versionLimpia = cleanVersionString(
    versionSeed,
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
  const sanitizedTokens = [];

  tokens.forEach((token, idx, arr) => {
    if (!token) return;
    if (/^[.,]$/.test(token)) return;

    if (/^\d+$/.test(token)) {
      const next = (arr[idx + 1] || "").toUpperCase();
      const prev = (arr[idx - 1] || "").toUpperCase();

      // Preserve numbers followed by anniversary/edition context
      if (/^(AÑOS|ANIVERSARIO|ANNIVERSARY|TH|EDITION|EDICION)$/i.test(next)) {
        sanitizedTokens.push(token);
        return;
      }

      // Preserve numbers in other valid contexts
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
    if (upperToken.length === 1 && RESIDUAL_SINGLE_TOKENS.has(upperToken))
      return;

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

  const normalized = {
    origen_aseguradora: "AXA",
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

function normalizeActiveFlag(value) {
  if (value === undefined || value === null) return true;
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value === 1;
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["true", "1", "t", "activo", "si", "s�"].includes(normalized))
      return true;
    if (["false", "0", "f", "inactivo", "no"].includes(normalized))
      return false;
  }
  return true;
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

  // 1. Remove NUEVO/NUEVA/NEW prefix (already covered in cleanAxaModel, but ensuring consistency)
  normalized = normalized.replace(/^(NUEVO|NUEVA|NEW)\s+/gi, "");

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
  if (!record.marca || record.marca.toString().trim() === "")
    errors.push("marca is required");
  if (!record.modelo || record.modelo.toString().trim() === "")
    errors.push("modelo is required");
  if (!record.anio || record.anio < 2000 || record.anio > 2030)
    errors.push("anio must be between 2000-2030");
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
  return AXA_BRAND_ALIASES[normalized] || normalized;
}

function normalizeText(value) {
  return value ? value.toString().trim().toUpperCase() : "";
}

function categorizeError(error) {
  const message = (error.message || "").toLowerCase();
  if (message.includes("validation")) return "VALIDATION_ERROR";
  if (message.includes("hash")) return "HASH_GENERATION_ERROR";
  return "NORMALIZATION_ERROR";
}

const outputItems = normalizeAxaRecords(items);
return outputItems;
