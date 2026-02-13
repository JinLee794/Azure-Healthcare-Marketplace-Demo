#!/bin/bash
# postdeploy hook for azd
#
# This script generates `.vscode/mcp.json` using azd environment outputs
# (Bicep outputs) to fill in URLs.
#
# Bicep outputs available as env vars via azd:
#   SERVICE_APIM_GATEWAY_URL                    - APIM gateway base URL
#   SERVICE_MCP_REFERENCE_DATA_RESOURCE_NAME    - Function App name
#   SERVICE_MCP_CLINICAL_RESEARCH_RESOURCE_NAME - Function App name
#   SERVICE_COSMOS_RAG_RESOURCE_NAME            - Function App name

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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
REFERENCE_DATA_FUNCTION_APP_NAME="$(resolve_value SERVICE_MCP_REFERENCE_DATA_RESOURCE_NAME)"

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

echo "  APIM Gateway URL:     $APIM_GATEWAY_URL"
echo "  Ref Data Function App:${REFERENCE_DATA_FUNCTION_APP_NAME:-<unknown>}"
echo ""

# ---------------------------------------------------------------------------
# Generate .vscode/mcp.json
# ---------------------------------------------------------------------------
mkdir -p "$REPO_ROOT/.vscode"

cat > "$OUTPUT" <<EOF
{
  "inputs": [
    {
      "id": "apimSubscriptionKey",
      "type": "promptString",
      "description": "APIM subscription key for MCP passthrough (/mcp-pt)",
      "password": true
    }
  ],
  "servers": {
    "local-reference-data": { "type": "http", "url": "http://localhost:7071/mcp" },
    "local-clinical-research": { "type": "http", "url": "http://localhost:7072/mcp" },
    "local-cosmos-rag": { "type": "http", "url": "http://localhost:7073/mcp" },
    "local-document-reader": { "type": "http", "url": "http://localhost:7078/mcp" },

    "healthcare-reference-data": {
      "type": "http",
      "url": "${APIM_GATEWAY_URL}/mcp-pt/reference-data/mcp",
      "headers": { "Ocp-Apim-Subscription-Key": "\${input:apimSubscriptionKey}" }
    },
    "healthcare-clinical-research": {
      "type": "http",
      "url": "${APIM_GATEWAY_URL}/mcp-pt/clinical-research/mcp",
      "headers": { "Ocp-Apim-Subscription-Key": "\${input:apimSubscriptionKey}" }
    },
    "healthcare-cosmos-rag": {
      "type": "http",
      "url": "${APIM_GATEWAY_URL}/mcp-pt/cosmos-rag/mcp",
      "headers": { "Ocp-Apim-Subscription-Key": "\${input:apimSubscriptionKey}" }
    }
  }
}
EOF

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
echo "  - Reference Data:     ${APIM_GATEWAY_URL}/mcp-pt/reference-data/mcp"
echo "  - Clinical Research:  ${APIM_GATEWAY_URL}/mcp-pt/clinical-research/mcp"
echo "  - Cosmos RAG:         ${APIM_GATEWAY_URL}/mcp-pt/cosmos-rag/mcp"
echo ""
echo "MCP Endpoints (OAuth):"
echo "  - Reference Data:     ${APIM_GATEWAY_URL}/mcp/reference-data/mcp"
echo "  - Clinical Research:  ${APIM_GATEWAY_URL}/mcp/clinical-research/mcp"
echo "  - Cosmos RAG:         ${APIM_GATEWAY_URL}/mcp/cosmos-rag/mcp"
echo ""
echo "✅ Deployment finished!"
