#!/usr/bin/env bash
# ============================================================================
# test-apim-passthrough.sh
# 
# Tests APIM → Function App backend connectivity using the lightweight
# passthrough API (no OAuth). Uses APIM subscription key for auth.
#
# Usage:
#   ./scripts/test-apim-passthrough.sh
#   ./scripts/test-apim-passthrough.sh --server npi
#   ./scripts/test-apim-passthrough.sh --all
#
# Prerequisites:
#   - az CLI logged in
#   - APIM passthrough module deployed
# ============================================================================

set -euo pipefail

# ---- Configuration ----
RG="${AZURE_RESOURCE_GROUP:-rg-hcmcp-eus2-dev}"
APIM_NAME="${APIM_NAME:-}"
SUBSCRIPTION_KEY="${APIM_SUBSCRIPTION_KEY:-}"
SERVER="${1:---all}"

SERVERS=(npi icd10 cms fhir pubmed clinical-trials)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[PASS]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ---- Auto-discover APIM name ----
if [[ -z "$APIM_NAME" ]]; then
    log "Discovering APIM instance in resource group $RG..."
    APIM_NAME=$(az apim list -g "$RG" --query "[0].name" -o tsv 2>/dev/null || true)
    if [[ -z "$APIM_NAME" ]]; then
        fail "Could not find APIM instance. Set APIM_NAME env var."
        exit 1
    fi
    log "Found APIM: $APIM_NAME"
fi

# ---- Get Gateway URL ----
GATEWAY_URL=$(az apim show -g "$RG" -n "$APIM_NAME" --query "gatewayUrl" -o tsv)
log "Gateway URL: $GATEWAY_URL"

# ---- Get Subscription Key ----
if [[ -z "$SUBSCRIPTION_KEY" ]]; then
    log "Fetching passthrough subscription key..."
    SUBSCRIPTION_KEY=$(az apim subscription show \
        -g "$RG" \
        -n "$APIM_NAME" \
        --subscription-id "mcp-passthrough-sub" \
        --query "primaryKey" -o tsv 2>/dev/null || true)
    
    if [[ -z "$SUBSCRIPTION_KEY" ]]; then
        # Try listing subscriptions to find it
        SUBSCRIPTION_KEY=$(az rest \
            --method get \
            --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/mcp-passthrough-sub/listSecrets?api-version=2023-09-01-preview" \
            --query "primaryKey" -o tsv 2>/dev/null || true)
    fi
    
    if [[ -z "$SUBSCRIPTION_KEY" ]]; then
        fail "Could not retrieve subscription key. Set APIM_SUBSCRIPTION_KEY env var."
        fail "Try: az rest --method post --url 'https://management.azure.com/subscriptions/{sub-id}/resourceGroups/$RG/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/mcp-passthrough-sub/listSecrets?api-version=2023-09-01-preview'"
        exit 1
    fi
    log "Got subscription key: ${SUBSCRIPTION_KEY:0:8}..."
fi

BASE_URL="$GATEWAY_URL/mcp-pt"

# ============================================================================
# Test Functions
# ============================================================================

test_health() {
    local server=$1
    log "Testing $server health check..."
    
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -H "Ocp-Apim-Subscription-Key: $SUBSCRIPTION_KEY" \
        "$BASE_URL/$server/health" 2>&1)
    
    local body http_code
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "200" ]]; then
        ok "$server health: $http_code - $body"
        return 0
    else
        fail "$server health: HTTP $http_code"
        echo "  Response: $body"
        return 1
    fi
}

test_mcp_get() {
    local server=$1
    log "Testing $server GET /mcp..."
    
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -H "Ocp-Apim-Subscription-Key: $SUBSCRIPTION_KEY" \
        "$BASE_URL/$server/mcp" 2>&1)
    
    local body http_code
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "200" || "$http_code" == "405" ]]; then
        ok "$server GET /mcp: HTTP $http_code"
        echo "  Response: $(echo "$body" | head -c 200)"
        return 0
    else
        fail "$server GET /mcp: HTTP $http_code"
        echo "  Response: $body"
        return 1
    fi
}

test_mcp_initialize() {
    local server=$1
    log "Testing $server POST /mcp (initialize)..."
    
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Ocp-Apim-Subscription-Key: $SUBSCRIPTION_KEY" \
        -d '{
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "test-script", "version": "1.0.0"}
            }
        }' \
        "$BASE_URL/$server/mcp" 2>&1)
    
    local body http_code
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "200" ]]; then
        if echo "$body" | grep -q '"result"'; then
            ok "$server initialize: HTTP $http_code - SUCCESS"
            echo "  Response: $(echo "$body" | python3 -m json.tool 2>/dev/null || echo "$body" | head -c 300)"
            return 0
        else
            warn "$server initialize: HTTP $http_code but unexpected body"
            echo "  Response: $body"
            return 1
        fi
    else
        fail "$server initialize: HTTP $http_code"
        echo "  Response: $body"
        return 1
    fi
}

test_mcp_tools_list() {
    local server=$1
    log "Testing $server POST /mcp (tools/list)..."
    
    local response
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Ocp-Apim-Subscription-Key: $SUBSCRIPTION_KEY" \
        -d '{
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": {}
        }' \
        "$BASE_URL/$server/mcp" 2>&1)
    
    local body http_code
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "200" ]]; then
        local tool_count
        tool_count=$(echo "$body" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('result',{}).get('tools',[])))" 2>/dev/null || echo "?")
        ok "$server tools/list: HTTP $http_code - $tool_count tools"
        return 0
    else
        fail "$server tools/list: HTTP $http_code"
        echo "  Response: $body"
        return 1
    fi
}

# ============================================================================
# Run Tests
# ============================================================================

run_server_tests() {
    local server=$1
    local pass=0 total=0
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Testing: $server"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Only NPI has a health endpoint exposed in passthrough
    if [[ "$server" == "npi" ]]; then
        total=$((total + 1))
        test_health "$server" && pass=$((pass + 1))
    fi
    
    total=$((total + 1))
    test_mcp_get "$server" && pass=$((pass + 1))
    
    total=$((total + 1))
    test_mcp_initialize "$server" && pass=$((pass + 1))
    
    total=$((total + 1))
    test_mcp_tools_list "$server" && pass=$((pass + 1))
    
    echo ""
    if [[ "$pass" == "$total" ]]; then
        ok "[$server] $pass/$total tests passed"
    else
        fail "[$server] $pass/$total tests passed"
    fi
    
    return $((total - pass))
}

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  APIM MCP Passthrough Connectivity Test             ║"
echo "║  API Path: /mcp-pt/{server}/mcp                    ║"
echo "║  Auth: Subscription Key (no OAuth)                  ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
log "Base URL: $BASE_URL"

total_failures=0

if [[ "$SERVER" == "--all" || "$SERVER" == "-a" ]]; then
    for s in "${SERVERS[@]}"; do
        run_server_tests "$s" || total_failures=$((total_failures + $?))
    done
elif [[ "$SERVER" == "--server" ]]; then
    run_server_tests "${2:-npi}" || total_failures=$?
else
    # Single server name passed
    run_server_tests "${SERVER#--}" || total_failures=$?
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$total_failures" -eq 0 ]]; then
    ok "All connectivity tests passed! Backend routing is working."
    echo ""
    log "Next steps:"
    log "  1. If passthrough works → issue is in OAuth/PRM policies"
    log "  2. Layer back OAuth by switching from /mcp-pt to /mcp endpoints"
    log "  3. Test each PRM endpoint individually"
else
    fail "$total_failures test(s) failed"
    echo ""
    log "Debugging tips:"
    log "  1. Check Function App IP restrictions (must allow APIM subnet)"
    log "  2. Check Function App is running: az functionapp show -g $RG -n {name} --query state"
    log "  3. Check APIM → backend VNet connectivity in APIM Network Status"
    log "  4. Enable APIM tracing: add Ocp-Apim-Trace: true header"
    log "  5. Try direct Function App access to isolate APIM vs Function issue"
fi

exit $total_failures
