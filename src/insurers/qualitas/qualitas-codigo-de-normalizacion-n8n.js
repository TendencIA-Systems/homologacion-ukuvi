// =====================================================
// NORMALIZACIÓN QUALITAS - CATÁLOGO MAESTRO
// Versión: 3.3.1 (JS)
// Fecha: 2025-09-11
// Objetivo: Extracción de TRIM (versión) robusta + prioridad de carrocería WAGON/SPORTWAGEN
//           Devuelve null cuando no hay trim real. Evita que términos
//           de carrocería/servicio/multimedia contaminen 'version'.
//           Prioriza WAGON/SPORTWAGEN sobre heurísticas de puertas.
// =====================================================

const crypto = require("crypto");
const ASEGURADORA = "QUALITAS";

// =====================================================
// UTILIDADES
// =====================================================
function normalizarTexto(texto) {
  if (!texto) return "";
  return texto
    .toString()
    .toUpperCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Z0-9\s\-\/]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function generarHash(...componentes) {
  const texto = componentes
    .filter((c) => c !== undefined && c !== null)
    .join("|")
    .toUpperCase();
  return crypto.createHash("sha256").update(texto).digest("hex");
}

function escapeRegex(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// =====================================================
// DICCIONARIOS MAESTROS
// =====================================================
const MARCAS_SINONIMOS = {
  VOLKSWAGEN: ["VW", "VOLKSWAGEN", "VOLKS WAGEN"],
  "MERCEDES BENZ": [
    "MERCEDES",
    "MERCEDES-BENZ",
    "MERCEDES BENZ",
    "MB",
    "MERCEDEZ",
  ],
  "ALFA ROMEO": ["ALFA ROMEO", "ALFA-ROMEO", "ALFA", "ALFAROMEO"],
  "LAND ROVER": ["LANDROVER", "LAND ROVER", "ROVER", "LAND-ROVER"],
  MINI: ["MINI", "MINI COOPER", "COOPER"],
  CHEVROLET: ["CHEVROLET", "CHEVY", "GM CHEVROLET", "CHEV"],
  GMC: ["GMC", "GM", "GENERAL MOTORS"],
  TESLA: ["TESLA", "TESLA MOTORS", "TESSLA"],
  LINCOLN: ["LINCOLN", "LINCON"],
  CADILLAC: ["CADILLAC", "CADILAC"],
  CHRYSLER: ["CHRYSLER", "CRYSLER", "CRISLER"],
  DODGE: ["DODGE", "DOGDE"],
  FORD: ["FORD", "FORT"],
  JEEP: ["JEEP", "JEEEP", "JEP"],
  RAM: ["RAM", "DODGE RAM"],
  TOYOTA: ["TOYOTA", "TOYOTTA"],
  HONDA: ["HONDA", "JONDA"],
  NISSAN: ["NISSAN", "NISAN", "DATSUN"],
  MAZDA: ["MAZDA", "MATSUDA"],
  MITSUBISHI: ["MITSUBISHI", "MITSIBUSHI", "MITS"],
  SUZUKI: ["SUZUKI", "SUSUKI"],
  SUBARU: ["SUBARU", "SUBAROO"],
  KIA: ["KIA", "KIA MOTORS"],
  HYUNDAI: ["HYUNDAI", "HYNDAI", "HUNDAI"],
  INFINITI: ["INFINITI", "INFINITY"],
  LEXUS: ["LEXUS", "LEXUSS"],
  ACURA: ["ACURA", "ACCURA"],
  "GREAT WALL": ["GREAT WALL", "GREAT WALL MOTORS", "GREATWALL"],
  JAC: ["JAC", "JAC MOTORS"],
  BAIC: ["BAIC", "BAIC MOTOR"],
  MG: ["MG", "MG MOTOR"],
  CHANGAN: ["CHANGAN", "CHANG AN"],
  CHIREY: ["CHIREY", "CHERY"],
  BYD: ["BYD", "BUILD YOUR DREAMS"],
  BMW: ["BMW", "BAYERISCHE MOTOREN WERKE"],
  AUDI: ["AUDI", "AUDII"],
  PORSCHE: ["PORSCHE", "PORCHE", "PORSHE"],
  JAGUAR: ["JAGUAR", "JAGUARR"],
  MASERATI: ["MASERATI", "MASSERATI"],
  FERRARI: ["FERRARI", "FERARI"],
  LAMBORGHINI: ["LAMBORGHINI", "LAMBO"],
  "ROLLS ROYCE": ["ROLLS ROYCE", "ROLLS-ROYCE", "ROLLS"],
  BENTLEY: ["BENTLEY", "BENTLY"],
  MCLAREN: ["MCLAREN", "MC LAREN"],
  VOLVO: ["VOLVO", "VOLVOO"],
  PEUGEOT: ["PEUGEOT", "PEUGOT", "PEUGEOUT"],
  RENAULT: ["RENAULT", "RENOLT", "RENO"],
  FIAT: ["FIAT", "FIATT"],
  SEAT: ["SEAT", "CEAT"],
  CUPRA: ["CUPRA", "CUPRA RACING"],
  SKODA: ["SKODA", "SCODA"],
  SMART: ["SMART", "SMAR"],
  GENESIS: ["GENESIS", "GENISIS"],
  BUICK: ["BUICK", "BUIK"],
};

const CARROCERIA_KEYWORDS = {
  SEDAN: ["SEDAN", "4P", "4 PUERTAS", "4DR", "BERLINA"],
  HATCHBACK: [
    "HATCHBACK",
    "HB",
    "3P",
    "5P",
    "3 PUERTAS",
    "5 PUERTAS",
    "LIFTBACK",
  ],
  SUV: ["SUV", "SPORT UTILITY", "CROSSOVER", "CUV"],
  PICKUP: [
    "PICKUP",
    "PICK UP",
    "PICK-UP",
    "CREW CAB",
    "DOBLE CABINA",
    "CAB REG",
    "CLUB CAB",
    "EXTENDED CAB",
  ],
  COUPE: ["COUPE", "2P", "2 PUERTAS", "2DR", "CUPE"],
  CONVERTIBLE: ["CONVERTIBLE", "CABRIO", "ROADSTER", "DESCAPOTABLE", "CONV"],
  VAN: ["VAN", "MINIVAN", "CARGO", "PANEL"],
  WAGON: [
    "WAGON",
    "ESTATE",
    "FAMILIAR",
    "STATION WAGON",
    "AVANT",
    "TOURING",
    "SPORTWAGEN",
    "SPORT WAGEN",
    "SPORTWAGON",
    "SPORT WAGON",
  ],
  CAMION: ["CHASIS CABINA", "CAMION", "TRUCK"],
};

const TIPOS_TRANSMISION = [
  "SPORTSHIFT",
  "SPORT SHIFT",
  "SHIFTRONIC",
  "SHIFT TRONIC",
  "POWERSHIFT",
  "POWER SHIFT",
  "SELECTSHIFT",
  "SELECT SHIFT",
  "GEARTRONIC",
  "GEAR TRONIC",
  "SPORTMATIC",
  "SPORT MATIC",
  "STEPTRONIC",
  "STEP TRONIC",
  "TIPTRONIC",
  "TIP TRONIC",
  "MULTITRONIC",
  "MULTI TRONIC",
  "DUALOGIC",
  "DUAL LOGIC",
  "EASYTRONIC",
  "EASY TRONIC",
  "ACTIVEMATIC",
  "ACTIVE MATIC",
  "DRIVELOGIC",
  "DRIVE LOGIC",
  "SPORTTRONIC",
  "SPORT TRONIC",
  "S-TRONIC",
  "S TRONIC",
  "STRONIC",
  "G-TRONIC",
  "G TRONIC",
  "GTRONIC",
  "XTRONIC",
  "X TRONIC",
  "7G-TRONIC",
  "9G-TRONIC",
  "DCT",
  "DSG",
  "PDK",
  "AMT",
  "SMG",
  "CVT",
  "CVTF",
  "ECVT",
  "AUTOMATICA",
  "AUTOMATIC",
  "AUTO",
  "AUT",
  "MANUAL",
  "ESTANDAR",
  "STD",
  "EST",
  "MAN",
  "MT",
  "AT",
];

// Catálogo grande de trims conocidos
const VERSIONES_VALIDAS = new Set([
  "TYPE S",
  "TYPE R",
  "TYPE A",
  "S LINE",
  "M SPORT",
  "AMG LINE",
  "RS LINE",
  "R LINE",
  "ST LINE",
  "M PERFORMANCE",
  "AMG",
  "RS",
  "SS",
  "ST",
  "GT",
  "GTI",
  "GTS",
  "GTR",
  "GTE",
  "JOHN COOPER WORKS",
  "JCW",
  "NISMO",
  "TRD PRO",
  "TRD SPORT",
  "TRD OFF-ROAD",
  "SPORT",
  "SPORT PLUS",
  "SPORT DESIGN",
  "SPORT PACKAGE",
  "R-DESIGN",
  "R-DYNAMIC",
  "S-DESIGN",
  "TECHNOLOGY PACKAGE",
  "TECHNOLOGY",
  "TECH PACKAGE",
  "TECH",
  "PREMIUM PACKAGE",
  "PREMIUM",
  "PREMIUM PLUS",
  "A-SPEC",
  "A SPEC",
  "EX-L",
  "X-LINE",
  "GT-LINE",
  "E-TRON",
  "SELECT",
  "DYNAMIC",
  "ADVANCE",
  "ADVANCE PLUS",
  "ELITE",
  "LIMITED",
  "EXCLUSIVE",
  "ULTIMATE",
  "SIGNATURE",
  "AVENIR",
  "TITANIUM",
  "PLATINUM",
  "COMPETITION",
  "VELOCE",
  "QUADRIFOGLIO",
  "QV",
  "TI",
  "SPRINT",
  "ESTREMA",
  "COMPETIZIONE",
  "LUXURY",
  "EXCELLENCE",
  "EXECUTIVE",
  "AVANTGARDE",
  "PROGRESSIVE",
  "AMBITION",
  "LARAMIE",
  "LARAMIE LONGHORN",
  "KING RANCH",
  "LARIAT",
  "RAPTOR",
  "REBEL",
  "SAHARA",
  "RUBICON",
  "TRAIL BOSS",
  "HIGH COUNTRY",
  "Z71",
  "ZR2",
  "DENALI",
  "AT4",
  "RST",
  "LTZ",
  "LT",
  "LS",
  "TRADESMAN",
  "BIG HORN",
  "LONGHORN",
  "TEXAS",
  "POWER WAGON",
  "TREMOR",
  "WILDTRAK",
  "BADLANDS",
  "PRO-4X",
  "PRO-X",
  "MIDNIGHT",
  "PLATINUM RESERVE",
  "WORK TRUCK",
  "WT",
  "CUSTOM",
  "TRAIL",
  "BASE",
  "SE",
  "SEL",
  "SEL PLUS",
  "S",
  "SV",
  "SL",
  "SR",
  "SR5",
  "LE",
  "XLE",
  "XSE",
  "XL",
  "XLT",
  "STX",
  "DX",
  "LX",
  "EX",
  "SI",
  "TOURING",
  "GRAND TOURING",
  "SPORT TOURING",
  "SLE",
  "SLT",
  "TERRAIN",
  "ELEVATION",
  "VALUE",
  "ESSENTIAL",
  "CORE",
  "ESSENCE",
  "PREFERRED",
  "PREFERRED II",
  "ACTIVE",
  "ALLURE",
  "FELINE",
  "GRIFFE",
  "TREND",
  "STYLE",
  "ELEGANCE",
  "INTENS",
  "ZEN",
  "LIFE",
  "EMOTION",
  "REFERENCE",
  "XCELLENCE",
  "FR",
  "CUPRA",
  "TEKNA",
  "ACENTA",
  "VISIA",
  "N-CONNECTA",
  "SPECIAL EDITION",
  "EDICION ESPECIAL",
  "ANNIVERSARY",
  "ANIVERSARIO",
  "BLACK EDITION",
  "DARK EDITION",
  "NIGHT EDITION",
  "MIDNIGHT EDITION",
  "SPORT EDITION",
  "LAUNCH EDITION",
  "FIRST EDITION",
  "LIMITED EDITION",
  "EXCLUSIVE EDITION",
  "AUTOBIOGRAPHY",
  "VOGUE",
  "VELAR",
  "EVOQUE",
  "DISCOVERY",
  "HSE",
  "SVR",
  "SVO",
  "SVX",
  "QUADRA-TRAC",
  "TRAILHAWK",
  "OVERLAND",
  "SUMMIT",
  "COOPER",
  "COUNTRYMAN",
  "CLUBMAN",
  "ICONIC",
  "RESERVE",
  "PERFORMANCE",
  "INDIVIDUAL",
  "INSCRIPTION",
  "MOMENTUM",
  "POLESTAR",
  "WORK",
  "TRABAJO",
  "CARGO",
  "COMMERCIAL",
  "PRO",
  "PRO MASTER",
  "PROMASTER",
]);

// Lista blanca adicional y por marca
const TRIMS_MULTI = new Set([
  "R LINE",
  "R-LINE",
  "WOLFSBURG EDITION",
  "HIGHLINE PLUS",
  "ALLTRACK",
]);
const TRIMS_SINGLE = new Set([
  "SPORT",
  "BASE",
  "GL",
  "GLS",
  "GLI",
  "GTI",
  "GTD",
  "GTE",
  "TRENDLINE",
  "COMFORTLINE",
  "HIGHLINE",
  "WOLFSBURG",
  "ALLTRACK",
]);
const VERSIONES_VALIDAS_POR_MARCA = {
  VOLKSWAGEN: new Set([
    "TRENDLINE",
    "COMFORTLINE",
    "HIGHLINE",
    "R LINE",
    "R-LINE",
    "WOLFSBURG",
    "WOLFSBURG EDITION",
    "ALLTRACK",
    "GLI",
    "GTI",
    "GTD",
    "GTE",
  ]),
};

// Stopwords del dominio que NUNCA son trims
const TOKENS_SERVICIO = new Set([
  "SERVPUB",
  "SERV PUB",
  "SERVICIO PUBLICO",
  "SERV PUBLICO",
]);
const TOKENS_MULTIMEDIA = new Set([
  "RADIO",
  "NAVEGACION",
  "PANTALLA",
  "TOUCH",
  "TOUCHSCREEN",
]);

// =====================================================
// NORMALIZADORES BÁSICOS
// =====================================================
function normalizarMarca(marca) {
  if (!marca) return "";
  const m = normalizarTexto(marca);
  for (const [estandar, sinonimos] of Object.entries(MARCAS_SINONIMOS)) {
    if (sinonimos.some((s) => m === s || m.includes(s))) return estandar;
  }
  if (m === "TRACTOS") return "TRACTOS";
  if (m === "REMOLQUES") return "REMOLQUES";
  if (m.includes("CHASIS CABINA")) return "CHASIS CABINA";
  return m;
}

function normalizarModelo(modelo, marca) {
  if (!modelo) return "";
  let mod = normalizarTexto(modelo);
  const brand = normalizarTexto(marca);
  if (mod.startsWith(brand + " ")) mod = mod.substring(brand.length + 1);
  mod = mod.replace(/^SERIE\s+(\d+)/, "$1 SERIES");
  mod = mod.replace(/^CLASE\s+([A-Z])/, "CLASE $1");
  return mod;
}

function normalizarTransmision(codigoTrans, transmisionValor) {
  if (codigoTrans) {
    const c = String(codigoTrans).toUpperCase();
    if (c === "A" || c === "T") return "AUTO";
    if (c === "S" || c === "M") return "MANUAL";
  }
  if (transmisionValor !== undefined && transmisionValor !== null) {
    const v = Number(transmisionValor);
    if (v === 2) return "AUTO";
    if (v === 1) return "MANUAL";
  }
  return null;
}

function extraerMotorConfig(versionCompleta) {
  if (!versionCompleta) return null;
  const t = versionCompleta.toUpperCase();
  const m = t.match(/\b([VLIHB])(2|3|4|5|6|8|10|12)\b/);
  if (m) return `${m[1]}${m[2]}`;
  if (/\b(ELECTRICO|ELECTRIC|EV)\b/.test(t)) return "ELECTRIC";
  if (/\b(PHEV)\b/.test(t)) return "PHEV";
  if (/\b(MHEV)\b/.test(t)) return "MHEV";
  if (/\b(HYBRID|HIBRIDO|HEV)\b/.test(t)) return "HYBRID";
  return null;
}

// =====================================================
// CARROCERÍA: v3.3.1 (prioridad WAGON/SPORTWAGEN)
// =====================================================
function inferirCarroceria(versionCompleta, modelo) {
  const texto = normalizarTexto(versionCompleta || "");
  const modeloNorm = normalizarTexto(modelo || "");
  if (!texto && !modeloNorm) return null;

  // 1) Señales FUERTES de WAGON primero (return inmediato)
  const WAGON_SYNONYMS = [
    "SPORTWAGEN",
    "SPORT WAGEN",
    "SPORTWAGON",
    "SPORT WAGON",
    "STATION WAGON",
    "WAGON",
    "ESTATE",
    "FAMILIAR",
    "AVANT",
    "TOURING",
  ];
  for (const w of WAGON_SYNONYMS) {
    const re = new RegExp(`(^|\s)${escapeRegex(w)}(\s|$)`);
    if (re.test(texto)) return "WAGON";
  }

  // 2) Señales FUERTES de PICKUP por cabina
  if (
    /(^|\s)(CREW\s*CAB|DOUBLE\s*CAB|EXTENDED\s*CAB|REG(?:ULAR)?\s*CAB|CLUB\s*CAB|SINGLE\s*CAB|DOBLE\s*CABINA|CAB\s*REG|CABINA\s*SENCILLA)(\s|$)/.test(
      texto
    )
  ) {
    return "PICKUP";
  }

  // 3) Coincidencias por diccionario (excluyendo tokens de puertas en esta etapa)
  const DOOR_TOKENS_SEDAN = ["4P", "4 PUERTAS", "4DR"];
  const DOOR_TOKENS_HB = [
    "3P",
    "5P",
    "3 PUERTAS",
    "5 PUERTAS",
    "HB",
    "HATCHBACK",
  ];

  function hasKw(tipo, keywords) {
    const skip = new Set(
      tipo === "SEDAN"
        ? DOOR_TOKENS_SEDAN
        : tipo === "HATCHBACK"
        ? DOOR_TOKENS_HB
        : []
    );
    return keywords.some(
      (kw) =>
        !skip.has(kw) &&
        new RegExp(`(^|\s)${escapeRegex(kw)}(\s|$)`).test(texto)
    );
  }

  // Orden: SUV, COUPE, CONVERTIBLE, VAN, CAMION (HATCHBACK/SEDAN se evalúan con puertas al final)
  const ORDER = ["SUV", "COUPE", "CONVERTIBLE", "VAN", "CAMION"];
  for (const tipo of ORDER) {
    const keywords = CARROCERIA_KEYWORDS[tipo] || [];
    if (hasKw(tipo, keywords)) return tipo;
  }

  // 4) Heurística por puertas (última prioridad)
  if (
    new RegExp(
      `(^|\s)(${DOOR_TOKENS_SEDAN.map(escapeRegex).join("|")})(\s|$)`
    ).test(texto)
  ) {
    return "SEDAN";
  }
  if (
    new RegExp(
      `(^|\s)(${DOOR_TOKENS_HB.map(escapeRegex).join("|")})(\s|$)`
    ).test(texto)
  ) {
    return "HATCHBACK";
  }

  // 5) Fallback por modelo conocido (ligero)
  const SUVS_CONOCIDOS = [
    "CR-V",
    "CRV",
    "RAV4",
    "RAV 4",
    "TUCSON",
    "SPORTAGE",
    "X-TRAIL",
    "XTRAIL",
    "TIGUAN",
    "Q5",
    "Q3",
    "Q7",
    "Q8",
    "X3",
    "X5",
    "X1",
    "X6",
    "X7",
    "EXPLORER",
    "HIGHLANDER",
    "PILOT",
    "TAHOE",
    "SUBURBAN",
    "EXPEDITION",
    "TRAVERSE",
    "EQUINOX",
    "BLAZER",
    "TRAILBLAZER",
    "EDGE",
    "ESCAPE",
    "BRONCO",
    "BRONCO SPORT",
    "4RUNNER",
    "LAND CRUISER",
    "SEQUOIA",
    "PATHFINDER",
    "MURANO",
    "ROGUE",
    "KICKS",
    "JUKE",
    "ARMADA",
    "CX-5",
    "CX-3",
    "CX-30",
    "CX-50",
    "CX-9",
    "CX-90",
    "COMPASS",
    "CHEROKEE",
    "GRAND CHEROKEE",
    "WRANGLER",
    "RENEGADE",
    "DURANGO",
    "JOURNEY",
    "ECOSPORT",
    "KUGA",
    "TERRITORY",
    "GLC",
    "GLE",
    "GLS",
    "GLB",
    "GLA",
    "EQC",
    "EQE",
    "EQS",
    "MACAN",
    "CAYENNE",
    "RDX",
    "MDX",
    "ZDX",
    "ADX",
  ];
  const PICKUPS_CONOCIDAS = [
    "F-150",
    "F150",
    "F-250",
    "F250",
    "F-350",
    "F350",
    "RAM",
    "RAM 1500",
    "RAM 2500",
    "RAM 3500",
    "RAM 700",
    "SILVERADO",
    "SIERRA",
    "TACOMA",
    "HILUX",
    "RANGER",
    "FRONTIER",
    "COLORADO",
    "TUNDRA",
    "TITAN",
    "RIDGELINE",
    "GLADIATOR",
    "LOBO",
    "CHEYENNE",
    "AMAROK",
    "MAVERICK",
    "LIGHTNING",
    "CYBERTRUCK",
    "RIVIAN R1T",
    "HUMMER EV",
  ];
  const SEDANS_CONOCIDOS = [
    "ILX",
    "TLX",
    "RLX",
    "ACCORD",
    "CIVIC",
    "CITY",
    "CAMRY",
    "COROLLA",
    "AVALON",
    "ALTIMA",
    "SENTRA",
    "MAXIMA",
    "JETTA",
    "PASSAT",
    "ARTEON",
    "ELANTRA",
    "SONATA",
    "ACCENT",
  ];

  if (SUVS_CONOCIDOS.some((s) => modeloNorm.includes(normalizarTexto(s))))
    return "SUV";
  if (PICKUPS_CONOCIDAS.some((s) => modeloNorm.includes(normalizarTexto(s))))
    return "PICKUP";
  if (SEDANS_CONOCIDOS.some((s) => modeloNorm === normalizarTexto(s)))
    return "SEDAN";

  return null;
}

function extraerTraccion(versionCompleta) {
  if (!versionCompleta) return null;
  const t = versionCompleta.toUpperCase();
  if (/\b4X4\b/.test(t) || /\b4WD\b/.test(t)) return "4X4";
  if (/\b4X2\b/.test(t) || /\b2WD\b/.test(t)) return "4X2";
  if (/\bAWD\b/.test(t)) return "AWD";
  if (/\bFWD\b/.test(t)) return "FWD";
  if (/\bRWD\b/.test(t)) return "RWD";
  if (/\b(4MATIC|XDRIVE|QUATTRO|4MOTION|ALL4)\b/.test(t)) return "AWD";
  return null;
}

// =====================================================
// EXTRACCIÓN DE TRIM (lista blanca + stopwords + n-gramas)
// =====================================================
function buscarTrim(tokens, marca) {
  const brand = (marca || "").toString().toUpperCase();
  const brandSet = VERSIONES_VALIDAS_POR_MARCA[brand] || new Set();
  const toks = tokens.filter(Boolean);

  // 3-gramas y 2-gramas
  for (let n = 3; n >= 2; n--) {
    for (let i = 0; i <= toks.length - n; i++) {
      const g = toks
        .slice(i, i + n)
        .join(" ")
        .trim();
      if (VERSIONES_VALIDAS.has(g) || TRIMS_MULTI.has(g) || brandSet.has(g))
        return g;
    }
  }
  // Unigramas
  for (const u of toks) {
    if (VERSIONES_VALIDAS.has(u) || TRIMS_SINGLE.has(u) || brandSet.has(u))
      return u;
  }
  return null;
}

function extraerVersion(versionCompleta, marca) {
  if (!versionCompleta) return null;
  let v = normalizarTexto(versionCompleta);

  // Casos triviales sin versión real
  if (
    v === "AUT" ||
    v === "STD" ||
    v === "MANUAL" ||
    v === "AUTO" ||
    /^(AUT|STD|MANUAL|AUTO)[\.,]\s*\d+\s*OCUP/.test(v)
  )
    return null;

  // 1) Ocupantes
  v = v
    .replace(/[\.,]\s*\d+\s*OCUP\.?$/g, "")
    .replace(/\s+\d+\s*OCUP\.?$/g, "")
    .replace(/\s+OCUP$/g, "");

  // 2) Transmisiones (ANTES de parsear)
  for (const t of TIPOS_TRANSMISION)
    v = v.replace(new RegExp(`\\b${escapeRegex(t)}\\b`, "gi"), " ");
  v = v
    .replace(/[\.,]\s*(AUT|STD|MANUAL|AUTO|CVT|MT|AT|MAN)\.?$/gi, "")
    .replace(
      /\s+\d+\s*(VEL|SPEED|VELOCIDADES?|MARCHAS?|CAMBIOS?)(\s+|$)/gi,
      " "
    );

  // 3) Especificaciones técnicas (orden crítico)
  v = v
    // motor + cilindrada
    .replace(/\b[VLI]\d+\s+\d+\.\d+[TL]?\b/g, " ")
    .replace(/\b[VLI]\d+\s+\d+[TL]?\b/g, " ")
    .replace(/\b\d+\.\d+[TL]?\s+[VLI]\d+\b/g, " ")
    // cilindradas decimales o ENTERAS con T|L + decimales sueltos
    .replace(/\b\d+(?:\.\d+)?[TL]\b/g, " ")
    .replace(/\b\d+\.\d+\b/g, " ")
    .replace(/\s+[TL]\b/g, " ")
    // config motor
    .replace(/\b[VLI]\d+\b/g, " ")
    .replace(/\bH\d+\b/g, " ")
    // puertas y tonelaje
    .replace(/\b\d+P\b/g, " ")
    .replace(/\b\d+\s*PUERTAS?\b/g, " ")
    .replace(/\b\d+\s*PTAS?\b/g, " ")
    .replace(/\b\d+(?:\.\d+)?\s*TONS?\b/gi, " ")
    // potencia
    .replace(/\b\d+\s*(HP|PS|KW)\b/gi, " ")
    // tracción
    .replace(
      /\b(4X4|4X2|AWD|FWD|RWD|4WD|2WD|4MATIC|XDRIVE|QUATTRO|4MOTION|ALL4)\b/g,
      " "
    )
    // tecnologías motor
    .replace(
      /\b(TURBO|TBO|BITBO|TDI|TSI|TFSI|FSI|GDI|MHEV|HEV|PHEV|DIESEL|HYBRID|ELECTRICO|ELECTRIC)\b/g,
      " "
    )
    // accesorios/códigos/materiales
    .replace(
      /\b(BA|ABS|AC|AA|EBD|ESP|TCS|VSC|QC|VP|NAVI|GPS|CD|DVD|MP3|USB|BT|BLUETOOTH)\b/g,
      " "
    )
    .replace(/\b(ONSTAR|BEDLINER|LEATHERETTE|PIEL|LEATHER|CLOTH|TELA)\b/g, " ")
    .replace(/\bR\d{2}\b/g, " ")
    .replace(/\b(CAM\s*TRAS|CAM\s*VIS\s*TRAS)\b/g, " ")
    .replace(/\b\d+AC\b/g, " ")
    .replace(/\b(IMP|FBX|FN|RA|DH|CB|CE|CA|CQ)\b/g, " ");

  // 4) Carrocerías → NO deben quedar en 'version'
  v = v
    .replace(
      /\b(SEDAN|HATCHBACK|SUV|PICKUP|COUPE|CONVERTIBLE|VAN|WAGON)\b/g,
      " "
    )
    .replace(/\bSPORT\s*WAGEN\b/g, " ")
    .replace(/\bSPORTWAGEN\b/g, " ")
    .replace(/\bSPORT\s*WAGON\b/g, " ")
    .replace(/\bSPORTWAGON\b/g, " ");

  // 5) Ruido operativo (servicio, multimedia) y códigos con '/'
  for (const tk of TOKENS_SERVICIO)
    v = v.replace(new RegExp(`\\b${escapeRegex(tk)}\\b`, "g"), " ");
  for (const tk of TOKENS_MULTIMEDIA)
    v = v.replace(new RegExp(`\\b${escapeRegex(tk)}\\b`, "g"), " ");
  v = v
    .replace(/\b[VT]\/P\b/g, " ")
    .replace(/\b\/P\b/g, " ")
    .replace(/\bVP\b/g, " ")
    .replace(/\bTP\b/g, " ");

  // 6) Limpieza final → tokens
  v = v
    .replace(/[,.•;:]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (!v) return null;
  const tokens = v.split(" ").filter(Boolean);

  // 7) Lista blanca (multi → single), con catálogo por marca
  const trim = buscarTrim(tokens, marca);
  if (trim) return trim;

  // 8) Gating: si tras limpiar no hay un trim válido, regresamos null
  return null;
}

// =====================================================
// PROCESAMIENTO PRINCIPAL PARA N8N
// =====================================================
function procesarRegistro(registro) {
  const marca = normalizarMarca(registro.marca);
  const modelo = normalizarModelo(registro.modelo, marca);
  const anio = registro.anio != null ? parseInt(registro.anio) : null;
  const transmision = normalizarTransmision(
    registro.transmision_codigo,
    registro.transmision_valor
  );
  const motorConfig = extraerMotorConfig(registro.version_completa);
  const carroceria = inferirCarroceria(registro.version_completa, modelo);
  const traccion = extraerTraccion(registro.version_completa);
  const version = extraerVersion(registro.version_completa, marca);

  const stringComercial = [marca, modelo, anio, transmision]
    .filter(Boolean)
    .join("|");
  const stringTecnico = [
    marca,
    modelo,
    anio,
    transmision,
    version,
    motorConfig,
    carroceria,
    traccion,
  ]
    .filter(Boolean)
    .join("|");

  const hashComercial = generarHash(marca, modelo, anio, transmision);
  const idCanonico = generarHash(
    marca,
    modelo,
    anio,
    transmision,
    version,
    motorConfig,
    carroceria,
    traccion
  );

  return {
    id_canonico: idCanonico,
    hash_comercial: hashComercial,
    string_comercial: stringComercial,
    string_tecnico: stringTecnico,

    marca: marca,
    modelo: modelo,
    anio: anio,
    transmision: transmision,
    version: version, // solo trim cuando existe, si no null
    motor_config: motorConfig,
    carroceria: carroceria,
    traccion: traccion,

    origen_aseguradora: ASEGURADORA,
    id_original: String(registro.id_original),
    version_original: registro.version_completa,
    activo:
      registro.activo === true ||
      String(registro.activo).toLowerCase() === "true" ||
      Number(registro.activo) === 1,
  };
}

// N8N I/O — Function (Run once for all items) o Function Item
const out = [];
for (const item of $input.all()) {
  try {
    out.push({ json: procesarRegistro(item.json) });
  } catch (e) {
    out.push({
      json: { error: true, mensaje: e.message, registro_original: item.json },
    });
  }
}
return out;
