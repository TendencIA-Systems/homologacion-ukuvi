# Quality Report Scripts

This directory contains scripts for generating comprehensive data quality reports for the vehicle homologation catalog.

## Files

### `generate_quality_report.sql`
Main SQL script that queries `catalogo_homologado` and generates a markdown-formatted quality report with:

- **Executive Summary**: Total records, unique vehicles, transmission coverage
- **Records by Insurer**: Breakdown of all 11 insurers with active/inactive counts
- **Transmission Distribution**: AUTO vs MANUAL counts and percentages
- **Top 20 Brands**: Most common brands by record count
- **Multi-Insurer Coverage**: Distribution showing how many insurers cover each vehicle
- **Version Token Analysis**: Quality metrics for token-based matching
- **Data Quality Indicators**: Pass/fail rates for key data fields
- **Year Distribution**: Vehicle distribution by year ranges
- **Correction Impact Summary**: List of applied normalization fixes
- **Final Summary**: Overall quality metrics with correction percentage

### `run_quality_report.sh`
Bash wrapper script that:
- Loads Supabase credentials from `.env` file
- Creates `reports/` directory if needed
- Executes the SQL report via `psql`
- Saves output to `reports/quality_report_[timestamp].md`
- Displays summary statistics

## Prerequisites

### 1. PostgreSQL Client (psql)
The scripts require `psql` command-line tool to connect to Supabase.

**Installation:**
```bash
# Ubuntu/Debian
sudo apt-get install postgresql-client

# macOS
brew install postgresql

# Windows (via chocolatey)
choco install postgresql
```

### 2. Supabase Credentials
Create a `.env` file in the project root with your Supabase connection details:

```bash
# .env file
SUPABASE_DB_HOST=db.xxxxxxxxxxxxx.supabase.co
SUPABASE_DB_PORT=5432
SUPABASE_DB_NAME=postgres
SUPABASE_DB_USER=postgres
SUPABASE_DB_PASSWORD=your_password_here
```

**Finding your credentials:**
1. Go to Supabase Dashboard → Project Settings → Database
2. Look for "Connection string" section
3. Extract host, port, database, user, and password

## Usage

### Option 1: Using the Wrapper Script (Recommended)

```bash
# From project root
./scripts/run_quality_report.sh
```

This will:
1. Validate your `.env` configuration
2. Create `reports/` directory if needed
3. Execute the SQL report
4. Save output to `reports/quality_report_[timestamp].md`
5. Display a summary

**Example output:**
```
============================================================================
Data Quality Report Generator
============================================================================

Configuration:
  Reports Directory: /path/to/reports
  Output File: quality_report_20250117_143022.md
  Database Host: db.xxxxxxxxxxxxx.supabase.co

Executing quality report SQL...

✓ Report generated successfully!

Report Details:
  Location: /path/to/reports/quality_report_20250117_143022.md
  Size: 24K
  Lines: 487

Summary:
✓ Quality Report: 242,656 total records, 95.7% corrected, 4.3% discarded

View report:
  cat /path/to/reports/quality_report_20250117_143022.md

============================================================================
Report generation completed
============================================================================
```

### Option 2: Direct SQL Execution

If you prefer to run the SQL directly:

```bash
# Using psql
psql -h db.xxxxxxxxxxxxx.supabase.co \
     -p 5432 \
     -d postgres \
     -U postgres \
     -f scripts/generate_quality_report.sql \
     -o reports/quality_report_$(date +%Y%m%d_%H%M%S).md

# Or via Supabase SQL Editor
# Copy contents of generate_quality_report.sql
# Paste into SQL Editor and execute
# Copy output and save as markdown
```

### Option 3: Supabase Dashboard

1. Go to Supabase Dashboard → SQL Editor
2. Copy the contents of `generate_quality_report.sql`
3. Paste and execute
4. Copy the output from the Results panel
5. Save to a file: `reports/quality_report_[timestamp].md`

## Report Output Structure

The generated report includes these sections:

```markdown
# Data Quality Report - Homologation Catalog
Generated: 2025-01-17 14:30:22

## Executive Summary
- Total Records: 242,656
- Unique Vehicles: 45,123
- Transmission Coverage: 95.7%

## Records by Insurer
| Insurer | Total Records | % of Catalog | ...
|---------|---------------|--------------|

## Transmission Distribution
| Transmission Type | Count | Percentage | Visual |
|-------------------|-------|------------|--------|

## Top 20 Brands by Record Count
| Rank | Brand | Records | % of Catalog |
|------|-------|---------|--------------|

## Multi-Insurer Coverage Distribution
| Insurers | Records | % of Catalog | ...
|----------|---------|--------------|

## Final Quality Report Summary
✓ Quality Report: 242,656 total records, 95.7% corrected, 4.3% discarded
```

## Troubleshooting

### Error: .env file not found
```bash
# Create .env file in project root
cp .env.example .env
# Edit with your Supabase credentials
nano .env
```

### Error: psql command not found
```bash
# Install PostgreSQL client
sudo apt-get install postgresql-client  # Ubuntu/Debian
brew install postgresql                  # macOS
```

### Error: Connection refused
- Check that your Supabase project is active
- Verify the host, port, and credentials in `.env`
- Ensure your IP is whitelisted in Supabase (if IP restrictions are enabled)

### Error: Permission denied
```bash
# Make script executable
chmod +x scripts/run_quality_report.sh
```

## Automation

### Schedule Regular Reports

You can automate report generation using cron (Linux/macOS):

```bash
# Edit crontab
crontab -e

# Add daily report at 2 AM
0 2 * * * cd /path/to/normalizacio-etl && ./scripts/run_quality_report.sh >> logs/quality_reports.log 2>&1
```

### CI/CD Integration

For continuous monitoring, add to your CI pipeline:

```yaml
# GitHub Actions example
- name: Generate Quality Report
  run: |
    ./scripts/run_quality_report.sh

- name: Upload Report
  uses: actions/upload-artifact@v3
  with:
    name: quality-report
    path: reports/quality_report_*.md
```

## Interpreting Results

### Expected Values (Post-Correction)

- **Total Records**: ~240,000-250,000
- **Insurers**: Exactly 11 (Qualitas, HDI, AXA, GNP, Mapfre, Chubb, Zurich, Atlas, BX, El Potosi, ANA)
- **Transmission Coverage**: >95% (records with AUTO or MANUAL)
- **Top Brands**: NISSAN, CHEVROLET, VOLKSWAGEN, FORD, TOYOTA typically in top 5
- **Multi-Insurer Coverage**: 40-50% of records matched across 2+ insurers

### Quality Indicators

**Good:**
- Hash Comercial Populated: 100%
- Version Not Empty: >99%
- Valid Year Range: 100%
- Transmission Coverage: >95%

**Needs Investigation:**
- Transmission Coverage <90%: Check normalization scripts
- Brand/Model Coverage <100%: Check extraction queries
- Low multi-insurer matching (<30%): Review similarity thresholds

## Related Documentation

- **Main README**: `/README.md` - Project overview
- **CLAUDE.md**: `/CLAUDE.md` - Architecture and development guide
- **Normalization Scripts**: `/src/insurers/[name]/` - Per-insurer processing logic
- **SQL Functions**: `/src/supabase/funciones-homologacion-actuales.sql` - Database functions

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review logs in `logs/quality_reports.log` (if automated)
3. Consult `/CLAUDE.md` for architecture details
4. Check Supabase logs in the dashboard
