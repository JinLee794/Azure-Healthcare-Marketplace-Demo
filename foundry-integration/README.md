# Azure AI Foundry Integration

This directory contains scripts and configurations for integrating healthcare MCP servers with Azure AI Foundry.

## Overview

Azure AI Foundry supports MCP (Model Context Protocol) servers as tools for agents. This integration allows you to:

1. Register healthcare MCP servers as callable tools
2. Create agents with healthcare-specific instructions
3. Manage tool permissions and access control

## Files

- `agent_setup.py` - Python utilities for creating and registering agents
- `agent_config.yaml` - Declarative agent configuration
- `tools_catalog.json` - Tools catalog entry for Foundry

## Quick Start

### 1. Set Environment Variables

```bash
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_RESOURCE_GROUP="your-resource-group"
export FOUNDRY_ENDPOINT="https://your-foundry.api.azureml.ms"
export FHIR_MCP_URL="https://healthcare-mcp.azurewebsites.net/mcp"
```

### 2. Create Agent Configuration

```python
from agent_setup import create_healthcare_agent

agent_config = create_healthcare_agent(
    endpoint="https://your-foundry.api.azureml.ms",
    fhir_mcp_url="https://healthcare-mcp.azurewebsites.net/mcp",
    coverage_mcp_url="https://coverage-mcp.azurewebsites.net/mcp"
)
```

### 3. Register in Azure AI Foundry

Use the Azure portal or SDK to register the agent:

```python
from azure.ai.agents.persistent import PersistentAgentsClient
from azure.identity import DefaultAzureCredential

client = PersistentAgentsClient(
    endpoint="https://your-foundry.api.azureml.ms",
    credential=DefaultAzureCredential()
)

agent = client.agents.create(**agent_config)
print(f"Created agent: {agent.id}")
```

## Agent Configuration

### Instructions Template

The agent is configured with healthcare-specific instructions that guide it to:

1. **Verify Identity**: Always confirm patient identity before accessing PHI
2. **Check Coverage**: Verify insurance coverage before procedures
3. **Use Proper Coding**: Apply correct ICD-10, CPT, and LOINC codes
4. **Maintain Compliance**: Follow HIPAA guidelines

### Available Tools

| Tool | Description | MCP Server |
|------|-------------|------------|
| `search_patients` | Search patients by demographics | azure-fhir |
| `get_patient` | Retrieve patient by ID | azure-fhir |
| `search_observations` | Get clinical observations | azure-fhir |
| `check_coverage_policy` | Check PA requirements | coverage-policy |
| `get_patient_coverage` | Get insurance info | azure-fhir |

## Security Considerations

1. **Authentication**: MCP servers should require Azure AD authentication
2. **Authorization**: Use RBAC to control tool access
3. **Audit Logging**: Enable diagnostic logging for all tool calls
4. **Data Residency**: Deploy servers in compliant regions

## Deployment Environments

| Environment | Foundry Endpoint | MCP Server URL |
|-------------|------------------|----------------|
| Development | localhost:5000 | localhost:3000 |
| Staging | foundry-staging.api.azureml.ms | mcp-staging.azurewebsites.net |
| Production | foundry.api.azureml.ms | mcp.azurewebsites.net |

## References

- [Azure AI Foundry MCP Integration](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/tools/model-context-protocol)
- [Foundry Tools Catalog](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/concepts/tool-catalog)
