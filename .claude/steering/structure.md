# Project Structure Steering Document

## Directory Organization

```
normalizacio-etl/
├── .claude/                          # Claude Code workspace
│   ├── steering/                     # THIS FILE - persistent context
│   │   ├── product.md               # Product vision and objectives
│   │   ├── tech.md                  # Technology decisions
│   │   └── structure.md             # File organization (this file)
│   └── specs/                        # Feature specifications
│       └── correcciones-homologacion/
│           ├── requirements.md
│           ├── design.md
│           └── tasks.md
│
├── src/
│   ├── insurers/                     # Per-insurer ETL modules
│   │   ├── qualitas/
│   │   ├── zurich/
│   │   ├── axa/
│   │   ├── hdı/
│   │   ├── gnp/
│   │   ├── mapfre/
│   │   ├── chubb/
│   │   ├── atlas/
│   │   ├── bx/
│   │   ├── elpotosi/
│   │   └── ana/
│   │
│   ├── supabase/                     # Database layer
│   │   └── funciones-homologacion-actuales.sql
│   │
│   ├── n8n/                          # n8n workflow files
│   │   ├── ETL - Insertar y Actualizar (1).json
│   │   └── Create embeddings and upload.json
│   │
│   ├── inngest/                      # Event processing
│   └── utils/                        # Shared utilities
│
├── correcciones/                     # Documentation and reports
│   ├── correcciones-adicionales-del-cliente.md
│   ├── reporte_normalizacion_ukuvi.md
│   └── REPORTE_PROBLEMAS_ADICIONALES_UKUVI.md
│
├── CLAUDE.md                         # Project-specific Claude guidance
├── data-model.md                     # Data model documentation
├── requirements.txt                  # Python dependencies
├── WARP.md                          # Additional context
└── .env.example                      # Environment configuration template
```

## File Naming Conventions

### Per-Insurer Modules (`src/insurers/[name]/`)
Each insurer directory contains:
```
[name]/
├── [name]-analisis.md                    # Data profiling and field mapping
├── [name]-query-de-extraccion.sql       # SQL extraction query
├── [name]-codigo-de-normalizacion.js    # n8n normalization logic
└── ETL - [Name].json                    # Complete n8n workflow
```

**Examples:**
- `qualitas-analisis.md`, `qualitas-query-de-extraccion.sql`, etc.
- `zurich-analisis.md`, `zurich-query-de-extraccion.sql`, etc.
- Always use lowercase for directory and file names except in `.json` filenames

### SQL Files (`src/supabase/`)
```
funciones-homologacion-actuales.sql      # Main RPC functions
```
- Contains all PostgreSQL stored procedures
- Named with Spanish keywords for consistency
- Use PL/pgSQL for function bodies

### n8n Workflows (`src/n8n/`)
```
ETL - [Process Description].json         # n8n workflow export
```
- English process names
- PascalCase for compound words
- JSON format (n8n export format)

### Documentation Files
```
[name]-[type].md                         # Documentation files
```
- **Types**: analisis, reporte, correcciones, notebook
- **Spanish preference**: Use Spanish for documentation describing business processes
- **English preference**: Use English for technical code comments and specifications

## Code Organization Patterns

### Normalization Code Structure (n8n JavaScript)
```javascript
// 1. Constants & Configuration
const BATCH_SIZE = 5000;
const PROTECTED_HYPHEN_TOKENS = ['A-SPEC', 'TYPE-S', 'S-LINE'];
const MARCA_CONSOLIDATION_MAP = { /* brand mappings */ };

// 2. Helper Functions
function validateRecord(record) { /* ... */ }
function normalizeTransmission(code) { /* ... */ }
function inferTransmissionFromVersion(version) { /* ... */ }
function cleanVersionString(version) { /* ... */ }

// 3. Main Normalization Function
function processRecord(record) {
  // Returns normalized record with all required fields
}

// 4. Batch Processing
const normalizedRecords = records.map(processRecord);
```

### PostgreSQL Function Structure
```sql
-- 1. Helper functions (utilities)
CREATE OR REPLACE FUNCTION normalize_token(token TEXT) RETURNS TEXT AS $$
  -- Token normalization logic
$$;

-- 2. Core matching function
CREATE OR REPLACE FUNCTION calculate_weighted_coverage(...) RETURNS DECIMAL AS $$
  -- Coverage score calculation
$$;

-- 3. Main RPC function
CREATE OR REPLACE FUNCTION procesar_batch_vehiculos(vehiculos_json JSONB)
RETURNS TABLE (...) AS $$
  -- Main processing logic
$$;
```

## Development Workflow

### Working on Normalization (Insurer Fixes)

1. **Analyze**: Read `src/insurers/[name]/[name]-analisis.md` for data profiling
2. **Extract**: Review `src/insurers/[name]/[name]-query-de-extraccion.sql`
3. **Normalize**: Modify `src/insurers/[name]/[name]-codigo-de-normalizacion.js`
4. **Test**: Use sample data from that insurer
5. **Deploy**: Update corresponding n8n workflow and test execution

### Working on Database Logic (Supabase)

1. **Review**: Read existing `src/supabase/funciones-homologacion-actuales.sql`
2. **Modify**: Update PL/pgSQL functions as needed
3. **Test**: Execute against test database
4. **Validate**: Verify with existing data quality tests
5. **Deploy**: Update production Supabase instance

### Adding a New Insurer

1. Create directory: `src/insurers/[new-name]/`
2. Create files:
   - `[new-name]-analisis.md` - Data profiling
   - `[new-name]-query-de-extraccion.sql` - Extraction query
   - `[new-name]-codigo-de-normalizacion.js` - Normalization logic
   - `ETL - [New Name].json` - n8n workflow
3. Add entries to centralized maps in other normalization scripts
4. Create test data and validation queries

## Testing Structure

### Test Organization
```
tests/
├── integration/
│   └── test_*.sql                    # PostgreSQL RPC function tests
├── validation/
│   └── test_*.js                     # Normalization function tests
└── performance/
    └── test_*.sql                    # Benchmark tests
```

### Test Naming Convention
- **Integration tests**: `test_[feature_name]_integration.sql`
- **Validation tests**: `test_[insurer_name]_normalization.js`
- **Performance tests**: `test_[function_name]_performance.sql`

## Key Files

### Critical Files (Modify with Caution)
- `src/supabase/funciones-homologacion-actuales.sql` - Core matching algorithm
- `CLAUDE.md` - Project guidance and patterns

### Configuration Files
- `.env` - Database credentials (not committed, use `.env.example` as template)
- `requirements.txt` - Python dependencies

### Reference Documentation
- `data-model.md` - Entity and field definitions
- `WARP.md` - Additional context and notes
- `correcciones/` - Collected reports and corrections

## Coding Standards

### JavaScript (n8n Normalization Code)
- **Style**: Modern ES6+ syntax
- **Error Handling**: Return structured error objects, never throw in batch processing
- **Constants**: UPPER_SNAKE_CASE for global constants
- **Functions**: camelCase for function names
- **Comments**: Explain WHY, not WHAT - code should be self-documenting

### SQL (PostgreSQL Functions)
- **Style**: PL/pgSQL standard library functions
- **Naming**: snake_case for all identifiers
- **Parameters**: p_ prefix for input parameters (e.g., `p_vehiculos_json`)
- **Comments**: Use SQL comments for complex logic sections
- **Transactions**: Explicit transaction control for data integrity

### Markdown Documentation
- **Language**: Spanish for business/domain documentation, English for technical specs
- **Sections**: Use clear H2/H3 hierarchy
- **Code Blocks**: Use appropriate syntax highlighting (sql, javascript, json)
- **Links**: Reference files relative to project root

## Data Flow Checkpoints

1. **Source Databases** → SQL extraction queries in `src/insurers/[name]/`
2. **n8n Workflows** → JavaScript normalization in n8n Code nodes
3. **Normalized Records** → Batch processing with schema validation
4. **Supabase RPC** → PostgreSQL matching logic in `funciones-homologacion-actuales.sql`
5. **Master Catalog** → `catalogo_homologado` table in Supabase

## Performance Considerations

### Batch Sizing
- **Default**: 5,000 records per batch
- **Rationale**: Balance between memory usage and network efficiency
- **Adjustment**: Can increase to 10,000-50,000 for small datasets, decrease for large sparse batches

### Indexing Strategy
- **GIN index** on `version_tokens_array` for fast token overlap queries
- **B-tree indexes** on `hash_comercial`, `marca`, `modelo`, `anio`
- **Partial indexes** on `activo=true` for active vehicle queries

### Query Optimization
- Use token arrays instead of LIKE searches
- Leverage `hash_comercial` for initial filtering
- Batch similarity calculations with vectorized operations

## Maintenance Tasks

### Regular Monitoring
- Check error logs in n8n workflows
- Review Supabase RPC execution times
- Monitor database growth and storage usage
- Validate token overlap scores across batches

### Data Quality Checks
```sql
-- Record count by insurer
SELECT origen_aseguradora, COUNT(*) FROM catalogo_homologado GROUP BY origen_aseguradora;

-- Vehicles with missing versions
SELECT COUNT(*) FROM catalogo_homologado WHERE version = '';

-- Recent changes
SELECT * FROM catalogo_homologado ORDER BY fecha_actualizacion DESC LIMIT 100;
```

### Updating Normalization Rules
1. Identify issue pattern in source data
2. Document in `[insurer]-analisis.md`
3. Create test cases with failing examples
4. Modify normalization function
5. Verify against test data
6. Deploy to n8n workflow
