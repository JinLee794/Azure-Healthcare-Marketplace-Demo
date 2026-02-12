#!/bin/bash
# =============================================================================
# deploy-mcp-containers.sh
#
# Builds Docker images for all MCP servers, pushes to Azure Container Registry,
# and updates each Function App's container configuration.
#
# Requirements:
#   - Azure CLI (`az`) logged in
#   - Docker daemon running
#   - azd environment variables set (via `azd env` or exported)
#
# Usage:
#   ./scripts/deploy-mcp-containers.sh              # Deploy all servers
#   ./scripts/deploy-mcp-containers.sh npi-lookup    # Deploy single server
#
# Environment variables (auto-resolved from azd env if not set):
#   AZURE_CONTAINER_REGISTRY_ENDPOINT  - ACR login server (e.g., myacr.azurecr.io)
#   AZURE_RESOURCE_GROUP               - Azure resource group name
#   IMAGE_TAG                          - Docker image tag (default: latest)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKERFILE="$REPO_ROOT/src/mcp-servers/Dockerfile"
BUILD_CONTEXT="$REPO_ROOT/src/mcp-servers"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# All MCP servers and their azure.yaml service names (used for Bicep output lookup)
declare -A SERVER_RESOURCE_VARS=(
  [npi-lookup]="SERVICE_NPI_LOOKUP_RESOURCE_NAME"
  [icd10-validation]="SERVICE_ICD10_VALIDATION_RESOURCE_NAME"
  [cms-coverage]="SERVICE_CMS_COVERAGE_RESOURCE_NAME"
  [fhir-operations]="SERVICE_FHIR_OPERATIONS_RESOURCE_NAME"
  [pubmed]="SERVICE_PUBMED_RESOURCE_NAME"
  [clinical-trials]="SERVICE_CLINICAL_TRIALS_RESOURCE_NAME"
  [cosmos-rag]="SERVICE_COSMOS_RAG_RESOURCE_NAME"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

resolve_azd_value() {
  local var_name="$1"
  local value="${!var_name:-}"
  if [ -z "$value" ]; then
    value=$(azd env get-value "$var_name" 2>/dev/null || true)
  fi
  echo "$value"
}

log_header() {
  echo ""
  echo "=============================================="
  echo "  $1"
  echo "=============================================="
  echo ""
}

log_step() {
  echo "  → $1"
}

log_ok() {
  echo "  ✅ $1"
}

log_err() {
  echo "  ❌ $1" >&2
}

# ---------------------------------------------------------------------------
# Resolve configuration
# ---------------------------------------------------------------------------

log_header "MCP Container Deployment"

ACR_LOGIN_SERVER="$(resolve_azd_value AZURE_CONTAINER_REGISTRY_ENDPOINT)"
RESOURCE_GROUP="$(resolve_azd_value AZURE_RESOURCE_GROUP)"

if [ -z "$ACR_LOGIN_SERVER" ]; then
  log_err "AZURE_CONTAINER_REGISTRY_ENDPOINT not set. Run 'azd provision' first or export it."
  exit 1
fi

if [ -z "$RESOURCE_GROUP" ]; then
  log_err "AZURE_RESOURCE_GROUP not set. Run 'azd provision' first or export it."
  exit 1
fi

echo "  ACR:             $ACR_LOGIN_SERVER"
echo "  Resource Group:  $RESOURCE_GROUP"
echo "  Image Tag:       $IMAGE_TAG"
echo "  Dockerfile:      $DOCKERFILE"

# ---------------------------------------------------------------------------
# Determine which servers to deploy
# ---------------------------------------------------------------------------

if [ $# -gt 0 ]; then
  SERVERS=("$@")
  for s in "${SERVERS[@]}"; do
    if [ -z "${SERVER_RESOURCE_VARS[$s]+x}" ]; then
      log_err "Unknown server: $s"
      echo "  Valid servers: ${!SERVER_RESOURCE_VARS[*]}"
      exit 1
    fi
  done
else
  SERVERS=("${!SERVER_RESOURCE_VARS[@]}")
fi

echo "  Servers:         ${SERVERS[*]}"

# ---------------------------------------------------------------------------
# ACR Login
# ---------------------------------------------------------------------------

log_header "Logging into ACR"
log_step "az acr login --name ${ACR_LOGIN_SERVER%%.*}"

az acr login --name "${ACR_LOGIN_SERVER%%.*}" 2>&1 | sed 's/^/  /'
log_ok "ACR login successful"

# ---------------------------------------------------------------------------
# Build, Tag, Push, Deploy each server
# ---------------------------------------------------------------------------

FAILED=()

for SERVER_NAME in "${SERVERS[@]}"; do
  log_header "Deploying: $SERVER_NAME"

  IMAGE_NAME="mcp-${SERVER_NAME}"
  FULL_IMAGE="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"

  # Resolve Function App resource name from Bicep output
  RESOURCE_VAR="${SERVER_RESOURCE_VARS[$SERVER_NAME]}"
  FUNC_APP_NAME="$(resolve_azd_value "$RESOURCE_VAR")"

  if [ -z "$FUNC_APP_NAME" ]; then
    log_err "Could not resolve Function App name from $RESOURCE_VAR. Skipping."
    FAILED+=("$SERVER_NAME")
    continue
  fi

  echo "  Function App:    $FUNC_APP_NAME"
  echo "  Image:           $FULL_IMAGE"

  # Build
  log_step "Building Docker image..."
  if ! docker build \
    --platform linux/amd64 \
    --build-arg SERVER_NAME="$SERVER_NAME" \
    -t "$IMAGE_NAME:$IMAGE_TAG" \
    -t "$FULL_IMAGE" \
    -f "$DOCKERFILE" \
    "$BUILD_CONTEXT" 2>&1 | tail -5 | sed 's/^/    /'; then
    log_err "Docker build failed for $SERVER_NAME"
    FAILED+=("$SERVER_NAME")
    continue
  fi
  log_ok "Image built"

  # Push
  log_step "Pushing to ACR..."
  if ! docker push "$FULL_IMAGE" 2>&1 | tail -3 | sed 's/^/    /'; then
    log_err "Docker push failed for $SERVER_NAME"
    FAILED+=("$SERVER_NAME")
    continue
  fi
  log_ok "Image pushed"

  # Update Function App container config
  log_step "Updating Function App container config..."
  if ! az functionapp config container set \
    --name "$FUNC_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --image "$FULL_IMAGE" \
    --registry-server "https://${ACR_LOGIN_SERVER}" \
    --output none 2>&1 | sed 's/^/    /'; then
    log_err "Function App update failed for $SERVER_NAME"
    FAILED+=("$SERVER_NAME")
    continue
  fi
  log_ok "Function App updated → $FULL_IMAGE"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

log_header "Deployment Summary"

DEPLOYED_COUNT=$(( ${#SERVERS[@]} - ${#FAILED[@]} ))
echo "  Deployed: $DEPLOYED_COUNT / ${#SERVERS[@]}"

if [ ${#FAILED[@]} -gt 0 ]; then
  echo "  Failed:   ${FAILED[*]}"
  exit 1
fi

echo ""
echo "  All MCP server containers deployed successfully! 🎉"
echo ""
echo "  To verify, check Function App container settings:"
echo "    az functionapp config container show --name <func-app-name> -g $RESOURCE_GROUP"
echo ""
