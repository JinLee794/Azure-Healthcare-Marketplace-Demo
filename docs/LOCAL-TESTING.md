# Local Testing Guide for Healthcare MCP Servers

This guide covers how to run and test the MCP servers locally, both directly (without APIM) and through Azure API Management.

## Prerequisites

- Python 3.11+
- [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) (for APIM testing)
- [Azurite](https://learn.microsoft.com/azure/storage/common/storage-use-azurite) (local storage emulator)
- [Docker & Docker Compose](https://docs.docker.com/get-docker/) (for containerised testing)

```bash
# Install Azure Functions Core Tools
brew install azure-functions-core-tools@4

# Install Azurite (for local storage)
npm install -g azurite
```

---

## Option 1: Local Testing (Without APIM)

This method runs the MCP server directly on your machine for rapid development and debugging.

### Step 1: Start Azurite Storage Emulator

```bash
# Start Azurite in a separate terminal
azurite --silent --location /tmp/azurite --debug /tmp/azurite/debug.log
```

### Step 2: Run a Single MCP Server

```bash
# Navigate to the MCP server directory
cd src/mcp-servers/npi-lookup

# Create and activate virtual environment
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start the Function App locally
func start
```

The server will start on `http://localhost:7071` by default.

### Step 3: Test the Endpoints

**MCP Discovery (GET):**
```bash
curl http://localhost:7071/.well-known/mcp | jq
```

**MCP Message - Initialize (POST):**
```bash
curl -X POST http://localhost:7071/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-06-18",
      "clientInfo": {"name": "test-client", "version": "1.0.0"}
    }
  }' | jq
```

**MCP Message - List Tools (POST):**
```bash
curl -X POST http://localhost:7071/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {}
  }' | jq
```

**MCP Message - Call Tool (POST):**
```bash
# Example: NPI Lookup
curl -X POST http://localhost:7071/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "lookup_npi",
      "arguments": {"npi": "1234567890"}
    }
  }' | jq
```

### Step 4: Configure VS Code for Local Testing

Create or update `.vscode/mcp.json` for local development:

```jsonc
{
  "servers": {
    "local-npi-lookup": {
      "type": "http",
      "url": "http://localhost:7071/mcp"
    },
    "local-icd10-validation": {
      "type": "http",
      "url": "http://localhost:7072/mcp"
    },
    "local-cms-coverage": {
      "type": "http",
      "url": "http://localhost:7073/mcp"
    }
  }
}
```

### Running Multiple MCP Servers Locally

Each server needs a different port. Update `local.settings.json` for each:

```bash
# Terminal 1: NPI Lookup (port 7071)
cd src/mcp-servers/npi-lookup && func start --port 7071

# Terminal 2: ICD-10 Validation (port 7072)
cd src/mcp-servers/icd10-validation && func start --port 7072

# Terminal 3: CMS Coverage (port 7073)
cd src/mcp-servers/cms-coverage && func start --port 7073

# Terminal 4: FHIR Operations (port 7074)
cd src/mcp-servers/fhir-operations && func start --port 7074

# Terminal 5: PubMed (port 7075)
cd src/mcp-servers/pubmed && func start --port 7075

# Terminal 6: Clinical Trials (port 7076)
cd src/mcp-servers/clinical-trials && func start --port 7076
```

---

## Option 1b: Docker Compose (Recommended for Full-Stack Testing)

Run all 6 MCP servers in containers with a single command. No Python venvs, no Azurite — everything is self-contained.

### Quick Start

```bash
# Build and start all servers (detached)
make docker-up

# Or without Make:
docker compose up --build -d
```

### Verify

```bash
# Check container status
make docker-ps

# Run health checks against all servers
make docker-test

# Manually test a single server (include function key)
curl "http://localhost:7071/health?code=docker-default-key" | jq
curl "http://localhost:7071/.well-known/mcp?code=docker-default-key" | jq
```

> **Note:** The containers use a pre-provisioned function key `docker-default-key`
> for local testing. In production, Azure manages function keys automatically.
> You can pass the key as a `?code=` query param or an `x-functions-key` header.

### Logs & Teardown

```bash
# Follow all logs
make docker-logs

# Stop & remove containers
make docker-down
```

### Environment Variables

Pass optional env vars via a `.env` file in the repo root:

```env
# .env (optional)
FHIR_SERVER_URL=https://your-fhir-server.azurehealthcareapis.com
NCBI_API_KEY=your-ncbi-api-key
```

### Port Mapping (same as local)

| Server | Host Port | Container Port |
|--------|-----------|----------------|
| npi-lookup | 7071 | 80 |
| icd10-validation | 7072 | 80 |
| cms-coverage | 7073 | 80 |
| fhir-operations | 7074 | 80 |
| pubmed | 7075 | 80 |
| clinical-trials | 7076 | 80 |

### VS Code MCP Config for Docker

```jsonc
// .vscode/mcp.json — identical to local; ports are the same
{
  "servers": {
    "npi-lookup":        { "type": "http", "url": "http://localhost:7071/mcp?code=docker-default-key" },
    "icd10-validation":  { "type": "http", "url": "http://localhost:7072/mcp?code=docker-default-key" },
    "cms-coverage":      { "type": "http", "url": "http://localhost:7073/mcp?code=docker-default-key" },
    "fhir-operations":   { "type": "http", "url": "http://localhost:7074/mcp?code=docker-default-key" },
    "pubmed":            { "type": "http", "url": "http://localhost:7075/mcp?code=docker-default-key" },
    "clinical-trials":   { "type": "http", "url": "http://localhost:7076/mcp?code=docker-default-key" }
  }
}
```

---

## Option 2: Testing with Azure APIM (Deployed)

This tests the full production-like flow with OAuth authentication.

### Prerequisites

1. Deploy the infrastructure first:
   ```bash
   azd up
   ```

2. Get your APIM gateway URL:
   ```bash
   azd env get-values | grep SERVICE_APIM_GATEWAY_URL
   ```

### Test PRM Endpoint (OAuth Discovery)

```bash
APIM_URL="https://your-apim.azure-api.net"

# Test Protected Resource Metadata endpoint
curl "$APIM_URL/.well-known/oauth-protected-resource" | jq
```

Expected response:
```json
{
  "resource": "https://your-apim.azure-api.net",
  "authorization_servers": ["https://login.microsoftonline.com/{tenant-id}/v2.0"],
  "bearer_methods_supported": ["header"],
  "scopes_supported": ["{client-id}/user_impersonate"]
}
```

### Test with OAuth Token

1. **Get an access token** (using Azure CLI):
   ```bash
   # Get the MCP App Client ID from Azure
   MCP_CLIENT_ID=$(az ad app list --display-name "Healthcare MCP" --query "[0].appId" -o tsv)
   
   # Get token for the MCP app
   TOKEN=$(az account get-access-token --resource "api://$MCP_CLIENT_ID" --query accessToken -o tsv)
   ```

2. **Call MCP endpoints with token:**
   ```bash
   APIM_URL="https://your-apim.azure-api.net"
   
   # MCP Discovery
   curl -H "Authorization: Bearer $TOKEN" \
     "$APIM_URL/mcp/npi/.well-known/mcp" | jq
   
   # Initialize
   curl -X POST "$APIM_URL/mcp/npi/mcp" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "jsonrpc": "2.0",
       "id": 1,
       "method": "initialize",
       "params": {
         "protocolVersion": "2025-06-18",
         "clientInfo": {"name": "test-client", "version": "1.0.0"}
       }
     }' | jq
   
   # Call Tool
   curl -X POST "$APIM_URL/mcp/npi/mcp" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "jsonrpc": "2.0",
       "id": 2,
       "method": "tools/call",
       "params": {
         "name": "validate_npi",
         "arguments": {"npi": "1234567890"}
       }
     }' | jq
   ```

### Test Without Token (Should Return 401)

```bash
# This should return 401 Unauthorized with WWW-Authenticate header
curl -v "$APIM_URL/mcp/npi/mcp" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}'
```

Expected headers in response:
```
HTTP/2 401
WWW-Authenticate: Bearer error="invalid_token", resource_metadata="https://your-apim.azure-api.net/.well-known/oauth-protected-resource"
```

---

## Option 3: Local APIM Proxy (Advanced)

For testing the OAuth flow locally without deploying to Azure, you can use the MCP HTTP proxy script.

### Using the MCP HTTP Proxy

```bash
# Set environment variables
export MCP_TENANT_ID="your-tenant-id"
export MCP_CLIENT_ID="your-client-id"
export APIM_GATEWAY_URL="https://your-apim.azure-api.net"

# Run the proxy
node scripts/mcp-http-proxy.js
```

This creates a local proxy that handles OAuth token validation similar to APIM.

---

## MCP Server Port Reference

| Server | Default Local Port | APIM Path |
|--------|-------------------|-----------|
| NPI Lookup | 7071 | `/mcp/npi` |
| ICD-10 Validation | 7072 | `/mcp/icd10` |
| CMS Coverage | 7073 | `/mcp/cms` |
| FHIR Operations | 7074 | `/mcp/fhir` |
| PubMed | 7075 | `/mcp/pubmed` |
| Clinical Trials | 7076 | `/mcp/clinical-trials` |

---

## Debugging Tips

### View Function App Logs

```bash
# Local logging (in func start terminal)
func start --verbose

# Azure logs (after deployment)
az webapp log tail --name healthcaremcp-npi-lookup-func --resource-group your-rg
```

### Common Issues

1. **"No job functions found"**: Ensure `function_app.py` is in the correct directory
2. **401 from APIM**: Check OAuth token audience matches `McpClientId`
3. **502 from APIM**: Function App may be cold starting or VNet routing issue
4. **CORS errors**: Local testing doesn't need CORS; APIM handles it in production

### Health Check Endpoints

Each MCP server exposes a health endpoint:

```bash
# Local
curl http://localhost:7071/health

# Via APIM (no auth required for health)
curl "$APIM_URL/mcp/npi/health"
```

---

## VS Code MCP Configuration

### For Local Development

```jsonc
// .vscode/mcp.local.json
{
  "servers": {
    "local-npi-lookup": {
      "type": "http",
      "url": "http://localhost:7071/mcp"
    }
  }
}
```

### For Azure (Production)

```jsonc
// .vscode/mcp.json
{
  "servers": {
    "healthcare-npi-lookup": {
      "type": "http",
      "url": "https://your-apim.azure-api.net/mcp/npi/mcp"
    }
  }
  // OAuth is automatically discovered via PRM endpoint
}
```

---

## Quick Start Script

Save this as `scripts/local-test.sh`:

```bash
#!/bin/bash
set -e

SERVER=${1:-npi-lookup}
PORT=${2:-7071}

echo "Starting $SERVER on port $PORT..."

cd "src/mcp-servers/$SERVER"

# Create venv if not exists
if [ ! -d ".venv" ]; then
    python -m venv .venv
fi

source .venv/bin/activate
pip install -q -r requirements.txt

echo ""
echo "MCP Server: $SERVER"
echo "Discovery:  http://localhost:$PORT/.well-known/mcp"
echo "Messages:   http://localhost:$PORT/mcp"
echo "Health:     http://localhost:$PORT/health"
echo ""

func start --port $PORT
```

Usage:
```bash
chmod +x scripts/local-test.sh
./scripts/local-test.sh npi-lookup 7071
./scripts/local-test.sh icd10-validation 7072
```
