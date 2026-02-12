"""Integration tests for ICD-10 Validation MCP server."""
import pytest

pytestmark = pytest.mark.integration


class TestICD10Discovery:
    def test_well_known_mcp(self, mcp_icd10):
        resp = mcp_icd10.discover()
        assert resp.status_code == 200

    def test_initialize(self, mcp_icd10):
        resp = mcp_icd10.initialize()
        assert resp.status_code == 200

    def test_tools_list(self, mcp_icd10):
        resp = mcp_icd10.list_tools()
        tools = resp.json().get("result", {}).get("tools", [])
        tool_names = {t["name"] for t in tools}
        assert {"validate_icd10", "lookup_icd10", "search_icd10"} <= tool_names


class TestICD10Tools:
    def test_validate_known_code(self, mcp_icd10):
        resp = mcp_icd10.call_tool("validate_icd10", {"code": "E11.9"})
        assert resp.status_code == 200
        result = resp.json().get("result", {})
        assert not result.get("isError", False)

    def test_lookup_icd10(self, mcp_icd10):
        resp = mcp_icd10.call_tool("lookup_icd10", {"code": "E11.9"})
        assert resp.status_code == 200

    def test_search_icd10(self, mcp_icd10):
        resp = mcp_icd10.call_tool("search_icd10", {"query": "diabetes"})
        assert resp.status_code == 200
