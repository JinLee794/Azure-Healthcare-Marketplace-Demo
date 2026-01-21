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
