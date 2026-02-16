#!/bin/bash
set -euo pipefail

# =============================================================================
# Quick wrapper: delete capability hosts using azd env vars
#
# Reads AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP from `azd env get-values`,
# discovers the AI Services account + project names via `az resource list`,
# and deletes capability hosts in the correct order:
#   1. Project capability host  (caphost-agents)
#   2. Account capability host  (caphost-account)
#
# Usage:
#   ./scripts/delete-cap-host-azd.sh            # uses current azd env
#   ./scripts/delete-cap-host-azd.sh --dry-run  # show what would be deleted
#   ./scripts/delete-cap-host-azd.sh --skip-project  # only delete account caphost
#   ./scripts/delete-cap-host-azd.sh --skip-account  # only delete project caphost
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DELETE_SCRIPT="${SCRIPT_DIR}/delete-cap-host.sh"

DRY_RUN=false
SKIP_PROJECT=false
SKIP_ACCOUNT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)       DRY_RUN=true;       shift ;;
        --skip-project)  SKIP_PROJECT=true;   shift ;;
        --skip-account)  SKIP_ACCOUNT=true;   shift ;;
        -h|--help)
            sed -n '3,14p' "$0"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# 1. Load azd environment
# ---------------------------------------------------------------------------
echo "=== Loading azd environment ==="

if ! command -v azd >/dev/null 2>&1; then
    echo "Error: azd is not installed. Install from https://aka.ms/azd"
    exit 1
fi

eval "$(azd env get-values 2>/dev/null)"

SUB="${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID not set in azd env}"
RG="${AZURE_RESOURCE_GROUP:?AZURE_RESOURCE_GROUP not set in azd env}"

echo "  Subscription:   ${SUB}"
echo "  Resource Group:  ${RG}"

# ---------------------------------------------------------------------------
# 2. Discover AI Services account (CognitiveServices/accounts)
# ---------------------------------------------------------------------------
echo -e "\n=== Discovering AI Services account ==="

ACCOUNT_NAME=$(az resource list \
    --subscription "${SUB}" \
    --resource-group "${RG}" \
    --resource-type "Microsoft.CognitiveServices/accounts" \
    --query "[?kind=='AIServices'].name | [0]" \
    -o tsv 2>/dev/null)

if [[ -z "${ACCOUNT_NAME}" || "${ACCOUNT_NAME}" == "None" ]]; then
    echo "Error: No AIServices account found in RG '${RG}'."
    echo "  Verify with: az resource list -g '${RG}' --resource-type Microsoft.CognitiveServices/accounts -o table"
    exit 1
fi

echo "  AI Services account: ${ACCOUNT_NAME}"

# ---------------------------------------------------------------------------
# 3. Discover the project name (first project under the account)
# ---------------------------------------------------------------------------
echo -e "\n=== Discovering Foundry project ==="

PROJECT_NAME=$(az rest \
    --method GET \
    --url "https://management.azure.com/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.CognitiveServices/accounts/${ACCOUNT_NAME}/projects?api-version=2025-04-01-preview" \
    2>/dev/null | jq -r '.value[0].name // empty')

if [[ -z "${PROJECT_NAME}" ]]; then
    echo "Warning: No project found under account '${ACCOUNT_NAME}'."
    echo "  Skipping project capability host deletion."
    SKIP_PROJECT=true
else
    echo "  Project: ${PROJECT_NAME}"
fi

# ---------------------------------------------------------------------------
# 4. Capability host names (from Bicep: caphost-account, caphost-agents)
# ---------------------------------------------------------------------------
ACCOUNT_CAPHOST="caphost-account"
PROJECT_CAPHOST="caphost-agents"

echo ""
echo "=== Deletion plan ==="
if [[ "${SKIP_PROJECT}" != true ]]; then
    echo "  1. DELETE project caphost:  ${ACCOUNT_NAME}/${PROJECT_NAME}/${PROJECT_CAPHOST}"
fi
if [[ "${SKIP_ACCOUNT}" != true ]]; then
    echo "  2. DELETE account caphost:  ${ACCOUNT_NAME}/${ACCOUNT_CAPHOST}"
fi
echo ""
echo "  (After deletion, wait ~20 min for subnet resources to unlink)"
echo ""

if [[ "${DRY_RUN}" == true ]]; then
    echo "[DRY RUN] Would execute the above deletions. Exiting."
    exit 0
fi

read -rp "Proceed with deletion? [y/N] " confirm
[[ "${confirm}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ---------------------------------------------------------------------------
# 5. Delete project capability host FIRST (required ordering)
# ---------------------------------------------------------------------------
if [[ "${SKIP_PROJECT}" != true ]]; then
    echo -e "\n=== Step 1/2: Deleting project capability host ==="
    # Project caphost uses the project-level API path
    # The delete script expects "account_name" — for project-level, we pass
    # the account/project path and the caphost name
    access_token=$(az account get-access-token --query accessToken -o tsv)
    
    project_api_url="https://management.azure.com/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.CognitiveServices/accounts/${ACCOUNT_NAME}/projects/${PROJECT_NAME}/capabilityHosts/${PROJECT_CAPHOST}?api-version=2025-04-01-preview"

    echo "  API URL: ${project_api_url}"
    echo "  Sending DELETE..."

    response_headers=$(mktemp)
    response_body=$(mktemp)

    http_code=$(curl -s -o "${response_body}" -w "%{http_code}" \
        -X DELETE \
        -H "Authorization: Bearer ${access_token}" \
        -H "Content-Type: application/json" \
        -D "${response_headers}" \
        "${project_api_url}") || true

    echo "  HTTP ${http_code}"

    if [[ "${http_code}" -ge 400 ]]; then
        echo "  Error deleting project caphost:"
        jq . "${response_body}" 2>/dev/null || cat "${response_body}"
        if [[ "${http_code}" == "404" ]]; then
            echo "  (May already be deleted — continuing)"
        else
            rm -f "${response_headers}" "${response_body}"
            exit 1
        fi
    else
        # Poll async operation
        operation_url=$(grep -i "Azure-AsyncOperation" "${response_headers}" | cut -d' ' -f2 | tr -d '\r')
        [[ -z "${operation_url}" ]] && operation_url=$(grep -i "^Location:" "${response_headers}" | cut -d' ' -f2 | tr -d '\r')

        if [[ -n "${operation_url}" ]]; then
            echo "  Polling: ${operation_url}"
            while true; do
                sleep 10
                access_token=$(az account get-access-token --query accessToken -o tsv)
                poll_resp=$(curl -s \
                    -H "Authorization: Bearer ${access_token}" \
                    -H "Content-Type: application/json" \
                    "${operation_url}")
                status=$(echo "${poll_resp}" | jq -r '.status // empty')
                echo "  Status: ${status}"
                case "${status}" in
                    Succeeded) echo "  Project caphost deleted."; break ;;
                    Failed|Canceled)
                        echo "  Project caphost deletion ${status}:"
                        echo "${poll_resp}" | jq . 2>/dev/null
                        exit 1 ;;
                    Deleting|InProgress|Running|Accepted) continue ;;
                    *) sleep 10 ;;
                esac
            done
        else
            echo "  Completed synchronously."
        fi
    fi
    rm -f "${response_headers}" "${response_body}"
fi

# ---------------------------------------------------------------------------
# 6. Delete account capability host
# ---------------------------------------------------------------------------
if [[ "${SKIP_ACCOUNT}" != true ]]; then
    echo -e "\n=== Step 2/2: Deleting account capability host ==="
    "${DELETE_SCRIPT}" \
        --subscription "${SUB}" \
        --resource-group "${RG}" \
        --account-name "${ACCOUNT_NAME}" \
        --caphost-name "${ACCOUNT_CAPHOST}"
fi

echo -e "\n=== Done ==="
echo "Wait ~20 minutes before reusing the subnet or recreating capability hosts."
