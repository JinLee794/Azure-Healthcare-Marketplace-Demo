# Azure FHIR MCP Server

A Model Context Protocol (MCP) server that provides tools for interacting with Azure API for FHIR and healthcare coverage policies.

## Features

- **Patient Search**: Search for patients by name, identifier, birthdate, or gender
- **Observation Query**: Retrieve clinical observations (lab results, vital signs)
- **Coverage Verification**: Check insurance coverage for patients
- **Policy Lookup**: Determine prior authorization requirements for procedures
- **FHIR Validation**: Validate FHIR resources against Azure profiles

## Prerequisites

- Node.js 18+
- Azure subscription with Azure API for FHIR deployed
- Azure AD credentials configured (DefaultAzureCredential)

## Installation

```bash
npm install
npm run build
```

## Configuration

Set the following environment variables:

```bash
# Required: Azure FHIR server URL
export FHIR_SERVER_URL="https://your-workspace-fhir.azurehealthcareapis.com"

# Azure authentication (choose one method)
# Option 1: Azure CLI login
az login

# Option 2: Service Principal
export AZURE_CLIENT_ID="<client-id>"
export AZURE_CLIENT_SECRET="<client-secret>"
export AZURE_TENANT_ID="<tenant-id>"

# Option 3: Managed Identity (when running in Azure)
# No additional configuration needed
```

## Usage

### Standalone Server

```bash
npm start
```

### With Claude Desktop

Add to your Claude Desktop configuration (`~/.config/claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "azure-fhir": {
      "command": "node",
      "args": ["/path/to/azure-fhir-mcp-server/dist/index.js"],
      "env": {
        "FHIR_SERVER_URL": "https://your-fhir-server.azurehealthcareapis.com"
      }
    }
  }
}
```

### With VS Code / GitHub Copilot

Configure in your MCP settings:

```json
{
  "servers": {
    "azure-fhir": {
      "type": "stdio",
      "command": "node",
      "args": ["./azure-fhir-mcp-server/dist/index.js"]
    }
  }
}
```

## Available Tools

### `search_patients`
Search for patients in Azure FHIR.

**Parameters:**
- `name` (optional): Patient name (partial match)
- `identifier` (optional): Patient identifier (MRN, SSN, etc)
- `birthdate` (optional): Birth date (YYYY-MM-DD)
- `gender` (optional): male, female, other, unknown

### `get_patient`
Retrieve a specific patient by ID.

**Parameters:**
- `patientId` (required): FHIR Patient resource ID

### `search_observations`
Search for clinical observations.

**Parameters:**
- `patientId` (required): FHIR Patient resource ID
- `category` (optional): vital-signs, laboratory, social-history, imaging
- `code` (optional): LOINC code
- `dateFrom` (optional): Start date (YYYY-MM-DD)
- `dateTo` (optional): End date (YYYY-MM-DD)

### `check_coverage_policy`
Check prior authorization requirements.

**Parameters:**
- `cptCode` (required): CPT procedure code
- `icd10Code` (optional): ICD-10 diagnosis code
- `payerId` (optional): Insurance payer identifier

### `get_patient_coverage`
Get insurance coverage for a patient.

**Parameters:**
- `patientId` (required): FHIR Patient resource ID

### `validate_fhir_resource`
Validate a FHIR resource.

**Parameters:**
- `resourceType` (required): FHIR resource type
- `resource` (required): FHIR resource JSON
- `profile` (optional): Profile URL to validate against

## Development

```bash
# Run in development mode with hot reload
npm run dev

# Run tests
npm test

# Lint code
npm run lint
```

## Deployment to Azure Functions

See the deployment guide in `/docs/deployment.md` for instructions on deploying this MCP server as an Azure Function with HTTP triggers.

## Security

- Uses Azure DefaultAzureCredential for authentication
- Supports Managed Identity for production deployments
- All FHIR requests use Bearer token authentication
- Configure Private Link for HIPAA compliance

## License

MIT
