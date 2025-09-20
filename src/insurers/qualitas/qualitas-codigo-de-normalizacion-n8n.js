/**
 * Qualitas ETL - Normalization Code Node v2
 *
 * Limpieza alineada con Zurich/Chubb/Atlas:
 * - Preserva trims con guion (A-SPEC, TYPE-S, S-LINE).
 * - Normaliza litros decimales y caballos de fuerza.
 * - Amplía diccionario de transmisiones y elimina tokens irrelevantes.
 */

const crypto = require("crypto");

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
    "NAVI",
    "CAM TRAS",
    "TBO",
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
    regex: /\bS[\s-]?LINE\b/gi,
    placeholder: "__Q_PROTECTED_S_LINE__",
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
  return value
    .replace(/\b(\d)(\d)L\b/g, "$1.$2L")
    .replace(/\b(?<!\d\.)\d+L\b/g, (match) => `${match.slice(0, -1)}.0L`)
    .replace(/\b(?<!\d\.)\d+\s+L\b/g, (match) => {
      const digits = match.match(/\d+/)[0];
      return `${digits}.0L`;
    });
}

function normalizeCylinders(value = "") {
  if (!value || typeof value !== "string") return "";
  let normalized = value;
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

function cleanVersionString(versionString, model = "") {
  if (!versionString || typeof versionString !== "string") return "";

  let cleaned = versionString.toUpperCase().trim();
  cleaned = applyProtectedTokens(cleaned);
  cleaned = cleaned.replace(/\bRA-?(\d+)\b/g, "R$1");
  cleaned = cleaned.replace(/[\/,]/g, " ");
  cleaned = cleaned.replace(/-/g, " ");

  cleaned = normalizeDrivetrain(cleaned);
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
    .replace(/\bCONV\b/g, "CONVERTIBLE");

  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);

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
  cleaned = cleaned.replace(/CIL(?=\d)/g, "CIL ");
  cleaned = cleaned.replace(/\b(\d+)\s+O\b/g, "$1OCUP");
  cleaned = cleaned.replace(/\b(\d+)\s+OCU\b/g, "$1OCUP");
  cleaned = cleaned.replace(/\b(\d+)\s+OC\b/g, "$1OCUP");
  cleaned = cleaned.replace(/\b(\d+)\s*HP\b/g, "$1HP");
  cleaned = cleaned.replace(/\s+/g, " ").trim();
  return cleaned;
}

function extractDoorsAndOccupants(versionOriginal = "") {
  const doorsMatch = versionOriginal.match(/\b(\d)\s*P(?:TAS?|TS?|TA)?\.?\b/i);
  const occMatch = versionOriginal.match(
    /\b0?(\d+)\s*(?:OC|OCU|OCUP|OCUP\.?|O\.?)\b/i
  );
  return {
    doors: doorsMatch ? `${doorsMatch[1]}PUERTAS` : "",
    occupants: occMatch ? `${parseInt(occMatch[1], 10)}OCUP` : "",
  };
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

const BATCH_SIZE = 5000;

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
    .replace(/\b\d\s*P(?:TAS?|TS?|TA)?\.?\b/gi, " ")
    .replace(/\b0?\d+\s*(?:OC|OCU|OCUP|OCUP\.?|O\.?)\b/gi, " ")
    .replace(/\s+[.,](?=\s|$)/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  const tokens = versionLimpia.split(" ").filter((token, idx, arr) => {
    if (!token) return false;
    if (/^[.,]$/.test(token)) return false;
    if (/^\d+$/.test(token)) {
      const next = arr[idx + 1] || "";
      if (/^\d+OCUP$/i.test(next) || /^OCUP$/i.test(next)) return false;
    }
    return true;
  });
  versionLimpia = tokens.join(" ");
  versionLimpia = versionLimpia.replace(/\s+/g, " ").trim();

  versionLimpia = [versionLimpia, doors, occupants]
    .filter(Boolean)
    .join(" ")
    .trim();

  const normalized = {
    origen_aseguradora: "QUALITAS",
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

const outputItems = normalizeQualitasRecords(items);
return outputItems;
