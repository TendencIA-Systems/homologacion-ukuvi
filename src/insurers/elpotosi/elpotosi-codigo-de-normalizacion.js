// src/insurers/elpotosi/elpotosi-codigo-de-normalizacion.js
/**
 * El PotosÃ­ ETL - Normalization Code Node
 *
 * Mirrors the Zurich/BX normalization pipeline while covering El PotosÃ­â€‘specific
 * quirks (VersionCorta fallback, â€œ0 Ton / Ocup / PTASâ€ blocks, comma-heavy trims).
 * Use inside an n8n Code node; it emits `{ json }` payloads and keeps validation
 * failures in-stream with `error: true`.
 */
const crypto = require("crypto");

const BATCH_SIZE = 5000;

const ELPOTOSI_NORMALIZATION_DICTIONARY = {
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
    "E/E",
    "A A",
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
    "SECUENCIAL",
    "SECUENCIAL.",
    "SELESPEED",
    "SELESPEDD",
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
    placeholder: "__EP_PROTECTED_A_SPEC__",
    canonical: "A-SPEC",
  },
  {
    regex: /\bTYPE[\s-]?S\b/gi,
    placeholder: "__EP_PROTECTED_TYPE_S__",
    canonical: "TYPE-S",
  },
  {
    regex: /\bTYPE[\s-]?R\b/gi,
    placeholder: "__EP_PROTECTED_TYPE_R__",
    canonical: "TYPE-R",
  },
  {
    regex: /\bTYPE[\s-]?F\b/gi,
    placeholder: "__EP_PROTECTED_TYPE_F__",
    canonical: "TYPE-F",
  },
  {
    regex: /\bS[\s-]?LINE\b/gi,
    placeholder: "__EP_PROTECTED_S_LINE__",
    canonical: "S-LINE",
  },
];

function applyProtectedTokens(value = "") {
  if (!value || typeof value !== "string") return "";
  let output = value;
  PROTECTED_HYPHEN_TOKENS.forEach(({ regex, placeholder }) => {
    output = output.replace(regex, placeholder);
  });
  return output;
}

function restoreProtectedTokens(value = "") {
  if (!value || typeof value !== "string") return "";
  let output = value;
  PROTECTED_HYPHEN_TOKENS.forEach(({ placeholder, canonical }) => {
    const placeholderRegex = new RegExp(placeholder, "g");
    output = output.replace(placeholderRegex, canonical);
  });
  return output;
}

function canonicalizeProtectedSpacing(value = "") {
  if (!value || typeof value !== "string") return "";
  let output = value;
  PROTECTED_HYPHEN_TOKENS.forEach(({ canonical }) => {
    const canonicalNoHyphen = canonical.replace(/-/g, " ");
    const pattern = new RegExp(
      `\\b${canonicalNoHyphen.replace(/\s+/g, "\\s+")}\\b`,
      "gi"
    );
    output = output.replace(pattern, canonical);
  });
  return output;
}

function escapeRegExp(text = "") {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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
  if (!versionString || typeof versionString !== "string") {
    return "";
  }
  let normalized = versionString;
  Object.entries(
    ELPOTOSI_NORMALIZATION_DICTIONARY.cylinder_normalization
  ).forEach(([from, to]) => {
    const regex = new RegExp(`\\b${escapeRegExp(from)}\\b`, "g");
    normalized = normalized.replace(regex, to);
  });
  return normalized;
}

function normalizeEngineDisplacement(versionString = "") {
  if (!versionString || typeof versionString !== "string") {
    return "";
  }
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
  let normalized = value;

  normalized = normalized.replace(
    /\b(\d+(?:\.\d+)?)\s*(?:LTS?|LITROS?)\b/g,
    (_, liters) => `${liters}L`
  );

  normalized = normalized.replace(
    /\b(\d+\.\d+)\b(?!\s*(?:L|LTS?|LITROS?|TON|TONELADAS?|OCUP|CIL|HP|K?G|TONS?))/g,
    (_, liters) => `${liters}L`
  );

  return normalized;
}

function normalizeHorsepower(versionString = "") {
  if (!versionString || typeof versionString !== "string") {
    return "";
  }
  return versionString
    .replace(/\b(\d+)\s*C\.P\.?\b/g, "$1HP")
    .replace(/\b(\d+)\s*CP\b/g, "$1HP")
    .replace(/\b(\d+)\s*H\.P\.?\b/g, "$1HP")
    .replace(/\b(\d+)\s*HP\b/g, "$1HP");
}

function normalizeTurboTokens(versionString = "") {
  if (!versionString || typeof versionString !== "string") {
    return "";
  }
  return versionString
    .replace(/\bTBO\b/g, "TURBO")
    .replace(/\bBI[-\s]?TURBO\b/g, "BITURBO")
    .replace(/\bTWIN[-\s]?TURBO\b/g, "TWIN TURBO")
    .replace(/\bT\/T\b/g, "TWIN TURBO");
}

function normalizeTonCapacity(versionString = "") {
  if (!versionString || typeof versionString !== "string") {
    return "";
  }
  return versionString.replace(
    /\b(\d+(?:\.\d+)?)\s*TON\b/g,
    (_, value) => `${value}TON`
  );
}

function stripLeadingPhrases(text, phrases = []) {
  let cleaned = text.replace(
    /([A-Z0-9]+)(AUT|MAN|STD|CVT|DSG|DCT|TIPTRONIC)\b/g,
    "$1 $2"
  );
  cleaned = cleaned.replace(/\bHB\b/g, "HATCHBACK");

  cleaned = cleaned.trim();
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

function cleanVersionString(versionString, marca = "", modelo = "") {
  if (!versionString || typeof versionString !== "string") {
    return "";
  }

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
    ELPOTOSI_NORMALIZATION_DICTIONARY.regex_patterns.decimal_comma,
    "$1.$2"
  );
  cleaned = stripLeadingPhrases(cleaned, [marca, modelo]);
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)T\b/g, "$1L TURBO");
  cleaned = cleaned.replace(/[,/]/g, " ").replace(/-/g, " ");
  cleaned = cleaned.replace(/(\d)([A-Z])/g, "$1 $2");
  cleaned = cleaned.replace(/([A-Z])(\d)/g, "$1 $2");
  cleaned = cleaned.replace(/\b(V|L|R|H|I|B)\s+(\d{1,2})\b/g, "$1$2");
  cleaned = cleaned.replace(/\b(\d{1,2})\s+CIL\b/g, "$1CIL");
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)\s+L\b/g, "$1L");
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)\s*LTS?\b/g, "$1L");

  cleaned = normalizeTonCapacity(cleaned);
  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeCylinders(cleaned);
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)T\b/g, "$1L TURBO");
  cleaned = normalizeHorsepower(cleaned);
  cleaned = normalizeTurboTokens(cleaned);

  ELPOTOSI_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach(
    (token) => {
      const regex = new RegExp(`\\b${escapeRegExp(token)}\\b`, "g");
      cleaned = cleaned.replace(regex, " ");
    }
  );

  ELPOTOSI_NORMALIZATION_DICTIONARY.transmission_tokens_to_strip.forEach(
    (token) => {
      const regex = new RegExp(`\\b${escapeRegExp(token)}\\b`, "g");
      cleaned = cleaned.replace(regex, " ");
    }
  );

  cleaned = cleaned.replace(/\s*\/\s*/g, " ");
  cleaned = cleaned.replace(
    ELPOTOSI_NORMALIZATION_DICTIONARY.regex_patterns.stray_punctuation,
    " "
  );
  cleaned = cleaned.replace(
    ELPOTOSI_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces,
    " "
  );
  cleaned = cleaned.replace(
    ELPOTOSI_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces,
    ""
  );

  cleaned = cleaned.replace(/\s+/g, " ").trim();
  cleaned = restoreProtectedTokens(cleaned);
  cleaned = canonicalizeProtectedSpacing(cleaned);
  return cleaned;
}

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
    /\b(\d)\s*(?:P(?:TAS?|TS?|TA)|PUERTAS?|PTS?)\b/
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
  if (!transmissionCode || typeof transmissionCode !== "string") {
    return "";
  }
  const normalized = transmissionCode
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .trim();
  return (
    ELPOTOSI_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] ||
    normalized
  );
}

function inferTransmissionFromVersion(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") {
    return "";
  }
  const normalized = versionOriginal
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
  for (const token of Object.keys(
    ELPOTOSI_NORMALIZATION_DICTIONARY.transmission_normalization
  )) {
    const regex = new RegExp(`\\b${escapeRegExp(token)}\\b`, "g");
    if (regex.test(normalized)) {
      return ELPOTOSI_NORMALIZATION_DICTIONARY.transmission_normalization[
        token
      ];
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

function processElPotosiRecord(record) {
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
    record.marca || "",
    record.modelo || ""
  );

  versionLimpia = versionLimpia
    .replace(/\b\d\s*(?:P(?:TAS?|TS?|TA)|PUERTAS?|PTS?)\b/gi, " ")
    .replace(/\b0?\d+\s*OCUP\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();

  versionLimpia = dedupeTokens(
    [versionLimpia, doors, occupants].filter(Boolean).join(" ").trim()
  );
  versionLimpia = canonicalizeProtectedSpacing(versionLimpia);
  versionLimpia = versionLimpia.replace(
    /\b(\d+\.\d+)\b(?!\s*(?:L|TON|OCUP|CIL|HP|K?G|TONS?))/g,
    "$1L"
  );

  if (!versionLimpia) {
    throw new Error("Normalization produced empty version_limpia");
  }

  const normalized = {
    origen_aseguradora: "ELPOTOSI",
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

function normalizeElPotosiData(records = []) {
  const results = [];
  const errors = [];

  for (let i = 0; i < records.length; i += BATCH_SIZE) {
    const batch = records.slice(i, i + BATCH_SIZE);
    for (const record of batch) {
      try {
        const processed = processElPotosiRecord(record);
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

function normalizeElPotosiRecords(items = []) {
  const rawRecords = items.map((it) => (it && it.json ? it.json : it));
  const { results, errors } = normalizeElPotosiData(rawRecords);
  const successItems = results.map((record) => ({ json: record }));
  const errorItems = errors.map((err) => ({ json: err }));
  return [...successItems, ...errorItems];
}

const outputItems = normalizeElPotosiRecords(items);
return outputItems;
