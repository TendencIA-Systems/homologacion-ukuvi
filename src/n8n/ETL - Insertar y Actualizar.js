/**
 * Zurich ETL - Supabase Batch Builder Code Node
 *
 * This script runs inside an n8n Code node and slices normalized Zurich
 * records into payloads for the `procesar_batch_zurich` Supabase RPC.
 * It returns an array of items where each `json` contains the batch
 * payload and metadata for downstream HTTP Request nodes.
 */

const SUPABASE_BATCH_SIZE = 500;

/**
 * Filter out invalid items and remove duplicates based on
 * `hash_comercial` and `version_limpia`.
 * @param {Array<Object>} records
 * @returns {Array<Object>} deduplicated valid records
 */
function filterValidUnique(records = []) {
  const seen = new Set();
  return records.filter((rec) => {
    if (rec.error) return false;
    const key = `${rec.hash_comercial}|${rec.version_limpia}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/**
 * Core batch builder operating on plain objects.
 * @param {Array<Object>} records - Normalized records, may contain {error:true}
 * @returns {Array<Object>} Array of batch payloads
 */
function buildSupabaseBatches(records = []) {
  const uniqueItems = filterValidUnique(records);
  const batches = [];

  for (let i = 0; i < uniqueItems.length; i += SUPABASE_BATCH_SIZE) {
    batches.push({
      vehiculos_json: uniqueItems.slice(i, i + SUPABASE_BATCH_SIZE),
      batch_number: Math.floor(i / SUPABASE_BATCH_SIZE) + 1,
      total_batches: Math.ceil(uniqueItems.length / SUPABASE_BATCH_SIZE),
    });
  }

  return batches;
}

/**
 * n8n wrapper that accepts n8n items and returns an array of `{ json }`
 * objects representing Supabase batch payloads.
 * @param {Array<Object>} items
 * @returns {Array<Object>}
 */
function createSupabaseBatchItems(items = []) {
  const records = items.map((it) => (it && it.json ? it.json : it));
  const batches = buildSupabaseBatches(records);
  return batches.map((b) => ({ json: b }));
}

// n8n execution: create batch payloads and return them
const outputItems = createSupabaseBatchItems(items);
return outputItems;
