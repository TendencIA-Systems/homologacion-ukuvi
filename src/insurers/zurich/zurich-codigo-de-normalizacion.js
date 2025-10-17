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
    "DH",
    "C",
    "FBX",
    "IMP",
    "CQ",
    "TELA",
    "ASIENTO GIRATORIO",
    // Wheel/rim sizes
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
    "RHYNE",
    "RHYNE SIZE",
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
  {
    regex: /\bT5\b/gi,
    placeholder: "__Z_PROTECTED_T5__",
    canonical: "T5",
  },
  {
    regex: /\bT6\b/gi,
    placeholder: "__Z_PROTECTED_T6__",
    canonical: "T6",
  },
  {
    regex: /\bT7\b/gi,
    placeholder: "__Z_PROTECTED_T7__",
    canonical: "T7",
  },
  {
    regex: /\bT8\b/gi,
    placeholder: "__Z_PROTECTED_T8__",
    canonical: "T8",
  },
  {
    regex: /\bT9\b/gi,
    placeholder: "__Z_PROTECTED_T9__",
    canonical: "T9",
  },
];

const ENGINE_ALIAS_PATTERNS = [
  { regex: /\bT[\s-]?FSI\b/gi, replacement: "TURBO" },
  { regex: /\bT[\s-]?SI\b/gi, replacement: "TURBO" },
  { regex: /\bFSI\s*TURBO\b/gi, replacement: "TURBO" },
  { regex: /\bFSI\b/gi, replacement: "FSI" },
  { regex: /\bGDI\b/gi, replacement: "GDI" },
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
  return text.replace(
    /\b(\d+\.\d+)(?!\s*(?:L\b|TON|TONELADAS|KG|KILOGRAMOS|PUERTAS|OCUP|CIL))/gi,
    (match, _value, offset, source) => {
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

function applyEngineAliases(text = "") {
  if (!text || typeof text !== "string") return "";
  let output = text;
  ENGINE_ALIAS_PATTERNS.forEach(({ regex, replacement }) => {
    output = output.replace(regex, replacement);
  });
  return output;
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

function normalizeTurboTokens(text = "") {
  if (!text || typeof text !== "string") return "";

  const explicitLiters = [];
  text.replace(/\b\d+(?:\.\d+)?L\b/gi, (match, offset) => {
    explicitLiters.push({ token: match, offset });
    return match;
  });

  return text.replace(
    /\b(\d+(?:\.\d+)?)(L)?[\s-]*T\b/gi,
    (fullMatch, rawNumber, hasL, offset) => {
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
    }
  );
}

function normalizeCylinders(text = "") {
  return text;
}

// NUEVA FUNCIÓN: Limpia la marca del modelo para Mazda
function cleanZurichModel(model, marca) {
  if (!model || !marca) return model;

  const normalizedMarca = marca.toUpperCase().trim();
  const normalizedModel = model.toUpperCase().trim();

  // Remover "MAZDA" del inicio del modelo si la marca es MAZDA
  if (normalizedMarca === "MAZDA" && normalizedModel.startsWith("MAZDA ")) {
    return normalizedModel.replace(/^MAZDA\s+/, "").trim();
  }

  return model;
}

function cleanVersionString(versionString, model = "") {
  if (!versionString || typeof versionString !== "string") return "";
  let cleaned = versionString
    .toString()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .replace(/["'\u201C\u201D\u2018\u2019]/g, " ")
    .trim();

  cleaned = cleaned.replace(/AUT(?=[A-Z0-9])/g, "AUT ");
  cleaned = applyProtectedTokens(cleaned);
  cleaned = cleaned.replace(/\bRA-?(\d+)\b/g, "R$1");
  cleaned = cleaned.replace(/-/g, " ");

  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeTurboTokens(cleaned);
  cleaned = applyEngineAliases(cleaned);
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);

  // Normalize horsepower values
  cleaned = cleaned
    .replace(/\b(\d+)\s*HP\b/gi, "$1HP")
    .replace(/\b(\d+)\s*C\.?P\.?\b/gi, "$1HP")
    .replace(/\b(\d+)\s*H\.?P\.?\b/gi, "$1HP");

  cleaned = cleaned
    .replace(/\b0+(?:\.\d+)?\s*TON(?:ELADAS)?\b/gi, " ")
    .replace(/\bTONELADAS?\b/gi, "TON")
    .replace(/LTON\b/g, "L TON");

  ZURICH_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach((token) => {
    cleaned = cleaned.replace(new RegExp(`\\b${token}\\b`, "gi"), " ");
  });

  if (model) {
    const normalizedModel = model.toUpperCase().trim();
    if (normalizedModel) {
      // Escape special regex characters and use word boundaries
      const escapedModel = normalizedModel.replace(
        /[.*+?^${}()|[\]\\]/g,
        "\\$&"
      );
      cleaned = cleaned.replace(new RegExp(`\\b${escapedModel}\\b`, "gi"), " ");
    }
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

  // NEW: Remove generation/trim prefixes (A7, MK VII, etc.)
  cleaned = cleaned.replace(
    /\b(A[4-7]|MK\s*VII?I?|MKVII?I?|GEN\s*\d+)\s+/gi,
    ""
  );

  cleaned = cleaned
    .replace(/\bHB\b/g, "HATCHBACK")
    .replace(/\bTUR\b/g, "TURBO")
    .replace(/\bCONV\b/g, "CONVERTIBLE")
    .replace(/\bGW\b/g, "WAGON")
    .replace(/\bV8\b/g, "8CIL")
    .replace(/\bPICK\s*UP\b/g, "PICKUP");

  // NEW: Remove body types from version
  cleaned = cleaned.replace(
    /\b(SEDAN|HATCHBACK|SUV|COUPE|CONVERTIBLE|PICKUP|VAN|WAGON)\b/gi,
    " "
  );

  cleaned = cleaned.replace(/(?<!\d)[\.,]|[\.,](?!\d)/g, " ");

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

  // NEW: Deduplicate tokens (critical for QUALITAS-like issues)
  const tokens = cleaned.split(/\s+/).filter(Boolean);
  const uniqueTokens = [...new Set(tokens)];
  cleaned = uniqueTokens.join(" ");

  return cleaned;
}

function extractDoorsAndOccupants(versionOriginal = "") {
  if (!versionOriginal || typeof versionOriginal !== "string") {
    return { doors: "", occupants: "" };
  }
  const upper = versionOriginal.toUpperCase();
  const doorsMatch = upper.match(
    /\b(\d{1,2})\s*(?:P(?:UERTAS?|TAS?|TS?|TA)?|PUERTAS?|P)\b/
  );
  let doors = "";
  if (doorsMatch) {
    const doorCount = parseInt(doorsMatch[1], 10);
    if ([2, 3, 4, 5, 7].includes(doorCount)) {
      doors = `${doorCount}PUERTAS`;
    }
  }
  const occMatch = upper.match(
    /\b0?(\d{1,2})\s*(?:OCUPANTES?|OCUP|OCU|OC|PAX|PASAJEROS?|PAS)\b/
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

  // MODIFICACIÓN: Limpiar el modelo removiendo "MAZDA" si aplica
  const cleanedModel = cleanZurichModel(record.modelo, record.marca);

  const { doors, occupants } = extractDoorsAndOccupants(
    record.version_original || ""
  );
  const validation = validateRecord(record);
  if (!validation.isValid) {
    throw new Error(`Validation failed: ${validation.errors.join(", ")}`);
  }

  let versionLimpia = cleanVersionString(
    record.version_original || "",
    cleanedModel || ""
  );
  versionLimpia = versionLimpia
    .replace(/\b\d\s*P(?:TAS|TA|TS)?\.?(?=\b)/gi, " ")
    .replace(/\b0?\d+\s*OCUP?\.?\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();

  // CRITICAL FIX: Only append doors/occupants if NOT already present
  // Prevents: "5PUERTAS ... 5PUERTAS" when already in versionLimpia
  const specsToAppend = [];
  if (doors && !versionLimpia.includes(doors)) {
    specsToAppend.push(doors);
  }
  if (occupants && !versionLimpia.includes(occupants)) {
    specsToAppend.push(occupants);
  }

  if (specsToAppend.length > 0) {
    versionLimpia = [versionLimpia, ...specsToAppend]
      .filter(Boolean)
      .join(" ")
      .trim();
  }

  const normalized = {
    origen_aseguradora: "ZURICH",
    id_original: record.id_original,
    marca: normalizeText(record.marca),
    modelo: normalizeModelo(record.marca, cleanedModel),
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
 * ENHANCED VERSION - adds NUEVO prefix, trim levels, body types, and letter spacing fixes
 * Fixes 4,641 cases of modelo contamination identified in analysis
 */
function normalizeModelo(marca, modelo) {
  if (!modelo || typeof modelo !== "string") return "";

  let normalized = modelo.toUpperCase().trim();
  const marcaUpper = (marca || "").toUpperCase().trim();

  // 1. Remove NUEVO/NUEVA/NEW prefix (1,195 cases) - NEW FIX
  normalized = normalized.replace(/^(NUEVO|NUEVA|NEW)\s+/gi, "");

  // 2. Remove generic prefixes (PICK UP, CAMIONETA, VAN, TRUCK) - existing
  normalized = normalized.replace(/^PICK\s*UP\s+/gi, "");
  normalized = normalized.replace(/^PICK-UP\s+/gi, "");
  normalized = normalized.replace(/^CAMIONETA\s+/gi, "");
  normalized = normalized.replace(/^VAN\s+/gi, "");
  normalized = normalized.replace(/^TRUCK\s+/gi, "");

  // 3. Remove brand name if repeated in model field - existing
  if (marcaUpper) {
    const brandPattern = new RegExp(
      `^${marcaUpper.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s+`,
      "gi"
    );
    normalized = normalized.replace(brandPattern, "");
  }

  // 4. Remove trim level/generation from modelo (72 cases) - NEW FIX
  normalized = normalized.replace(/\s+(MK\s*VII?I?|MKVII?I?|GEN\s*\d+)$/gi, "");

  // 5. Remove body type from modelo (2,084 cases) - NEW FIX
  normalized = normalized.replace(
    /\s+(SEDAN|HATCHBACK|SUV|COUPE|CONVERTIBLE|PICKUP|VAN|WAGON)$/gi,
    ""
  );

  // 6. Collapse spaces in letter+number models (1,290 cases) - NEW FIX
  // "A 3" → "A3", "E TRON" → "ETRON", "T T" → "TT"
  normalized = normalized.replace(/^([A-Z])\s+([A-Z0-9])/g, "$1$2");

  // 6b. E-TRON needs hyphen (special case) - NEW FIX
  normalized = normalized.replace(/\bETRON\b/g, "E-TRON");

  // 7. Remove single letter trim codes (e.g., "C 1500" → "1500") - existing
  normalized = normalized.replace(/\s+([A-Z])\s+(\d)/g, " $2");

  // 8. Remove cab type and configuration codes - existing
  normalized = normalized.replace(/\s+CAB\.?\s*REG\.?(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+CAB\.?\s*REGULAR(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+CREW\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+QUAD\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+MEGA\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+SUPER\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+KING\s+CAB(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+DOBLE\s+CABINA(?:\s+|$)/gi, " ");
  normalized = normalized.replace(/\s+SENCILLA\s+CABINA(?:\s+|$)/gi, " ");

  // 9. Remove standalone trim codes at end - existing
  normalized = normalized.replace(/\s+(DR|WT|SL|SLE|SLT)$/gi, "");

  // 10. Remove trim level suffixes from end - existing
  normalized = normalized.replace(
    /\s+(CREW|QUAD|MEGA|SUPER|KING)\s+CAB$/gi,
    ""
  );
  normalized = normalized.replace(/\s+(DOBLE|SENCILLA)\s+CABINA$/gi, "");

  // Final cleanup
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
