# Tasks: Zurich ETL Vehicle Homologation Specification

**Input**: Design documents from `/specs/003-create-the-specification/`
**Prerequisites**: research.md, data-model.md, contracts/, quickstart.md

## Phase 3.1: Setup

- [ ] T001 Create n8n workflow structure for Zurich ETL process
  - Build workflow with nodes: Start → SQL Server (Zurich extraction) → Code (normalization) → HTTP Request (Supabase RPC) → Summary.
  - Name workflow `zurich_etl_workflow` and enable daily schedule.
- [ ] T002 [P] Configure SQL Server connection credentials in n8n
  - Set host, database, username, password, port, encrypt, trustServerCertificate per quickstart Step 1.1.
  - Store credentials in n8n credential manager as `Zurich SQL Server`.
- [ ] T003 [P] Configure Supabase API connection with service role key
  - Create HTTP Request credentials using Supabase service role key and base URL.
  - Expose `procesar_batch_vehiculos` endpoint for RPC calls.

## Phase 3.2: n8n Workflow Implementation

- [ ] T012 SQL extraction query implementation for Zurich database in n8n Microsoft SQL Server node
  - Embed optimized query from quickstart Step 1.2 filtering years 2000–2030 and selecting origen_aseguradora, id_original, marca, modelo, anio, version_original, transmision, activo.
  - Expect ~39,009 records ordered by marca, modelo, anio.
- [ ] T013 Data normalization Code node implementation in `src/n8n/normalization_code_node.js`
  - Implement JavaScript template from quickstart Step 2.2 with `BATCH_SIZE = 5000` and no console logging; return a flat array of `{ json }` items.
  - Inline Zurich normalization dictionary with extended comfort/audio tokens (AA, EE, CD, DVD, GPS, BT, USB, MP3, AM, RA, FX, BOSE, BA, ABS, QC, Q/C, Q.C., VP, PIEL, GAMUZA, CA, C/A, A/C, AC, CE, SQ, CB, SIS/NAV, SIS.NAV., T.S, T.P., FBX).
  - Normalize transmissions to `AUTO`/`MANUAL`, expanding support for codes like MULTITRONIC, STEPTRONIC, GEARTRONIC, STRONIC, SECUENCIAL, DRIVELOGIC, DUALOGIC, SPEEDSHIFT, G‑TRONIC, and 4MATIC, and infer transmission from `version_original` when missing.
  - Include `processZurichRecord`, `createCommercialHash`, `cleanVersionString`, and return `version_original` for traceability.
  - [ ] T014 Version string cleaning logic
    - Strip comfort/security terms from `version_original` to produce `version_limpia`.
    - Remove duplicate model tokens and translate door counts (e.g., `3P`, `3PTAS` → `3PUERTAS`), appending occupant counts (`5OCUP`).
    - Canonicalize drivetrain terminology so variants like `4X4`, `AWD`, `QUATTRO`, `4MATIC`, `FWD`, `RWD`, or `4X2` normalize to `4WD`, `AWD`, `FWD`, or `RWD` before token comparison.
    - Replace body-style abbreviations like `HB`, `TUR`, and `CONV` with full terms (`HATCHBACK`, `TURBO`, `CONVERTIBLE`).
    - Remove stray punctuation (periods or commas not part of numeric values) from the cleaned version.
- [ ] T015 Commercial hash generation implementation (SHA-256 of marca+modelo+anio+transmision)
  - Generate 64-character hex hash using Node `crypto` and enforce uniqueness within each batch.
- [ ] T016 Batch processing logic for managing n8n memory limits (5000 records per batch)
  - Process items in chunks of 5000 and clear processed batches to respect 16MB payload limit.
- [ ] T017 Error handling and validation logic in normalization code
  - Capture validation errors with `codigo_error`, `mensaje`, and original record, following rules in data-model.md.
  - Reject records missing `version_original` or unresolved `transmision` after inference, emitting them with `error: true` in the output array.
- [ ] T018 Deduplication and Supabase batch builder Code node in `src/n8n/supabase_batch_node.js`
  - Drop records flagged with `error: true` and remove duplicates sharing `hash_comercial` and `version_limpia`.
  - Slice remaining records into payloads of 50,000 items for downstream RPC calls.
- [ ] T019 HTTP Request node configuration for Supabase RPC calls
  - Configure POST to `https://<project>.supabase.co/rest/v1/rpc/procesar_batch_vehiculos` with `Authorization: Bearer <service_role_key>` and `Content-Type: application/json`.
  - In the Body tab choose **JSON** and add a single field named `body` with value expression `{{$json.body}}`; this submits `{ "body": { "vehiculos_json": [...] } }` so the RPC receives the expected payload.
  - Send batches of normalized records and handle response statistics.

## Phase 3.3: Supabase Integration

- [ ] T020 Create Supabase RPC function `procesar_batch_vehiculos` in `src/supabase/rpc_functions/procesar_batch_vehiculos.sql`
  - Define SQL function accepting a JSONB payload with a `body.vehiculos_json` array for a single insurer per call, performing upserts into `catalogo_homologado`, persisting `version_tokens`/`version_tokens_array`, and returning summary counts and errors.
- [ ] T021 Implement token-overlap matching algorithm using `version_tokens_array`
  - Tokenize `version_limpia` with `tokenize_version` and compare against stored tokens per `hash_comercial`, measuring overlap ratio (intersection ÷ max token count).
  - Apply dynamic thresholds: ≥ 0.92 when the best match already includes the same insurer in `disponibilidad`, otherwise ≥ 0.50 for other insurers.
- [ ] T022 Hash-based exact matching for existing vehicle records
  - Lookup `hash_comercial`; when match exists, update availability without creating duplicates.
- [ ] T023 Availability JSONB update logic for insurer data
  - Before processing, mark existing entries for the batch's insurer as `disponible:false`.
  - Insert/update `disponibilidad -> <ASEGURADORA>` with JSON object containing `aseguradora`, `id_original`, `version_original`, `disponible`, `confianza_score`, `origen`, and `fecha_actualizacion` fields.
- [ ] T024 Error response formatting and processing statistics
- Return JSON with `status`, `total_procesados`, `registros_creados`, `registros_actualizados`, `registros_homologados`, `duplicados_omitidos`, `registros_invalidos`, and a detailed `errores_detalle` array for failed records.

## Dependencies

- T009-T011 (data models) before T012-T019 (n8n implementation)
- T012 (SQL extraction) blocks T013-T018 (normalization and dedup logic)
- T013-T019 (n8n nodes) before T020-T024 (Supabase integration)
- T020 (RPC function) blocks T021-T024 (homologation logic)

## Notes

- [P] tasks = different files, no dependencies
- `version_limpia` only removes non-technical tokens; technical specs are not extracted
  - Security features and comfort/audio tokens (AA, EE, CD, DVD, GPS, BT, USB, MP3, AM, RA, FX, BOSE, BA, ABS, QC, Q/C, Q.C., VP, PIEL, GAMUZA, CA, C/A, A/C, AC, CE, SQ, CB, SIS/NAV, SIS.NAV., T.S, T.P., FBX) are stripped before appending door and occupant counts (`3PUERTAS`, `5OCUP`)
  - Body-style abbreviations and boosters are expanded (`HB`→`HATCHBACK`, `TUR`→`TURBO`, `CONV`→`CONVERTIBLE`)
  - Transmission inferred from `version_original` when blank, using expanded mapping (MULTITRONIC, STEPTRONIC, GEARTRONIC, STRONIC, SECUENCIAL, DRIVELOGIC, DUALOGIC, SPEEDSHIFT, G‑TRONIC, 4MATIC)
  - Records missing `version_original` or unresolved `transmision` are flagged as validation errors and excluded from RPC payloads
- Duplicates with identical `hash_comercial` and `version_limpia` are removed before RPC batching
- Commercial hash uses SHA-256 of marca+modelo+anio+transmision for cross-insurer matching
- Token-overlap + trigram matching computes combined scores on `version_tokens_array` (0.92 intra-insurer, 0.50 cross-insurer) y siempre selecciona el puntaje más alto por `hash_comercial`
- `disponibilidad` JSONB retains per-insurer metadata: `aseguradora`, `id_original`, `version_original`, `disponible`, `confianza_score`, `origen`, `fecha_actualizacion`
- Target performance: <5 minutes for complete 39K record processing
- Memory management: 5K records per n8n batch, 50K records per Supabase RPC batch
- Each RPC call handles records for a single insurer, and upstream normalization ensures batches are deduplicated

## Success Criteria

- [ ] All 39,009 Zurich records extracted from SQL Server
- [ ] > 95% normalization success rate in n8n Code nodes
- [ ] Commercial hashes generated for all valid records
- [ ] Version strings cleaned of irrelevant tokens
- [ ] Duplicate records removed prior to Supabase batching
- [ ] Token-based matching identifies similar vehicles across insurers
- [ ] Supabase homologation completes without data corruption
- [ ] Processing completes within 5-minute performance target
- [ ] Error handling preserves failed records for manual review
      ana-codigo-de-normalizacion.js
      +264
      -0

/\*\*

- Ana ETL - Normalization Code Node
-
- This script mirrors the Zurich/Qualitas/Chubb normalization flow and is
- intended for execution inside an n8n Code node. It cleans Ana vehicle
- records, infers transmissions, and outputs normalized objects ready for
- Supabase ingestion.
  */
  const crypto = require('crypto');
  // Inlined Ana normalization dictionary
  const ANA_NORMALIZATION_DICTIONARY = {
  // Comfort/Audio features and other non-technical tokens to strip from version
  irrelevant_comfort_audio: [
  'AA', 'EE', 'CD', 'DVD', 'GPS', 'BT', 'USB', 'MP3', 'AM', 'RA', 'FX', 'BOSE',
  'BA', 'ABS', 'QC', 'Q/C', 'Q.C.', 'VP', 'PIEL', 'GAMUZA', 'CA', 'C/A', 'A/C', 'AC', 'CE', 'SQ', 'CB',
  'SIS/NAV', 'SIS.NAV.', 'T.S', 'T.P.', 'FBX', 'NAVI', 'CAM TRAS', 'TBO',
  // Transmission indicators (also removed from version string)
  'STD', 'AUT', 'CVT', 'DSG', 'S TRONIC', 'TIPTRONIC', 'SELESPEED', 'Q-TRONIC', 'DCT',
  'MULTITRONIC', 'STEPTRONIC', 'GEARTRONIC', 'STRONIC', 'SECUENCIAL', 'DRIVELOGIC',
  'DUALOGIC', 'SPEEDSHIFT', 'G-TRONIC', 'G TRONIC', '4MATIC', 'PDK', 'S-TRONIC', 'MULTITRO'
  ],
  // Cylinder normalization mapping
  cylinder_normalization: {
  L3: '3CIL', L4: '4CIL', L5: '5CIL', L6: '6CIL',
  V6: '6CIL', V8: '8CIL', V10: '10CIL', V12: '12CIL', W12: '12CIL',
  H4: '4CIL', H6: '6CIL', I3: '3CIL', I4: '4CIL', I5: '5CIL', I6: '6CIL',
  R3: '3CIL', R4: '4CIL', R6: '6CIL', B4: '4CIL', B6: '6CIL'
  },
  // Transmission normalization mapping
  transmission_normalization: {
  STD: 'MANUAL', MANUAL: 'MANUAL', SECUENCIAL: 'MANUAL', DRIVELOGIC: 'MANUAL', DUALOGIC: 'MANUAL',
  AUT: 'AUTO', AUTO: 'AUTO', CVT: 'AUTO', DSG: 'AUTO', 'S TRONIC': 'AUTO', STRONIC: 'AUTO',
  TIPTRONIC: 'AUTO', SELESPEED: 'AUTO', 'Q-TRONIC': 'AUTO', DCT: 'AUTO', MULTITRONIC: 'AUTO',
  STEPTRONIC: 'AUTO', GEARTRONIC: 'AUTO', SPEEDSHIFT: 'AUTO', 'G-TRONIC': 'AUTO',
  'G TRONIC': 'AUTO', '4MATIC': 'AUTO', PDK: 'AUTO', 'S-TRONIC': 'AUTO', MULTITRO: 'AUTO'
  },
  // Regex patterns used during version cleanup
  regex_patterns: {
  year_codes: /\b(20\d{2})\b/g,
  multiple_spaces: /\s+/g,
  trim_spaces: /^\s+|\s+$/g,
  },
  };
  function normalizeDrivetrain(versionString = '') {
  return versionString
  .replace(/\bALL[-\s]?WHEEL DRIVE\b/g, 'AWD')
  .replace(/\b4MATIC\b/g, 'AWD')
  .replace(/\bQUATTRO\b/g, 'AWD')
  .replace(/\bTRACCION\s+TOTAL\b/g, 'AWD')
  .replace(/\bAWD\b/g, 'AWD')
  .replace(/\b4\s*X\s*4\b/g, '4WD')
  .replace(/\b4\s*WD\b/g, '4WD')
  .replace(/\b4\s*WHEEL DRIVE\b/g, '4WD')
  .replace(/\bTRACCION\s+4X4\b/g, '4WD')
  .replace(/\bFRONT[-\s]?WHEEL DRIVE\b/g, 'FWD')
  .replace(/\bTRACCION\s+DELANTERA\b/g, 'FWD')
  .replace(/\bFWD\b/g, 'FWD')
  .replace(/\bREAR[-\s]?WHEEL DRIVE\b/g, 'RWD')
  .replace(/\bTRACCION\s+TRASERA\b/g, 'RWD')
  .replace(/\b4\s*X\s*2\b/g, 'RWD')
  .replace(/\b2WD\b/g, 'RWD')
  .replace(/\bRWD\b/g, 'RWD');
  }
  /\*\* Normalize cylinder nomenclature */
  function normalizeCylinders(versionString = '') {
  let normalized = versionString;
  Object.entries(ANA_NORMALIZATION_DICTIONARY.cylinder_normalization).forEach(([from, to]) => {
  const regex = new RegExp(`\\b${from}\\s*(?=\\d+\\.\\d+|\\s|$)`, 'gi');
  normalized = normalized.replace(regex, to);
  const regexExact = new RegExp(`\\b${from}\\b`, 'gi');
  normalized = normalized.replace(regexExact, to);
  });
  return normalized;
  }
  /\*\*
- Clean version string by removing comfort/audio features and model tokens
- while preserving technical specs
  _/
  function cleanVersionString(versionString, model = '') {
  if (!versionString || typeof versionString !== 'string') {
  return '';
  }
  let cleaned = versionString.toUpperCase().trim();
  cleaned = normalizeDrivetrain(cleaned);
  // Normalize cylinders first
  cleaned = normalizeCylinders(cleaned);
  // Remove comfort/audio features
  ANA_NORMALIZATION_DICTIONARY.irrelevant_comfort_audio.forEach(spec => {
  const regex = new RegExp(`\\b${spec}\\b`, 'gi');
  cleaned = cleaned.replace(regex, ' ');
  });
  // Remove model token if present in version string
  if (model) {
  const modelRegex = new RegExp(`\\b${model.toUpperCase()}\\b`, 'gi');
  cleaned = cleaned.replace(modelRegex, ' ');
  }
  // Translate body style abbreviations
  cleaned = cleaned.replace(/\bHB\b/g, 'HATCHBACK');
  cleaned = cleaned.replace(/\bTUR\b/g, 'TURBO');
  cleaned = cleaned.replace(/\bCONV\b/g, 'CONVERTIBLE');
  // Remove stray punctuation not tied to numbers
  cleaned = cleaned.replace(/(?<!\d)[\.,]|[\.,](?!\d)/g, ' ');
  // Apply generic cleanup patterns
  Object.values(ANA_NORMALIZATION_DICTIONARY.regex_patterns).forEach(pattern => {
  if (pattern !== ANA_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces &&
  pattern !== ANA_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces) {
  cleaned = cleaned.replace(pattern, ' ');
  }
  });
  cleaned = cleaned.replace(ANA_NORMALIZATION_DICTIONARY.regex_patterns.multiple_spaces, ' ');
  cleaned = cleaned.replace(ANA_NORMALIZATION_DICTIONARY.regex_patterns.trim_spaces, '');
  return cleaned;
  }
  /\*\* Extract door and occupant tokens _/
  function extractDoorsAndOccupants(versionOriginal = '') {
  const doorsMatch = versionOriginal.match(/\b(\d)\s*P(?:TAS?)?\b/i);
  const occMatch = versionOriginal.match(/\b0?(\d+)\s*OCUP?\b/i);
  return {
  doors: doorsMatch ? `${doorsMatch[1]}PUERTAS` : '',
  occupants: occMatch ? `${occMatch[1]}OCUP` : '',
  };
  }
  /** Normalize transmission values to AUTO/MANUAL \*/
  function normalizeTransmission(code) {
  if (!code || typeof code !== 'string') return '';
  const normalized = code.toUpperCase().trim();
  return ANA_NORMALIZATION_DICTIONARY.transmission_normalization[normalized] || normalized;
  }
  /** Infer transmission from version string when missing _/
  function inferTransmissionFromVersion(versionOriginal = '') {
  const version = versionOriginal.toUpperCase();
  for (const code of Object.keys(ANA_NORMALIZATION_DICTIONARY.transmission_normalization)) {
  const regex = new RegExp(`\\b${code}\\b`, 'i');
  if (regex.test(version)) {
  return normalizeTransmission(code);
  }
  }
  return '';
  }
  const BATCH_SIZE = 5000;
  /\*\* Core normalization routine returning raw results and errors _/
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
  /** n8n Code node wrapper \*/
  function normalizeAnaRecords(items = []) {
  const rawRecords = items.map(it => (it && it.json) ? it.json : it);
  const { results, errors } = normalizeAnaData(rawRecords);
  const successItems = results.map(r => ({ json: r }));
  const errorItems = errors.map(e => ({ json: e }));
  return [...successItems, ...errorItems];
  }
  /** Process a single Ana record */
  function processAnaRecord(record) {
  const derivedTransmission =
  normalizeTransmission(record.transmision) || inferTransmissionFromVersion(record.version_original);
  record.transmision = derivedTransmission;
  const { doors, occupants } = extractDoorsAndOccupants(record.version_original || '');
  const validation = validateRecord(record);
  if (!validation.isValid) {
  throw new Error(`Validation failed: ${validation.errors.join(', ')}`);
  }
  let versionLimpia = cleanVersionString(record.version_original || '', record.modelo || '');
  versionLimpia = versionLimpia
  .replace(/\b\d\s*P(?:TAS?)?\b[\.,]?/gi, ' ')
  .replace(/\b0?\d+\s*OCUP?\b[\.,]?/gi, ' ')
  .replace(/\s+/g, ' ')
  .trim();
  versionLimpia = [versionLimpia, doors, occupants].filter(Boolean).join(' ').trim();
  const normalized = {
  origen_aseguradora: 'ANA',
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
  /\*\* Create SHA-256 commercial hash */
  function createCommercialHash(vehicle) {
  const key = [
  vehicle.marca || '',
  vehicle.modelo || '',
  vehicle.anio ? vehicle.anio.toString() : '',
  vehicle.transmision || '',
  ].join('|').toLowerCase().trim();
  return crypto.createHash('sha256').update(key).digest('hex');
  }
  /** Validate minimal fields \*/
  function validateRecord(record) {
  const errors = [];
  if (!record.marca || record.marca.trim() === '') errors.push('marca is required');
  if (!record.modelo || record.modelo.trim() === '') errors.push('modelo is required');
  if (!record.anio || record.anio < 2000 || record.anio > 2030) errors.push('anio must be between 2000-2030');
  if (!record.version_original || record.version_original.trim() === '') errors.push('version is required');
  if (!record.transmision || record.transmision.trim() === '') errors.push('transmision is required');
  return { isValid: errors.length === 0, errors };
  }
  /** Normalize generic text fields \*/
  function normalizeText(value) {
  return value ? value.trim().toUpperCase() : '';
  }
  function categorizeError(error) {
  const message = error.message.toLowerCase();
  if (message.includes('validation')) return 'VALIDATION_ERROR';
  if (message.includes('hash')) return 'HASH_GENERATION_ERROR';
  return 'NORMALIZATION_ERROR';
  }
  // n8n execution: process incoming items and return normalized results
  const outputItems = normalizeAnaRecords(items);
  return outputItems;
