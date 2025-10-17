/**
 * ═══════════════════════════════════════════════════════════════════════════
 * MAPFRE ETL - CÓDIGO DE NORMALIZACIÓN V2.4 FIXED
 * ═══════════════════════════════════════════════════════════════════════════
 * FIXES V2.4:
 * - Agregar normalización de PLAZAS y PASAJEROS a OCUPANTES
 * - Proteger tokens de versión como T5, T6, T7, T8, T9 (trims/versiones)
 * - Agregar RIN (español) a tokens irrelevantes
 * - Agregar AM y FM a tokens de audio irrelevantes
 * - Agregar GEARTR, GEARTRONIC a normalizaciones de transmisión automática
 * - Mejorar extracción de ocupantes para incluir todas las variantes
 * ═══════════════════════════════════════════════════════════════════════════
 */

const crypto = require("crypto");

const BATCH_SIZE = 5000;

// ═══════════════════════════════════════════════════════════════════════════
// CATÁLOGO MAESTRO COMPLETO
// ═══════════════════════════════════════════════════════════════════════════
const CATALOGO_MAESTRO_MARCAS_MODELOS = {
  ACURA: [
    "ADX",
    "ILX",
    "INTEGRA",
    "MDX",
    "NSX",
    "RDX",
    "RL",
    "RLX",
    "TL",
    "TLX",
    "TSX",
    "ZDX",
  ],
  VOLKSWAGEN: [
    "AMAROK",
    "AMAROK ENTRY",
    "ARTEON",
    "ATLAS",
    "BEETLE",
    "BORA",
    "CADDY",
    "CC",
    "CLASICO",
    "CRAFTER",
    "CROSSFOX",
    "DERBY",
    "EOS",
    "EUROVAN",
    "GOLF",
    "GTI",
    "JETTA",
    "PASSAT",
    "POINTER",
    "POLO",
    "RABBIT",
    "ROUTAN",
    "SAVEIRO",
    "SEDAN",
    "SHARAN",
    "T-CROSS",
    "TAOS",
    "TERAMONT",
    "TIGUAN",
    "TOUAREG",
    "TRANSPORTER",
    "UP",
    "VENTO",
    "VIRTUS",
  ],
  JMC: ["BLACK", "EV BLACK", "GRAND AVENUE", "VIGUS", "VIGUS 3"],
  VOLVO: [
    "C30",
    "C40",
    "C70",
    "EX30",
    "EX90",
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
  TOYOTA: [
    "4RUNNER",
    "AVANZA",
    "BZ4X",
    "C-HR",
    "CAMRY",
    "COROLLA",
    "COROLLA CROSS",
    "FJ CRUISER",
    "HIACE",
    "HIGHLANDER",
    "HILUX",
    "LAND CRUISER",
    "PRIUS",
    "RAIZE",
    "RAV4",
    "SEQUOIA",
    "SIENNA",
    "SUPRA",
    "TACOMA",
    "TUNDRA",
    "YARIS",
  ],
  FORD: [
    "BRONCO",
    "BRONCO SPORT",
    "ECOSPORT",
    "EDGE",
    "ESCAPE",
    "EXPEDITION",
    "EXPLORER",
    "F150",
    "F250",
    "F350",
    "FIESTA",
    "FOCUS",
    "FUSION",
    "LOBO",
    "MAVERICK",
    "MUSTANG",
    "RANGER",
    "TERRITORY",
    "TRANSIT",
  ],
  CHEVROLET: [
    "AVEO",
    "BEAT",
    "BLAZER",
    "BOLT",
    "CAMARO",
    "CAPTIVA",
    "CAVALIER",
    "CHEYENNE",
    "COLORADO",
    "CORVETTE",
    "CRUZE",
    "EQUINOX",
    "GROOVE",
    "MALIBU",
    "ONIX",
    "SILVERADO",
    "SONIC",
    "SPARK",
    "SUBURBAN",
    "TAHOE",
    "TRACKER",
    "TRAILBLAZER",
    "TRAVERSE",
    "TRAX",
  ],
  NISSAN: [
    "ALTIMA",
    "ARMADA",
    "FRONTIER",
    "KICKS",
    "LEAF",
    "MARCH",
    "MAXIMA",
    "MURANO",
    "NP300",
    "PATHFINDER",
    "SENTRA",
    "TITAN",
    "URVAN",
    "VERSA",
    "X-TRAIL",
    "XTERRA",
  ],
  HONDA: [
    "ACCORD",
    "BR-V",
    "CITY",
    "CIVIC",
    "CR-V",
    "CR-Z",
    "FIT",
    "HR-V",
    "ODYSSEY",
    "PILOT",
    "RIDGELINE",
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
  KIA: [
    "EV6",
    "FORTE",
    "K3",
    "K4",
    "K900",
    "NIRO",
    "OPTIMA",
    "RIO",
    "SELTOS",
    "SORENTO",
    "SOUL",
    "SPORTAGE",
    "STINGER",
    "TELLURIDE",
  ],
  HYUNDAI: [
    "ACCENT",
    "ELANTRA",
    "GRAND I10",
    "IONIQ",
    "IONIQ 5",
    "PALISADE",
    "SANTA FE",
    "SONATA",
    "TUCSON",
    "VELOSTER",
  ],
  BMW: [
    "118I",
    "120I",
    "125I",
    "218",
    "220I",
    "320I",
    "325I",
    "328I",
    "330I",
    "335I",
    "420I",
    "428I",
    "430I",
    "435I",
    "520I",
    "528I",
    "530I",
    "535I",
    "540I",
    "550I",
    "640I",
    "650I",
    "740I",
    "750I",
    "760I",
    "I3",
    "I4",
    "I5",
    "I7",
    "I8",
    "IX",
    "M2",
    "M3",
    "M4",
    "M5",
    "M6",
    "M8",
    "SERIE 1",
    "SERIE 2",
    "SERIE 3",
    "SERIE 4",
    "SERIE 5",
    "SERIE 6",
    "SERIE 7",
    "SERIE 8",
    "X1",
    "X2",
    "X3",
    "X4",
    "X5",
    "X6",
    "X7",
    "XM",
    "Z3",
    "Z4",
    "Z8",
    "MINI COOPER",
  ],
  "MERCEDES BENZ": [
    "A-180",
    "A-200",
    "A-250",
    "C-180",
    "C-200",
    "C-250",
    "C-300",
    "C-350",
    "C-63",
    "CLA-180",
    "CLA-200",
    "CLA-250",
    "CLE-300",
    "CLK-320",
    "CLK-350",
    "CLS-350",
    "E-200",
    "E-250",
    "E-300",
    "E-350",
    "E-400",
    "E-450",
    "E-500",
    "EQA",
    "EQB",
    "EQC",
    "EQE",
    "EQS",
    "G-500",
    "G-63",
    "GLA-180",
    "GLA-200",
    "GLA-250",
    "GLB-180",
    "GLB-200",
    "GLB-250",
    "GLC-200",
    "GLC-250",
    "GLC-300",
    "GLE-350",
    "GLE-450",
    "GLK-300",
    "GLK-350",
    "GLS-450",
    "GLS-580",
    "S-400",
    "S-450",
    "S-500",
    "S-600",
    "SL-500",
    "SLK-200",
    "SLK-350",
    "SPRINTER",
  ],
  AUDI: [
    "A1",
    "A3",
    "A4",
    "A5",
    "A6",
    "A7",
    "A8",
    "E-TRON",
    "Q2",
    "Q3",
    "Q5",
    "Q6",
    "Q7",
    "Q8",
    "R8",
    "RS3",
    "RS4",
    "RS5",
    "RS6",
    "RS7",
    "RSQ3",
    "RSQ8",
    "S3",
    "S4",
    "S5",
    "S6",
    "S7",
    "S8",
    "SQ5",
    "SQ7",
    "SQ8",
    "TT",
    "TTS",
  ],
  PORSCHE: [
    "718",
    "911",
    "918",
    "BOXSTER",
    "CAYENNE",
    "CAYMAN",
    "MACAN",
    "PANAMERA",
    "TAYCAN",
  ],
  JEEP: [
    "CHEROKEE",
    "COMMANDER",
    "COMPASS",
    "GLADIATOR",
    "GRAND CHEROKEE",
    "GRAND WAGONEER",
    "LIBERTY",
    "PATRIOT",
    "RENEGADE",
    "WAGONEER",
    "WRANGLER",
  ],
  DODGE: [
    "ATTITUDE",
    "AVENGER",
    "CALIBER",
    "CHALLENGER",
    "CHARGER",
    "DAKOTA",
    "DART",
    "DURANGO",
    "JOURNEY",
    "NEON",
    "NITRO",
    "RAM",
    "RAM 700",
    "RAM 1500",
    "RAM 2500",
    "RAM 3500",
    "VIPER",
  ],
  RAM: ["700", "1200", "1500", "2500", "3500", "PROMASTER"],
  CHRYSLER: [
    "200",
    "300",
    "PACIFICA",
    "PT CRUISER",
    "SEBRING",
    "TOWN & COUNTRY",
    "VOYAGER",
  ],
  FIAT: [
    "124",
    "500",
    "500E",
    "500L",
    "500X",
    "600",
    "ARGO",
    "DUCATO",
    "MOBI",
    "PALIO",
    "PULSE",
    "STRADA",
    "UNO",
  ],
  MITSUBISHI: [
    "ASX",
    "ECLIPSE",
    "L200",
    "LANCER",
    "MIRAGE",
    "MONTERO",
    "OUTLANDER",
    "XPANDER",
  ],
  SUBARU: [
    "BRZ",
    "CROSSTREK",
    "FORESTER",
    "IMPREZA",
    "LEGACY",
    "OUTBACK",
    "WRX",
    "XV",
  ],
  SUZUKI: [
    "BALENO",
    "CIAZ",
    "ERTIGA",
    "FRONX",
    "GRAND VITARA",
    "IGNIS",
    "JIMNY",
    "S-CROSS",
    "SWIFT",
    "VITARA",
    "XL7",
  ],
  PEUGEOT: [
    "2008",
    "206",
    "207",
    "208",
    "3008",
    "301",
    "307",
    "308",
    "5008",
    "508",
    "EXPERT",
    "LANDTREK",
    "PARTNER",
    "RIFTER",
  ],
  RENAULT: [
    "ARKANA",
    "CAPTUR",
    "CLIO",
    "DUSTER",
    "FLUENCE",
    "KANGOO",
    "KARDIAN",
    "KOLEOS",
    "KWID",
    "LOGAN",
    "MASTER",
    "MEGANE",
    "OROCH",
    "SANDERO",
    "STEPWAY",
    "TRAFIC",
    "ZOE",
  ],
  SEAT: ["ALHAMBRA", "ARONA", "ATECA", "IBIZA", "LEON", "TARRACO", "TOLEDO"],
  LEXUS: ["ES", "GX", "IS", "LC", "LS", "LX", "NX", "RX", "TX", "UX"],
  INFINITI: [
    "FX35",
    "FX37",
    "FX50",
    "G37",
    "JX35",
    "M37",
    "M56",
    "Q50",
    "Q60",
    "Q70",
    "QX30",
    "QX50",
    "QX55",
    "QX56",
    "QX60",
    "QX70",
    "QX80",
  ],
  CADILLAC: [
    "ATS",
    "CT5-V",
    "CTS",
    "ESCALADE",
    "ESCALADE-V",
    "LYRIQ",
    "OPTIQ",
    "SRX",
    "STS",
    "XT4",
    "XT5",
  ],
  GMC: ["ACADIA", "CANYON", "SIERRA", "TERRAIN", "YUKON"],
  BUICK: [
    "ENCLAVE",
    "ENCORE",
    "ENVISION",
    "ENVISTA",
    "LACROSSE",
    "REGAL",
    "VERANO",
  ],
  LINCOLN: ["AVIATOR", "CORSAIR", "MKC", "MKX", "MKZ", "NAUTILUS", "NAVIGATOR"],
  "ALFA ROMEO": [
    "147",
    "156",
    "159",
    "166",
    "4C",
    "BRERA",
    "GIULIA",
    "GIULIETTA",
    "MITO",
    "SPIDER",
    "STELVIO",
    "TONALE",
  ],
  JAGUAR: ["E-PACE", "F-PACE", "F-TYPE", "I-PACE", "XE", "XF", "XJ", "XK"],
  "LAND ROVER": [
    "DEFENDER",
    "DISCOVERY",
    "DISCOVERY SPORT",
    "EVOQUE",
    "FREELANDER",
    "RANGE ROVER",
    "RANGE ROVER SPORT",
    "RANGE ROVER VELAR",
    "VELAR",
  ],
  MINI: ["COOPER", "COOPER S", "COOPER SE", "COUNTRYMAN", "JOHN COOPER WORKS"],
  TESLA: ["CYBERTRUCK", "MODEL 3", "MODEL S", "MODEL X", "MODEL Y"],
  FERRARI: [
    "296",
    "458",
    "488",
    "812",
    "F8",
    "PORTOFINO",
    "PUROSANGUE",
    "ROMA",
    "SF90",
  ],
  LAMBORGHINI: ["AVENTADOR", "HURACAN", "REVUELTO", "URUS", "VENENO"],
  BENTLEY: [
    "BENTAYGA",
    "CONTINENTAL",
    "CONTINENTAL GT",
    "FLYING SPUR",
    "MULSANNE",
  ],
  "ROLLS ROYCE": ["CULLINAN", "GHOST", "PHANTOM", "SPECTRE", "WRAITH"],
  "ASTON MARTIN": [
    "DB11",
    "DB12",
    "DB9",
    "DBS",
    "DBX",
    "RAPIDE",
    "VANQUISH",
    "VANTAGE",
  ],
  MASERATI: [
    "GHIBLI",
    "GRAN TURISMO",
    "GRECALE",
    "LEVANTE",
    "MC20",
    "QUATTROPORTE",
  ],
  MCLAREN: [
    "540C",
    "570GT",
    "570S",
    "600LT",
    "720S",
    "750S",
    "ARTURA",
    "GT",
    "SENNA",
  ],
  LOTUS: ["ELISE", "EMIRA", "EVORA", "EXIGE"],
  CHIREY: [
    "ARRIZO",
    "ARRIZO 8",
    "OMODA 5",
    "TIGGO",
    "TIGGO 2",
    "TIGGO 4",
    "TIGGO 7",
    "TIGGO 8",
  ],
  JAC: [
    "J2",
    "J4",
    "J7",
    "SEI1",
    "SEI2",
    "SEI3",
    "SEI4",
    "SEI6",
    "SEI7",
    "T6",
    "T8",
  ],
  BYD: ["DOLPHIN", "HAN", "SEAL", "SEALION", "SHARK", "SONG", "TANG", "YUAN"],
  GEELY: [
    "CITYRAY",
    "COOLRAY",
    "EMGRAND",
    "GEOMETRY",
    "GX3",
    "MONJARO",
    "OKAVANGO",
    "STARRAY",
  ],
  OMODA: ["C5", "C7", "E5", "O5"],
  JAECOO: ["7", "8"],
  MG: ["3", "4", "5", "7", "HS", "MG4", "MG5", "ONE", "ZS"],
  DONGFENG: ["CAPTAIN", "RICH 6", "SHINE", "SKYLINE", "T5L", "U-VAN"],
  CHANGAN: ["ALSVIN", "CS35", "CS55", "CS75", "EADO", "HUNTER", "UNI-K"],
  HAVAL: ["H6", "JOLION"],
  "GREAT WALL": [
    "HAVAL H6",
    "HAVAL JOLION",
    "ORA 03",
    "POER",
    "TANK",
    "WINGLE",
  ],
  GWM: ["HAVAL", "HAVAL H6", "HAVAL JOLION", "ORA 03", "POER", "TANK"],
  GAC: ["AION Y", "EMKOO", "EMZOOM", "GN8", "GS8"],
  EXEED: ["LX", "RX", "TXL", "VX"],
  JETOUR: ["DASHING", "X70"],
  BAIC: ["BJ40", "D20", "EU5", "U5", "X35", "X55"],
  SMART: ["FORFOUR", "FORTWO"],
  SKYWELL: ["D11"],
  SEV: ["E-WAN", "FRIDAY"],
  STARVIA: ["EMPOWER", "SAVER"],
  ZACUA: ["M2", "M3", "MX3"],
  VUHL: ["5"],
};

// ═══════════════════════════════════════════════════════════════════════════
// DICCIONARIO DE NORMALIZACIÓN
// ═══════════════════════════════════════════════════════════════════════════
const MAPFRE_NORMALIZATION_DICTIONARY = {
  brand_aliases: {
    "GENERAL MOTORS": "GENERAL MOTORS",
    "MG ROVER": "MG",
    WOLKSWAGEN: "VOLKSWAGEN",
    "WOLKSWAGEN VW": "VOLKSWAGEN",
    "VOLKSWAGEN VW": "VOLKSWAGEN",
    VW: "VOLKSWAGEN",
    "JAC SEI": "JAC",
    "JAC MOTORS": "JAC",
    "JIANGLING MOTORS": "JMC",
    JIANGLING: "JMC",
    "GREAT WALL MOTORS": "GWM",
    "GREAT WALL": "GWM",
    "KIA MOTORS": "KIA",
    "GAC MOTOR": "GAC",
    "GAC MOTORS": "GAC",
    GM: "GMC",
    "CHRYSLER-DODGE": "CHRYSLER",
    "CHRYSLER-DODGE DG": "CHRYSLER",
    "BMW BW": "BMW",
    "BMW MINI": "BMW",
    "BMW-MINI": "BMW",
    MINI: "BMW",
    "MINI COOPER": "BMW",
    MINICOOPER: "BMW",
    "CHEVROLET GM": "GENERAL MOTORS",
  },

  // ACTUALIZADO: Agregar AM, FM, RIN y más especificaciones irrelevantes
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
    "WELTRADIO",
    "WELRADIO",
    "5PLAZAS",
    "7PLAZAS",
    "ACT",
    "ACT.",
    // NUEVOS: Audio y especificaciones de ruedas
    "AM",
    "FM",
    "AM/FM",
    "RIN",
    "RINES",
    "WHEELS",
    "ALLOY",
    "ALEACION",
    "R15",
    "R16",
    "R17",
    "R18",
    "R19",
    "R20",
    "R21",
    "R22",
    "RHYNE",
    "RHYNE SIZE",
  ],

  transmission_tokens_to_strip: [
    "TA",
    "T/A",
    "T A",
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
    "GEARTRONIC", // Ya existía
    "GEARTR", // NUEVO: Agregado como solicitado
    "MULTITRONIC",
    "SPORTSHIFT",
    "S-TRONIC",
    "S TRONIC",
    "STRONIC",
    "TRONIC",
    "Q-TRONIC",
    "Q TRONIC",
    "QTRONIC",
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

  // ACTUALIZADO: Agregar GEARTR y GEARTRONIC
  transmission_normalization: {
    // MANUAL variants
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
    ESTANDAR: "MANUAL",
    STANDARD: "MANUAL",

    // AUTO variants
    AUT: "AUTO",
    "AUT.": "AUTO",
    AUTO: "AUTO",
    AT: "AUTO",
    "AT.": "AUTO",
    TA: "AUTO",
    "T/A": "AUTO",
    "T A": "AUTO",
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
    TRONIC: "AUTO",
    TIPTRONIC: "AUTO",
    STEPTRONIC: "AUTO",
    SELESPEED: "AUTO",
    "Q-TRONIC": "AUTO",
    "Q TRONIC": "AUTO",
    QTRONIC: "AUTO",
    DCT: "AUTO",
    MULTITRONIC: "AUTO",
    GEARTRONIC: "AUTO", // Ya existía
    GEARTR: "AUTO", // NUEVO: Agregado como solicitado
    SPEEDSHIFT: "AUTO",
    SPORTSHIFT: "AUTO",
    POWERSHIFT: "AUTO",
    TORQUEFLITE: "AUTO",
    IVT: "AUTO",
    VARIADOR: "AUTO",
    "VARIADOR CONTINUO": "AUTO",
  },

  regex_patterns: {
    decimal_comma: /(\d),(\d)/g,
    multiple_spaces: /\s+/g,
    trim_spaces: /^\s+|\s+$/g,
    stray_punctuation: /(?<!\d)[\.,;]|[\.,;](?!\d)/g,
  },
};

const NUMERIC_CONTEXT_TOKENS = new Set([
  "OCUP",
  "OCUPANTE",
  "OCUPANTES",
  "OCUPACION",
  "PASAJEROS",
  "PASAJERO",
  "PASAJ",
  "PAS",
  "PASAJE",
  "PLAZA",
  "PLAZAS",
  "PUERTAS",
  "PUERTA",
  "PAX",
  "TON",
  "TONELADAS",
  "TONS",
]);

const RESIDUAL_SINGLE_TOKENS = new Set(["A", "B", "C", "E", "Q", "V", "P"]);

const VALID_DOOR_COUNTS = new Set([2, 3, 4, 5, 7]);

const UNWANTED_MODEL_TOKENS = new Set([
  "NUEVO",
  "NUEVA",
  "NEW",
  "LINEA",
  "PASAJERO",
  "PASAJEROS",
  "PASAJ",
  "PAS",
  "PLAZA",
  "PLAZAS",
]);

const SPECIAL_TRIM_NORMALIZATIONS = [
  { regex: /\bA[\s-]?SPECH\b/gi, replacement: "A-SPEC" },
  { regex: /\bS\s+LSLINE\b/gi, replacement: "S-LINE" },
  { regex: /\bLSLINE\b/gi, replacement: "S-LINE" },
  { regex: /\bLS\s+LINE\b/gi, replacement: "S-LINE" },
  { regex: /\bS\s+LS\s+LINE\b/gi, replacement: "S-LINE" },
];

// ACTUALIZADO: Proteger tokens de versión como T5, T6, T7, T8, T9
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
    regex: /\b(?:S[\s-]?LINE|SLINE|S\s+LINE)\b/gi,
    placeholder: "__MAPFRE_PROTECTED_S_LINE__",
    canonical: "S-LINE",
  },
  {
    regex: /\bMK[\s]?VI\b/gi,
    placeholder: "__MAPFRE_PROTECTED_MK_VI__",
    canonical: "MK VI",
  },
  {
    regex: /\bMK[\s]?VII\b/gi,
    placeholder: "__MAPFRE_PROTECTED_MK_VII__",
    canonical: "MK VII",
  },
  // NUEVOS: Proteger versiones T5, T6, T7, T8, T9
  {
    regex: /\bT5\b/gi,
    placeholder: "__MAPFRE_PROTECTED_T5__",
    canonical: "T5",
  },
  {
    regex: /\bT6\b/gi,
    placeholder: "__MAPFRE_PROTECTED_T6__",
    canonical: "T6",
  },
  {
    regex: /\bT7\b/gi,
    placeholder: "__MAPFRE_PROTECTED_T7__",
    canonical: "T7",
  },
  {
    regex: /\bT8\b/gi,
    placeholder: "__MAPFRE_PROTECTED_T8__",
    canonical: "T8",
  },
  {
    regex: /\bT9\b/gi,
    placeholder: "__MAPFRE_PROTECTED_T9__",
    canonical: "T9",
  },
];

const TRANSMISSION_TOKENS = new Set(
  Object.keys(MAPFRE_NORMALIZATION_DICTIONARY.transmission_normalization)
);

// ═══════════════════════════════════════════════════════════════════════════
// FUNCIONES AUXILIARES
// ═══════════════════════════════════════════════════════════════════════════

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

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
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

function normalizeBrand(value = "") {
  if (!value) return "";
  const normalized = normalizeText(value);
  const mapped = MAPFRE_NORMALIZATION_DICTIONARY.brand_aliases[normalized];
  return (mapped || normalized).trim();
}

function isContaminatedModelToken(token, modeloBase) {
  if (!token || !modeloBase) return false;

  const modeloBaseNorm = normalizeText(modeloBase);
  const tokenNorm = normalizeText(token);

  if (UNWANTED_MODEL_TOKENS.has(tokenNorm)) {
    return true;
  }

  if (tokenNorm === modeloBaseNorm) {
    return false;
  }

  if (
    tokenNorm.startsWith(modeloBaseNorm) &&
    tokenNorm.length > modeloBaseNorm.length
  ) {
    const suffix = tokenNorm.substring(modeloBaseNorm.length);

    const knownTrims = [
      "ADVANCE",
      "TECH",
      "SPORT",
      "BASE",
      "ELITE",
      "LUXURY",
      "PREMIUM",
      "TYPE",
      "ASPEC",
      "A-SPEC",
      "SLINE",
      "S-LINE",
      "LIMITED",
      "PLATINUM",
      "SL",
      "SX",
      "EX",
      "LX",
    ];

    for (const trim of knownTrims) {
      const trimNorm = normalizeText(trim);
      if (suffix.includes(trimNorm) || suffix === trimNorm) {
        return true;
      }
    }
  }

  const contaminatedPatterns = [
    /^MD(ADVANCE|TECH|SPORT|BASE)/,
    /^RD(ADVANCE|TECH|SPORT|BASE)/,
    /^TL(ADVANCE|TECH|SPORT|BASE)/,
    /^NS(ADVANCE|TECH|SPORT|BASE)/,
    /^ZD(ADVANCE|TECH|SPORT|BASE)/,
  ];

  for (const pattern of contaminatedPatterns) {
    if (pattern.test(tokenNorm)) {
      return true;
    }
  }

  return false;
}

function extractBaseModel(modeloContaminado = "", marcaNormalizada = "") {
  if (!modeloContaminado || !marcaNormalizada) return "";

  const modeloNorm = normalizeText(modeloContaminado);

  let cleaned = modeloNorm;
  if (cleaned.startsWith(marcaNormalizada + " ")) {
    cleaned = cleaned.substring(marcaNormalizada.length).trim();
  }

  cleaned = cleaned
    .replace(/\bNUEVA\s+LINEA\b/g, "")
    .replace(/\bLINEA\s+NUEVA\b/g, "")
    .replace(/\bNUEVO\b/g, "")
    .replace(/\bNUEVA\b/g, "")
    .replace(/\bNEW\b/g, "")
    .replace(/\bPASAJEROS?\b/g, "")
    .replace(/\bGENERACION\b/g, "GEN")
    .replace(/\bGEN\.?\s*(\d)/g, "GEN $1")
    .replace(/\bGEN\./g, "GEN");

  if (marcaNormalizada === "FORD") {
    cleaned = cleaned.replace(/([A-Z])[-.](\d+)/g, "$1$2");
  }

  if (marcaNormalizada === "VOLKSWAGEN" && /\bJETTA\b/.test(cleaned)) {
    return "JETTA";
  }

  if (marcaNormalizada === "BMW" && /\bMINI\b/.test(cleaned)) {
    return "MINI COOPER";
  }

  cleaned = cleaned.replace(/\s+/g, " ").trim();

  const modelosCatalogo =
    CATALOGO_MAESTRO_MARCAS_MODELOS[marcaNormalizada] || [];
  const modelosOrdenados = [...modelosCatalogo].sort(
    (a, b) => b.length - a.length
  );

  for (const modeloCatalogo of modelosOrdenados) {
    const modeloCatalogoNorm = normalizeText(modeloCatalogo);

    if (
      cleaned.startsWith(modeloCatalogoNorm + " ") ||
      cleaned === modeloCatalogoNorm
    ) {
      return modeloCatalogo;
    }
  }

  for (const modeloCatalogo of modelosOrdenados) {
    const modeloCatalogoNorm = normalizeText(modeloCatalogo);
    const firstToken = cleaned.split(" ")[0];

    if (firstToken === modeloCatalogoNorm) {
      return modeloCatalogo;
    }
  }

  const tokens = cleaned.split(" ").filter(Boolean);
  if (tokens.length > 0) {
    for (const token of tokens) {
      if (/^\d/.test(token)) continue;
      if (/CIL|HP|TURBO|DOORS|OCUP|PUERTAS/.test(token)) continue;
      if (
        MAPFRE_NORMALIZATION_DICTIONARY.transmission_tokens_to_strip.includes(
          token
        )
      )
        continue;
      if (
        MAPFRE_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.includes(token)
      )
        continue;

      return token;
    }
    return tokens[0];
  }

  return "";
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * CORRECCIÓN ESPECIAL: Mercedes Benz
 * ═══════════════════════════════════════════════════════════════════════════
 */
function processMercedesBenzModel(marca, modelo, version) {
  if (!marca || normalizeText(marca) !== "MERCEDES BENZ") {
    return { modelo, version };
  }

  if (!modelo || !version) {
    return { modelo, version };
  }

  const modeloNorm = normalizeText(modelo);
  const versionNorm = normalizeText(version);

  const mercedesBaseModels = [
    "A",
    "C",
    "E",
    "S",
    "G",
    "B",
    "CLA",
    "CLE",
    "CLS",
    "GLA",
    "GLB",
    "GLC",
    "GLE",
    "GLK",
    "GLS",
    "SL",
    "SLK",
    "SLC",
    "AMG",
    "EQ",
    "EQA",
    "EQB",
    "EQC",
    "EQE",
    "EQS",
    "CLASE A",
    "CLASE C",
    "CLASE E",
    "CLASE S",
    "CLASE G",
    "CLASE B",
  ];

  const isBaseModel = mercedesBaseModels.some(
    (base) => modeloNorm === normalizeText(base)
  );

  if (!isBaseModel) {
    return { modelo, version };
  }

  const numberMatch = versionNorm.match(/^(\d+)\s+(.*)$/);

  if (!numberMatch) {
    return { modelo, version };
  }

  const number = numberMatch[1];
  const remainingVersion = numberMatch[2];

  const newModelo = `${modeloNorm}-${number}`;

  return {
    modelo: newModelo,
    version: remainingVersion.trim(),
  };
}

function reconstructFullVersion(
  modeloOriginal = "",
  versionOriginal = "",
  marcaNormalizada = "",
  modeloBase = ""
) {
  const modeloNorm = normalizeText(modeloOriginal);
  const versionNorm = normalizeText(versionOriginal);
  const modeloBaseNorm = normalizeText(modeloBase);

  let modeloSinMarca = modeloNorm;
  if (modeloSinMarca.startsWith(marcaNormalizada + " ")) {
    modeloSinMarca = modeloSinMarca.substring(marcaNormalizada.length).trim();
  }

  let especsDelModelo = "";
  if (modeloSinMarca.startsWith(modeloBaseNorm + " ")) {
    especsDelModelo = modeloSinMarca.substring(modeloBaseNorm.length).trim();
  } else if (modeloSinMarca === modeloBaseNorm) {
    especsDelModelo = "";
  } else {
    especsDelModelo = modeloSinMarca;
  }

  let versionLimpia = versionNorm;
  const tokensVersion = versionLimpia.split(" ").filter(Boolean);
  const tokensValidosVersion = [];

  for (const token of tokensVersion) {
    if (isContaminatedModelToken(token, modeloBase)) {
      continue;
    }
    tokensValidosVersion.push(token);
  }

  const tokensEspecsModelo = especsDelModelo.split(" ").filter(Boolean);
  const tokensValidosEspecsModelo = [];

  for (const token of tokensEspecsModelo) {
    if (isContaminatedModelToken(token, modeloBase)) {
      continue;
    }
    tokensValidosEspecsModelo.push(token);
  }

  const tokensFinales = [];
  const seen = new Set();

  for (const token of tokensValidosVersion) {
    if (!seen.has(token)) {
      seen.add(token);
      tokensFinales.push(token);
    }
  }

  for (const token of tokensValidosEspecsModelo) {
    if (!seen.has(token)) {
      seen.add(token);
      tokensFinales.push(token);
    }
  }

  return tokensFinales.join(" ");
}

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
    const normalizedSegment = normalizeText(segment);
    if (!normalizedSegment) return;
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
    const regex = new RegExp(`\\b${escapeRegExp(from)}\\b`, "gi");
    normalized = normalized.replace(regex, to);
  });

  return normalized;
}

function normalizeEngineDisplacement(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";
  return versionString
    .replace(/\b(?<!\.)(\d)(\d)L\b/g, "$1.$2L")
    .replace(/\b(?<!\d\.)\d+L\b/g, (match) => `${match.slice(0, -1)}.0L`)
    .replace(/\b(?<!\d\.)\d+\s+L\b/g, (match) => {
      const digits = match.match(/\d+/)[0];
      return `${digits}.0L`;
    });
}

function normalizeStandaloneLiters(versionString = "") {
  if (!versionString || typeof versionString !== "string") return "";

  const collapsed = versionString.replace(
    /\b(\d+(?:\.\d+)?)\s*(?:LTS?|LITROS?|L)\b/gi,
    (_full, liters) => `${liters}L`
  );

  return collapsed.replace(
    /\b(\d+\.\d+)(?=\s|$)(?!\s*(?:L\b|LTS?|LITROS?|T\b|TON|TONELADAS?|TONS?|OCUP|PASAJEROS?|PAS|HP\b|CIL|SERIE|K?G))/gi,
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

function splitConcatenatedLiters(value = "") {
  if (!value || typeof value !== "string") return "";
  return value.replace(/(\d+(?:\.\d+)?L)(\d+(?:\.\d+)?L)/gi, "$1 $2");
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
    /\b(\d+(?:\.\d+)?)\s*TON(?:ELADAS|S)?\b/gi,
    (fullMatch, rawTon) => {
      const tonValue = parseFloat(rawTon);
      if (!Number.isFinite(tonValue) || tonValue <= 0) {
        return " ";
      }
      const formatted = Number.isInteger(tonValue)
        ? tonValue.toString()
        : tonValue.toString();
      return `${formatted}TON`;
    }
  );
}

function stripLeadingPhrases(text, phrases = []) {
  let cleaned = text.trim();
  phrases.forEach((phrase) => {
    if (!phrase) return;
    const normalized = normalizeText(phrase);
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
  cleaned = cleaned.replace(/([A-Z0-9])AUT\b/g, "$1 AUT");
  cleaned = cleaned.replace(/\bAUT(?!O)(?=[A-Z0-9])/g, "AUT ");
  cleaned = cleaned.replace(
    MAPFRE_NORMALIZATION_DICTIONARY.regex_patterns.decimal_comma,
    "$1.$2"
  );

  cleaned = cleaned.replace(/[,/]/g, " ");
  cleaned = cleaned.replace(/-/g, " ");

  // Remove marca and modelo BEFORE splitting letters from numbers to avoid breaking alphanumeric models
  cleaned = stripLeadingPhrases(cleaned, [marca, modelo]);

  cleaned = cleaned.replace(/(\d)([A-Z])/g, "$1 $2");
  cleaned = cleaned.replace(/([A-Z])(\d)/g, "$1 $2");
  cleaned = cleaned.replace(/\bHB\b/g, "HATCHBACK");
  cleaned = cleaned.replace(/\bGW\b/g, "WAGON");
  cleaned = cleaned.replace(/\bPICK\s*UP\b/g, "PICKUP");
  cleaned = cleaned.replace(/\bNUEVA\s+LINEA\b/g, " ");
  cleaned = cleaned.replace(/\bLINEA\s+NUEVA\b/g, " ");
  cleaned = cleaned.replace(/\bNUEVO\b/g, " ");
  cleaned = cleaned.replace(/\bNUEVA\b/g, " ");
  cleaned = cleaned.replace(/\bNEW\b/g, " ");
  cleaned = cleaned.replace(/\bPASAJEROS?\b/g, " ");
  cleaned = cleaned.replace(/\bPLAZAS?\b/g, " ");
  cleaned = cleaned.replace(/\b(V|L|R|H|I|B)\s+(\d{1,2})\b/g, "$1$2");
  cleaned = cleaned.replace(/\b(\d{1,2})\s+CIL\b/g, "$1CIL");
  cleaned = cleaned.replace(/\b(\d+(?:\.\d+)?)\s+L\b/g, "$1L");
  cleaned = cleaned
    .replace(/\bGENERACION\b/g, "GEN")
    .replace(/\bGEN\.?\s*(\d)/g, "GEN $1")
    .replace(/\bGEN\./g, "GEN");

  cleaned = normalizeTonCapacity(cleaned);
  cleaned = normalizeDrivetrain(cleaned);
  cleaned = normalizeCylinders(cleaned);
  cleaned = normalizeEngineDisplacement(cleaned);
  cleaned = normalizeStandaloneLiters(cleaned);
  cleaned = splitConcatenatedLiters(cleaned);
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
  cleaned = cleaned.replace(/\b0\s*TON(?:ELADAS|S)?\b/g, " ");
  cleaned = cleaned.replace(/\b0TON\b/g, " ");
  cleaned = restoreProtectedTokens(cleaned);

  return cleaned;
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * MEJORADA: Extracción de puertas y ocupantes
 * ═══════════════════════════════════════════════════════════════════════════
 * CAMBIOS:
 * - Ahora reconoce PLAZAS como sinónimo de OCUPANTES
 * - Ahora reconoce PASAJE, PASAJERO, PASAJEROS como sinónimo de OCUPANTES
 * - Mantiene todas las variantes existentes
 */
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
    /\b0?(\d{1,2})\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX|PASAJ(?:E|ERO)?S?|PAS|PLAZAS?)\b/
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

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * IMPROVED TRANSMISSION NORMALIZATION
 * ═══════════════════════════════════════════════════════════════════════════
 */
function normalizeTransmission(transmissionCode) {
  if (!transmissionCode || typeof transmissionCode !== "string") return "";

  const normalized = transmissionCode
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toUpperCase()
    .trim();

  if (MAPFRE_NORMALIZATION_DICTIONARY.transmission_normalization[normalized]) {
    return MAPFRE_NORMALIZATION_DICTIONARY.transmission_normalization[
      normalized
    ];
  }

  for (const [token, standardValue] of Object.entries(
    MAPFRE_NORMALIZATION_DICTIONARY.transmission_normalization
  )) {
    if (normalized.includes(token)) {
      return standardValue;
    }
  }

  // MEJORADO: Incluir GEARTR en la detección
  if (
    /\b(AUT|AUTO|AUTOMATIC|CVT|DSG|TRONIC|GEARTR|T\/A|A\/T)\b/.test(normalized)
  ) {
    return "AUTO";
  }
  if (/\b(MAN|MANUAL|STD|MECA|STANDARD|ESTANDAR)\b/.test(normalized)) {
    return "MANUAL";
  }

  if (/\d+AT|A\/T|\dA\b/.test(normalized)) {
    return "AUTO";
  }
  if (/\d+MT|M\/T|\dM\b/.test(normalized)) {
    return "MANUAL";
  }

  return "";
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * IMPROVED TRANSMISSION INFERENCE FROM VERSION
 * ═══════════════════════════════════════════════════════════════════════════
 */
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

  // MEJORADO: Incluir GEARTR en los patrones automáticos
  const autoPatterns = [
    /\bAUTO(?:MATICO|MATICA|MATIC|MATIZADA|MATIZADO)?\b/,
    /\b(?:CVT|DSG|DCT|IVT)\b/,
    /\b(?:TIP|STEP|GEAR|MULTI|SPORT|POWER|TORQUE)TRONIC\b/,
    /\bGEARTR\b/, // NUEVO
    /\bS[\s-]?TRONIC\b/,
    /\bQ[\s-]?TRONIC\b/,
    /\bT\/A\b/,
    /\bA\/T\b/,
    /\b\d+AT\b/,
    /\bVARIADOR\b/,
  ];

  const manualPatterns = [
    /\bMANUAL\b/,
    /\bMECANIC[AO]\b/,
    /\b(?:STD|STANDARD|ESTANDAR)\b/,
    /\bSECUENCIAL\b/,
    /\b\d+MT\b/,
  ];

  for (const pattern of autoPatterns) {
    if (pattern.test(normalized)) {
      return "AUTO";
    }
  }

  for (const pattern of manualPatterns) {
    if (pattern.test(normalized)) {
      return "MANUAL";
    }
  }

  return "";
}

/**
 * Detecta si un token es una especificación con número
 * Ejemplos: "5PUERTAS", "4CIL", "2.0L", "200HP", "7OCUP"
 */
function isNumericSpecification(token) {
  if (!token || typeof token !== "string") return false;
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
      const specType = normalized.replace(/^\d+(\.\d+)?/, "");
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

  // Use intelligent deduplication
  const intelligentDeduped = deduplicateTokens(deduped);
  return intelligentDeduped.join(" ");
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
  if (message.includes("transmission")) return "TRANSMISSION_ERROR";
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

/**
 * ═══════════════════════════════════════════════════════════════════════════
 * FUNCIÓN PRINCIPAL DE PROCESAMIENTO CON VALIDACIÓN ROBUSTA
 * ═══════════════════════════════════════════════════════════════════════════
 */
function processMapfreRecord(record) {
  const parsedSegments = parseMapfreVersionSegments(
    record.version_original || ""
  );

  const transmissionFromSegment =
    normalizeTransmission(parsedSegments.transmissionSegment || "") ||
    inferTransmissionFromVersion(parsedSegments.transmissionSegment || "");

  const transmissionFromField = normalizeTransmission(record.transmision || "");

  const transmissionFromVersion = inferTransmissionFromVersion(
    record.version_original || ""
  );

  let derivedTransmission =
    transmissionFromField || transmissionFromSegment || transmissionFromVersion;

  if (!derivedTransmission) {
    derivedTransmission = "AUTO";
  }

  if (derivedTransmission !== "AUTO" && derivedTransmission !== "MANUAL") {
    const reNormalized = normalizeTransmission(derivedTransmission);
    derivedTransmission = reNormalized || "AUTO";
  }

  if (derivedTransmission.length > 20) {
    derivedTransmission = derivedTransmission.substring(0, 20).trim();
  }

  record.transmision = derivedTransmission;

  const marcaNormalizada = normalizeBrand(record.marca || "");
  const modeloBase = extractBaseModel(record.modelo || "", marcaNormalizada);

  const mercedesProcessed = processMercedesBenzModel(
    marcaNormalizada,
    modeloBase,
    record.version_original || ""
  );
  const modeloFinal = mercedesProcessed.modelo;
  const versionParaProcesar = mercedesProcessed.version;

  const versionCompleta = reconstructFullVersion(
    record.modelo || "",
    versionParaProcesar,
    marcaNormalizada,
    modeloFinal
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
    modelo: modeloFinal,
  });
  if (!validation.isValid) {
    throw new Error(`Validation failed: ${validation.errors.join(", ")}`);
  }

  let versionLimpia = cleanVersionString(
    versionCompleta,
    marcaNormalizada,
    modeloFinal
  );

  versionLimpia = versionLimpia
    .replace(
      /\b0?([23457])(?!\d)\s*(?:P(?:TAS?|TS?|TA)?|PUERTAS?|PTS?)\b/gi,
      " "
    )
    .replace(
      /\b0?\d{1,2}\s*(?:OCUPANTES?|OCUP|OCU|OC|O\.?|PAX|PASAJ(?:E|ERO)?S?|PAS|PLAZAS?)\b/gi,
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
          return;
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

  versionLimpia = dedupeTokens(sanitizedTokens.join(" "));

  const finalDoors = doors || fallbackDoors;
  versionLimpia = [versionLimpia, finalDoors, occupants]
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();

  if (!versionLimpia) {
    throw new Error("Normalization produced empty version_limpia");
  }

  if (
    !derivedTransmission ||
    (derivedTransmission !== "AUTO" && derivedTransmission !== "MANUAL")
  ) {
    throw new Error(
      `Invalid transmission after normalization: '${derivedTransmission}'. Must be AUTO or MANUAL.`
    );
  }

  if (derivedTransmission.length > 20) {
    throw new Error(
      `Transmission exceeds 20 characters: '${derivedTransmission}' (${derivedTransmission.length} chars)`
    );
  }

  const baseNormalized = {
    origen_aseguradora: "MAPFRE",
    id_original: record.id_original,
    marca: marcaNormalizada,
    modelo: normalizeModelo(marcaNormalizada, modeloFinal),
    anio: record.anio,
    transmision: derivedTransmission,
    version_original: record.version_original,
    version_limpia: versionLimpia,
    fecha_procesamiento: new Date().toISOString(),
  };

  const normalized = {
    ...baseNormalized,
    hash_comercial: createCommercialHash(baseNormalized),
  };

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
