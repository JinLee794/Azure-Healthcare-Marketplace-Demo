"""Integration tests for NPI Lookup MCP server."""

import pytest

pytestmark = pytest.mark.integration


class TestNPILookupDiscovery:
    """MCP discovery and protocol tests."""

    def test_well_known_mcp(self, mcp_npi):
        resp = mcp_npi.discover()
        assert resp.status_code == 200

    def test_initialize(self, mcp_npi):
        resp = mcp_npi.initialize()
        assert resp.status_code == 200
        body = resp.json()
        assert body.get("result", {}).get("protocolVersion") == "2025-06-18"

    def test_tools_list_returns_expected_tools(self, mcp_npi):
        resp = mcp_npi.list_tools()
        assert resp.status_code == 200
        tools = resp.json().get("result", {}).get("tools", [])
        tool_names = {t["name"] for t in tools}
        assert {"lookup_npi", "search_providers", "validate_npi"} <= tool_names


class TestNPILookupTools:
    """Tool invocation tests."""

    def test_lookup_npi_valid(self, mcp_npi):
        resp = mcp_npi.call_tool("lookup_npi", {"npi": "1234567890"})
        assert resp.status_code == 200
        result = resp.json().get("result", {})
        assert not result.get("isError", False)

    def test_validate_npi_format(self, mcp_npi):
        resp = mcp_npi.call_tool("validate_npi", {"npi": "1234567890"})
        assert resp.status_code == 200

    def test_search_providers(self, mcp_npi):
        resp = mcp_npi.call_tool("search_providers", {"last_name": "Smith", "state": "NY"})
        assert resp.status_code == 200
        result = resp.json().get("result", {})
        assert not result.get("isError", False)
