# Insurer Normalization Fix Plan

## Global Corrections (apply to all insurers)
- Reorder token protection so `applyProtectedTokens()` runs **before** any digit/letter splitting; this prevents trims like `T5` or `G500` from turning into `T 5` or `G 500` (see `MAPFRE` records such as BMW X4 2016 in `data/pipeline-result/catalogo-maestro.csv`).
- Tighten `normalizeStandaloneLiters()` to only append `L` when the value is 0.5-8.0 and the nearby context is not weight, doors, or identifiers; current output shows impossible values like `9.150L` (ANA) and `17.230L` (QA findings).
- Harden door extraction: only admit {2,3,4,5,7} doors and guard against model numbers being misread as doors. The catalog shows tokens like `335PUERTAS`, `300PUERTAS`, `650PUERTAS`, and even `0PUERTAS` that originate from horsepower or trim codes.
- Scrub duplicated displacement tokens such as `4CIL.0.0L` (seen on PEUGEOT EXPERT TEPEE 2018 in `data/pipeline-result/catalogo-maestro.csv`) by ensuring liter suffix logic does not re-append to cylinder tokens.

---

## ANA
- Carry over QA issues: over-aggressive liter tagging, faulty door extraction, and token protection ordering.
- CSV review highlights:
  - Model numbers are glued to `PUERTAS`, e.g. `CHEVROLET SILVERADO 3500 2022` -> `CHASIS CABINA AUTOMATI 3500PUERTAS` (`data/pipeline-result/catalogo-maestro.csv`).
  - Standalone digits remain in the normalized trim (`350 SPORT AMG ... 5 5PUERTAS`), indicating partial removal of `5P/5PTAS` tokens.
- Fix focus: after the global door guard, ensure any door value pulled from `PTA/PTAS/PUERTAS` is normalized to 2/3/4/5/7 and strip residual digits; review occupant extraction so we either keep `5OCUP` or drop the orphan digit.

## MAPFRE
- Carry over QA issue: protect tokens before transformations to stop `T5`/`28IA` from splitting (e.g., `XDRIVE 28 IA LSLINE TA`).
- CSV review highlights:
  - New trims already normalized still exhibit split alphanumerics (`XDRIVE 28 IA`, `5.6L PERFECTON`), confirming the protection order bug.
  - Door logic occasionally converts series numbers into doors (`335PUERTAS`, various BMW records).
- Fix focus: implement the token protection reorder immediately, then apply the global door guard; watch for special trims ending in `ON` to avoid flagging true names like `PERFECTON` as tonnage.

## ZURICH
- QA flagged potential token/door issues; CSV sample mostly clean but keep an eye on:
  - Residual standalone numbers (`200`, `250`) from power ratings that might be better represented as `HP` tokens.
  - Door guard should still be applied to avoid future regressions.
- Fix focus: adopt global fixes, then audit power token formatting so HP values retain their unit.

## EL POTOSI
- Carry over QA pending items (token order, liters, doors).
- CSV review highlights:
  - `0TON` appears on nearly every Jeep Liberty record (e.g., 2009 SPORT) even though tonnage is unspecified; also `0PUERTAS` shows up on some entries.
  - Standalone `0` tokens surface after normalization.
- Fix focus: adjust tonnage handling to drop zeros, ensure we only keep ton values when meaningful, and apply door guard to prevent zero-door output.

## QUALITAS
- No prior QA analysis; apply global fixes.
- CSV review highlights:
  - Normalized trims preserve literal quotes (`"D" PICK UP DOBLE CABINA`), which should be stripped during cleanup.
  - Excess standalone digits (`1`, `2`, `7`) show the same door/occupant leakage seen elsewhere.
- Fix focus: extend text cleanup to remove stray quotes before tokenization and rely on global guards for doors and liters.

## CHUBB
- No prior QA analysis; apply global fixes.
- CSV review highlights:
  - Duplicate liter patterns appear (`2.0L HDI 4CIL.0.0L TURBO 5PUERTAS`), pointing to a suffix reapply bug we should patch alongside the global fix.
  - Heavy trucks show `3500PUERTAS` or `1500PUERTAS` (e.g., 2002 Silverado Chassis Cab) from series numbers being misread as doors.
  - Many trims end with `DIS`/`CQ` fragments that might be ancillary equipment - confirm whether they should stay or move to an "extras" list.
- Fix focus: prioritize the door guard; review token filters so accessory codes like `DIS`, `CQ`, `CB` are either grouped or dropped according to business rules.

## ATLAS
- No prior QA analysis; apply global fixes.
- CSV review highlights:
  - Same series-to-door bug (`LIMITED 6CIL ... 300PUERTAS` for Chrysler 300, 2012).
  - Some tokens like `00` survive normalization, suggesting leading zeros are not trimmed.
- Fix focus: tighten numeric cleanup to collapse repeated zeros and rely on global door guard.

## AXA
- QA already flagged potential token/door issues.
- CSV review highlights:
  - Stray terminal digits remain (Audi A6 2020 -> `... 2.0L 4`) because `4P`/`4CIL` lose their suffix.
  - Door misreads occur on high-series trims (`330PUERTAS`, `416PUERTAS`).
- Fix focus: after door guard, ensure unit suffixes (`CIL`, `P`) are preserved when splitting tokens so digits do not end up alone.

## BX
- QA pending; apply global fixes.
- CSV review highlights:
  - `650PUERTAS`, `530PUERTAS` etc. (BMW Serie 6 2011) due to series numbers being tagged as doors.
  - Double-liter tokens such as `5.7L5.9L` remain concatenated; decide whether to split into two displacement options or keep the first reading.
- Fix focus: door guard plus a post-processing step that splits concatenated liters on repeated `L` patterns.

## HDI
- QA pending; apply global fixes.
- CSV review highlights:
  - Model numbers leak into doors (`CX TOURING ... 9PUERTAS` for Mazda CX-9 2007).
  - Several records still carry `0TON`, indicating tonnage cleanup is needed here as well.
- Fix focus: apply door guard with explicit exclusion of model digits (CX-9, MX-5, etc.) and share the tonnage fix from El Potosi.

## GNP
- QA pending; apply global fixes.
- CSV review highlights:
  - BMW trims (`335IA`, `325IA`) normalized as `335PUERTAS`, `325PUERTAS`.
  - Standalone high numbers (`2500`, `300`) left in the version, likely from engine or package codes without units.
- Fix focus: door guard to stop hijacking trim numbers, and ensure numeric tokens regain their unit (e.g., append `HP` when value originated from horsepower).

# Next Steps
1. Implement the three global fixes in the shared utilities and roll them out insurer by insurer.
2. For each insurer, re-run normalization on a focused sample from `/data/origin/{insurer}-origin.csv` to confirm doors, liters, and protected tokens behave as expected.
3. Extend insurer-specific cleanup as noted above before we begin code edits.
