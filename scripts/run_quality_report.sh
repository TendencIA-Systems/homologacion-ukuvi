#!/bin/bash
# ============================================================================
# Quality Report Generator Wrapper Script
# ============================================================================
# Purpose: Execute quality report SQL and save output to markdown file
# Usage: ./scripts/run_quality_report.sh
# Requirements: Supabase credentials in .env file
# ============================================================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
REPORTS_DIR="$PROJECT_ROOT/reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="$REPORTS_DIR/quality_report_$TIMESTAMP.md"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}Data Quality Report Generator${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# Check if .env file exists
if [ ! -f "$PROJECT_ROOT/.env" ]; then
    echo -e "${RED}Error: .env file not found in project root${NC}"
    echo "Please create .env with Supabase connection details:"
    echo "  SUPABASE_DB_HOST=..."
    echo "  SUPABASE_DB_PORT=..."
    echo "  SUPABASE_DB_NAME=..."
    echo "  SUPABASE_DB_USER=..."
    echo "  SUPABASE_DB_PASSWORD=..."
    exit 1
fi

# Load environment variables
source "$PROJECT_ROOT/.env"

# Validate required variables
if [ -z "$SUPABASE_DB_HOST" ] || [ -z "$SUPABASE_DB_NAME" ] || [ -z "$SUPABASE_DB_USER" ] || [ -z "$SUPABASE_DB_PASSWORD" ]; then
    echo -e "${RED}Error: Missing required Supabase credentials in .env${NC}"
    echo "Required variables: SUPABASE_DB_HOST, SUPABASE_DB_NAME, SUPABASE_DB_USER, SUPABASE_DB_PASSWORD"
    exit 1
fi

# Create reports directory if it doesn't exist
mkdir -p "$REPORTS_DIR"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Reports Directory: $REPORTS_DIR"
echo "  Output File: quality_report_$TIMESTAMP.md"
echo "  Database Host: $SUPABASE_DB_HOST"
echo ""

# Execute SQL report
echo -e "${BLUE}Executing quality report SQL...${NC}"

# Use psql to execute the report and capture output
PGPASSWORD="$SUPABASE_DB_PASSWORD" psql \
    -h "$SUPABASE_DB_HOST" \
    -p "${SUPABASE_DB_PORT:-5432}" \
    -d "$SUPABASE_DB_NAME" \
    -U "$SUPABASE_DB_USER" \
    -f "$SCRIPT_DIR/generate_quality_report.sql" \
    -o "$OUTPUT_FILE" \
    2>&1

# Check if report was generated successfully
if [ $? -eq 0 ] && [ -f "$OUTPUT_FILE" ]; then
    echo ""
    echo -e "${GREEN}✓ Report generated successfully!${NC}"
    echo ""
    echo -e "${YELLOW}Report Details:${NC}"
    echo "  Location: $OUTPUT_FILE"
    echo "  Size: $(du -h "$OUTPUT_FILE" | cut -f1)"
    echo "  Lines: $(wc -l < "$OUTPUT_FILE")"
    echo ""

    # Extract and display summary line
    if grep -q "✓ Quality Report:" "$OUTPUT_FILE"; then
        echo -e "${GREEN}Summary:${NC}"
        grep "✓ Quality Report:" "$OUTPUT_FILE" | sed 's/^[ \t]*//'
        echo ""
    fi

    # Display file path for easy access
    echo -e "${BLUE}View report:${NC}"
    echo "  cat $OUTPUT_FILE"
    echo ""

else
    echo -e "${RED}Error: Failed to generate report${NC}"
    exit 1
fi

echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}Report generation completed${NC}"
echo -e "${GREEN}============================================================================${NC}"
