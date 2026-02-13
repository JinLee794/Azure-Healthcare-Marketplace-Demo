#!/bin/bash
# ============================================================================
# Setup MCP Servers in Azure API Management
# ============================================================================
# This script configures the deployed Function App MCP servers as proper
# MCP-compatible APIs in Azure API Management using the REST API.
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - Infrastructure deployed via azd provision
#   - Function Apps deployed via azd deploy
#
# Usage:
#   ./scripts/setup-mcp-servers.sh [resource-group] [apim-name] [function-base-name]
#
# Example:
#   ./scripts/setup-mcp-servers.sh rg-healthcare-mcp healthcare-mcp-apim hcmcp
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="${1:-}"
APIM_NAME="${2:-}"
FUNCTION_BASE_NAME="${3:-}"

# Consolidated MCP Servers (v2)
MCP_SERVERS=(
    "mcp-reference-data:Reference Data:NPI lookup, ICD-10 validation, and CMS coverage (12 tools)"
    "mcp-clinical-research:Clinical Research:FHIR operations, PubMed search, and clinical trials (20 tools)"
    "cosmos-rag:Cosmos RAG:Cosmos DB RAG search and audit logging (6 tools)"
)

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Please install: https://aka.ms/installazurecli"
        exit 1
    fi

    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure CLI. Run: az login"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

get_resource_info() {
    log_info "Retrieving resource information..."

    # Try to get from azd environment if not provided
    if [ -z "$RESOURCE_GROUP" ]; then
        if command -v azd &> /dev/null; then
            RESOURCE_GROUP=$(azd env get-values 2>/dev/null | grep AZURE_RESOURCE_GROUP | cut -d'=' -f2 | tr -d '"' || echo "")
        fi
    fi

    if [ -z "$RESOURCE_GROUP" ]; then
        log_error "Resource group not found. Please provide as argument or run from azd environment."
        echo "Usage: $0 <resource-group> <apim-name> <function-base-name>"
        exit 1
    fi

    # Try to find APIM instance if not provided
    if [ -z "$APIM_NAME" ]; then
        APIM_NAME=$(az apim list -g "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi

    if [ -z "$APIM_NAME" ]; then
        log_error "API Management instance not found in resource group: $RESOURCE_GROUP"
        exit 1
    fi

    # Try to find Function App base name if not provided
    if [ -z "$FUNCTION_BASE_NAME" ]; then
        # Get any function app and extract base name
        FUNC_APP=$(az functionapp list -g "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
        if [ -n "$FUNC_APP" ]; then
            # Extract base name (e.g., "hcmcp" from "hcmcp-npi-lookup-func")
            FUNCTION_BASE_NAME=$(echo "$FUNC_APP" | sed 's/-[^-]*-func$//' | sed 's/-mcp-reference-data$//' | sed 's/-mcp-clinical-research$//' | sed 's/-cosmos-rag$//')
        fi
    fi

    if [ -z "$FUNCTION_BASE_NAME" ]; then
        log_error "Could not determine Function App base name. Please provide as argument."
        exit 1
    fi

    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "APIM Name: $APIM_NAME"
    log_info "Function Base Name: $FUNCTION_BASE_NAME"
}

get_apim_gateway_url() {
    az apim show -g "$RESOURCE_GROUP" -n "$APIM_NAME" --query "gatewayUrl" -o tsv
}

get_function_url() {
    local server_name="$1"
    local func_app_name="${FUNCTION_BASE_NAME}-${server_name}-func"

    # Get Function App hostname
    local hostname=$(az functionapp show -g "$RESOURCE_GROUP" -n "$func_app_name" --query "defaultHostName" -o tsv 2>/dev/null)

    if [ -z "$hostname" ]; then
        log_warning "Function App not found: $func_app_name"
        return 1
    fi

    echo "https://${hostname}/api"
}

get_function_key() {
    local server_name="$1"
    local func_app_name="${FUNCTION_BASE_NAME}-${server_name}-func"

    # Get Function App master key
    az functionapp keys list -g "$RESOURCE_GROUP" -n "$func_app_name" --query "masterKey" -o tsv 2>/dev/null
}

# ============================================================================
# APIM Configuration Functions
# ============================================================================

create_mcp_backend() {
    local server_name="$1"
    local display_name="$2"
    local description="$3"
    local backend_url="$4"

    local backend_name="${server_name}-backend"

    log_info "Creating backend: $backend_name"

    # Check if backend exists
    if az apim backend show -g "$RESOURCE_GROUP" -n "$APIM_NAME" --backend-id "$backend_name" &>/dev/null; then
        log_info "Backend already exists, updating..."
        az apim backend update \
            -g "$RESOURCE_GROUP" \
            -n "$APIM_NAME" \
            --backend-id "$backend_name" \
            --url "$backend_url" \
            --protocol http
    else
        az apim backend create \
            -g "$RESOURCE_GROUP" \
            -n "$APIM_NAME" \
            --backend-id "$backend_name" \
            --url "$backend_url" \
            --protocol http \
            --title "$display_name Backend" \
            --description "Backend for $description"
    fi

    log_success "Backend configured: $backend_name"
}

create_mcp_api() {
    local server_name="$1"
    local display_name="$2"
    local description="$3"
    local backend_url="$4"

    local api_id="${server_name}-mcp"
    local api_path="mcp/${server_name}"

    log_info "Creating API: $api_id"

    # Check if API exists
    if az apim api show -g "$RESOURCE_GROUP" -n "$APIM_NAME" --api-id "$api_id" &>/dev/null; then
        log_info "API already exists, updating..."
        az apim api update \
            -g "$RESOURCE_GROUP" \
            -n "$APIM_NAME" \
            --api-id "$api_id" \
            --display-name "$display_name MCP Server" \
            --description "$description - MCP Protocol 2025-06-18" \
            --service-url "$backend_url"
    else
        az apim api create \
            -g "$RESOURCE_GROUP" \
            -n "$APIM_NAME" \
            --api-id "$api_id" \
            --display-name "$display_name MCP Server" \
            --description "$description - MCP Protocol 2025-06-18" \
            --path "$api_path" \
            --protocols https \
            --service-url "$backend_url" \
            --subscription-required false
    fi

    log_success "API configured: $api_id"
}

create_mcp_operations() {
    local server_name="$1"
    local api_id="${server_name}-mcp"

    log_info "Creating MCP operations for: $api_id"

    # MCP Discovery endpoint (GET /.well-known/mcp)
    if ! az apim api operation show -g "$RESOURCE_GROUP" -n "$APIM_NAME" --api-id "$api_id" --operation-id "mcp-discovery" &>/dev/null; then
        az apim api operation create \
            -g "$RESOURCE_GROUP" \
            -n "$APIM_NAME" \
            --api-id "$api_id" \
            --operation-id "mcp-discovery" \
            --display-name "MCP Discovery" \
            --method GET \
            --url-template "/.well-known/mcp" \
            --description "Returns MCP server capabilities and tools"
    fi

    # MCP Message endpoint (POST /mcp) - Streamable HTTP
    if ! az apim api operation show -g "$RESOURCE_GROUP" -n "$APIM_NAME" --api-id "$api_id" --operation-id "mcp-message" &>/dev/null; then
        az apim api operation create \
            -g "$RESOURCE_GROUP" \
            -n "$APIM_NAME" \
            --api-id "$api_id" \
            --operation-id "mcp-message" \
            --display-name "MCP Message" \
            --method POST \
            --url-template "/mcp" \
            --description "Handle MCP JSON-RPC messages (Streamable HTTP transport)"
    fi

    log_success "Operations configured for: $api_id"
}

apply_mcp_policy() {
    local server_name="$1"
    local api_id="${server_name}-mcp"
    local backend_name="${server_name}-backend"

    log_info "Applying MCP policy for: $api_id"

    # Create policy XML
    local policy_xml="<policies>
  <inbound>
    <base />
    <set-backend-service backend-id=\"${backend_name}\" />
    <set-header name=\"X-MCP-Protocol-Version\" exists-action=\"override\">
      <value>2025-06-18</value>
    </set-header>
    <set-header name=\"Cache-Control\" exists-action=\"override\">
      <value>no-cache</value>
    </set-header>
    <cors allow-credentials=\"false\">
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>POST</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>*</header>
      </allowed-headers>
    </cors>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <set-header name=\"X-Content-Type-Options\" exists-action=\"override\">
      <value>nosniff</value>
    </set-header>
    <set-header name=\"Content-Type\" exists-action=\"override\">
      <value>application/json</value>
    </set-header>
  </outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code=\"500\" reason=\"Internal Server Error\" />
      <set-header name=\"Content-Type\" exists-action=\"override\">
        <value>application/json</value>
      </set-header>
      <set-body>{\"jsonrpc\": \"2.0\", \"error\": {\"code\": -32603, \"message\": \"Internal error\"}, \"id\": null}</set-body>
    </return-response>
  </on-error>
</policies>"

    # Write policy to temp file
    local policy_file=$(mktemp)
    echo "$policy_xml" > "$policy_file"

    # Apply policy using Azure CLI
    az apim api policy create \
        -g "$RESOURCE_GROUP" \
        -n "$APIM_NAME" \
        --api-id "$api_id" \
        --xml-policy "$policy_file"

    rm -f "$policy_file"

    log_success "Policy applied for: $api_id"
}

add_api_to_product() {
    local server_name="$1"
    local api_id="${server_name}-mcp"
    local product_id="healthcare-mcp"

    log_info "Adding $api_id to product: $product_id"

    # Check if product exists, create if not
    if ! az apim product show -g "$RESOURCE_GROUP" -n "$APIM_NAME" --product-id "$product_id" &>/dev/null; then
        log_info "Creating product: $product_id"
        az apim product create \
            -g "$RESOURCE_GROUP" \
            -n "$APIM_NAME" \
            --product-id "$product_id" \
            --product-name "Healthcare MCP APIs" \
            --description "Healthcare Model Context Protocol servers" \
            --subscription-required true \
            --approval-required false \
            --state published
    fi

    # Add API to product
    az apim product api add \
        -g "$RESOURCE_GROUP" \
        -n "$APIM_NAME" \
        --product-id "$product_id" \
        --api-id "$api_id" 2>/dev/null || true

    log_success "API added to product: $product_id"
}

# ============================================================================
# Main Setup
# ============================================================================

setup_mcp_server() {
    local server_entry="$1"

    # Parse server entry (name:display_name:description)
    IFS=':' read -r server_name display_name description <<< "$server_entry"

    echo ""
    log_info "=========================================="
    log_info "Setting up MCP Server: $display_name"
    log_info "=========================================="

    # Get Function App URL
    local backend_url=$(get_function_url "$server_name")

    if [ -z "$backend_url" ]; then
        log_warning "Skipping $server_name - Function App not found"
        return
    fi

    log_info "Backend URL: $backend_url"

    # Create backend
    create_mcp_backend "$server_name" "$display_name" "$description" "$backend_url"

    # Create API
    create_mcp_api "$server_name" "$display_name" "$description" "$backend_url"

    # Create operations
    create_mcp_operations "$server_name"

    # Apply policy
    apply_mcp_policy "$server_name"

    # Add to product
    add_api_to_product "$server_name"

    log_success "MCP Server setup complete: $display_name"
}

generate_mcp_config() {
    local gateway_url=$(get_apim_gateway_url)

    echo ""
    log_info "=========================================="
    log_info "VS Code MCP Configuration"
    log_info "=========================================="

    echo "Add the following to your .vscode/mcp.json:"
    echo ""
    echo "{"
    echo '  "servers": {'

    local first=true
    for server_entry in "${MCP_SERVERS[@]}"; do
        IFS=':' read -r server_name display_name description <<< "$server_entry"

        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi

        echo "    \"healthcare-${server_name}\": {"
        echo '      "type": "http",'
        echo "      \"url\": \"${gateway_url}/mcp/${server_name}/mcp\","
        echo '      "headers": {'
        echo '        "Ocp-Apim-Subscription-Key": "${input:apimSubscriptionKey}"'
        echo "      }"
        echo -n "    }"
    done

    echo ""
    echo '  },'
    echo '  "inputs": ['
    echo '    {'
    echo '      "id": "apimSubscriptionKey",'
    echo '      "type": "promptString",'
    echo '      "description": "APIM Subscription Key for Healthcare MCP APIs",'
    echo '      "password": true'
    echo '    }'
    echo '  ]'
    echo "}"
    echo ""
}

main() {
    echo ""
    echo "=============================================="
    echo "  Healthcare MCP Server Setup for Azure APIM"
    echo "=============================================="
    echo ""

    check_prerequisites
    get_resource_info

    # Setup each MCP server
    for server_entry in "${MCP_SERVERS[@]}"; do
        setup_mcp_server "$server_entry"
    done

    # Generate VS Code configuration
    generate_mcp_config

    echo ""
    log_success "=============================================="
    log_success "  All MCP Servers configured successfully!"
    log_success "=============================================="
    echo ""

    local gateway_url=$(get_apim_gateway_url)
    log_info "APIM Gateway URL: $gateway_url"
    log_info ""
    log_info "MCP Server URLs:"
    for server_entry in "${MCP_SERVERS[@]}"; do
        IFS=':' read -r server_name display_name description <<< "$server_entry"
        log_info "  - ${display_name}: ${gateway_url}/mcp/${server_name}/mcp"
    done
    echo ""
    log_info "To get a subscription key, run:"
    log_info "  az apim subscription list -g $RESOURCE_GROUP -n $APIM_NAME --query \"[?contains(scope, 'healthcare-mcp')].primaryKey\" -o tsv"
    echo ""
}

# Run main function
main "$@"
