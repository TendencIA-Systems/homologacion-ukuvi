# Insurer Normalization Task Template

Use this template whenever we assign an agent to improve or refactor the normalization code of a specific insurer. Copy the checklist into the insurer tracking issue or task file and keep evidence links updated.

## 0. Inputs and references
- QA baseline: qa-analysis.md (focus on engine, transmission, and formatting findings).
- Strategy: PLAN-HOMOLOGACION.md.
- Shared rules: docs/normalization/shared-normalization-rules.md.
- Extraction query: src/insurers/<aseguradora>/<aseguradora>-query-de-extraccion.sql.
- Normalization analysis: src/insurers/<aseguradora>/<aseguradora>-analisis.md.
- Origin data sample: data/origin/<aseguradora>-origin.csv (request a filtered CSV if it is missing).
- Current normalization script: src/insurers/<aseguradora>/<aseguradora>-codigo-de-normalizacion.js.
- Master catalog sample: data/pipeline-result/catalogo_maestro.csv.

## 1. Kick-off checklist
- [ ] Confirm scope with product/QA (fields to prioritize, delivery timeline, acceptance tests).
- [ ] Snapshot current behaviour (sample 50 records, note transmission inference coverage, list of leftover comfort tokens).
- [ ] Log any blockers or data gaps before coding.

## 2. Data profiling
- [ ] Run descriptive stats on the origin CSV (unique transmissions, frequency of engine tags, top comfort tokens).
- [ ] Identify transmission aliases absent from the shared dictionary and document them (include hyphenated variants like S-TRONIC, TOUCHTRONIC, AUTOTRANS, etc.).
- [ ] Detect non-standard separators (commas, slashes, hyphens) and protected trims (A-SPEC, S-LINE, TYPE-S, etc.) that require additional parsing logic.
- [ ] Flag spelling variants for comfort/safety tokens (for example COMFORT vs CONFORT) so the shared dictionary stays aligned.
- [ ] Capture engine injection/turbo patterns (TFSI, T-SI, FSI TURBO, ECOBOOST, etc.) and note whether they already map to the shared alias list.

## 3. Dictionary alignment
- [ ] Update the shared dictionary proposal: list new tokens for transmission, engine, comfort, body style, or occupant/door removal.
- [ ] Validate the new tokens with QA or product and append them to the shared rules document.
- [ ] Record insurer-specific exceptions (e.g., tokens that must stay because they alter trim identity).

## 4. Code changes
- [ ] Normalize input fields (marca/modelo/anio/transmision) using the shared helper functions; keep helper code DRY.
- [ ] Expand transmission inference to cover every alias found in profiling; ensure output values are restricted to the canonical set (AUTO, MANUAL) and that those tokens are stripped from `version_limpia`.
- [ ] Apply the shared cleaning steps in order: sanitize string, protect hyphenated trims, strip irrelevant specs, normalize numeric tokens (`###HP`, `#.#L`, `#CIL`), rebuild version string without transmission tokens.
- [ ] Translate engine aliases after turbo inference (`TFSI`/`TSI` → `TURBO`, `FSI TURBO` → `TURBO`, standalone `FSI` → `FSI`, `GDI` → `GDI`) so scripts share the same output vocabulary.
- [ ] Ensure validation errors use the { error: true, codigo_error, mensaje, registro_original } contract.
- [ ] Guard batch processing to respect BATCH_SIZE = 5000 unless the insurer requires a different limit.

## 5. Regression validation
- [ ] Produce a before/after diff for at least 100 random rows (check transmission fill rate, trimmed version text, new hash stability).
- [ ] Re-run sampling on catalogo_maestro to see how many records now share multiple insurers (expect positive movement or a documented explanation).
- [ ] Confirm that transmission tokens (AUT., S TRONIC, TOUCHTRONIC, etc.) no longer appear inside version_limpia and that doors/occupants use the canonical `#PUERTAS` / `#OCUP` format.
- [ ] Spot-check normalized turbo output: numeric `T` suffixes become `#.#L TURBO` when litres are missing, explicit litres stay untouched (`3.2 TURBO` alongside `4.0L`), and manufacturer tags like `TFSI`/`TSI` are converted consistently across insurers.
- [ ] List any remaining edge cases that require manual homologation or a follow-up story.

## 6. Deliverables
- [ ] Pull request (or script export) with code updates and updated shared documentation.
- [ ] QA evidence (CSV samples, queries, screenshots) attached to the task.
- [ ] Updated insurer status in the tracking table (see section below).

## 7. Tracking table example

| Insurer | Status | Last Update | Transmission Coverage | Notes |
| ------- | ------ | ----------- | --------------------- | ----- |
| ZURICH | In progress | 2025-09-24 | 97% inferred or provided | Needs CVT alias review |
| QUALITAS | Pending | - | - | awaiting assignment |
| MAPFRE | Ready | 2025-09-20 | 100% canonical | Shared dictionary synced |

Duplicate the table per task or maintain a central table if multiple insurers are tracked together.


