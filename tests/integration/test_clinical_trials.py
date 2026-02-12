"""Integration tests for Clinical Trials MCP server."""
import pytest

pytestmark = pytest.mark.integration


class TestClinicalTrialsDiscovery:
    def test_well_known_mcp(self, mcp_clinical_trials):
        resp = mcp_clinical_trials.discover()
        assert resp.status_code == 200

    def test_initialize(self, mcp_clinical_trials):
        resp = mcp_clinical_trials.initialize()
        assert resp.status_code == 200

    def test_tools_list(self, mcp_clinical_trials):
        resp = mcp_clinical_trials.list_tools()
        tools = resp.json().get("result", {}).get("tools", [])
        tool_names = {t["name"] for t in tools}
        assert {"search_trials", "get_trial", "search_by_condition"} <= tool_names


class TestClinicalTrialsTools:
    def test_search_trials(self, mcp_clinical_trials):
        resp = mcp_clinical_trials.call_tool("search_trials", {
            "condition": "non-small cell lung cancer",
            "page_size": 3,
        })
        assert resp.status_code == 200
        result = resp.json().get("result", {})
        assert not result.get("isError", False)

    def test_search_by_condition(self, mcp_clinical_trials):
        resp = mcp_clinical_trials.call_tool("search_by_condition", {
            "condition": "breast cancer",
            "location": "New York",
        })
        assert resp.status_code == 200
