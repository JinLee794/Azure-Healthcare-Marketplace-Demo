"""Integration tests for PubMed MCP server."""

import pytest

pytestmark = pytest.mark.integration


class TestPubMedDiscovery:
    def test_well_known_mcp(self, mcp_pubmed):
        resp = mcp_pubmed.discover()
        assert resp.status_code == 200

    def test_initialize(self, mcp_pubmed):
        resp = mcp_pubmed.initialize()
        assert resp.status_code == 200

    def test_tools_list(self, mcp_pubmed):
        resp = mcp_pubmed.list_tools()
        tools = resp.json().get("result", {}).get("tools", [])
        tool_names = {t["name"] for t in tools}
        assert {"search_pubmed", "get_article", "get_article_abstract"} <= tool_names


class TestPubMedTools:
    def test_search_pubmed(self, mcp_pubmed):
        resp = mcp_pubmed.call_tool(
            "search_pubmed",
            {
                "query": "type 2 diabetes glp-1",
                "max_results": 3,
            },
        )
        assert resp.status_code == 200
        result = resp.json().get("result", {})
        assert not result.get("isError", False)

    def test_search_clinical_queries(self, mcp_pubmed):
        resp = mcp_pubmed.call_tool(
            "search_clinical_queries",
            {
                "query": "metformin cardiovascular outcomes",
                "category": "therapy",
                "max_results": 3,
            },
        )
        assert resp.status_code == 200
