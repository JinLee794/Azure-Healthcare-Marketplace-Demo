"""
Azure AI Foundry Agent Setup for Healthcare

This module provides utilities for registering healthcare MCP servers
with Azure AI Foundry agents.
"""

from azure.identity import DefaultAzureCredential
from typing import Optional
import os


def create_healthcare_agent(
    endpoint: str,
    agent_name: str = "healthcare-assistant",
    model: str = "gpt-4o",
    fhir_mcp_url: Optional[str] = None,
    coverage_mcp_url: Optional[str] = None,
) -> dict:
    """
    Create a healthcare agent with MCP server tools.
    
    Args:
        endpoint: Azure AI Foundry endpoint URL
        agent_name: Name for the agent
        model: Model to use (default: gpt-4o)
        fhir_mcp_url: URL for the FHIR MCP server
        coverage_mcp_url: URL for the coverage policy MCP server
        
    Returns:
        Agent configuration dictionary
    """
    
    # Build tools list
    tools = []
    
    if fhir_mcp_url:
        tools.append({
            "type": "mcp",
            "server_label": "azure_fhir",
            "server_url": fhir_mcp_url,
            "allowed_tools": [
                "search_patients",
                "get_patient",
                "search_observations",
                "get_patient_coverage",
                "validate_fhir_resource"
            ]
        })
    
    if coverage_mcp_url:
        tools.append({
            "type": "mcp",
            "server_label": "coverage_policy",
            "server_url": coverage_mcp_url,
            "allowed_tools": [
                "check_coverage_policy",
                "get_ncd_details",
                "get_lcd_details"
            ]
        })
    
    # Agent configuration
    agent_config = {
        "model": model,
        "name": agent_name,
        "instructions": """You are a healthcare administrative assistant specializing in:

1. **Patient Information**: Help look up patient demographics and clinical data
2. **Coverage Verification**: Check insurance coverage and eligibility
3. **Prior Authorization**: Determine PA requirements and assist with submissions
4. **Clinical Documentation**: Help with FHIR resource creation and validation

## Guidelines

- Always verify patient identity before disclosing PHI
- Check coverage policies before recommending procedures
- Use proper medical coding (ICD-10, CPT, LOINC)
- Maintain HIPAA compliance in all interactions
- Document all authorization decisions

## Available Tools

Use the available MCP tools to:
- Search for patients by name, MRN, or demographics
- Retrieve clinical observations and lab results
- Check insurance coverage for patients
- Verify prior authorization requirements
- Validate FHIR resources""",
        "tools": tools
    }
    
    return agent_config


def register_agent_with_foundry(agent_config: dict, endpoint: str):
    """
    Register an agent with Azure AI Foundry.
    
    Note: This requires the azure-ai-agents package when available.
    Currently returns the config for manual registration.
    
    Args:
        agent_config: Agent configuration dictionary
        endpoint: Azure AI Foundry endpoint
        
    Returns:
        Registration result or config for manual setup
    """
    
    try:
        # When azure-ai-agents SDK is available:
        # from azure.ai.agents.persistent import PersistentAgentsClient
        # 
        # credential = DefaultAzureCredential()
        # client = PersistentAgentsClient(
        #     endpoint=endpoint,
        #     credential=credential
        # )
        # 
        # agent = client.agents.create(**agent_config)
        # return {"status": "created", "agent_id": agent.id}
        
        # For now, return config for manual registration
        return {
            "status": "config_generated",
            "message": "Use this configuration to register the agent in Azure AI Foundry portal",
            "config": agent_config,
            "endpoint": endpoint
        }
        
    except Exception as e:
        return {
            "status": "error",
            "message": str(e),
            "config": agent_config
        }


# Example usage and configuration templates
EXAMPLE_CONFIGS = {
    "development": {
        "endpoint": "https://your-foundry-dev.api.azureml.ms",
        "fhir_mcp_url": "http://localhost:3000/mcp",
        "coverage_mcp_url": "http://localhost:3001/mcp",
    },
    "staging": {
        "endpoint": "https://your-foundry-staging.api.azureml.ms",
        "fhir_mcp_url": "https://healthcare-mcp-staging.azurewebsites.net/mcp",
        "coverage_mcp_url": "https://coverage-mcp-staging.azurewebsites.net/mcp",
    },
    "production": {
        "endpoint": "https://your-foundry.api.azureml.ms",
        "fhir_mcp_url": "https://healthcare-mcp.azurewebsites.net/mcp",
        "coverage_mcp_url": "https://coverage-mcp.azurewebsites.net/mcp",
    }
}


if __name__ == "__main__":
    # Example: Create agent configuration
    env = os.getenv("ENVIRONMENT", "development")
    config = EXAMPLE_CONFIGS.get(env, EXAMPLE_CONFIGS["development"])
    
    agent = create_healthcare_agent(
        endpoint=config["endpoint"],
        fhir_mcp_url=config.get("fhir_mcp_url"),
        coverage_mcp_url=config.get("coverage_mcp_url"),
    )
    
    print("Generated agent configuration:")
    import json
    print(json.dumps(agent, indent=2))
