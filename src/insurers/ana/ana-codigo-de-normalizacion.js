/**
 * Ana ETL - Normalization Code Node
 *
 * Mirrors the insurer normalization pipeline used for Zurich/Qualitas/Chubb.
 * Intended to run inside an n8n Code node: it cleans ANA vehicle records,
 * infers transmissions when missing, extracts door/occupant tokens, and
 * outputs normalized objects ready for Supabase ingestion.
 */

const crypto = require("crypto");

const ANA_NORMALIZATION_DICTIONARY = {
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
    "PIEL",
    "GAMUZA",
    "CA",
    "C/A",
    "A/C",
    "AC",
    "CE",
    "SQ",
    "CB",
    "SIS/NAV",
    "SIS.NAV.",
    "T.S",
    "T.P.",
    "L.N",
    "VE",
    "FBX",
    "NAVI",
    "CAM TRAS",
    "SENSOR",
    "CAMARA",
    "COMFORT",
    "CONFORT",
    "FRENOS CERAM",
    "FRENOS CERAMICA",
    "TBO",
    "STD",
    "STD.",
    "AUT",
    "MANUAL",
    "ESTANDAR",
    "AUT.",
    "AUTOMATICA",
    "AUTOMATICO",
    "AUTOMATIC",
    "AUTOMATI",
    "AUTOMA",
    "AUTOM",
    "CVT",
    "DSG",
    "S TRONIC",
    "R TRONIC",
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
    AUTOMATI: "AUTO",
    AUTOMA: "AUTO",
    AUTOM: "AUTO",
    CVT: "AUTO",
    CVT7: "AUTO",
    DSG: "AUTO",
    "S TRONIC": "AUTO",
    "R TRONIC": "AUTO",
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

const ANA_BRAND_ALIASES = {
  IZSUZU: "ISUZU",
  "MERCEDES-BENZ": "MERCEDES BENZ",
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
  "SIN INFORMACIÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“N",
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

function expandTurboSuffix(text = "") {
  if (!text || typeof text !== "string") return "";
  return text.replace(/\b(\d+\.\d+)(?:L)?T\b/gi, (_, num) => `${num}L TURBO`);
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
  Object.entries(ANA_NORMALIZATION_DICTIONARY.cylinder_normalization).forEach(
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
    .replace(/\bQUARO\b/g, "AWD")
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

function cleanAnaModel(rawModel = "", marca = "") {
  const normalizedModel = normalizeText(rawModel);
  if (!normalizedModel) return "";

  let cleaned = normalizedModel;
  const normalizedMarca = marca ? marca.toUpperCase() : "";

  if (normalizedMarca) {
    const variants = [normalizedMarca, normalizedMarca.replace(/\s+/g, "")];
    variants.forEach((variant) => {
      if (!variant) return;
      const startRegex = new RegExp(`^${escapeRegex(variant)}\\s*`);
      cleaned = cleaned.replace(startRegex, "");
      const inlineRegex = new RegExp(`\\s+${escapeRegex(variant)}\\b`, "g");
      cleaned = cleaned.replace(inlineRegex, "");
    });
  }

  cleaned = cleaned.replace(/^[A-Z]{2}\s+(?=[A-Z])/g, "");
  cleaned = cleaned.replace(/\s+/g, " ").trim();
  return cleaned;
}

function cleanVersionString(versionString = "", model = "", marca = "") {
  if (!versionString || typeof versionString !== "string") return "";

  let cleaned = versionString.toUpperCase().trim();
  cleaned = applyProtectedTokens(cleaned);
  cleaned = cleaned.replace(/^[A-Z]{1,2}\s+(?=[A-Z])/g, "");
  cleaned = cleaned.replace(/\bRA-?(\d+)\b/g, "RA$1");
  cleaned = cleaned.replace(/[\/,]/g, " ");
  cleaned = cleaned.replace(/-/g, " ");

  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeCylinders(cleaned);
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);
  cleaned = expandTurboSuffix(cleaned);
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)\s*CP\b/g, "$1HP");
  cleaned = cleaned.replace(/\b(\d+)\s*CC\b/g, "$1CC");
  cleaned = cleaned.replace(/\b(\d+\.\d+)I\b/g, "$1L");

  ANA_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach((token) => {
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
    const normalizedMarca = marca.toUpperCase();
    const marcaVariants = [
      normalizedMarca,
      normalizedMarca.replace(/\s+/g, ""),
      normalizedMarca.split(" ")[0],
    ].filter(Boolean);
    marcaVariants.forEach((variant) => {
      cleaned = cleaned.replace(
        new RegExp(`\\b${escapeRegex(variant)}\\b`, "gi"),
        " "
      );
    });
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
    ANA_NORMALIZATION_DICTIONARY.regex_patterns;
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

  const normalizedOriginal = versionOriginal.toUpperCase();
  const doorPatterns = [
    /\b(\d+)\s*P(?:TAS?|TS?|TA)?\.?\b/,
    /\b(\d+)\s*PUERTAS?\b/,
    /\b(\d)\s*(?:ABS|D\/T)\b/,
  ];

  let doors = "";
  for (const pattern of doorPatterns) {
    const match = normalizedOriginal.match(pattern);
    if (match) {
      const value = parseInt(match[1], 10);
      if (Number.isFinite(value) && value > 0) {
        doors = `${value}PUERTAS`;
        break;
      }
    }
  }

  const occupantPatterns = [
    /\b0?(\d+)\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX)\b/,
    /\b0?(\d+)(?:OCUPANTES?|OCUP|OCU|OC)\b/,
    /\b0?(\d+)\s*(?:PASAJEROS?|PAS)\b/,
  ];

  let occupants = "";
  for (const pattern of occupantPatterns) {
    const match = normalizedOriginal.match(pattern);
    if (match) {
      const value = parseInt(match[1], 10);
      if (Number.isFinite(value) && value > 0) {
        occupants = `${value}OCUP`;
        break;
      }
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
    ANA_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] ||
    normalized;
  if (NORMALIZED_TRANSMISSIONS.has(mapped)) return mapped;
  return "";
}

function inferTransmissionFromVersion(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") return "";
  const version = versionOriginal.toUpperCase();
  for (const code of Object.keys(
    ANA_NORMALIZATION_DICTIONARY.transmission_normalization
  )) {
    const regex = new RegExp(`\\b${escapeRegex(code)}\\b`, "i");
    if (regex.test(version)) {
      const normalized = normalizeTransmission(code);
      if (normalized) return normalized;
    }
  }
  return "";
}

function dedupeTokens(tokens = []) {
  const seen = new Set();
  const deduped = [];
  tokens.forEach((token) => {
    if (!token) return;
    if (!seen.has(token)) {
      seen.add(token);
      deduped.push(token);
    }
  });
  return deduped;
}

const BATCH_SIZE = 5000;

function normalizeAnaData(records = []) {
  const results = [];
  const errors = [];

  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const batch = records.slice(i, i + BATCH_SIZE);
    for (const record of batch) {
      try {
        const processed = processAnaRecord(record);
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

function normalizeAnaRecords(items = []) {
  const rawRecords = items.map((item) =>
    item && item.json ? item.json : item
  );
  const { results, errors } = normalizeAnaData(rawRecords);
  const successItems = results.map((record) => ({ json: record }));
  const errorItems = errors.map((error) => ({ json: error }));
  return [...successItems, ...errorItems];
}

function processAnaRecord(record) {
  const marcaNormalizada = normalizeMarca(record.marca);
  const modeloNormalizado = cleanAnaModel(record.modelo, marcaNormalizada);
  const modeloFinal = modeloNormalizado || normalizeText(record.modelo);

  const derivedTransmission =
    normalizeTransmission(record.transmision) ||
    normalizeTransmission(record.transmision_codigo) ||
    inferTransmissionFromVersion(record.version_original);
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

  let versionLimpia = cleanVersionString(
    record.version_original || "",
    modeloFinal || "",
    marcaNormalizada || ""
  );
  versionLimpia = versionLimpia.replace(/\b(\d+\.\d+)L?T\b/g, "$1L TURBO");
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
        if (Number.isFinite(numericValue) && numericValue > 0) {
          fallbackDoors = `${numericValue}PUERTAS`;
        }
      }
      const next = arr[idx + 1] || "";
      if (/^\d+OCUP$/i.test(next) || /^OCUP$/i.test(next)) return;
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
  versionLimpia = versionLimpia
    .replace(/\bABS\b/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  const finalDoors = doors || fallbackDoors;
  versionLimpia = [versionLimpia, finalDoors, occupants]
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();

  const normalized = {
    origen_aseguradora: "ANA",
    id_original: record.id_original,
    marca: marcaNormalizada,
    modelo: modeloFinal,
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

  if (!record.marca || record.marca.toString().trim() === "") {
    errors.push("marca is required");
  }
  if (!record.modelo || record.modelo.toString().trim() === "") {
    errors.push("modelo is required");
  }
  if (!record.anio || record.anio < 1990 || record.anio > 2035) {
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

function normalizeMarca(value) {
  const normalized = normalizeText(value);
  if (!normalized) return "";
  return ANA_BRAND_ALIASES[normalized] || normalized;
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

const outputItems = normalizeAnaRecords(items);
return outputItems;
