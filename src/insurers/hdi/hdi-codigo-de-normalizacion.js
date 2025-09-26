/**
 * HDI ETL - Normalization Code Node
 *
 * Harmonizes HDI records with the shared homologation contract.
 * - Canonicalizes AUTO/MANUAL transmissions (numeric + textual) and strips aliases from trims.
 * - Normalizes drivetrain, engine specs, comfort tokens (COMFORT/CONFORT), and compact turbo/ton strings.
 * - Preserves trim tokens while removing door/occupant noise via numeric-context guards.
 */
const crypto = require("crypto");

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
};

const HDI_NORMALIZATION_DICTIONARY = {
  irrelevant_comfort_audio: [
    "ABS",
    "CA",
    "AC",
    "CE",
    "CD",
    "CB",
    "CQ",
    "SQ",
    "EQ",
    "A/A",
    "A A",
    "E/E",
    "E E",
    "AA",
    "EE",
    "B/A",
    "B A",
    "Q/C",
    "Q C",
    "QC",
    "BA",
    "PIEL",
    "TELA",
    "VINIL",
    "ALUMINIO",
    "ALARM",
    "ALARMA",
    "RADIO",
    "STEREO",
    "MP3",
    "DVD",
    "GPS",
    "BT",
    "USB",
    "NAV",
    "NAVI",
    "CAM",
    "CAMARA",
    "CAM TRAS",
    "SENSOR",
    "SENSORES",
    "PARK",
    "PARKTRONIC",
    "CLIMA",
    "CLIMATRONIC",
    "D/T",
    "D T",
    "D/V",
    "D V",
    "DIS",
    "PADDLE",
    "KEYLESS",
    "PUSH",
    "START",
    "BOTON",
    "ENCENDIDO",
    "VE",
    "V.E.",
    "C/A",
    "S/D",
    "COMFORT",
    "CONFORT",
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
    .replace(/\b(\d)(\d)L\b/g, "$1.$2L")
    .replace(/\b(?<!\d\.)\d+L\b/g, (match) => `${match.slice(0, -1)}.0L`)
    .replace(/\b(?<!\d\.)\d+\s+L\b/g, (match) => {
      const digits = match.match(/\d+/)[0];
      return `${digits}.0L`;
    });
}

function normalizeStandaloneLiters(value = "") {
  if (!value || typeof value !== "string") return "";
  return value.replace(/\b(\d+\.\d+)(?!L\b)(?!\d)(?![A-Z])/g, (match) => {
    const liters = parseFloat(match);
    if (!Number.isFinite(liters) || liters <= 0 || liters > 12) return match;
    return `${match}L`;
  });
}

function normalizeHorsepower(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b(\d+)\s*C\.P\.?\b/gi, "$1HP")
    .replace(/\b(\d+)\s*CP\b/gi, "$1HP")
    .replace(/\b(\d+)\s*H\.P\.?\b/gi, "$1HP")
    .replace(/\b(\d+)\s*HP\b/gi, "$1HP");
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
  return value.replace(/\b(\d+(?:\.\d+)?)\s*TON\b/gi, (_, ton) => `${ton}TON`);
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

function cleanVersionString(versionString = "", brand = "", model = "") {
  if (!versionString || typeof versionString !== "string") return "";

  let cleaned = versionString
    .toString()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/"/g, " ")
    .trim();

  cleaned = applyProtectedTokens(cleaned);
  cleaned = cleaned.replace(
    HDI_NORMALIZATION_DICTIONARY.regex_patterns.decimal_comma,
    "$1.$2"
  );
  cleaned = cleaned.replace(/[\\/]/g, " ");
  cleaned = cleaned.replace(/\s*&\s*/g, " ");
  cleaned = cleaned.replace(/-/g, " ");
  cleaned = cleaned.replace(/(\d)([A-Z])/g, "$1 $2");
  cleaned = cleaned.replace(/([A-Z])(\d)/g, "$1 $2");
  cleaned = cleaned.replace(
    /\b([A-Z0-9]+)(AUT|MAN|STD|CVT|DSG|DCT|IVT|TIPTRONIC)\b/g,
    "$1 $2"
  );
  cleaned = cleaned.replace(/\bHB\b/g, "HATCHBACK");
  cleaned = cleaned.replace(/\b(V|L|R|H|I|B)\s+(\d{1,2})\b/g, "$1$2");
  cleaned = cleaned.replace(/\b(\d{1,2})\s+CIL\b/g, "$1CIL");
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)\s+L\b/g, "$1L");

  cleaned = normalizeTonCapacity(cleaned);
  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeCylinders(cleaned);
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);
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

  if (brand) {
    const normalizedBrand = normalizeBrand(brand);
    const variants = [
      normalizedBrand,
      normalizedBrand.replace(/\s+/g, ""),
      normalizedBrand.split(" ")[0],
    ].filter(Boolean);
    variants.forEach((variant) => {
      cleaned = cleaned.replace(
        new RegExp(`\\b${escapeRegExp(variant)}\\b`, "gi"),
        " "
      );
    });
  }

  if (model) {
    const normalizedModel = normalizeText(model);
    if (normalizedModel) {
      cleaned = cleaned.replace(
        new RegExp(`\\b${escapeRegExp(normalizedModel)}\\b`, "gi"),
        " "
      );
    }
  }

  cleaned = cleaned.replace(
    HDI_NORMALIZATION_DICTIONARY.regex_patterns.stray_punctuation,
    " "
  );
  cleaned = restoreProtectedTokens(cleaned);
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

  const doorsMatch = normalized.match(
    /\b(\d)\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/
  );
  const occMatch = normalized.match(
    /\b0?(\d+)\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX|PASAJEROS?|PAS)\b/
  );

  return {
    doors: doorsMatch ? `${parseInt(doorsMatch[1], 10)}PUERTAS` : "",
    occupants: occMatch ? `${parseInt(occMatch[1], 10)}OCUP` : "",
  };
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

function dedupeTokens(tokens = []) {
  const seen = new Set();
  const result = [];
  tokens.forEach((token) => {
    const normalized = token.trim();
    if (!normalized) return;
    if (seen.has(normalized)) return;
    seen.add(normalized);
    result.push(normalized);
  });
  return result;
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

function createCommercialHash(vehicle) {
  const key = [
    vehicle.marca || "",
    vehicle.modelo || "",
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
  const modeloNormalizado = normalizeText(record.modelo || "");

  const { doors, occupants } = extractDoorsAndOccupants(versionOriginal);

  const validation = validateRecord({
    ...record,
    marca: marcaNormalizada,
    modelo: modeloNormalizado,
    transmision: record.transmision,
  });
  if (!validation.isValid) {
    throw new Error(`Validation failed: ${validation.errors.join(", ")}`);
  }

  let versionLimpia = cleanVersionString(
    versionOriginal,
    marcaNormalizada,
    modeloNormalizado
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
  let fallbackDoors = "";

  tokens.forEach((token, idx, arr) => {
    if (!token) return;
    if (/^[.,]$/.test(token)) return;
    if (/^\d+$/.test(token)) {
      if (!doors && !fallbackDoors) {
        const numericValue = parseInt(token, 10);
        if (Number.isFinite(numericValue) && numericValue > 0) {
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
    if (upperToken.length === 1 && RESIDUAL_SINGLE_TOKENS.has(upperToken)) {
      return;
    }
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

  if (!versionLimpia) {
    throw new Error("Normalization produced empty version_limpia");
  }

  const normalized = {
    origen_aseguradora: "HDI",
    id_original: record.id_original,
    marca: marcaNormalizada,
    modelo: modeloNormalizado,
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
