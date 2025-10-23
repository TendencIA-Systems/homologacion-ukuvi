# Quick Deployment Checklist - Task 109
## 5-Minute Deployment Guide

**Version**: v2.8.0 FINAL
**Date**: 2025-10-17

---

## Prerequisites (2 minutes)

```bash
# 1. Verify Supabase CLI
supabase --version
# Expected: >= 1.0.0

# 2. Check database connection
supabase link --project-ref [PROJECT_REF]
# Expected: "Linked to project [PROJECT_REF]"

# 3. Verify current directory
pwd
# Expected: /mnt/c/Users/lfern/OneDrive/Escritorio/normalizacio-etl
```

---

## Deployment (2 minutes)

### Option A: Supabase CLI (Recommended)
```bash
# Deploy function
supabase db push

# Verify deployment
supabase db remote status
```

### Option B: SQL Editor (If CLI fails)
1. Open: https://[project-ref].supabase.co/project/[project-ref]/sql
2. Copy: `src/supabase/funciones-homologacion-actuales.sql` (all 629 lines)
3. Paste into SQL Editor
4. Click "Run"
5. Verify: "Success. No rows returned"

---

## Smoke Test (1 minute)

```sql
-- Test with minimal batch (2 records)
SELECT procesar_batch_vehiculos('[
    {
        "hash_comercial": "test_smoke_1",
        "marca": "TOYOTA",
        "modelo": "CAMRY",
        "anio": 2023,
        "transmision": "AUTO",
        "version_limpia": "XLE 203HP 2.5L 4CIL 4PUERTAS",
        "origen_aseguradora": "ZURICH",
        "id_original": "ZUR-SMOKE-001",
        "version_original": "XLE 203HP 2.5L"
    },
    {
        "hash_comercial": "test_smoke_2",
        "marca": "HONDA",
        "modelo": "ACCORD",
        "anio": 2023,
        "transmision": "AUTO",
        "version_limpia": "SPORT 192HP 1.5L TURBO 4CIL 4PUERTAS",
        "origen_aseguradora": "HDI",
        "id_original": "HDI-SMOKE-002",
        "version_original": "SPORT 1.5T CVT"
    }
]'::jsonb);

-- Expected output:
-- insertados | actualizados | skipped | tier1 | tier2 | tier3 | multi_matches | time_ms
-- -----------+--------------+---------+-------+-------+-------+---------------+---------
--          2 |            0 |       0 |     0 |     0 |     0 |             0 |   15-50
```

**Success Criteria**:
- ✅ Function executes without errors
- ✅ 2 records inserted (insertados=2)
- ✅ Processing time < 100ms
- ✅ No ROLLBACK in logs

---

## Verification (30 seconds)

```sql
-- Check function exists
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_name = 'procesar_batch_vehiculos';

-- Expected:
-- routine_name              | routine_type
-- --------------------------+--------------
-- procesar_batch_vehiculos  | FUNCTION

-- Check helper functions (should be 8)
SELECT COUNT(*) AS helper_function_count
FROM information_schema.routines
WHERE routine_name IN (
    'normalize_token',
    'deduplicate_tokens_intelligent',
    'clean_and_tokenize_version',
    'is_minimal_version_match',
    'detect_conflicts',
    'has_different_trims',
    'calculate_weighted_coverage_with_trim_penalty',
    'calculate_jaccard_similarity'
);

-- Expected: 8
```

---

## Rollback (If needed)

```bash
# Immediate rollback via CLI
supabase db remote rollback

# OR manually via SQL Editor:
# 1. Open deployment history
# 2. Find previous version
# 3. Copy and run previous SQL
```

---

## Status Reporting

```bash
# Mark task as complete
echo "✓ Deployment: SQL function updated, smoke test passed (2/2 records)"

# Update task tracker
claude-code-spec-workflow get-tasks correcciones-homologacion 109 --mode complete
```

---

## Next Steps

After successful deployment:
1. **Monitor**: Check logs for 2 hours
2. **Notify**: Inform client of deployment
3. **Proceed**: Move to Task 110 (n8n workflow updates)

---

## Emergency Contacts

- **Supabase Dashboard**: https://[project-ref].supabase.co
- **Database Logs**: Supabase Dashboard → Logs → Database
- **Function Logs**: Search for "BEST_MATCH_EVALUATION"

---

**Deployment Time**: ~5 minutes
**Risk Level**: Low (fully tested, rollback available)
**Impact**: Critical (fixes A-SPEC vs TECH bug)
