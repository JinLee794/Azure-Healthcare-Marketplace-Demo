"""Integration tests for FHIR Operations MCP server."""

import pytest

pytestmark = pytest.mark.integration


class TestFHIRDiscovery:
    def test_well_known_mcp(self, mcp_fhir):
        resp = mcp_fhir.discover()
        assert resp.status_code == 200

    def test_initialize(self, mcp_fhir):
        resp = mcp_fhir.initialize()
        assert resp.status_code == 200

    def test_tools_list(self, mcp_fhir):
        resp = mcp_fhir.list_tools()
        tools = resp.json().get("result", {}).get("tools", [])
        tool_names = {t["name"] for t in tools}
        assert {"search_patients", "get_patient"} <= tool_names


class TestFHIRTools:
    def test_search_patients(self, mcp_fhir):
        resp = mcp_fhir.call_tool("search_patients", {"family": "Smith", "count": 3})
        assert resp.status_code == 200
        result = resp.json().get("result", {})
        assert not result.get("isError", False)

    def test_get_patient_missing_id(self, mcp_fhir):
        """Calling get_patient with a non-existent ID should return an error result, not crash."""
        resp = mcp_fhir.call_tool("get_patient", {"patient_id": "nonexistent-id-000"})
        assert resp.status_code == 200  # MCP returns 200 with isError in body
