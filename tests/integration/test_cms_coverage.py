"""Integration tests for CMS Coverage MCP server."""
import pytest

pytestmark = pytest.mark.integration


class TestCMSCoverageDiscovery:
    def test_well_known_mcp(self, mcp_cms):
        resp = mcp_cms.discover()
        assert resp.status_code == 200

    def test_initialize(self, mcp_cms):
        resp = mcp_cms.initialize()
        assert resp.status_code == 200

    def test_tools_list(self, mcp_cms):
        resp = mcp_cms.list_tools()
        tools = resp.json().get("result", {}).get("tools", [])
        tool_names = {t["name"] for t in tools}
        assert {"search_coverage", "get_coverage_by_cpt", "check_medical_necessity"} <= tool_names


class TestCMSCoverageTools:
    def test_get_coverage_by_cpt(self, mcp_cms):
        resp = mcp_cms.call_tool("get_coverage_by_cpt", {"cpt_code": "27447"})
        assert resp.status_code == 200
        result = resp.json().get("result", {})
        assert not result.get("isError", False)

    def test_get_coverage_by_icd10(self, mcp_cms):
        resp = mcp_cms.call_tool("get_coverage_by_icd10", {"icd10_code": "M17.11"})
        assert resp.status_code == 200

    def test_check_medical_necessity(self, mcp_cms):
        resp = mcp_cms.call_tool("check_medical_necessity", {
            "cpt_code": "27447",
            "icd10_codes": ["M17.11"],
        })
        assert resp.status_code == 200
