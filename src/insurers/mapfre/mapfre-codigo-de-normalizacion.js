/**
 * Mapfre ETL – Normalization Code Node
 *
 * Limpia campos comprimidos de Mapfre, infiere transmisión, normaliza
 * cilindrada/cilindros y genera `hash_comercial`. Diseñado para un nodo
 * Code de n8n.
 */
const crypto = require("crypto");

const BATCH_SIZE = 5000;

const MAPFRE_NORMALIZATION_DICTIONARY = {
  brand_aliases: {
    "VOLKSWAGEN VW": "VOLKSWAGEN",
    "VOLKSWAGEN AG": "VOLKSWAGEN",
    "VOLKSWAGEN DE MEXICO": "VOLKSWAGEN",
    "CHEVROLET GM": "CHEVROLET",
    "GM CHEVROLET": "CHEVROLET",
    "BMW BW": "BMW",
    "BMW AG": "BMW",
    "CHRYSLER-DODGE": "DODGE",
    "CHRYSLER-DODGE DG": "DODGE",
    "CHRYSLER DODGE": "DODGE",
    "MINI COOPER": "MINI",
    "NISSAN MOTOR": "NISSAN",
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
    "PAQ",
    "PAQ A",
    "PAQ B",
    "PAQ C",
    "PAQ D",
    "PAQ E",
    "PAQ M",
    "PAQ SEG",
    "PAQ. SEG",
    "PAQ. D",
    "PAQ.D",
    "PAQ D.",
    "PAQ. A",
    "PAQ. B",
    "PAQ. C",
    "PAQ. D.",
    "PAQ. E.",
    "PAQ. M",
    "PAQ. 1",
    "PAQ. 2",
    "PAQ. 3",
    "Q/C",
    "BA AA",
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
    "TM",
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
    TM: "MANUAL",
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
    TA: "AUTO",
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

const PROTECTED_HYPHEN_TOKENS = { "A-SPEC": "ASPEC" };

const MODEL_TRIM_TOKENS = [
  "A-SPEC",
  "ASPEC",
  "S-LINE",
  "SLINE",
  "SPORT",
  "LIMITED",
  "PREMIUM",
  "EXCLUSIVE",
  "ADVANCE",
  "ADVANCED",
  "ACTIVE",
  "ALLURE",
  "BASE",
  "GT",
  "GL",
  "GLS",
  "GLX",
  "LX",
  "LE",
  "SE",
  "XSE",
  "XLE",
  "SR",
  "SV",
  "SL",
  "LT",
  "LTZ",
  "L",
  "S",
  "TI",
  "LUSSO",
  "PLATINUM",
  "SIGNATURE",
  "ELITE",
  "EL",
  "XDRIVE",
  "BLACK",
  "ICONIC",
  "ESSENCE",
  "ULTIMATE",
  "LUXURY",
  "EXECUTIVE",
  "PRESTIGE",
  "CLASSIC",
  "COOL",
  "TOP",
  "PACK",
  "PAQ",
  "PLUS",
  "EDGE",
  "STYLE",
  "FR",
  "REFERENCE",
  "LITE",
  "CORE",
  "MID",
  "SELECT",
  "TITANIUM",
  "VELOCE",
  "SUPER",
  "ELX",
  "TECH",
  "TECHNOLOGY",
  "ESSENTIAL",
  "SPORTLINE",
  "GRAND",
  "GR",
  "TYPE",
  "TYPE S",
  "TYPE-S",
  "S-TYPE",
  "F-TYPE",
  "R-DYNAMIC",
  "R LINE",
  "R-LINE",
  "GTI",
  "GLI",
  "TRENDLINE",
  "COMFORTLINE",
  "HIGHLINE",
  "TREND",
  "PRESTIGE",
  "ICON",
  "INNOVATION",
  "PRIME",
];

const MODEL_BREAK_TOKENS = new Set([
  ...MODEL_TRIM_TOKENS.map((token) => token.replace(/[^A-Z0-9]/g, "")),
  "TYPE",
  "TYPES",
  "AWD",
  "FWD",
  "RWD",
  "4WD",
  "4X4",
  "4X2",
  "2WD",
  "QUATTRO",
  "4MATIC",
  "TORQUE",
  "MANUAL",
  "AUT",
  "TA",
  "TM",
  "CVT",
  "DSG",
  "TIPTRONIC",
  "TCT",
  "TURBO",
  "TWIN",
  "BITURBO",
  "COUPE",
  "SEDAN",
  "HATCHBACK",
  "HB",
  "SUV",
  "CROSSOVER",
  "VAN",
  "PICKUP",
  "CAB",
  "CABINA",
  "CHASIS",
  "HYBRID",
  "HYBRIDO",
  "HYBRIDA",
  "HEV",
  "PHEV",
  "MHEV",
  "BEV",
  "PLUG",
  "PLUG-IN",
  "ELECTRIC",
  "ELECTRICO",
  "ELECTRICA",
  "ELECT",
  "RSPORT",
  "SPORTBACK",
  "CABRIO",
  "ROADSTER",
  "AWD",
]);

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
  Object.entries(
    MAPFRE_NORMALIZATION_DICTIONARY.cylinder_normalization
  ).forEach(([from, to]) => {
    const regex = new RegExp(`\\b${escapeRegExp(from)}\\b`, "g");
    normalized = normalized.replace(regex, to);
  });
  return normalized;
}

function normalizeEngineDisplacement(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString
    .replace(/\b(\d)(\d)L\b/g, "$1.$2L")
    .replace(/\b(?<!\d\.)\d+L\b/g, (m) => `${m.slice(0, -1)}.0L`)
    .replace(/\b(?<!\d\.)\d+\s+L\b/g, (m) => `${m.match(/\d+/)[0]}.0L`);
}

function normalizeStandaloneLiters(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString.replace(/\b(\d+\.\d+)(?!L\b)(?!\d)/g, (m) => {
    const liters = parseFloat(m);
    return Number.isFinite(liters) && liters > 0 && liters <= 12 ? `${m}L` : m;
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

function normalizeTonCapacity(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString.replace(
    /\b(\d+(?:\.\d+)?)\s*TON\b/g,
    (_, v) => `${v}TON`
  );
}

function stripLeadingPhrases(text, phrases = []) {
  let cleaned = text.trim();
  phrases.forEach((phrase) => {
    if (!phrase) return;
    const norm = phrase
      .toString()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toUpperCase()
      .replace(/\s+/g, " ")
      .trim();
    if (!norm) return;
    const variants = [norm, norm.replace(/\s+/g, "")];
    let changed = true;
    while (changed && cleaned) {
      changed = false;
      for (const variant of variants) {
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

function cleanModelString(rawModel = "", brand = "") {
  if (!rawModel || typeof rawModel !== "string") return "";
  let cleaned = rawModel
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase();
  cleaned = stripLeadingPhrases(cleaned, [brand]);
  Object.entries(PROTECTED_HYPHEN_TOKENS).forEach(([token, placeholder]) => {
    cleaned = cleaned.replace(
      new RegExp(`\\b${escapeRegExp(token)}\\b`, "g"),
      placeholder
    );
  });
  cleaned = cleaned.replace(/[,/]/g, " ").replace(/\s+/g, " ").trim();
  return cleaned;
}

function cleanVersionString(versionString, marca = "", modelo = "") {
  if (!versionString || typeof versionString !== "string") return "";
  let cleaned = versionString
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/"/g, " ")
    .trim();
  cleaned = cleaned.replace(
    MAPFRE_NORMALIZATION_DICTIONARY.regex_patterns.decimal_comma,
    "$1.$2"
  );
  cleaned = stripLeadingPhrases(cleaned, [marca, modelo]);

  Object.entries(PROTECTED_HYPHEN_TOKENS).forEach(([token, placeholder]) => {
    cleaned = cleaned.replace(
      new RegExp(`\\b${escapeRegExp(token)}\\b`, "g"),
      placeholder
    );
  });

  cleaned = cleaned
    .replace(/[,/]/g, " ")
    .replace(/-/g, " ")
    .replace(/(\d)([A-Z])/g, "$1 $2")
    .replace(/([A-Z])(\d)/g, "$1 $2")
    .replace(
      /\b([A-Z0-9]+)(AUT|MAN|STD|CVT|DSG|DCT|IVT|TA|TM|TIPTRONIC)\b/g,
      "$1 $2"
    )
    .replace(/\bHB\b/g, "HATCHBACK")
    .replace(/\b(V|L|R|H|I|B)\s+(\d{1,2})\b/g, "$1$2")
    .replace(/\b(\d{1,2})\s+CIL\b/g, "$1CIL")
    .replace(/\b(\d+(?:\.\d+)?)\s+L\b/g, "$1L");

  cleaned = normalizeTonCapacity(cleaned);
  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeCylinders(cleaned);
  cleaned = cleaned
    .replace(/\bV(\d+)\b/g, "$1CIL")
    .replace(/\b(\d+)\s*V\b/g, "$1CIL");
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);
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

  cleaned = cleaned
    .replace(/\s*\/\s*/g, " ")
    .replace(
      MAPFRE_NORMALIZATION_DICTIONARY.regex_patterns.stray_punctuation,
      " "
    )
    .replace(
      MAPFRE_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces,
      " "
    )
    .replace(MAPFRE_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces, "");

  Object.values(PROTECTED_HYPHEN_TOKENS).forEach((placeholder) => {
    cleaned = cleaned.replace(
      new RegExp(`\\b${escapeRegExp(placeholder)}\\b`, "g"),
      Object.keys(PROTECTED_HYPHEN_TOKENS).find(
        (k) => PROTECTED_HYPHEN_TOKENS[k] === placeholder
      )
    );
  });

  return cleaned;
}

function extractDoorsAndOccupants(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string")
    return { doors: "", occupants: "" };
  const normalized = versionOriginal
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/[,/]/g, " ");
  const doorsMatch = normalized.match(
    /\b(\d)\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/
  );
  const occMatch = normalized.match(/\b0?(\d{1,2})\s*(?:OCUP|PASAJEROS?)\b/);
  return {
    doors: doorsMatch ? `${doorsMatch[1]}PUERTAS` : "",
    occupants:
      occMatch && !Number.isNaN(parseInt(occMatch[1], 10))
        ? `${parseInt(occMatch[1], 10)}OCUP`
        : "",
  };
}

function normalizeTransmission(code) {
  if (!code || typeof code !== "string") return "";
  const normalized = code
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .trim();
  return (
    MAPFRE_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] ||
    normalized
  );
}

function inferTransmissionFromText(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  const normalized = versionString
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
  if (/\bT\s*A\b/.test(normalized) || /TA\b/.test(normalized)) return "AUTO";
  if (/\bT\s*M\b/.test(normalized) || /TM\b/.test(normalized)) return "MANUAL";
  return "";
}

function tokenShouldBreak(tokenSanitized) {
  if (!tokenSanitized) return false;
  if (MODEL_BREAK_TOKENS.has(tokenSanitized)) return true;
  if (/^\d+(?:\.\d+)?(?:L|T|HP|KW)?$/.test(tokenSanitized)) return true;
  if (/^\d+CIL$/.test(tokenSanitized)) return true;
  if (/^\d+V$/.test(tokenSanitized)) return true;
  if (/^\d+PAS$/.test(tokenSanitized)) return true;
  if (/^\d+OCUP$/.test(tokenSanitized)) return true;
  if (/^\d+P$/.test(tokenSanitized)) return true;
  if (/^\d+$/.test(tokenSanitized)) return true;
  if (/^\d{1,2}[A-Z]+$/.test(tokenSanitized)) return true;
  if (
    /^[A-Z]{1,2}\d{2,}$/.test(tokenSanitized) &&
    !/^CX\d{1,2}$/.test(tokenSanitized)
  )
    return true;
  return false;
}

function extractModel(rawModel = "", brand = "") {
  const cleaned = cleanModelString(rawModel, brand);
  if (!cleaned) return "";
  const tokens = cleaned.split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return "";
  const modelTokens = [];
  for (const token of tokens) {
    const normalizedToken = token.replace(/[^A-Z0-9-]/g, "");
    const sanitized = normalizedToken.replace(/[^A-Z0-9]/g, "");
    if (!sanitized) continue;
    if (modelTokens.length > 0 && tokenShouldBreak(sanitized)) break;
    if (modelTokens.length === 0 && tokenShouldBreak(sanitized)) continue;
    modelTokens.push(normalizedToken);
  }
  if (modelTokens.length === 0) {
    return tokens[0].replace(/[^A-Z0-9-]/g, "");
  }
  return modelTokens.join(" ");
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
  if (!Number.isInteger(year) || year < 2000 || year > 2030)
    errors.push("anio must be between 2000-2030");
  else record.anio = year;
  if (
    !record.version_original ||
    record.version_original.toString().trim() === ""
  )
    errors.push("version is required");
  if (!record.transmision || record.transmision.toString().trim() === "")
    errors.push("transmision is required");
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
  const marcaNormalizada = normalizeBrand(record.marca || "");
  const modeloNormalizado = extractModel(
    record.modelo_version_completo || "",
    marcaNormalizada
  );
  const modeloFinal =
    modeloNormalizado || normalizeText(record.modelo_version_completo || "");

  const inferredTransmission =
    normalizeTransmission(record.transmision) ||
    inferTransmissionFromText(record.version_corta || "") ||
    inferTransmissionFromText(record.modelo_version_completo || "");
  record.transmision = inferredTransmission;

  const versionOriginal =
    record.version_corta && record.version_corta.trim()
      ? record.version_corta
      : record.modelo_version_completo;

  const { doors, occupants } = extractDoorsAndOccupants(versionOriginal || "");

  const validation = validateRecord({
    ...record,
    marca: marcaNormalizada,
    modelo: modeloFinal,
    version_original: versionOriginal,
  });
  if (!validation.isValid) {
    throw new Error(`Validation failed: ${validation.errors.join(", ")}`);
  }

  let versionLimpia = cleanVersionString(
    versionOriginal || "",
    marcaNormalizada,
    modeloFinal
  );
  versionLimpia = versionLimpia
    .replace(/\b\d\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/gi, " ")
    .replace(/\b0?\d+\s*(?:OCUP|PASAJEROS?)\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();

  versionLimpia = dedupeTokens(
    [versionLimpia, doors, occupants].filter(Boolean).join(" ").trim()
  );

  Object.entries(PROTECTED_HYPHEN_TOKENS).forEach(([token, placeholder]) => {
    versionLimpia = versionLimpia.replace(
      new RegExp(`\\b${escapeRegExp(placeholder)}\\b`, "g"),
      token
    );
  });

  if (!versionLimpia) {
    throw new Error("Normalization produced empty version_limpia");
  }

  const normalized = {
    origen_aseguradora: "MAPFRE",
    id_original: record.id_original,
    marca: marcaNormalizada,
    modelo: modeloFinal,
    anio: record.anio,
    transmision: record.transmision,
    version_original: versionOriginal,
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
        results.push(processMapfreRecord(record));
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
