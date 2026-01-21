# Azure Healthcare Marketplace

An Azure-native healthcare marketplace providing Skills, MCP Servers, and AI Agent integrations for healthcare development.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AZURE HEALTHCARE MARKETPLACE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐         │
│  │  GitHub Repo    │    │  Azure AI       │    │  VS Code        │         │
│  │  (Skills Store) │    │  Foundry Agents │    │  Extension      │         │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘         │
│           │                      │                      │                   │
│           ▼                      ▼                      ▼                   │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │                    MCP SERVER LAYER                              │       │
│  │  (Azure Functions / Azure Container Apps)                        │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                    │                                        │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │                    AZURE HEALTH DATA SERVICES                    │       │
│  │  • Azure API for FHIR    • DICOM Service    • MedTech Service   │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
healthcare-for-microsoft/
├── .github/
│   └── skills/                    # Healthcare skills (static knowledge)
│       ├── azure-fhir-developer/  # Azure FHIR development skill
│       ├── azure-health-data-services/  # DICOM & MedTech skill
│       └── prior-auth-azure/      # Prior authorization skill
│
├── azure-fhir-mcp-server/         # MCP server for FHIR operations
│   └── src/
│       ├── index.ts               # Server entry point
│       ├── fhir-client.ts         # Azure FHIR client
│       └── coverage-policy.ts     # Coverage policy service
│
├── foundry-integration/           # Azure AI Foundry integration
│   ├── agent_setup.py             # Agent registration utilities
│   ├── agent_config.yaml          # Declarative agent config
│   └── tools_catalog.json         # Foundry tools catalog entry
│
├── vscode-extension/              # VS Code chat participant
│   └── src/
│       ├── extension.ts           # Extension entry point
│       ├── chat/                   # Chat handlers
│       └── skills/                 # Skill loader
│
├── Agent.md                       # Beads change tracking
└── README.md                      # This file
```

## Components

### 1. Skills Layer

Static knowledge injected into LLM context. Skills teach the AI *how* to do healthcare development tasks.

**Available Skills:**
- `azure-fhir-developer` - Azure API for FHIR, SMART on FHIR, bulk operations
- `azure-health-data-services` - DICOM imaging, MedTech device data
- `prior-auth-azure` - Prior authorization workflows, X12 278, Da Vinci guides

### 2. MCP Server Layer

Dynamic tools callable by AI agents for real-time data access.

**Available Tools:**
- `search_patients` - Search patients in Azure FHIR
- `get_patient` - Retrieve patient by ID
- `search_observations` - Query clinical observations
- `check_coverage_policy` - Check PA requirements
- `validate_fhir_resource` - Validate FHIR resources

### 3. Foundry Integration

Register MCP servers with Azure AI Foundry for agent orchestration.

### 4. VS Code Extension

GitHub Copilot chat participant with healthcare-specific commands.

## Quick Start

### Prerequisites

- Node.js 18+
- Azure subscription
- Azure Health Data Services deployed
- GitHub Copilot (for VS Code extension)

### Setup MCP Server

```bash
cd azure-fhir-mcp-server
npm install
npm run build

# Configure environment
export FHIR_SERVER_URL="https://your-fhir.azurehealthcareapis.com"

# Start server
npm start
```

### Use Skills with Copilot

Skills are automatically loaded from `.github/skills/` directory. Use `@healthcare` in GitHub Copilot Chat:

```
@healthcare How do I create a Patient resource?
@healthcare /fhir What's the search syntax for observations?
@healthcare /pa Does CPT 27447 require prior auth?
```

## Development Phases

See [anthropic-healthcare-analysis.md](./anthropic-healthcare-analysis.md) for detailed architecture analysis.

### Phase 1: Skills Layer ✅
- [x] azure-fhir-developer skill
- [x] azure-health-data-services skill  
- [x] prior-auth-azure skill

### Phase 2: MCP Server Layer ✅
- [x] MCP server scaffold
- [x] FHIR client implementation
- [x] Coverage policy service

### Phase 3: Foundry Integration ✅
- [x] Agent configuration
- [x] Tools catalog entry
- [x] Registration utilities

### Phase 4: VS Code Extension ✅
- [x] Chat participant
- [x] Skill loader
- [x] Commands (/fhir, /dicom, /pa, /validate)

### Phase 5: Production (TODO)
- [ ] Deploy MCP server to Azure Functions
- [ ] Configure Private Link
- [ ] Set up monitoring
- [ ] HIPAA compliance review

## Security

- All FHIR endpoints require Azure AD authentication
- MCP servers use managed identity
- Private Link for HIPAA compliance
- Audit logging enabled

## References

- [MCP Specification](https://modelcontextprotocol.io/docs)
- [Azure AI Foundry MCP Integration](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/tools/model-context-protocol)
- [Azure Health Data Services](https://learn.microsoft.com/en-us/azure/healthcare-apis/)
- [VS Code Chat Extensions](https://code.visualstudio.com/api/extension-guides/chat)

## License

MIT
