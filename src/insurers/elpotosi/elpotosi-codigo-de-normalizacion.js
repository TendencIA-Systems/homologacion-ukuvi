/**
 * El Potosi ETL - Normalization Code Node (FIXED)
 *
 * CORRECCIONES APLICADAS:
 * - MINI COOPER: Marca → BMW, Modelo → MINI COOPER
 * - Volvo: Eliminar espacio en modelos (XC 60 → XC60)
 * - Mazda: Eliminar MAZDA del modelo
 * - Jaguar: Eliminar JAGUAR del modelo
 * - Mercedes Benz: Eliminar MERCEDES del modelo
 * - Separar AUT pegado a otros specs
 * - NUEVO/NEW: Eliminar del modelo
 * - PASAJEROS: Eliminar del modelo
 */

const crypto = require("crypto");

const BATCH_SIZE = 5000;

// ═══════════════════════════════════════════════════════════════════════════
// CATÁLOGO MAESTRO DE MODELOS
// ═══════════════════════════════════════════════════════════════════════════
const CATALOGO_MAESTRO_MARCAS_MODELOS = {
  VOLKSWAGEN: [
    "POINTER",
    "JETTA",
    "GOLF",
    "TIGUAN",
    "AMAROK",
    "VENTO",
    "POLO",
    "T-CROSS",
    "TERAMONT",
    "TRANSPORTER",
  ],
  "MERCEDES BENZ": [
    "CLASE A",
    "CLASE C",
    "CLASE E",
    "CLASE G",
    "CLASE S",
    "GLA",
    "GLB",
    "GLC",
    "GLE",
    "GLS",
  ],
  VOLVO: [
    "C30",
    "C40",
    "C70",
    "S40",
    "S60",
    "S70",
    "S80",
    "S90",
    "V40",
    "V50",
    "V60",
    "V70",
    "V90",
    "XC40",
    "XC60",
    "XC70",
    "XC90",
  ],
  MAZDA: [
    "2",
    "3",
    "5",
    "6",
    "CX-3",
    "CX-30",
    "CX-5",
    "CX-50",
    "CX-7",
    "CX-9",
    "CX-90",
    "MX-5",
  ],
  JAGUAR: ["E-PACE", "F-PACE", "F-TYPE", "I-PACE", "XE", "XF", "XJ", "XK"],
};

const ELPOTOSI_BRAND_ALIASES = {
  MINI: "BMW", // CORRECCIÓN: MINI → BMW
};

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
    "PREMIUM SOUND",
    "0TON",
    "RHYNE",
    "RHYNE SIZE",
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
  {
    regex: /\bF[\s-]?TYPE\b/gi,
    placeholder: "__EP_PROTECTED_F_TYPE__",
    canonical: "F-TYPE",
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
  "TON",
  "TONELADAS",
  "TONS",
]);

const VALID_DOOR_COUNTS = new Set([2, 3, 4, 5, 7]);

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

ELPOTOSI_NORMALIZATION_DICTIONARY.transmission_tokens = Array.from(
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

ELPOTOSI_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio = Array.from(
  new Set(
    ELPOTOSI_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.map((token) =>
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

  // First, compact spaced cylinders like "6 CIL" → "6CIL"
  output = output.replace(/\b(\d+)\s+CIL\b/gi, "$1CIL");

  // Then apply standard cylinder normalization (L4 → 4CIL, V6 → 6CIL, etc.)
  Object.entries(
    ELPOTOSI_NORMALIZATION_DICTIONARY.cylinder_normalization
  ).forEach(([from, to]) => {
    const pattern = new RegExp(`\\b${escapeRegExp(from)}\\b`, "gi");
    output = output.replace(pattern, to);
  });
  return output;
}

function normalizeEngineDisplacement(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b(?<!\.)(\d)(\d)L\b/g, "$1.$2L")
    .replace(/\b(?<!\d\.)\d+L\b/g, (match) => `${match.slice(0, -1)}.0L`)
    .replace(/\b(?<!\d\.)\d+\s+L\b/g, (match) => {
      const digits = match.match(/\d+/)[0];
      return `${digits}.0L`;
    });
}

function normalizeStandaloneLiters(value = "") {
  if (!value || typeof value !== "string") return "";

  // First, compact spaced liters like "3.5 L" → "3.5L"
  const collapsed = value.replace(/\b(\d+(?:\.\d+)?)\s+L\b/gi, "$1L");

  // Then add L to standalone decimal numbers that look like engine displacement
  return collapsed.replace(
    /\b(\d+\.\d+)(?!\s*(?:L\b|LTS?|LITROS?|TON|TONELADAS?|TONS?|HP\b|K?G|CIL))/gi,
    (match, _raw, offset, source) => {
      const liters = parseFloat(match);
      if (!Number.isFinite(liters) || liters < 0.5 || liters > 8) {
        return match;
      }

      const leadingChar = offset > 0 ? source[offset - 1] : "";
      if (leadingChar && /[A-Za-z.]/.test(leadingChar)) {
        return match;
      }

      const before = source
        .substring(Math.max(0, offset - 20), offset)
        .toUpperCase();
      if (/\b(TON|TONELADAS|KG|KILOGRAMOS|PESO|CAB|CHASIS)\b/.test(before)) {
        return match;
      }

      // Only skip if the number is IMMEDIATELY followed by door/occupant context
      // (e.g., "2.5 PUERTAS" shouldn't get L, but "2.5 6CIL" should)
      const immediateAfter = source
        .substring(offset + match.length, offset + match.length + 10)
        .toUpperCase()
        .trim();
      if (/^(PUERTAS?|PTS?|OCUP|PASAJEROS?|PAS)\b/.test(immediateAfter)) {
        return match;
      }

      return `${match}L`;
    }
  );
}

function splitConcatenatedLiters(value = "") {
  if (!value || typeof value !== "string") return "";
  return value.replace(/(\d+(?:\.\d+)?L)(\d+(?:\.\d+)?L)/gi, "$1 $2");
}

function collapseDisplacementArtifacts(value = "") {
  if (!value || typeof value !== "string") return "";
  return value
    .replace(/\b(\d+CIL)\.0(?:\.0L)?\b/g, "$1")
    .replace(/\b(\d+CIL)\s+0\.0L\b/g, "$1")
    .replace(/\b(\d+(?:\.\d+)?L)(?:\s*\1)+\b/g, "$1")
    .replace(/\b(\d+(?:\.\d+)?L)L\b/g, "$1");
}

function normalizeHorsepower(value = "") {
  if (!value || typeof value !== "string") return "";
  return (
    value
      // Convert ptas → PUERTAS before other replacements
      .replace(/\b(\d+)\s*ptas\b/gi, "$1PUERTAS")
      .replace(/\b(\d+)\s*C\.P\.?\b/gi, "$1HP")
      .replace(/\b(\d+)\s*CP\b/gi, "$1HP")
      .replace(/\b(\d+)\s*H\.P\.?\b/gi, "$1HP")
      .replace(/\b(\d+)\s*HP\b/gi, "$1HP")
  );
}

function formatTurboDisplacement(raw = "") {
  const value = parseFloat(raw);
  if (!Number.isFinite(value) || value <= 0 || value > 12) {
    return "";
  }
  return Number.isInteger(value) ? `${value}.0` : value.toString();
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

function applyEngineAliases(value = "") {
  if (!value || typeof value !== "string") return "";
  let output = value;
  ENGINE_ALIAS_PATTERNS.forEach(({ regex, replacement }) => {
    output = output.replace(regex, replacement);
  });
  return output;
}

function normalizeTonCapacity(value = "") {
  if (!value || typeof value !== "string") return "";
  return value.replace(
    /\b(\d+(?:\.\d+)?)\s*TON(?:ELADAS|S)?\b/gi,
    (fullMatch, rawTon) => {
      const tonValue = parseFloat(rawTon);
      if (!Number.isFinite(tonValue) || tonValue <= 0) {
        return " ";
      }
      const normalizedNumber = Number.isInteger(tonValue)
        ? tonValue.toString()
        : tonValue.toString();
      return `${normalizedNumber}TON`;
    }
  );
}

/**
 * Extrae el modelo base del catálogo maestro
 */
function extractBaseModel(modeloContaminado = "", marcaNormalizada = "") {
  if (!modeloContaminado || !marcaNormalizada) return modeloContaminado;

  const modeloNorm = normalizeText(modeloContaminado);
  const modelosCatalogo =
    CATALOGO_MAESTRO_MARCAS_MODELOS[marcaNormalizada] || [];

  const modelosOrdenados = [...modelosCatalogo].sort(
    (a, b) => b.length - a.length
  );

  for (const modeloCatalogo of modelosOrdenados) {
    const modeloCatalogoNorm = normalizeText(modeloCatalogo);

    if (
      modeloNorm === modeloCatalogoNorm ||
      modeloNorm.startsWith(modeloCatalogoNorm + " ")
    ) {
      return modeloCatalogo;
    }
  }

  const tokens = modeloNorm.split(" ").filter(Boolean);
  if (tokens.length > 0) {
    return tokens[0];
  }

  return modeloContaminado;
}

/**
 * CORRECCIÓN: Limpia el modelo EL POTOSI
 */
function cleanElPotosiModel(rawModel = "", marca = "", originalMarca = "") {
  const normalizedModel = normalizeText(rawModel);
  if (!normalizedModel) return "";

  let cleaned = normalizedModel;
  const normalizedMarca = normalizeText(marca);

  // Proteger F-TYPE antes de limpiar
  cleaned = applyProtectedTokens(cleaned);

  // CORRECCIÓN 1: MINI COOPER
  if (originalMarca && normalizeText(originalMarca) === "MINI") {
    cleaned = restoreProtectedTokens(cleaned);
    return "MINI COOPER";
  }

  // CORRECCIÓN 2: Volvo - eliminar espacio en modelos
  if (normalizedMarca === "VOLVO") {
    cleaned = cleaned
      .replace(/\bXC\s+60\b/g, "XC60")
      .replace(/\bXC\s+70\b/g, "XC70")
      .replace(/\bXC\s+90\b/g, "XC90")
      .replace(/\bXC\s+40\b/g, "XC40")
      .replace(/\bV\s+40\b/g, "V40")
      .replace(/\bV\s+50\b/g, "V50")
      .replace(/\bV\s+60\b/g, "V60")
      .replace(/\bV\s+70\b/g, "V70")
      .replace(/\bV\s+90\b/g, "V90")
      .replace(/\bS\s+40\b/g, "S40")
      .replace(/\bS\s+60\b/g, "S60")
      .replace(/\bS\s+80\b/g, "S80")
      .replace(/\bS\s+90\b/g, "S90")
      .replace(/\bC\s+30\b/g, "C30")
      .replace(/\bC\s+70\b/g, "C70");
  }

  // CORRECCIÓN 3: Mazda - eliminar MAZDA del modelo
  if (normalizedMarca === "MAZDA") {
    cleaned = cleaned.replace(/^MAZDA\s+/, "");
  }

  // CORRECCIÓN 4: Jaguar - eliminar JAGUAR del modelo
  if (normalizedMarca === "JAGUAR") {
    cleaned = cleaned.replace(/^JAGUAR\s+/, "");
  }

  // CORRECCIÓN 5: Mercedes Benz - eliminar MERCEDES del modelo
  if (normalizedMarca === "MERCEDES BENZ") {
    cleaned = cleaned.replace(/^MERCEDES\s+/, "");
  }

  // CORRECCIÓN 6: Eliminar NUEVO, NUEVA, NEW del modelo
  cleaned = cleaned
    .replace(/\bNUEVO\s+/g, "")
    .replace(/\bNUEVA\s+/g, "")
    .replace(/\bNEW\s+/g, "")
    .replace(/\bNUEVA\s+LINEA\b/g, "")
    .replace(/\bLINEA\s+NUEVA\b/g, "")
    .replace(/\s+NUEVO\b/g, "")
    .replace(/\s+NUEVA\b/g, "")
    .replace(/\s+NEW\b/g, "");

  // CORRECCIÓN 7: Eliminar PASAJEROS del modelo
  cleaned = cleaned.replace(/\bPASAJEROS?\b/g, "").trim();

  // Normalizar GENERACION → GEN
  cleaned = cleaned
    .replace(/\bGENERACION\b/g, "GEN")
    .replace(/\bGEN\.?\s*(\d)/g, "GEN $1")
    .replace(/\bGEN\./g, "GEN");

  // Ajustar modelos de FORD a formato compacto (F150, L200, etc.)
  if (normalizedMarca === "FORD") {
    cleaned = cleaned
      .replace(/\bF[\s.-]?(\d{2,3})\b/g, "F$1")
      .replace(/\bL[\s.-]?(\d{3})\b/g, "L$1");
  }

  cleaned = cleaned.replace(/\s+/g, " ").trim();

  // Restaurar tokens protegidos
  cleaned = restoreProtectedTokens(cleaned);

  // Intentar extraer del catálogo maestro
  if (normalizedMarca && CATALOGO_MAESTRO_MARCAS_MODELOS[normalizedMarca]) {
    const baseModel = extractBaseModel(cleaned, normalizedMarca);
    if (baseModel) {
      cleaned = baseModel;
    }
  }

  return cleaned;
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

  // CORRECCIÓN: Separar AUT cuando está pegado a otros specs (ambas direcciones)
  cleaned = cleaned.replace(/AUT(?=[A-Z0-9])(?!O)/g, "AUT ");
  cleaned = cleaned.replace(/([A-Z0-9])AUT\b/g, "$1 AUT");

  cleaned = cleaned.replace(
    ELPOTOSI_NORMALIZATION_DICTIONARY.regex_patterns.decimal_comma,
    "$1.$2"
  );
  cleaned = cleaned.replace(/[\\/]/g, " ");
  cleaned = cleaned.replace(/\s*&\s*/g, " ");
  cleaned = cleaned.replace(/-/g, " ");
  cleaned = cleaned.replace(/PICK[\s-]?UP/g, "PICKUP");
  cleaned = cleaned.replace(/\bHB\b/g, "HATCHBACK");
  cleaned = cleaned.replace(/\bSW\b/g, "WAGON");
  cleaned = cleaned.replace(/\bPICK\s*UP\b/g, "PICKUP");

  cleaned = cleaned
    .replace(/\bGENERACION\b/g, "GEN")
    .replace(/\bGEN\.?\s*(\d)/g, "GEN $1")
    .replace(/\bGEN\./g, "GEN");

  // NEW: Remove generation/trim prefixes (A7, MK VII, etc.) - GEN already handled above, NUEVO in cleanElPotosiModel
  cleaned = cleaned.replace(/\b(A[4-7]|MK\s*VII?I?|MKVII?I?)\s+/gi, "");

  // NEW: Remove body types from version
  cleaned = cleaned.replace(
    /\b(SEDAN|HATCHBACK|SUV|COUPE|CONVERTIBLE|PICKUP|VAN|WAGON)\b/gi,
    " "
  );

  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeTurboTokens(cleaned);
  cleaned = applyEngineAliases(cleaned);
  cleaned = normalizeCylinders(cleaned);
  cleaned = normalizeTonCapacity(cleaned);
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);
  cleaned = splitConcatenatedLiters(cleaned);
  cleaned = collapseDisplacementArtifacts(cleaned);
  cleaned = normalizeHorsepower(cleaned);

  cleaned = stripTokens(
    cleaned,
    ELPOTOSI_NORMALIZATION_DICTIONARY.transmission_tokens
  );
  cleaned = stripTokens(
    cleaned,
    ELPOTOSI_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio
  );

  // Remove "0 Ton" (useless weight data)
  cleaned = cleaned.replace(/\b0\s*TON\b/gi, "");

  cleaned = cleaned
    .replace(/\b0\s*(P(?:TAS?|TS?|TA)?|PUERTAS?|PTS)\b/g, " ")
    .replace(/\b0(P(?:TAS?|TS?|TA)?|PUERTAS?|PTS)\b/g, " ")
    .replace(/\b0\s*TON(?:ELADAS|S)?\b/g, " ")
    .replace(/\b0TON\b/g, " ");

  if (brand) {
    const normalizedBrand = normalizeText(brand);
    if (normalizedBrand) {
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
    ELPOTOSI_NORMALIZATION_DICTIONARY.regex_patterns.stray_punctuation,
    " "
  );
  cleaned = restoreProtectedTokens(cleaned);
  cleaned = cleaned.replace(
    ELPOTOSI_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces,
    " "
  );
  cleaned = cleaned.replace(
    ELPOTOSI_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces,
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
    /\b0?([23457])(?!\d)\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/
  );
  let doors = "";
  if (doorsMatch) {
    const doorCount = parseInt(doorsMatch[1], 10);
    if (VALID_DOOR_COUNTS.has(doorCount)) {
      doors = `${doorCount}PUERTAS`;
    }
  }

  const occMatch = normalized.match(
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

/**
 * Detecta si un token es una especificación con número
 * Ejemplos: "5PUERTAS", "4CIL", "2.0L", "200HP", "7OCUP"
 */
function isNumericSpecification(token) {
  if (!token || typeof token !== 'string') return false;
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
      const specType = normalized.replace(/^\d+(\.\d+)?/, '');
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

function normalizeMarca(value, originalMarca) {
  const normalized = normalizeText(value);
  if (!normalized) return "";
  return ELPOTOSI_BRAND_ALIASES[normalized] || normalized;
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

/**
 * Normalize modelo field to remove contamination patterns before hash generation
 * Fixes issue where "PICK UP SILVERADO" vs "SILVERADO" create different hashes
 * Enhanced to remove single-letter trim codes and cab type specifications
 */
function normalizeModelo(marca, modelo) {
  if (!modelo || typeof modelo !== "string") return "";

  let normalized = modelo.toUpperCase().trim();
  const marcaUpper = (marca || "").toUpperCase().trim();

  // 1. Remove NUEVO/NUEVA/NEW prefix (already handled in cleanElPotosiModel, but ensuring consistency)
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

function processElPotosiRecord(record) {
  const originalMarca = record.marca;

  const versionOriginal = record.version_original
    ? record.version_original.toString()
    : "";
  const derivedTransmission =
    normalizeTransmission(record.transmision) ||
    inferTransmissionFromVersion(versionOriginal);

  record.transmision = derivedTransmission;

  const { doors, occupants } = extractDoorsAndOccupants(versionOriginal);

  // Normalizar marca con aliases
  const marcaNormalizada = normalizeMarca(record.marca, originalMarca);

  // Limpiar modelo con correcciones
  const modeloLimpio = cleanElPotosiModel(
    record.modelo,
    marcaNormalizada,
    originalMarca
  );
  const modeloFinal = modeloLimpio || normalizeText(record.modelo);

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
    versionOriginal,
    marcaNormalizada || "",
    modeloFinal || ""
  );

  versionLimpia = versionLimpia
    .replace(
      /\b0?([23457])(?!\d)\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/gi,
      " "
    )
    .replace(
      /\b0?\d{1,2}\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX|PASAJEROS?|PAS)\b/gi,
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
      const next = (arr[idx + 1] || "").toUpperCase();
      const prev = (arr[idx - 1] || "").toUpperCase();
      if (
        /^\d+OCUP$/i.test(next) ||
        NUMERIC_CONTEXT_TOKENS.has(next) ||
        NUMERIC_CONTEXT_TOKENS.has(prev)
      ) {
        return;
      }
      if (!doors && !fallbackDoors) {
        const numericValue = parseInt(token, 10);
        if (
          Number.isFinite(numericValue) &&
          VALID_DOOR_COUNTS.has(numericValue)
        ) {
          fallbackDoors = `${numericValue}PUERTAS`;
        }
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
    origen_aseguradora: "ELPOTOSI",
    id_original: record.id_original,
    marca: marcaNormalizada,
    modelo: normalizeModelo(marcaNormalizada, modeloFinal),
    anio: record.anio,
    transmision: record.transmision,
    version_original: versionOriginal,
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
        results.push(processElPotosiRecord(record));
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
  const errorItems = errors.map((error) => ({ json: error }));
  return [...successItems, ...errorItems];
}

const outputItems = normalizeElPotosiRecords(items);
return outputItems;
