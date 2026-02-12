"""
Centralized configuration for Healthcare Agent Orchestration.

MCP server URLs sourced from APIM passthrough endpoints.
Supports environment variable overrides for local development.
"""

import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()

# Default APIM base URL (passthrough — no OAuth, function key injected by APIM policy)
DEFAULT_APIM_BASE_URL = "https://healthcaremcp-apim-v4nrndu5paa6o.azure-api.net/mcp-pt"

# APIM subscription key header name
APIM_SUBSCRIPTION_KEY_HEADER = "Ocp-Apim-Subscription-Key"

# Local development ports (match docs/LOCAL-TESTING.md)
LOCAL_PORTS = {
    "npi": 7071,
    "icd10": 7072,
    "cms": 7073,
    "fhir": 7074,
    "pubmed": 7075,
    "clinical-trials": 7076,
    "cosmos-rag": 7077,
}


@dataclass(frozen=True)
class MCPEndpoints:
    """MCP server endpoint URLs."""

    npi: str
    icd10: str
    cms: str
    fhir: str
    pubmed: str
    clinical_trials: str
    cosmos_rag: str

    @classmethod
    def from_env(cls, local: bool = False) -> "MCPEndpoints":
        """Build endpoints from environment, with optional local override."""
        if local:
            return cls(
                npi=os.getenv("MCP_NPI_URL", f"http://localhost:{LOCAL_PORTS['npi']}/mcp"),
                icd10=os.getenv("MCP_ICD10_URL", f"http://localhost:{LOCAL_PORTS['icd10']}/mcp"),
                cms=os.getenv("MCP_CMS_URL", f"http://localhost:{LOCAL_PORTS['cms']}/mcp"),
                fhir=os.getenv("MCP_FHIR_URL", f"http://localhost:{LOCAL_PORTS['fhir']}/mcp"),
                pubmed=os.getenv("MCP_PUBMED_URL", f"http://localhost:{LOCAL_PORTS['pubmed']}/mcp"),
                clinical_trials=os.getenv(
                    "MCP_CLINICAL_TRIALS_URL", f"http://localhost:{LOCAL_PORTS['clinical-trials']}/mcp"
                ),
                cosmos_rag=os.getenv("MCP_COSMOS_RAG_URL", f"http://localhost:{LOCAL_PORTS['cosmos-rag']}/mcp"),
            )

        base = os.getenv("APIM_BASE_URL", DEFAULT_APIM_BASE_URL).rstrip("/")
        return cls(
            npi=os.getenv("MCP_NPI_URL", f"{base}/npi/mcp"),
            icd10=os.getenv("MCP_ICD10_URL", f"{base}/icd10/mcp"),
            cms=os.getenv("MCP_CMS_URL", f"{base}/cms/mcp"),
            fhir=os.getenv("MCP_FHIR_URL", f"{base}/fhir/mcp"),
            pubmed=os.getenv("MCP_PUBMED_URL", f"{base}/pubmed/mcp"),
            clinical_trials=os.getenv("MCP_CLINICAL_TRIALS_URL", f"{base}/clinical-trials/mcp"),
            cosmos_rag=os.getenv("MCP_COSMOS_RAG_URL", f"{base}/cosmos-rag/mcp"),
        )


@dataclass(frozen=True)
class AzureOpenAIConfig:
    """Azure OpenAI settings for agent LLM backend."""

    endpoint: str = ""
    deployment_name: str = "gpt-4o"
    api_version: str = "preview"
    temperature: float = 0.3

    @classmethod
    def from_env(cls) -> "AzureOpenAIConfig":
        return cls(
            endpoint=os.getenv("AZURE_OPENAI_ENDPOINT", ""),
            deployment_name=os.getenv("AZURE_OPENAI_DEPLOYMENT_NAME", "gpt-4o"),
            api_version=os.getenv("AZURE_OPENAI_API_VERSION", "preview"),
            temperature=float(os.getenv("AGENT_TEMPERATURE", "0.3")),
        )


@dataclass
class AgentConfig:
    """Top-level configuration bundle."""

    endpoints: MCPEndpoints
    openai: AzureOpenAIConfig
    apim_subscription_key: str = ""

    @classmethod
    def load(cls, local: bool = False) -> "AgentConfig":
        return cls(
            endpoints=MCPEndpoints.from_env(local=local),
            openai=AzureOpenAIConfig.from_env(),
            apim_subscription_key=os.getenv("APIM_SUBSCRIPTION_KEY", ""),
        )
