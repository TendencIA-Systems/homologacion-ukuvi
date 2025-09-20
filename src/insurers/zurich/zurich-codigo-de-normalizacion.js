/**
 * Zurich ETL - Normalization Code Node
 *
 * Este script se ejecuta en un nodo Code de n8n. Normaliza registros de Zurich,
 * infiere la transmisión cuando falta, limpia tokens redundantes y emite objetos
 * `{ json }`. Los fallos de validación se devuelven con `error: true`.
 */
const crypto = require("crypto");

const ZURICH_NORMALIZATION_DICTIONARY = {
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
    "VP",
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
    // indicadores de transmisión (para limpiar la versión)
    "STD",
    "AUT",
    "CVT",
    "DSG",
    "S TRONIC",
    "TIPTRONIC",
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
  ],
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
    "SEMI AUTOMATICO": "MANUAL",
    CVT: "AUTO",
    DSG: "AUTO",
    "S TRONIC": "AUTO",
    "S-TRONIC": "AUTO",
    STRONIC: "AUTO",
    TIPTRONIC: "AUTO",
    SELESPEED: "AUTO",
    SALESPEED: "AUTO",
    "Q-TRONIC": "AUTO",
    DCT: "AUTO",
    MULTITRONIC: "AUTO",
    GEARTRONIC: "AUTO",
    STEPTRONIC: "AUTO",
    SPEEDSHIFT: "AUTO",
    "G-TRONIC": "AUTO",
    "G TRONIC": "AUTO",
    PDK: "MANUAL",
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
    placeholder: "__Z_PROTECTED_A_SPEC__",
    canonical: "A-SPEC",
  },
  {
    regex: /\bTYPE[\s-]?S\b/gi,
    placeholder: "__Z_PROTECTED_TYPE_S__",
    canonical: "TYPE-S",
  },
  {
    regex: /\bTYPE[\s-]?R\b/gi,
    placeholder: "__Z_PROTECTED_TYPE_R__",
    canonical: "TYPE-R",
  },
  {
    regex: /\bTYPE[\s-]?F\b/gi,
    placeholder: "__Z_PROTECTED_TYPE_F__",
    canonical: "TYPE-F",
  },
];

function applyProtectedTokens(text = "") {
  let output = text;
  PROTECTED_HYPHEN_TOKENS.forEach(({ regex, placeholder }) => {
    output = output.replace(regex, placeholder);
  });
  return output;
}
function restoreProtectedTokens(text = "") {
  let output = text;
  PROTECTED_HYPHEN_TOKENS.forEach(({ placeholder, canonical }) => {
    output = output.replace(new RegExp(placeholder, "g"), canonical);
  });
  return output;
}
function normalizeStandaloneLiters(text = "") {
  if (!text || typeof text !== "string") return "";
  return text.replace(/\b(\d+\.\d+)(?!L\b)(?!\d)/g, (match) => {
    const liters = parseFloat(match);
    if (!Number.isFinite(liters) || liters <= 0 || liters > 12) return match;
    return `${match}L`;
  });
}

function normalizeDrivetrain(text = "") {
  return text
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
function normalizeEngineDisplacement(text = "") {
  if (!text || typeof text !== "string") return "";
  return text
    .replace(/\b(\d)(\d)L\b/g, "$1.$2L")
    .replace(/\b(?<!\d\.)\d+L\b/g, (match) => `${match.slice(0, -1)}.0L`)
    .replace(/\b(?<!\d\.)\d+\s+L\b/g, (match) => {
      const digits = match.match(/\d+/)[0];
      return `${digits}.0L`;
    });
}
function normalizeCylinders(text = "") {
  return text;
}

function cleanVersionString(versionString, model = "") {
  if (!versionString || typeof versionString !== "string") return "";
  let cleaned = versionString.toUpperCase().trim();
  cleaned = applyProtectedTokens(cleaned);
  cleaned = cleaned.replace(/\bRA-?(\d+)\b/g, "R$1");
  cleaned = cleaned.replace(/-/g, " ");

  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);

  ZURICH_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach((token) => {
    cleaned = cleaned.replace(new RegExp(`\\b${token}\\b`, "gi"), " ");
  });

  if (model) {
    cleaned = cleaned.replace(
      new RegExp(`\\b${model.toUpperCase()}\\b`, "gi"),
      " "
    );
  }

  cleaned = cleaned
    .replace(/\bHB\b/g, "HATCHBACK")
    .replace(/\bTUR\b/g, "TURBO")
    .replace(/\bCONV\b/g, "CONVERTIBLE")
    .replace(/(?<!\d)[\.,]|[\.,](?!\d)/g, " ");

  Object.values(ZURICH_NORMALIZATION_DICTIONARY.regex_patterns).forEach(
    (pattern) => {
      if (
        pattern !==
          ZURICH_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces &&
        pattern !== ZURICH_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces
      ) {
        cleaned = cleaned.replace(pattern, " ");
      }
    }
  );
  cleaned = cleaned.replace(
    ZURICH_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces,
    " "
  );
  cleaned = cleaned.replace(
    ZURICH_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces,
    ""
  );

  cleaned = restoreProtectedTokens(cleaned);
  return cleaned;
}

function extractDoorsAndOccupants(versionOriginal = "") {
  const doorsMatch = versionOriginal.match(
    /\b(\d)\s*P(?:TAS|TA|TS)?\.?(?=\b)/i
  );
  const occMatch = versionOriginal.match(/\b0?(\d+)\s*OCUP?\.?\b/i);
  return {
    doors: doorsMatch ? `${doorsMatch[1]}PUERTAS` : "",
    occupants: occMatch ? `${parseInt(occMatch[1], 10)}OCUP` : "",
  };
}

function normalizeTransmission(code) {
  if (!code || typeof code !== "string") return "";
  const normalized = code.toUpperCase().trim();
  return (
    ZURICH_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] ||
    normalized
  );
}

function inferTransmissionFromVersion(versionOriginal = "") {
  const version = (versionOriginal || "").toUpperCase();
  for (const token of Object.keys(
    ZURICH_NORMALIZATION_DICTIONARY.transmission_normalization
  )) {
    if (new RegExp(`\\b${token}\\b`, "i").test(version)) {
      return normalizeTransmission(token);
    }
  }
  return "";
}

const BATCH_SIZE = 5000;

function normalizeZurichData(records = []) {
  const results = [];
  const errors = [];
  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const batch = records.slice(i, i + BATCH_SIZE);
    for (const record of batch) {
      try {
        results.push(processZurichRecord(record));
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

function normalizeZurichRecords(items = []) {
  const rawRecords = items.map((it) => (it && it.json ? it.json : it));
  const { results, errors } = normalizeZurichData(rawRecords);
  return [
    ...results.map((r) => ({ json: r })),
    ...errors.map((e) => ({ json: e })),
  ];
}

function processZurichRecord(record) {
  const derivedTransmission =
    normalizeTransmission(record.transmision) ||
    inferTransmissionFromVersion(record.version_original);
  record.transmision = derivedTransmission;

  const { doors, occupants } = extractDoorsAndOccupants(
    record.version_original || ""
  );
  const validation = validateRecord(record);
  if (!validation.isValid) {
    throw new Error(`Validation failed: ${validation.errors.join(", ")}`);
  }

  let versionLimpia = cleanVersionString(
    record.version_original || "",
    record.modelo || ""
  );
  versionLimpia = versionLimpia
    .replace(/\b\d\s*P(?:TAS|TA|TS)?\.?(?=\b)/gi, " ")
    .replace(/\b0?\d+\s*OCUP?\.?\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
  versionLimpia = [versionLimpia, doors, occupants]
    .filter(Boolean)
    .join(" ")
    .trim();

  const normalized = {
    origen_aseguradora: "ZURICH",
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

const outputItems = normalizeZurichRecords(items);
return outputItems;
