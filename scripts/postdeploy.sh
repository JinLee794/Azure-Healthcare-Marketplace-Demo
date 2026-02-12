#!/bin/bash
# postdeploy hook for azd
#
# This script:
# 1. Generates .vscode/mcp.json from the parameterized template
# 2. Uses azd environment outputs (Bicep outputs) to fill in URLs
#
# Bicep outputs available as env vars via azd:
#   SERVICE_APIM_GATEWAY_URL       - APIM gateway base URL
#   SERVICE_NPI_LOOKUP_RESOURCE_NAME - NPI function app resource name

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/mcp.json.template"
OUTPUT="$REPO_ROOT/.vscode/mcp.json"

echo "=============================================="
echo "  Post-Deploy: Generating .vscode/mcp.json"
echo "=============================================="
echo ""

# Sync local env hints from azd outputs for first-run local workflows.
if [ -x "$REPO_ROOT/scripts/sync-local-env-from-azd.sh" ]; then
  echo "Syncing local .env.local from azd outputs..."
  "$REPO_ROOT/scripts/sync-local-env-from-azd.sh" || true
  echo ""
fi

# ---------------------------------------------------------------------------
# Resolve values from azd environment (Bicep outputs are injected as env vars
# during azd hooks). Fall back to `azd env get-value` if not set.
# ---------------------------------------------------------------------------
resolve_value() {
  local var_name="$1"
  local value="${!var_name:-}"
  if [ -z "$value" ]; then
    value=$(azd env get-value "$var_name" 2>/dev/null || true)
  fi
  echo "$value"
}

APIM_GATEWAY_URL="$(resolve_value SERVICE_APIM_GATEWAY_URL)"
NPI_FUNCTION_APP_NAME="$(resolve_value SERVICE_NPI_LOOKUP_RESOURCE_NAME)"

# ---------------------------------------------------------------------------
# Validate required values
# ---------------------------------------------------------------------------
if [ -z "$APIM_GATEWAY_URL" ]; then
  echo "⚠️  WARNING: SERVICE_APIM_GATEWAY_URL not found in azd environment."
  echo "   Run 'azd provision' first, or set it manually:"
  echo "     azd env set SERVICE_APIM_GATEWAY_URL https://<your-apim>.azure-api.net"
  echo ""
  echo "   Skipping .vscode/mcp.json generation."
  exit 0
fi

if [ -z "$NPI_FUNCTION_APP_NAME" ]; then
  echo "⚠️  WARNING: SERVICE_NPI_LOOKUP_RESOURCE_NAME not found. Direct function endpoint will be incomplete."
  NPI_FUNCTION_APP_NAME="<FUNCTION_APP_NAME>"
fi

echo "  APIM Gateway URL:     $APIM_GATEWAY_URL"
echo "  NPI Function App:     $NPI_FUNCTION_APP_NAME"
echo ""

# ---------------------------------------------------------------------------
# Generate .vscode/mcp.json from template
# ---------------------------------------------------------------------------
if [ ! -f "$TEMPLATE" ]; then
  echo "❌ Template not found: $TEMPLATE"
  exit 1
fi

mkdir -p "$REPO_ROOT/.vscode"

sed \
  -e "s|\${APIM_GATEWAY_URL}|${APIM_GATEWAY_URL}|g" \
  -e "s|\${NPI_FUNCTION_APP_NAME}|${NPI_FUNCTION_APP_NAME}|g" \
  "$TEMPLATE" > "$OUTPUT"

echo "✅ Generated $OUTPUT"
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=============================================="
echo "  Post-Deploy Complete"
echo "=============================================="
echo ""
echo "APIM APIs configured via Bicep deployment."
echo "MCP server config written to .vscode/mcp.json"
echo ""
echo "MCP Endpoints (Passthrough - subscription key):"
echo "  - NPI Lookup:        ${APIM_GATEWAY_URL}/mcp-pt/npi/mcp"
echo "  - ICD-10 Validation: ${APIM_GATEWAY_URL}/mcp-pt/icd10/mcp"
echo "  - CMS Coverage:      ${APIM_GATEWAY_URL}/mcp-pt/cms/mcp"
echo "  - FHIR Operations:   ${APIM_GATEWAY_URL}/mcp-pt/fhir/mcp"
echo "  - PubMed:            ${APIM_GATEWAY_URL}/mcp-pt/pubmed/mcp"
echo "  - Clinical Trials:   ${APIM_GATEWAY_URL}/mcp-pt/clinical-trials/mcp"
echo ""
echo "MCP Endpoints (OAuth):"
echo "  - NPI Lookup:        ${APIM_GATEWAY_URL}/mcp/npi/mcp"
echo "  - ICD-10 Validation: ${APIM_GATEWAY_URL}/mcp/icd10/mcp"
echo "  - CMS Coverage:      ${APIM_GATEWAY_URL}/mcp/cms/mcp"
echo "  - FHIR Operations:   ${APIM_GATEWAY_URL}/mcp/fhir/mcp"
echo "  - PubMed:            ${APIM_GATEWAY_URL}/mcp/pubmed/mcp"
echo "  - Clinical Trials:   ${APIM_GATEWAY_URL}/mcp/clinical-trials/mcp"
echo ""
echo "✅ Deployment finished!"
