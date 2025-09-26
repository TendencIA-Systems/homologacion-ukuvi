/**
 * MAPFRE ETL - Normalization Code Node
 *
 * Mirrors the Zurich/Qualitas/Atlas pattern while handling MAPFRE's comma-separated specs:
 * - Splits `version_original` slots (trim, engine config, displacement, horsepower, doors, transmission, extras).
 * - Infers transmission codes (AUT, STD, CVT, DSG, etc.) when the `transmision` field is empty.
 * - Preserves hyphenated trims (A-SPEC, S-LINE, TYPE-S) before cleaning and restores them afterward.
 * - Normalizes compact engine tokens such as `1.0T` -> `1.0L TURBO` and converts horsepower/door counts.
 * - Strips comfort/audio tokens while keeping the commercial hash inputs and a clean `version_limpia`.
 *
 * Use inside an n8n Code node. Emits a flat array of `{ json }`; validation issues
 * appear with `{ error: true }` so downstream nodes can log or branch.
 */
const crypto = require("crypto");

const BATCH_SIZE = 5000;

const MAPFRE_NORMALIZATION_DICTIONARY = {
  brand_aliases: {
    "GENERAL MOTORS": "GMC",
    "GENERAL MOTORS 2": "GMC",
    "GENERAL MOTORS COMPANY": "GMC",
    "GENERAL MOTORS CORPORATION": "GMC",
    GMC: "GMC",
    "JAC SEI": "JAC",
    "MG ROVER": "MG",
  },
  irrelevant_comfort_audio: [
    "ABS",
    "CA",
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
    "TM",
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
  ],
  transmission_tokens_to_strip: [
    "AUT",
    "AUT.",
    "AUTO",
    "AT",
    "AT.",
    "TA",
    "AUTOMATICO",
    "AUTOMATICA",
    "AUTOMATIC",
    "AUTOMATIZADO",
    "AUTOMATIZADA",
    "TIPTRONIC",
    "STEPTRONIC",
    "GEARTRONIC",
    "MULTITRONIC",
    "SPORTSHIFT",
    "S-TRONIC",
    "S TRONIC",
    "STRONIC",
    "Q-TRONIC",
    "Q TRONIC",
    "CVT",
    "DSG",
    "DCT",
    "IVT",
    "SECUENCIAL",
    "SECUENCIAL.",
    "SELESPEED",
    "POWERSHIFT",
    "TORQUEFLITE",
    "MANUAL",
    "MAN",
    "MAN.",
    "STD",
    "STD.",
    "MECANICO",
    "MECANICA",
    "MECA",
    "MECHANICO",
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
    "3V": "3CIL",
    "4V": "4CIL",
    "5V": "5CIL",
    "6V": "6CIL",
    "8V": "8CIL",
  },
  transmission_normalization: {
    STD: "MANUAL",
    "STD.": "MANUAL",
    MANUAL: "MANUAL",
    MAN: "MANUAL",
    "MAN.": "MANUAL",
    MECA: "MANUAL",
    MECANICO: "MANUAL",
    MECANICA: "MANUAL",
    MECHANICO: "MANUAL",
    SECUENCIAL: "MANUAL",
    "SECUENCIAL.": "MANUAL",
    DRIVELOGIC: "MANUAL",
    DUALOGIC: "MANUAL",
    AUT: "AUTO",
    "AUT.": "AUTO",
    AUTO: "AUTO",
    AT: "AUTO",
    "AT.": "AUTO",
    AUTOMATICO: "AUTO",
    AUTOMATICA: "AUTO",
    AUTOMATIC: "AUTO",
    AUTOMATIZADO: "AUTO",
    AUTOMATIZADA: "AUTO",
    CVT: "AUTO",
    DSG: "AUTO",
    "S TRONIC": "AUTO",
    "S-TRONIC": "AUTO",
    STRONIC: "AUTO",
    TIPTRONIC: "AUTO",
    STEPTRONIC: "AUTO",
    SELESPEED: "AUTO",
    "Q-TRONIC": "AUTO",
    "Q TRONIC": "AUTO",
    DCT: "AUTO",
    MULTITRONIC: "AUTO",
    GEARTRONIC: "AUTO",
    SPEEDSHIFT: "AUTO",
    SPORTSHIFT: "AUTO",
    POWERSHIFT: "AUTO",
    TORQUEFLITE: "AUTO",
    IVT: "AUTO",
  },
  regex_patterns: {
    decimal_comma: /(\d),(\d)/g,
    multiple_spaces: /\s+/g,
    trim_spaces: /^\s+|\s+$/g,
    stray_punctuation: /(?<!\d)[\.,;]|[\.,;](?!\d)/g,
  },
};
const SPECIAL_TRIM_NORMALIZATIONS = [
  { regex: /\bA[\s-]?SPECH\b/gi, replacement: "A-SPEC" },
];

const PROTECTED_HYPHEN_TOKENS = [
  {
    regex: /\bA[\s-]?SPEC\b/gi,
    placeholder: "__MAPFRE_PROTECTED_A_SPEC__",
    canonical: "A-SPEC",
  },
  {
    regex: /\bTYPE[\s-]?S\b/gi,
    placeholder: "__MAPFRE_PROTECTED_TYPE_S__",
    canonical: "TYPE-S",
  },
  {
    regex: /\bTYPE[\s-]?R\b/gi,
    placeholder: "__MAPFRE_PROTECTED_TYPE_R__",
    canonical: "TYPE-R",
  },
  {
    regex: /\bTYPE[\s-]?F\b/gi,
    placeholder: "__MAPFRE_PROTECTED_TYPE_F__",
    canonical: "TYPE-F",
  },
  {
    regex: /\bS[\s-]?LINE\b/gi,
    placeholder: "__MAPFRE_PROTECTED_S_LINE__",
    canonical: "S-LINE",
  },
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

const TRANSMISSION_TOKENS = new Set(
  Object.keys(MAPFRE_NORMALIZATION_DICTIONARY.transmission_normalization)
);

function parseMapfreVersionSegments(versionOriginal = "") {
  const info = {
    trimSegment: "",
    engineSegment: "",
    displacementSegment: "",
    horsepowerSegment: "",
    doorsSegment: "",
    transmissionSegment: "",
    extras: [],
    rawSegments: [],
    normalizedSegments: [],
    orderedSegments: [],
  };

  if (!versionOriginal || typeof versionOriginal !== "string") {
    return info;
  }

  const segments = versionOriginal
    .split(",")
    .map((segment) => segment.trim())
    .filter(Boolean);

  if (segments.length === 0) {
    return info;
  }

  info.rawSegments = segments.slice();

  const transmissionTokens = Array.from(TRANSMISSION_TOKENS);

  segments.forEach((segment, index) => {
    const normalizedSegment = segment
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toUpperCase()
      .replace(/\s+/g, " ")
      .trim();

    if (!normalizedSegment) {
      return;
    }

    info.normalizedSegments.push(normalizedSegment);

    const looksLikeEngineConfig = /\b(?:L|V|I|R|H|B)\d{1,2}\b/.test(
      normalizedSegment
    );
    if (!info.engineSegment && looksLikeEngineConfig) {
      info.engineSegment = normalizedSegment;
      return;
    }

    const looksLikeDisplacement = /\b\d+(?:\.\d+)?\s*(?:L|T)\b/.test(
      normalizedSegment
    );
    if (!info.displacementSegment && looksLikeDisplacement) {
      info.displacementSegment = normalizedSegment;
      return;
    }

    const looksLikeHorsepower = /\b\d+\s*(?:CP|HP|C\.P\.|H\.P\.)\b/.test(
      normalizedSegment
    );
    if (!info.horsepowerSegment && looksLikeHorsepower) {
      info.horsepowerSegment = normalizedSegment;
      return;
    }

    const looksLikeDoors = /\b\d+\s*PUERTAS?\b/.test(normalizedSegment);
    if (!info.doorsSegment && looksLikeDoors) {
      info.doorsSegment = normalizedSegment;
      return;
    }

    if (!info.transmissionSegment) {
      for (const token of transmissionTokens) {
        if (normalizedSegment === token || normalizedSegment.includes(token)) {
          info.transmissionSegment = normalizedSegment;
          return;
        }
      }
    }

    if (!info.trimSegment && index === 0) {
      info.trimSegment = normalizedSegment;
      return;
    }

    info.extras.push(normalizedSegment);
  });

  if (!info.trimSegment && info.normalizedSegments.length) {
    info.trimSegment = info.normalizedSegments[0];
  }

  info.orderedSegments = [
    info.trimSegment,
    info.engineSegment,
    info.displacementSegment,
    info.horsepowerSegment,
    info.doorsSegment,
    info.transmissionSegment,
    ...info.extras,
  ].filter(Boolean);

  return info;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function normalizeDrivetrain(versionString = "") {
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

function normalizeCylinders(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  let normalized = versionString;
  normalized = normalized
    .replace(/\b(3|4|5|6|8)\s*V\b/g, "$1CIL")
    .replace(/\b(3|4|5|6|8)V\b/g, "$1CIL")
    .replace(/\b(\d{1,2})\s*CIL(?:INDROS)?\b/g, "$1CIL")
    .replace(/\b(\d{1,2})\s*CYL\b/g, "$1CIL");

  Object.entries(
    MAPFRE_NORMALIZATION_DICTIONARY.cylinder_normalization
  ).forEach(([from, to]) => {
    const regex = new RegExp(`\b${escapeRegExp(from)}\b`, "gi");
    normalized = normalized.replace(regex, to);
  });
  return normalized;
}

function normalizeEngineDisplacement(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString
    .replace(/\b(\d)(\d)L\b/g, "$1.$2L")
    .replace(/\b(?<!\d\.)\d+L\b/g, (match) => `${match.slice(0, -1)}.0L`)
    .replace(/\b(?<!\d\.)\d+\s+L\b/g, (match) => {
      const digits = match.match(/\d+/)[0];
      return `${digits}.0L`;
    });
}

function normalizeStandaloneLiters(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString.replace(
    /\b(\d+\.\d+)(?!L\b)(?!\d)(?![A-Z])/g,
    (match) => {
      const liters = parseFloat(match);
      if (!Number.isFinite(liters) || liters <= 0 || liters > 10) return match;
      return `${match}L`;
    }
  );
}

function normalizeHorsepower(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString
    .replace(/\b(\d+)\s*C\.P\.?\b/g, "$1HP")
    .replace(/\b(\d+)\s*CP\b/g, "$1HP")
    .replace(/\b(\d+)\s*H\.P\.?\b/g, "$1HP")
    .replace(/\b(\d+)\s*HP\b/g, "$1HP");
}

function normalizeTurboTokens(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString
    .replace(/\bTBO\b/g, "TURBO")
    .replace(/\bBI[-\s]?TURBO\b/g, "BITURBO")
    .replace(/\bTWIN[-\s]?TURBO\b/g, "TWIN TURBO")
    .replace(/\bT\/T\b/g, "TWIN TURBO");
}

function normalizeTurboSuffix(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString
    .replace(/\b(\d+\.\d+)T\b/g, "$1L TURBO")
    .replace(/\b(\d+\.\d+)\s*T\b/g, "$1L TURBO");
}

function normalizeTonCapacity(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString.replace(
    /\b(\d+(?:\.\d+)?)\s*TON\b/g,
    (_, value) => `${value}TON`
  );
}

function stripLeadingPhrases(text, phrases = []) {
  let cleaned = text.trim();
  phrases.forEach((phrase) => {
    if (!phrase) return;
    const normalized = phrase
      .toString()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toUpperCase()
      .replace(/\s+/g, " ")
      .trim();
    if (!normalized) return;
    const variations = [normalized, normalized.replace(/\s+/g, "")];
    let changed = true;
    while (changed && cleaned) {
      changed = false;
      for (const variant of variations) {
        if (!variant) continue;
        if (cleaned === variant) {
          cleaned = "";
          changed = true;
        } else if (cleaned.startsWith(`${variant} `)) {
          cleaned = cleaned.slice(variant.length).trimStart();
          changed = true;
        }
      }
    }
  });
  return cleaned.trim();
}

function normalizeBrand(value = "") {
  if (!value) return "";
  const normalized = value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toUpperCase();
  const mapped = MAPFRE_NORMALIZATION_DICTIONARY.brand_aliases[normalized];
  return (mapped || normalized).trim();
}

function normalizeText(value) {
  return value
    ? value
        .toString()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .trim()
        .toUpperCase()
    : "";
}

function cleanVersionString(versionString, marca = "", modelo = "") {
  if (!versionString || typeof versionString !== "string") return "";

  let cleaned = versionString
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/"/g, " ")
    .trim();

  SPECIAL_TRIM_NORMALIZATIONS.forEach(({ regex, replacement }) => {
    cleaned = cleaned.replace(regex, replacement);
  });

  cleaned = applyProtectedTokens(cleaned);
  cleaned = applyProtectedTokens(cleaned);

  cleaned = cleaned.replace(
    MAPFRE_NORMALIZATION_DICTIONARY.regex_patterns.decimal_comma,
    "$1.$2"
  );
  cleaned = stripLeadingPhrases(cleaned, [marca, modelo]);

  cleaned = cleaned.replace(/[,/]/g, " ");
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

  MAPFRE_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach((token) => {
    const regex = new RegExp(`\\b${escapeRegExp(token)}\\b`, "g");
    cleaned = cleaned.replace(regex, " ");
  });

  MAPFRE_NORMALIZATION_DICTIONARY.transmission_tokens_to_strip.forEach(
    (token) => {
      const regex = new RegExp(`\\b${escapeRegExp(token)}\\b`, "g");
      cleaned = cleaned.replace(regex, " ");
    }
  );

  cleaned = cleaned.replace(/\s*\/\s*/g, " ");
  cleaned = cleaned.replace(
    MAPFRE_NORMALIZATION_DICTIONARY.regex_patterns.stray_punctuation,
    " "
  );
  cleaned = cleaned.replace(
    MAPFRE_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces,
    " "
  );
  cleaned = cleaned.replace(
    MAPFRE_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces,
    ""
  );
  cleaned = restoreProtectedTokens(cleaned);

  return cleaned;
}

// --- NUEVO: limpieza espec�fica de la columna MODELO ---
function cleanModeloString(modelo = "", marca = "", versionOriginal = "") {
  let base = normalizeText(modelo);
  const marcaNorm = normalizeBrand(marca);

  base = applyProtectedTokens(base);
  base = base.replace(/[,/]/g, " ").replace(/\s+/g, " ").trim();

  // 1) quitar la marca al inicio
  base = stripLeadingPhrases(base, [marcaNorm]);

  // 2) quitar la versi�n al final (tal como viene en la fuente)
  let ver = normalizeText(versionOriginal);
  ver = applyProtectedTokens(ver)
    .replace(/[,/]/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (ver) {
    if (base.endsWith(ver)) {
      base = base.slice(0, base.length - ver.length).trim();
    } else {
      // intento token a token desde el final
      const vTokens = ver.split(" ").filter(Boolean);
      let bTokens = base.split(" ").filter(Boolean);
      if (vTokens.length && bTokens.length) {
        const vJoined = vTokens.join(" ");
        const bJoined = bTokens.join(" ");
        if (bJoined.endsWith(vJoined)) {
          bTokens = bTokens.slice(0, bTokens.length - vTokens.length);
        }
      }
      base = bTokens.join(" ").trim();
    }
  }

  base = restoreProtectedTokens(base);
  base = base
    .replace(
      MAPFRE_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces,
      " "
    )
    .replace(MAPFRE_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces, "");
  return base;
}
// --- FIN NUEVO ---

function extractDoorsAndOccupants(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") {
    return { doors: "", occupants: "" };
  }
  const normalized = versionOriginal
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/[,/]/g, " ");

  const doorsMatch = normalized.match(
    /\b(\d)\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/
  );
  const occMatch = normalized.match(/\b0?(\d{1,2})\s*OCUP\b/);

  const doors = doorsMatch ? `${doorsMatch[1]}PUERTAS` : "";
  const occupants =
    occMatch && !Number.isNaN(parseInt(occMatch[1], 10))
      ? `${parseInt(occMatch[1], 10)}OCUP`
      : "";

  return { doors, occupants };
}

function normalizeTransmission(transmissionCode) {
  if (!transmissionCode || typeof transmissionCode !== "string") return "";
  const normalized = transmissionCode
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .trim();
  return (
    MAPFRE_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] ||
    normalized
  );
}

function inferTransmissionFromVersion(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") return "";
  const normalized = versionOriginal
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
  for (const token of Object.keys(
    MAPFRE_NORMALIZATION_DICTIONARY.transmission_normalization
  )) {
    const regex = new RegExp(`\\b${escapeRegExp(token)}\\b`, "g");
    if (regex.test(normalized)) {
      return MAPFRE_NORMALIZATION_DICTIONARY.transmission_normalization[token];
    }
  }
  return "";
}

function dedupeTokens(value = "") {
  if (!value) return "";
  const tokens = value.split(" ").filter(Boolean);
  const seen = new Set();
  const deduped = [];
  tokens.forEach((token) => {
    const formatted = token.trim();
    if (!formatted) return;
    if (formatted.length === 1 && !/\d/.test(formatted)) return;
    if (!seen.has(formatted)) {
      seen.add(formatted);
      deduped.push(formatted);
    }
  });
  return deduped.join(" ");
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
  if (!record.transmision || record.transmision.toString().trim() === "") {
    errors.push("transmision is required");
  }

  return { isValid: errors.length === 0, errors };
}

function categorizeError(error) {
  const message = error.message.toLowerCase();
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

function processMapfreRecord(record) {
  const parsedSegments = parseMapfreVersionSegments(
    record.version_original || ""
  );

  const transmissionFromSegment =
    normalizeTransmission(parsedSegments.transmissionSegment || "") ||
    inferTransmissionFromVersion(parsedSegments.transmissionSegment || "");

  const derivedTransmission =
    normalizeTransmission(record.transmision) ||
    transmissionFromSegment ||
    inferTransmissionFromVersion(record.version_original);

  record.transmision = derivedTransmission;

  const marcaNormalizada = normalizeBrand(record.marca || "");
  const modeloNormalizado = cleanModeloString(
    record.modelo || "",
    marcaNormalizada,
    record.version_original || ""
  );

  const segmentDoorData = extractDoorsAndOccupants(
    parsedSegments.doorsSegment || ""
  );
  const fullDoorData = extractDoorsAndOccupants(record.version_original || "");
  const doors = segmentDoorData.doors || fullDoorData.doors;
  const occupants = segmentDoorData.occupants || fullDoorData.occupants;

  const validation = validateRecord({
    ...record,
    marca: marcaNormalizada,
    modelo: modeloNormalizado,
  });
  if (!validation.isValid) {
    throw new Error(`Validation failed: ${validation.errors.join(", ")}`);
  }

  const sourceForCleaning =
    parsedSegments.orderedSegments.length > 0
      ? parsedSegments.orderedSegments.join(", ")
      : record.version_original || "";

  let versionLimpia = cleanVersionString(
    sourceForCleaning,
    marcaNormalizada,
    modeloNormalizado
  );

  versionLimpia = versionLimpia
    .replace(/\b\d\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/gi, " ")
    .replace(/\b0?\d+\s*OCUP\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();

  versionLimpia = dedupeTokens(
    [versionLimpia, doors, occupants].filter(Boolean).join(" ").trim()
  );

  if (!versionLimpia) {
    throw new Error("Normalization produced empty version_limpia");
  }

  const normalized = {
    origen_aseguradora: "MAPFRE",
    id_original: record.id_original,
    marca: marcaNormalizada,
    modelo: modeloNormalizado,
    anio: record.anio,
    transmision: record.transmision,
    version_original: record.version_original,
    version_limpia: versionLimpia,
    fecha_procesamiento: new Date().toISOString(),
  };

  normalized.hash_comercial = createCommercialHash(normalized);
  return normalized;
}

function normalizeMapfreData(records = []) {
  const results = [];
  const errors = [];

  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const batch = records.slice(i, i + BATCH_SIZE);
    for (const record of batch) {
      try {
        const processed = processMapfreRecord(record);
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

function normalizeMapfreRecords(items = []) {
  const rawRecords = items.map((it) => (it && it.json ? it.json : it));
  const { results, errors } = normalizeMapfreData(rawRecords);
  const successItems = results.map((record) => ({ json: record }));
  const errorItems = errors.map((err) => ({ json: err }));
  return [...successItems, ...errorItems];
}

const outputItems = normalizeMapfreRecords(items);
return outputItems;
