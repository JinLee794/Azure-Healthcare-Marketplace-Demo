"""
Shared pytest fixtures for MCP server integration tests.

These fixtures provide HTTP clients and helper utilities for testing
MCP servers running locally or in Docker.
"""
import os
import pytest
import httpx

# Default base URLs — override via env vars for CI or Docker
MCP_SERVER_PORTS = {
    "npi-lookup": int(os.getenv("MCP_NPI_PORT", "7071")),
    "icd10-validation": int(os.getenv("MCP_ICD10_PORT", "7072")),
    "cms-coverage": int(os.getenv("MCP_CMS_PORT", "7073")),
    "fhir-operations": int(os.getenv("MCP_FHIR_PORT", "7074")),
    "pubmed": int(os.getenv("MCP_PUBMED_PORT", "7075")),
    "clinical-trials": int(os.getenv("MCP_CLINICALTRIALS_PORT", "7076")),
}

MCP_BASE_HOST = os.getenv("MCP_BASE_HOST", "http://localhost")
MCP_FUNCTION_KEY = os.getenv("MCP_FUNCTION_KEY", "")  # empty for local, set for Docker


def _base_url(server_name: str) -> str:
    port = MCP_SERVER_PORTS[server_name]
    return f"{MCP_BASE_HOST}:{port}"


def _headers() -> dict:
    headers = {"Content-Type": "application/json"}
    if MCP_FUNCTION_KEY:
        headers["x-functions-key"] = MCP_FUNCTION_KEY
    return headers


# ---------------------------------------------------------------------------
# Generic MCP helpers
# ---------------------------------------------------------------------------

class MCPClient:
    """Lightweight wrapper for MCP JSON-RPC calls."""

    def __init__(self, base_url: str, headers: dict | None = None):
        self.base_url = base_url
        self.headers = headers or _headers()
        self._http = httpx.Client(base_url=base_url, headers=self.headers, timeout=30.0)
        self._id = 0

    def _next_id(self) -> int:
        self._id += 1
        return self._id

    # -- Discovery -----------------------------------------------------------
    def discover(self) -> httpx.Response:
        return self._http.get("/.well-known/mcp")

    # -- JSON-RPC helpers ----------------------------------------------------
    def rpc(self, method: str, params: dict | None = None) -> httpx.Response:
        payload = {
            "jsonrpc": "2.0",
            "id": self._next_id(),
            "method": method,
            "params": params or {},
        }
        return self._http.post("/mcp", json=payload)

    def initialize(self) -> httpx.Response:
        return self.rpc("initialize", {
            "protocolVersion": "2025-06-18",
            "clientInfo": {"name": "pytest", "version": "1.0.0"},
        })

    def list_tools(self) -> httpx.Response:
        return self.rpc("tools/list")

    def call_tool(self, name: str, arguments: dict | None = None) -> httpx.Response:
        return self.rpc("tools/call", {"name": name, "arguments": arguments or {}})

    def close(self):
        self._http.close()


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def mcp_npi(request) -> MCPClient:
    client = MCPClient(_base_url("npi-lookup"))
    yield client
    client.close()


@pytest.fixture(scope="session")
def mcp_icd10(request) -> MCPClient:
    client = MCPClient(_base_url("icd10-validation"))
    yield client
    client.close()


@pytest.fixture(scope="session")
def mcp_cms(request) -> MCPClient:
    client = MCPClient(_base_url("cms-coverage"))
    yield client
    client.close()


@pytest.fixture(scope="session")
def mcp_fhir(request) -> MCPClient:
    client = MCPClient(_base_url("fhir-operations"))
    yield client
    client.close()


@pytest.fixture(scope="session")
def mcp_pubmed(request) -> MCPClient:
    client = MCPClient(_base_url("pubmed"))
    yield client
    client.close()


@pytest.fixture(scope="session")
def mcp_clinical_trials(request) -> MCPClient:
    client = MCPClient(_base_url("clinical-trials"))
    yield client
    client.close()
