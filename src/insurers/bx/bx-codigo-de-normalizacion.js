/**
 * BX ETL - Normalization Code Node
 *
 * Mirrors the Zurich/Qualitas/Chubb pipeline and covers BX quirks (comma‑separated
 * trims, OCUP. suffixes, drivetrain noise, etc.). It runs inside an n8n Code node
 * and emits `{ json }` objects—validation errors are returned alongside successes.
 */
const crypto = require("crypto");

const BATCH_SIZE = 5_000;

const BX_NORMALIZATION_DICTIONARY = {
  irrelevant_comfort_audio: [
    "AA",
    "A/A",
    "EE",
    "E/E",
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
    "BA",
    "ABS",
    "QC",
    "VP",
    "V/P",
    "PIEL",
    "GAMUZA",
    "TELA",
    "VINIL",
    "CA",
    "CE",
    "CLIMA",
    "SQ",
    "CB",
    "EQ",
    "SIS/NAV",
    "SIS.NAV.",
    "SIS.NAV",
    "NAV",
    "NAVI",
    "CAM",
    "CAMARA",
    "CAM TRAS",
    "CAM. TRAS",
    "SENSOR",
    "SENSORES",
    "PARK",
    "PARKTRONIC",
    "ALARM",
    "ALARMA",
    "STEREO",
    "RADIO",
    "XENON",
    "BIXENON",
    "BI-XENON",
    "LED",
    "HALOGENO",
    "HALOGENOS",
    "FOG",
    "HID",
    "PREMIUM SOUND",
    "PANORAMIC",
    "SUNROOF",
    "S/ROOF",
  ],
  transmission_tokens_to_strip: [
    "AUT",
    "AUT.",
    "AUTO",
    "AT",
    "AT.",
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
    "POWERSHIFT",
    "TORQUEFLITE",
    "DUAL CLUTCH",
    "DUAL-CLUTCH",
    "MANUAL",
    "MAN",
    "MAN.",
    "STD",
    "STD.",
    "MECA",
    "MECANICO",
    "MECANICA",
    "MECHANICO",
    "SECUENCIAL",
    "SECUENCIAL.",
    "DRIVELOGIC",
    "DUALOGIC",
    "SPEEDSHIFT",
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
    "3V": "3CIL",
    "4V": "4CIL",
    "5V": "5CIL",
    "6V": "6CIL",
    "8V": "8CIL",
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
    "DUAL CLUTCH": "AUTO",
    "DUAL-CLUTCH": "AUTO",
    TORQUEFLITE: "AUTO",
  },
  regex_patterns: {
    multiple_spaces: /\s+/g,
    trim_spaces: /^\s+|\s+$/g,
    decimal_comma: /(\d),(\d)/g,
    stray_punctuation: /(?<!\d)[\.,]|[.,](?!\d)/g,
  },
};

const PROTECTED_HYPHEN_TOKENS = [
  {
    regex: /\bA[\s-]?SPEC\b/gi,
    placeholder: "__BX_PROTECTED_A_SPEC__",
    canonical: "A-SPEC",
  },
  {
    regex: /\bTYPE[\s-]?S\b/gi,
    placeholder: "__BX_PROTECTED_TYPE_S__",
    canonical: "TYPE-S",
  },
  {
    regex: /\bTYPE[\s-]?R\b/gi,
    placeholder: "__BX_PROTECTED_TYPE_R__",
    canonical: "TYPE-R",
  },
  {
    regex: /\bTYPE[\s-]?F\b/gi,
    placeholder: "__BX_PROTECTED_TYPE_F__",
    canonical: "TYPE-F",
  },
  {
    regex: /\bS[\s-]?LINE\b/gi,
    placeholder: "__BX_PROTECTED_S_LINE__",
    canonical: "S-LINE",
  },
];

function applyProtectedTokens(value = "") {
  if (!value) return "";
  let output = value;
  PROTECTED_HYPHEN_TOKENS.forEach(({ regex, placeholder }) => {
    output = output.replace(regex, placeholder);
  });
  return output;
}

function restoreProtectedTokens(value = "") {
  if (!value) return "";
  let output = value;
  PROTECTED_HYPHEN_TOKENS.forEach(({ placeholder, canonical }) => {
    const placeholderRegex = new RegExp(placeholder, "g");
    output = output.replace(placeholderRegex, canonical);
  });
  return output;
}

function escapeRegExp(value = "") {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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

function normalizeCylinders(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  let normalized = versionString;
  Object.entries(BX_NORMALIZATION_DICTIONARY.cylinder_normalization).forEach(
    ([from, to]) => {
      const pattern = new RegExp(`\\b${escapeRegExp(from)}\\b`, "g");
      normalized = normalized.replace(pattern, to);
    }
  );
  normalized = normalized.replace(/\b(\d+)V\b/g, "$1CIL");
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

function normalizeStandaloneLiters(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b(\d+\.\d+)\s+L\b/g, "$1L")
    .replace(/\b(\d+\.\d+)(?=\s|$)/g, (match) => {
      const liters = parseFloat(match);
      if (!Number.isFinite(liters) || liters <= 0 || liters > 12) return match;
      return `${match}L`;
    });
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

function cleanVersionString(versionString, model = "") {
  if (!versionString || typeof versionString !== "string") return "";

  let cleaned = versionString
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/"/g, " ")
    .trim();

  cleaned = applyProtectedTokens(cleaned);

  cleaned = cleaned.replace(
    /([A-Z0-9]+)(AUT|MAN|STD|CVT|DSG|DCT|TIPTRONIC)\b/g,
    "$1 $2"
  );
  cleaned = cleaned.replace(/\bHB\b/g, "HATCHBACK");

  cleaned = cleaned.replace(
    BX_NORMALIZATION_DICTIONARY.regex_patterns.decimal_comma,
    "$1.$2"
  );
  cleaned = cleaned.replace(/\//g, " ");
  cleaned = cleaned.replace(/PICK[\s-]?UP/g, "PICKUP");

  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeCylinders(cleaned);
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)T\b/g, "$1L TURBO");
  cleaned = normalizeHorsepower(cleaned);
  cleaned = normalizeTurboTokens(cleaned);
  cleaned = normalizeHorsepower(cleaned);

  BX_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach((token) => {
    const regex = new RegExp(`\\b${escapeRegExp(token)}\\b`, "g");
    cleaned = cleaned.replace(regex, " ");
  });

  BX_NORMALIZATION_DICTIONARY.transmission_tokens_to_strip.forEach((token) => {
    const regex = new RegExp(`\\b${escapeRegExp(token)}\\b`, "g");
    cleaned = cleaned.replace(regex, " ");
  });

  if (model) {
    const normalizedModel = model
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toUpperCase()
      .trim();
    if (normalizedModel) {
      const modelRegex = new RegExp(
        `\\b${escapeRegExp(normalizedModel)}\\b`,
        "g"
      );
      cleaned = cleaned.replace(modelRegex, " ");
    }
  }

  cleaned = cleaned.replace(
    BX_NORMALIZATION_DICTIONARY.regex_patterns.stray_punctuation,
    " "
  );
  cleaned = cleaned.replace(/\s*-\s*/g, " ");
  cleaned = cleaned.replace(/\s*\+\s*/g, " ");
  cleaned = cleaned.replace(
    BX_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces,
    " "
  );
  cleaned = cleaned.replace(
    BX_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces,
    ""
  );

  cleaned = cleaned.replace(/\s+/g, " ").trim();
  cleaned = restoreProtectedTokens(cleaned);
  return cleaned;
}

function extractDoorsAndOccupants(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string")
    return { doors: "", occupants: "" };

  const normalized = versionOriginal
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();

  const doorsMatch = normalized.match(
    /\b(\d)\s*(?:P(?:TAS?|TS?)|PUERTAS?|PTS)\b/
  );
  const occMatch = normalized.match(/\b0?(\d{1,2})\s*OCUP\.?\b/);

  return {
    doors: doorsMatch ? `${doorsMatch[1]}PUERTAS` : "",
    occupants:
      occMatch && !Number.isNaN(parseInt(occMatch[1], 10))
        ? `${parseInt(occMatch[1], 10)}OCUP`
        : "",
  };
}

function normalizeTransmission(transmissionCode) {
  if (!transmissionCode || typeof transmissionCode !== "string") return "";
  const normalized = transmissionCode
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .trim();

  return (
    BX_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] ||
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
    BX_NORMALIZATION_DICTIONARY.transmission_normalization
  )) {
    const regex = new RegExp(`\\b${escapeRegExp(token)}\\b`, "g");
    if (regex.test(normalized)) {
      return BX_NORMALIZATION_DICTIONARY.transmission_normalization[token];
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

  if (!record.marca || record.marca.toString().trim() === "")
    errors.push("marca is required");
  if (!record.modelo || record.modelo.toString().trim() === "")
    errors.push("modelo is required");
  if (!Number.isInteger(year) || year < 2000 || year > 2030) {
    errors.push("anio must be between 2000-2030");
  } else {
    record.anio = year;
  }
  if (
    !record.version_original ||
    record.version_original.toString().trim() === ""
  )
    errors.push("version is required");
  if (!record.transmision || record.transmision.toString().trim() === "")
    errors.push("transmision is required");

  return { isValid: errors.length === 0, errors };
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

function processBxRecord(record) {
  const derivedTransmission =
    normalizeTransmission(record.transmision) ||
    inferTransmissionFromVersion(record.version_original);

  record.transmision = derivedTransmission;

  const { doors, occupants } = extractDoorsAndOccupants(
    record.version_original || ""
  );
  const validation = validateRecord(record);
  if (!validation.isValid)
    throw new Error(`Validation failed: ${validation.errors.join(", ")}`);

  let versionLimpia = cleanVersionString(
    record.version_original || "",
    record.modelo || ""
  );

  versionLimpia = versionLimpia
    .replace(/\b\d\s*(?:P(?:TAS?|TS?)|PUERTAS?|PTS)\b/gi, " ")
    .replace(/\b0?\d+\s*OCUP\.?\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();

  versionLimpia = dedupeTokens(
    [versionLimpia, doors, occupants].filter(Boolean).join(" ").trim()
  );
  if (!versionLimpia)
    throw new Error("Normalization produced empty version_limpia");

  const normalized = {
    origen_aseguradora: "BX",
    id_original: record.id_original,
    marca: normalizeText(record.marca),
    modelo: normalizeText(record.modelo),
    anio: record.anio,
    transmision: record.transmision,
    version_original: record.version_original,
    version_limpia: versionLimpia,
    fecha_procesamiento: new Date().toISOString(),
  };

  normalized.hash_comercial = createCommercialHash(normalized);
  return normalized;
}

function normalizeBxData(records = []) {
  const results = [];
  const errors = [];

  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const batch = records.slice(i, i + BATCH_SIZE);
    for (const record of batch) {
      try {
        results.push(processBxRecord(record));
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
x |
  function normalizeBxRecords(items = []) {
    const rawRecords = items.map((it) => (it && it.json ? it.json : it));
    const { results, errors } = normalizeBxData(rawRecords);
    const successItems = results.map((record) => ({ json: record }));
    const errorItems = errors.map((err) => ({ json: err }));
    return [...successItems, ...errorItems];
  };

const outputItems = normalizeBxRecords(items);
return outputItems;
