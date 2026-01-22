# Agent.md - Healthcare Marketplace for Azure

## Project Overview
Building an Azure-native healthcare marketplace with Skills, MCP Servers, and AI Agent integrations inspired by the Anthropic healthcare marketplace architecture.

## Beads (bd) Change Tracking

### Active Bead: `bd-001-init`
**Status**: ✅ Complete  
**Description**: Initial project scaffold creation

#### Changes Tracked
- [x] Project structure initialization
- [x] Skills layer scaffolds (azure-fhir-developer, azure-health-data-services, prior-auth-azure)
- [x] MCP server scaffold (azure-fhir-mcp-server)
- [x] Azure Foundry integration scaffold
- [x] VS Code extension scaffold
- [x] Configuration files (package.json, tsconfig.json, etc.)

#### Files Created
```
.github/skills/azure-fhir-developer/
├── SKILL.md
└── references/
    ├── fhir-r4-resources.md
    └── azure-fhir-api.md

.github/skills/azure-health-data-services/
├── SKILL.md
└── references/
    └── dicom-api.md

.github/skills/prior-auth-azure/
├── SKILL.md
└── templates/
    └── prior-auth-request.json

azure-fhir-mcp-server/
├── package.json
├── tsconfig.json
├── README.md
└── src/
    ├── index.ts
    ├── fhir-client.ts
    └── coverage-policy.ts

foundry-integration/
├── README.md
├── agent_setup.py
├── agent_config.yaml
└── tools_catalog.json

vscode-extension/
├── package.json
├── tsconfig.json
├── README.md
└── src/
    ├── extension.ts
    ├── chat/
    │   └── chat-handler.ts
    └── skills/
        └── skill-loader.ts
```

---

## Bead History

| Bead ID | Description | Status | Date |
|---------|-------------|--------|------|
| bd-001-init | Initial project scaffold | ✅ Complete | 2026-01-21 |
| bd-002-apim | Anthropic parity + APIM architecture | ✅ Complete | 2026-01-21 |
| bd-003-iac | Production IaC with private networking | ✅ Complete | 2026-01-21 |

---

### Bead: `bd-003-iac`
**Status**: ✅ Complete  
**Description**: Production-grade Infrastructure as Code with APIM Standard v2, private VNet, Function Apps, and AI Foundry

#### Changes Tracked
- [x] VNet Bicep module with 4 subnets (agent, pe, apim, function)
- [x] APIM Standard v2 module with Healthcare MCP APIs
- [x] Private endpoints and DNS zones module
- [x] Function Apps module for MCP servers (6x)
- [x] AI Foundry module with model deployments
- [x] Dependent resources (Storage, AI Search, Cosmos DB, App Insights)
- [x] Main orchestration template
- [x] Updated Jupyter notebook for deployment walkthrough

#### Files Created
```
deploy/infra/
├── main.bicep                     # Main orchestration template
├── main.bicepparam                # Parameter file
└── modules/
    ├── vnet.bicep                 # VNet with 4 subnets
    ├── apim.bicep                 # APIM Standard v2 + MCP APIs
    ├── private-endpoints.bicep    # Private endpoints + DNS zones
    ├── function-apps.bicep        # 6 Function Apps for MCP servers
    ├── ai-foundry.bicep           # AI Services + Project
    └── dependent-resources.bicep  # Storage, Search, Cosmos, Insights

deploy/
└── deploy-healthcare-mcp.ipynb    # Deployment notebook (updated)
```

#### Network Architecture
```
VNet: 192.168.0.0/16
├── agent-subnet (192.168.0.0/24)    - AI Foundry agents (Container Apps)
├── pe-subnet (192.168.1.0/24)       - Private endpoints for all services
├── apim-subnet (192.168.2.0/24)     - APIM Standard v2
└── function-subnet (192.168.3.0/24) - Function Apps (MCP servers)
```

#### Private Endpoints Configured
| Service | Group ID | DNS Zone |
|---------|----------|----------|
| AI Services | account | privatelink.services.ai.azure.com |
| AI Search | searchService | privatelink.search.windows.net |
| Storage | blob | privatelink.blob.core.windows.net |
| Cosmos DB | Sql | privatelink.documents.azure.com |
| APIM | Gateway | privatelink.azure-api.net |
| Function Apps | sites | privatelink.azurewebsites.net |

---

### Bead: `bd-002-apim`
**Status**: ✅ Complete  
**Description**: Update skills to match Anthropic healthcare marketplace structure with Azure APIM-based MCP architecture

#### Changes Tracked
- [x] APIM architecture design for secure MCP exposure
- [x] Clinical trial protocol skill with full waypoint architecture
- [x] Prior auth skill update with subskill structure and demo assets
- [x] Azure FHIR developer skill update (Anthropic format)
- [x] Azure Health Data Services skill update + DICOM/MedTech references
- [x] Plugin marketplace configuration (.claude-plugin/marketplace.json)

#### Files Created/Updated
```
docs/architecture/
└── APIM-ARCHITECTURE.md          # Azure APIM design for MCP security

.github/skills/clinical-trial-protocol/
├── SKILL.md                       # 6-waypoint workflow for FDA protocols
├── references/
│   ├── 00-initialize-intervention.md
│   ├── 01-research-protocols.md
│   ├── 02-protocol-foundation.md
│   ├── 03-protocol-intervention.md
│   ├── 04-protocol-operations.md
│   └── 05-concatenate-protocol.md
├── scripts/
│   └── sample_size_calculator.py  # Statistical power analysis
└── assets/
    └── FDA-Clinical-Protocol-Template.md

.github/skills/prior-auth-azure/
├── SKILL.md                       # Updated workflow with MCP calls
├── references/
│   ├── 01-intake-assessment.md    # Validation subskill
│   ├── 02-decision-notification.md # Decision subskill
│   └── rubric.md                  # Decision rules
└── assets/sample/
    ├── pa_request.json
    ├── ct_chest_report.txt
    ├── pet_scan_report.txt
    └── pulmonology_consultation.txt

.github/skills/azure-fhir-developer/
└── SKILL.md                       # Comprehensive FHIR R4 reference

.github/skills/azure-health-data-services/
├── SKILL.md                       # Workspace + service overview
└── references/
    ├── 01-dicom-service.md        # DICOMweb operations
    └── 02-medtech-service.md      # IoT device ingestion

.claude-plugin/
└── marketplace.json               # Plugin registry with skills & MCP servers
```

#### MCP Server URLs (via Azure APIM)
| Service | APIM Endpoint |
|---------|---------------|
| CMS Coverage | `https://healthcare-mcp.azure-api.net/cms-coverage/mcp` |
| NPI Registry | `https://healthcare-mcp.azure-api.net/npi-registry/mcp` |
| ICD-10 Codes | `https://healthcare-mcp.azure-api.net/icd10/mcp` |
| Clinical Trials | `https://healthcare-mcp.azure-api.net/clinical-trials/mcp` |
| FHIR Operations | `https://healthcare-mcp.azure-api.net/fhir/mcp` |
| PubMed | `https://healthcare-mcp.azure-api.net/pubmed/mcp` |

---

## Git Integration

### Commit Convention
```
bd-XXX: <type>(<scope>): <description>

Types: feat, fix, docs, style, refactor, test, chore
```

### Example Commits
```bash
git commit -m "bd-001-init: feat(scaffold): initialize project structure"
git commit -m "bd-001-init: feat(skills): add azure-fhir-developer skill"
git commit -m "bd-001-init: feat(mcp): scaffold azure-fhir-mcp-server"
```

---

## Architecture Layers

1. **Skills Layer** - Static knowledge in SKILL.md files
2. **MCP Server Layer** - Dynamic tools via Azure Functions
3. **Azure Foundry Layer** - Agent registration and orchestration
4. **Distribution Layer** - VS Code extension + Foundry catalog

---

## Quick Commands

```bash
# Start new bead
bd new <description>

# Complete current bead
bd complete

# List bead history
bd list

# View current bead changes
bd status
```
