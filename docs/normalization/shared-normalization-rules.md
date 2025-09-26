# Shared Normalization Rules

The goal of this document is to align every insurer normalization script around the same cleaning contract so we can improve match rates and keep consistent quality.

## 1. Mandatory string sanitation
- Normalize to uppercase ASCII/UTF-8, strip leading/trailing whitespace, collapse multiple spaces.
- Replace commas, semicolons, and slashes with spaces unless they are part of a numeric value.
- Remove duplicated model tokens (for example brand/model repeated in version) only after extracting primary specs.
- Canonicalize punctuation: replace hyphen variants with a single hyphen, collapse repeated hyphens, and drop trailing punctuation.
- Before cleaning, protect hyphenated trims such as A-SPEC, S-LINE, M-SPORT, TYPE-S/TYPE-R so they survive separator normalization.

## 2. Transmission handling
- Canonical values: AUTO and MANUAL; map every other alias (CVT, DSG, TIPTRONIC, etc.) to one of these before validation.
- Always infer transmission when the `transmision` field is empty by scanning the version string first, then any segmented fields.
- Map brand aliases to the canonical set by translating CVT, DSG, DCT, TIPTRONIC, and similar tokens to AUTO while keeping manual aliases mapped to MANUAL.
- Every detected transmission token must be removed from the cleaned `version_limpia` to avoid leaking drivetrain clues into matching scores.
- Baseline token list to match and strip (case insensitive, trim punctuation):
  AUT, AUT., AUTO, AUTOTRANS, AUTOM, AUTOMATICO, AUTOMATICA, AUTOMATIC, AUTOMATIZADO, AUTOMATIZADA,
  AT, AT., HYDROMATIC, MULTIDRIVE, CVT, E-CVT, E CVT, IVT, XTRONIC, X-TRONIC, MULTITRONIC,
  STRONIC, S TRONIC, S-TRONIC, S.TRONIC, DSG, DCT, PDK, POWERSHIFT, TIPTRONIC, TIPTRNIC, Q-TRONIC, TOUCHTRONIC,
  STEPTRONIC, GEARTRONIC, SPEEDSHIFT, SELESPEED, SALESPEED, SECUENCIAL, DUALOGIC, DRIVELOGIC, SMG,
  STD, STD., MANUAL, MAN., TM, MECANICO, MECANICA, MECA.
- Log any new transmission tokens per insurer and add them to the shared dictionary before closing the task.

## 3. Engine and fuel terminology
- Normalize displacement to the `#.#L` format with one decimal when possible (for example 1598CC -> 1.6L).
- Normalize cylinder notations (V6, L4, H6, etc.) to `#CIL` and de-duplicate trailing punctuation.
- Map forced-induction tags to a canonical set: TURBO, BITURBO, SUPERCHARGED, DIESEL, DIESEL_TURBO.
- Minimum alias mapping:
  TFSI/T-FSI/T FSI -> TURBO, TSI/T-SI/T SI -> TURBO, FSI TURBO -> TURBO,
  standalone FSI -> FSI (keep as direct-injection spec), GDI -> GDI,
  T-JET/TJET/T JET -> TURBO, ECOBOOST -> TURBO,
  TDI/TDCI/CDI/HDI/BLUETEC -> DIESEL_TURBO,
  HEMI -> HEMI (keep but ensure displacement is preserved separately).
- After translating aliases, ensure the normalized string runs through the shared
  engine-alias pass so `TFSI`, `TSI`, and similar tokens are converted before
  deduplication; this prevents mixed `TFSI`/`TURBO` outputs between insurers.
- Convert decimal turbo tokens like `1.5T` or `2.0T` into `1.5L TURBO` / `2.0L TURBO` when they are the only litre hint; if the same string already carries a dedicated litres token (for example `4L`), emit `3.2 TURBO` to avoid conflicting displacements and rely on the explicit litres value.
- Remove duplicate engine power tokens (HP, HP.) after converting to canonical `###HP`.

## 4. Doors, occupants, and body style
- Standard door token: `#PUERTAS` (no space). Detect variants P, PTA, PTAS, PUERTAS, PUERT.
- Standard occupant token: `#OCUP`. Accept variants OCUP, OCUPANTES, OCUP., PAX, PASAJEROS.
- Body styles should use canonical words: SEDAN, HATCHBACK, COUPE, CONVERTIBLE, PICK UP, SUV, CROSSOVER, VAN, MINIVAN.
- Normalize compact abbreviations: HB -> HATCHBACK, CP -> COUPE, SW -> WAGON, GTI stays GTI if trim, but remove trailing punctuation.

## 5. Drivetrain vocabulary
- Canonical tokens: 4X2, 4X4, 4WD, AWD, FWD, RWD.
- Replace 4X4, 4 X 4, 4WD, AWD, QUATTRO, 4MATIC with 4WD unless an insurer requires a more granular split.
- Replace FWD, DELANTERA with FWD; replace RWD, TRASERA with RWD; map 2WD/4X2 variants to 4X2.
- Remove the drivetrain token from `version_limpia` only if it is already captured in a dedicated field; otherwise keep the canonical token.

## 6. Comfort and irrelevant spec tokens
- Maintain a consolidated array of irrelevant tokens (comfort, audio, safety abbreviations) shared across insurers.
- Always split multi-token groups like AA, A/A, E/E, QC, Q/C, RADIO etc. before filtering.\n- Include language variants such as COMFORT/CONFORT so spelling differences do not leak into version_limpia.
- Leave safety-critical indicators (for example BLINDADO, FLOTILLA, TAXI) unless the business confirms they are non-influential for matching.

## 7. Hash and validation contract
- `hash_comercial` must be SHA-256 over `marca|modelo|anio|transmision` after normalization.
- Validation rules: marca/modelo non-empty, anio within 1990-2035 (extend as business evolves), `version_limpia` non-empty, `transmision` resolved to canonical values.
- Emit structured errors `{ error: true, codigo_error, mensaje, registro_original }` for downstream logging.

## 8. Dataset sampling and QA checkpoints
- For each insurer update, profile at least three 500-row samples: first batch, random sample, high-frequency models.
- Compare before/after coverage in `catalogo_maestro` by counting how many records share the updated hash and insurer code.
- Track the percentage of `disponibilidad` entries with more than one insurer to measure homologation lift.

## 9. Change management
- Append every new token or mapping to the shared dictionary first, then sync the insurer-specific script.
- Document exceptions and temporary insurer-specific rules in the insurer task file so that future cycles know why they exist.
- After delivering changes, run the regression smoke tests (or manual sampling if automation is unavailable) and log evidence in the QA tracker.



