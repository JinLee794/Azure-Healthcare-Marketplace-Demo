#!/bin/bash
set -euo pipefail

# =============================================================================
# Script to create the account/project capability host for Azure AI Foundry
#
# Usage (interactive):
#   ./create-cap-host.sh
#
# Usage (non-interactive):
#   ./create-cap-host.sh \
#     --subscription <id> \
#     --resource-group <rg> \
#     --account-name <name> \
#     --caphost-name <name> \
#     --subnet-id <full-ARM-resource-id>
#
# Ref: https://github.com/microsoft-foundry/foundry-samples/tree/main/infrastructure/infrastructure-setup-bicep/15-private-network-standard-agent-setup
# =============================================================================

POLL_INTERVAL=10
MAX_POLL_MINUTES=30

# ---------------------------------------------------------------------------
# Parse CLI arguments (fall back to interactive prompts)
# ---------------------------------------------------------------------------
subscription_id=""
resource_group=""
account_name=""
caphost_name=""
subnet_resource_id=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --subscription)      subscription_id="$2";    shift 2 ;;
        --resource-group)    resource_group="$2";      shift 2 ;;
        --account-name)      account_name="$2";        shift 2 ;;
        --caphost-name)      caphost_name="$2";        shift 2 ;;
        --subnet-id)         subnet_resource_id="$2";  shift 2 ;;
        -h|--help)
            sed -n '3,12p' "$0"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

[[ -z "$subscription_id" ]]    && read -rp "Enter Subscription ID: " subscription_id
[[ -z "$resource_group" ]]     && read -rp "Enter Resource Group name: " resource_group
[[ -z "$account_name" ]]       && read -rp "Enter Foundry Account or Project name: " account_name
[[ -z "$caphost_name" ]]       && read -rp "Enter CapabilityHost name: " caphost_name
[[ -z "$subnet_resource_id" ]] && read -rp "Enter Customer full ARM subnet ResourceId: " subnet_resource_id

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
get_token() {
    local token
    token=$(az account get-access-token --query accessToken -o tsv 2>/dev/null) || true
    if [[ -z "${token}" ]]; then
        echo "Error: Failed to get access token. Run 'az login' first." >&2
        exit 1
    fi
    echo "${token}"
}

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
echo "=== Pre-flight checks ==="

command -v az  >/dev/null 2>&1 || { echo "Error: Azure CLI (az) is not installed."; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "Error: jq is not installed."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Error: curl is not installed."; exit 1; }

echo "Getting Azure access token..."
access_token=$(get_token)
echo "Token acquired."

# Validate subnet format
if [[ ! "${subnet_resource_id}" =~ ^/subscriptions/.+/resourceGroups/.+/providers/Microsoft.Network/virtualNetworks/.+/subnets/.+ ]]; then
    echo "Warning: subnet ID doesn't look like a valid ARM resource ID."
    echo "  Expected format: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>"
    read -rp "Continue anyway? [y/N] " confirm
    [[ "${confirm}" =~ ^[Yy]$ ]] || exit 1
fi

echo ""
echo "IMPORTANT REMINDERS (from Microsoft docs):"
echo "  • The subnet must be exclusively delegated to Microsoft.App/environments."
echo "  • The subnet must NOT already be in use by another Foundry account."
echo "  • If re-creating after a delete, wait ~20 min for resources to unlink."
echo ""

# ---------------------------------------------------------------------------
# Construct API URL & body
# ---------------------------------------------------------------------------
api_url="https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.CognitiveServices/accounts/${account_name}/capabilityHosts/${caphost_name}?api-version=2025-04-01-preview"

echo "Creating capability host: ${caphost_name}"
echo "  Account:  ${account_name}"
echo "  RG:       ${resource_group}"
echo "  Subnet:   ${subnet_resource_id}"
echo "  API URL:  ${api_url}"

read -r -d '' BODY <<EOF || true
{
  "properties": {
    "capabilityHostKind": "Agents",
    "customerSubnet": "${subnet_resource_id}"
  }
}
EOF

# ---------------------------------------------------------------------------
# Send PUT request — capture BOTH headers and body, plus HTTP status code
# ---------------------------------------------------------------------------
echo -e "\nSending PUT request..."
response_headers=$(mktemp)
response_body=$(mktemp)

http_code=$(curl -s -o "${response_body}" -w "%{http_code}" \
    -X PUT \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    --data "${BODY}" \
    -D "${response_headers}" \
    "${api_url}") || {
    echo "Error: curl failed to connect."
    rm -f "${response_headers}" "${response_body}"
    exit 1
}

echo "HTTP status code: ${http_code}"

# Surface the response body so API errors are visible
if [[ -s "${response_body}" ]]; then
    echo "Response body:"
    jq . "${response_body}" 2>/dev/null || cat "${response_body}"
fi

# Fail fast on client/server errors
if [[ "${http_code}" -ge 400 ]]; then
    echo -e "\nError: API returned HTTP ${http_code}."
    # Surface common issues
    error_code=$(jq -r '.error.code // empty' "${response_body}" 2>/dev/null)
    error_msg=$(jq -r '.error.message // empty' "${response_body}" 2>/dev/null)
    if [[ -n "${error_code}" ]]; then
        echo "  Error code:    ${error_code}"
        echo "  Error message: ${error_msg}"
    fi
    if [[ "${error_msg}" == *"subnet"* ]] || [[ "${error_msg}" == *"Subnet"* ]]; then
        echo ""
        echo "Hint: The subnet may still be linked to a previous capability host."
        echo "  1. Delete & purge the old account, OR"
        echo "  2. Run delete-cap-host.sh and wait ~20 min before retrying."
    fi
    rm -f "${response_headers}" "${response_body}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Extract async operation URL
# ---------------------------------------------------------------------------
operation_url=$(grep -i "Azure-AsyncOperation" "${response_headers}" | cut -d' ' -f2 | tr -d '\r')

# Some responses may also use Location header for long-running ops
if [[ -z "${operation_url}" ]]; then
    operation_url=$(grep -i "^Location:" "${response_headers}" | cut -d' ' -f2 | tr -d '\r')
fi

rm -f "${response_headers}" "${response_body}"

if [[ -z "${operation_url}" ]]; then
    # If HTTP 200/201 with no async header, the operation completed synchronously
    if [[ "${http_code}" -le 201 ]]; then
        echo -e "\nCapability host created synchronously (HTTP ${http_code})."
        exit 0
    fi
    echo -e "\nError: No async operation URL found in response headers."
    exit 1
fi

echo -e "\nCapability host creation request accepted."
echo "Polling operation: ${operation_url}"

# ---------------------------------------------------------------------------
# Poll until terminal state
# ---------------------------------------------------------------------------
start_time=$(date +%s)
max_seconds=$((MAX_POLL_MINUTES * 60))

while true; do
    elapsed=$(( $(date +%s) - start_time ))
    if [[ ${elapsed} -ge ${max_seconds} ]]; then
        echo "Error: Timed out after ${MAX_POLL_MINUTES} minutes."
        exit 1
    fi

    echo "Checking operation status... (${elapsed}s elapsed)"
    access_token=$(get_token)

    operation_response=$(curl -s \
        -H "Authorization: Bearer ${access_token}" \
        -H "Content-Type: application/json" \
        "${operation_url}") || {
        echo "Warning: poll request failed, retrying in ${POLL_INTERVAL}s..."
        sleep "${POLL_INTERVAL}"
        continue
    }

    # Handle transient errors
    error_code=$(echo "${operation_response}" | jq -r '.error.code // empty')
    if [[ "${error_code}" == "TransientError" ]]; then
        echo "Transient error — retrying in ${POLL_INTERVAL}s..."
        sleep "${POLL_INTERVAL}"
        continue
    fi

    status=$(echo "${operation_response}" | jq -r '.status // empty')

    if [[ -z "${status}" ]]; then
        echo "Warning: Could not determine status. Response:"
        echo "${operation_response}" | jq . 2>/dev/null || echo "${operation_response}"
        sleep "${POLL_INTERVAL}"
        continue
    fi

    echo "Current status: ${status}"

    case "${status}" in
        Succeeded)
            echo -e "\nCapability host creation completed successfully."
            exit 0
            ;;
        Failed|Canceled)
            echo -e "\nCapability host creation ${status,,}."
            echo "Full response:"
            echo "${operation_response}" | jq . 2>/dev/null || echo "${operation_response}"
            exit 1
            ;;
        Creating|InProgress|Running|Accepted|Provisioning)
            # All known in-progress states — keep polling
            sleep "${POLL_INTERVAL}"
            ;;
        *)
            echo "Warning: Unrecognized status '${status}', continuing to poll..."
            sleep "${POLL_INTERVAL}"
            ;;
    esac
done