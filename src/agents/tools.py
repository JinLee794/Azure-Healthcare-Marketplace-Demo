"""
MCP Tool factory for Healthcare Agent Orchestration.

Creates MCPStreamableHTTPTool instances for each healthcare MCP server.
Each tool connects to the APIM passthrough endpoints and auto-discovers
available tools at runtime via the MCP protocol.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

import httpx
from agent_framework import MCPStreamableHTTPTool

from .config import APIM_SUBSCRIPTION_KEY_HEADER

if TYPE_CHECKING:
    from .config import MCPEndpoints

logger = logging.getLogger(__name__)


def _build_http_client(subscription_key: str | None) -> httpx.AsyncClient | None:
    """Create a shared httpx client that injects the APIM subscription key header."""
    if not subscription_key:
        return None
    return httpx.AsyncClient(
        headers={APIM_SUBSCRIPTION_KEY_HEADER: subscription_key},
        timeout=httpx.Timeout(60.0, connect=30.0),
    )


# ---------------------------------------------------------------------------
# Tool name → allowed_tools mapping
# Restricts each agent to only its relevant tool subset from the MCP server
# ---------------------------------------------------------------------------

NPI_TOOLS_COMPLIANCE = ["validate_npi", "lookup_npi"]
NPI_TOOLS_SEARCH = ["search_providers"]

ICD10_TOOLS_COMPLIANCE = ["validate_icd10", "lookup_icd10"]
ICD10_TOOLS_SEARCH = ["search_icd10", "get_icd10_chapter"]

CMS_TOOLS_ALL = [
    "search_coverage",
    "get_coverage_by_cpt",
    "get_coverage_by_icd10",
    "check_medical_necessity",
    "get_mac_jurisdiction",
]

FHIR_TOOLS_ALL = [
    "search_patients",
    "get_patient",
    "get_patient_conditions",
    "get_patient_medications",
    "get_patient_observations",
    "get_patient_encounters",
    "search_practitioners",
    "validate_resource",
]

PUBMED_TOOLS_ALL = [
    "search_pubmed",
    "get_article",
    "get_articles_batch",
    "get_article_abstract",
    "find_related_articles",
    "search_clinical_queries",
]

CLINICAL_TRIALS_TOOLS_ALL = [
    "search_trials",
    "get_trial",
    "get_trial_eligibility",
    "get_trial_locations",
    "search_by_condition",
    "get_trial_results",
]

COSMOS_RAG_TOOLS_SEARCH = [
    "hybrid_search",
    "vector_search",
]

COSMOS_RAG_TOOLS_INDEX = [
    "index_document",
]

COSMOS_RAG_TOOLS_AUDIT = [
    "record_audit_event",
    "get_audit_trail",
    "get_session_history",
]

COSMOS_RAG_TOOLS_ALL = COSMOS_RAG_TOOLS_SEARCH + COSMOS_RAG_TOOLS_INDEX + COSMOS_RAG_TOOLS_AUDIT


# ---------------------------------------------------------------------------
# Factory functions
# ---------------------------------------------------------------------------


def create_npi_tool(
    url: str,
    *,
    allowed_tools: list[str] | None = None,
    name: str = "Healthcare NPI Lookup",
    http_client: httpx.AsyncClient | None = None,
) -> MCPStreamableHTTPTool:
    """Create an MCP tool connected to the NPI Lookup server."""
    return MCPStreamableHTTPTool(
        name=name,
        url=url,
        allowed_tools=allowed_tools,
        description="NPI Registry — provider lookup, search, and Luhn validation",
        http_client=http_client,
        load_prompts=False,
    )


def create_icd10_tool(
    url: str,
    *,
    allowed_tools: list[str] | None = None,
    name: str = "Healthcare ICD-10 Validation",
    http_client: httpx.AsyncClient | None = None,
) -> MCPStreamableHTTPTool:
    """Create an MCP tool connected to the ICD-10 Validation server."""
    return MCPStreamableHTTPTool(
        name=name,
        url=url,
        allowed_tools=allowed_tools,
        description="ICD-10-CM code validation, lookup, and search via NLM Clinical Tables API",
        http_client=http_client,
        load_prompts=False,
    )


def create_cms_tool(
    url: str,
    *,
    allowed_tools: list[str] | None = None,
    name: str = "Healthcare CMS Coverage",
    http_client: httpx.AsyncClient | None = None,
) -> MCPStreamableHTTPTool:
    """Create an MCP tool connected to the CMS Coverage server."""
    return MCPStreamableHTTPTool(
        name=name,
        url=url,
        allowed_tools=allowed_tools,
        description="Medicare coverage policy lookup — LCD/NCD search, CPT/ICD-10 coverage, medical necessity",
        http_client=http_client,
        load_prompts=False,
    )


def create_fhir_tool(
    url: str,
    *,
    allowed_tools: list[str] | None = None,
    name: str = "Healthcare FHIR Operations",
    http_client: httpx.AsyncClient | None = None,
) -> MCPStreamableHTTPTool:
    """Create an MCP tool connected to the FHIR Operations server."""
    return MCPStreamableHTTPTool(
        name=name,
        url=url,
        allowed_tools=allowed_tools,
        description="Azure FHIR R4 — patient search, conditions, meds, observations, encounters, practitioners",
        http_client=http_client,
        load_prompts=False,
    )


def create_pubmed_tool(
    url: str,
    *,
    allowed_tools: list[str] | None = None,
    name: str = "Healthcare PubMed",
    http_client: httpx.AsyncClient | None = None,
) -> MCPStreamableHTTPTool:
    """Create an MCP tool connected to the PubMed server."""
    return MCPStreamableHTTPTool(
        name=name,
        url=url,
        allowed_tools=allowed_tools,
        description="PubMed / NCBI E-utilities — article search, retrieval, clinical queries, related articles",
        http_client=http_client,
        load_prompts=False,
    )


def create_clinical_trials_tool(
    url: str,
    *,
    allowed_tools: list[str] | None = None,
    name: str = "Healthcare Clinical Trials",
    http_client: httpx.AsyncClient | None = None,
) -> MCPStreamableHTTPTool:
    """Create an MCP tool connected to the Clinical Trials server."""
    return MCPStreamableHTTPTool(
        name=name,
        url=url,
        allowed_tools=allowed_tools,
        description="ClinicalTrials.gov v2 — trial search, eligibility, locations, results",
        http_client=http_client,
        load_prompts=False,
    )


def create_cosmos_rag_tool(
    url: str,
    *,
    allowed_tools: list[str] | None = None,
    name: str = "Healthcare Cosmos RAG & Audit",
    http_client: httpx.AsyncClient | None = None,
) -> MCPStreamableHTTPTool:
    """Create an MCP tool connected to the Cosmos DB RAG & Audit server."""
    return MCPStreamableHTTPTool(
        name=name,
        url=url,
        allowed_tools=allowed_tools,
        description="Cosmos DB RAG — hybrid search, document indexing, audit trail, agent memory",
        http_client=http_client,
        load_prompts=False,
    )


@dataclass
class MCPToolKit:
    """
    Convenience container that holds all MCP tool instances.

    Usage::

        toolkit = MCPToolKit.from_endpoints(config.endpoints, subscription_key="...")
        async with toolkit:
            agent = Agent(..., tools=toolkit.compliance_tools())
    """

    npi: MCPStreamableHTTPTool
    icd10: MCPStreamableHTTPTool
    cms: MCPStreamableHTTPTool
    fhir: MCPStreamableHTTPTool
    pubmed: MCPStreamableHTTPTool
    clinical_trials: MCPStreamableHTTPTool
    cosmos_rag: MCPStreamableHTTPTool

    # Keep a flat list so we can enter/exit all at once
    _all: list[MCPStreamableHTTPTool] = field(default_factory=list, repr=False)
    # Shared httpx client with APIM subscription key header
    _http_client: httpx.AsyncClient | None = field(default=None, repr=False)

    @classmethod
    def from_endpoints(
        cls,
        endpoints: MCPEndpoints,
        subscription_key: str | None = None,
    ) -> MCPToolKit:
        client = _build_http_client(subscription_key)
        npi = create_npi_tool(endpoints.npi, http_client=client)
        icd10 = create_icd10_tool(endpoints.icd10, http_client=client)
        cms = create_cms_tool(endpoints.cms, http_client=client)
        fhir = create_fhir_tool(endpoints.fhir, http_client=client)
        pubmed = create_pubmed_tool(endpoints.pubmed, http_client=client)
        clinical_trials = create_clinical_trials_tool(endpoints.clinical_trials, http_client=client)
        cosmos_rag = create_cosmos_rag_tool(endpoints.cosmos_rag, http_client=client)
        return cls(
            npi=npi,
            icd10=icd10,
            cms=cms,
            fhir=fhir,
            pubmed=pubmed,
            clinical_trials=clinical_trials,
            cosmos_rag=cosmos_rag,
            _all=[npi, icd10, cms, fhir, pubmed, clinical_trials, cosmos_rag],
            _http_client=client,
        )

    async def __aenter__(self) -> MCPToolKit:
        for tool in self._all:
            await tool.__aenter__()
        return self

    async def __aexit__(self, *exc: object) -> None:
        for tool in reversed(self._all):
            try:
                await tool.__aexit__(None, None, None)
            except Exception:
                logger.warning("Error closing MCP tool %s", tool.name, exc_info=True)
        # Close the shared httpx client
        if self._http_client:
            try:
                await self._http_client.aclose()
            except Exception:
                logger.warning("Error closing shared httpx client", exc_info=True)

    # ----- Convenience groupings for agents -----

    def compliance_tools(self) -> list[MCPStreamableHTTPTool]:
        """Tools for the Compliance Agent: NPI + ICD-10 validation."""
        return [
            create_npi_tool(
                self.npi.url, allowed_tools=NPI_TOOLS_COMPLIANCE, name="NPI (Compliance)", http_client=self._http_client
            ),
            create_icd10_tool(
                self.icd10.url,
                allowed_tools=ICD10_TOOLS_COMPLIANCE,
                name="ICD-10 (Compliance)",
                http_client=self._http_client,
            ),
        ]

    def clinical_reviewer_tools(self) -> list[MCPStreamableHTTPTool]:
        """Tools for the Clinical Reviewer Agent: FHIR + PubMed + Clinical Trials."""
        return [
            create_fhir_tool(self.fhir.url, name="FHIR (Clinical)", http_client=self._http_client),
            create_pubmed_tool(self.pubmed.url, name="PubMed (Clinical)", http_client=self._http_client),
            create_clinical_trials_tool(
                self.clinical_trials.url, name="Trials (Clinical)", http_client=self._http_client
            ),
        ]

    def coverage_tools(self) -> list[MCPStreamableHTTPTool]:
        """Tools for the Coverage Agent: CMS + ICD-10 search + RAG policy search."""
        return [
            create_cms_tool(self.cms.url, name="CMS (Coverage)", http_client=self._http_client),
            create_icd10_tool(
                self.icd10.url,
                allowed_tools=ICD10_TOOLS_SEARCH,
                name="ICD-10 (Coverage)",
                http_client=self._http_client,
            ),
            create_cosmos_rag_tool(
                self.cosmos_rag.url,
                allowed_tools=COSMOS_RAG_TOOLS_SEARCH,
                name="RAG (Coverage)",
                http_client=self._http_client,
            ),
        ]

    def patient_tools(self) -> list[MCPStreamableHTTPTool]:
        """Tools for Patient Data Agent: FHIR + NPI (provider search)."""
        return [
            create_fhir_tool(self.fhir.url, name="FHIR (Patient)", http_client=self._http_client),
            create_npi_tool(
                self.npi.url, allowed_tools=NPI_TOOLS_SEARCH, name="NPI (Patient)", http_client=self._http_client
            ),
        ]

    def literature_tools(self) -> list[MCPStreamableHTTPTool]:
        """Tools for the Literature Agent: PubMed."""
        return [
            create_pubmed_tool(self.pubmed.url, name="PubMed (Literature)", http_client=self._http_client),
        ]

    def trials_research_tools(self) -> list[MCPStreamableHTTPTool]:
        """Tools for the Trials Research Agent: Clinical Trials + PubMed."""
        return [
            create_clinical_trials_tool(
                self.clinical_trials.url, name="Trials (Research)", http_client=self._http_client
            ),
            create_pubmed_tool(self.pubmed.url, name="PubMed (Research)", http_client=self._http_client),
        ]

    # ----- Orchestrator-level groupings (skill-aligned) -----

    def rag_search_tools(self) -> list[MCPStreamableHTTPTool]:
        """Tools for RAG retrieval: hybrid and vector search over indexed documents."""
        return [
            create_cosmos_rag_tool(
                self.cosmos_rag.url,
                allowed_tools=COSMOS_RAG_TOOLS_SEARCH,
                name="RAG (Search)",
                http_client=self._http_client,
            ),
        ]

    def audit_tools(self) -> list[MCPStreamableHTTPTool]:
        """Tools for audit trail: record events, query trails and history."""
        return [
            create_cosmos_rag_tool(
                self.cosmos_rag.url,
                allowed_tools=COSMOS_RAG_TOOLS_AUDIT,
                name="Audit Trail",
                http_client=self._http_client,
            ),
        ]

    def indexing_tools(self) -> list[MCPStreamableHTTPTool]:
        """Tools for document indexing: chunk, embed, and store documents."""
        return [
            create_cosmos_rag_tool(
                self.cosmos_rag.url,
                allowed_tools=COSMOS_RAG_TOOLS_INDEX,
                name="RAG (Index)",
                http_client=self._http_client,
            ),
        ]

    def all_tools(self) -> list[MCPStreamableHTTPTool]:
        """All 7 MCP tools — for the top-level Healthcare Orchestrator."""
        return [
            create_npi_tool(self.npi.url, name="NPI Lookup", http_client=self._http_client),
            create_icd10_tool(self.icd10.url, name="ICD-10 Validation", http_client=self._http_client),
            create_cms_tool(self.cms.url, name="CMS Coverage", http_client=self._http_client),
            create_fhir_tool(self.fhir.url, name="FHIR Operations", http_client=self._http_client),
            create_pubmed_tool(self.pubmed.url, name="PubMed", http_client=self._http_client),
            create_clinical_trials_tool(
                self.clinical_trials.url, name="Clinical Trials", http_client=self._http_client
            ),
            create_cosmos_rag_tool(self.cosmos_rag.url, name="Cosmos RAG & Audit", http_client=self._http_client),
        ]

    def prior_auth_tools(self) -> list[MCPStreamableHTTPTool]:
        """All tools for the Prior Auth Orchestrator (all 7 MCP servers)."""
        return [
            create_npi_tool(self.npi.url, name="NPI (PA)", http_client=self._http_client),
            create_icd10_tool(self.icd10.url, name="ICD-10 (PA)", http_client=self._http_client),
            create_cms_tool(self.cms.url, name="CMS (PA)", http_client=self._http_client),
            create_fhir_tool(self.fhir.url, name="FHIR (PA)", http_client=self._http_client),
            create_pubmed_tool(self.pubmed.url, name="PubMed (PA)", http_client=self._http_client),
            create_clinical_trials_tool(self.clinical_trials.url, name="Trials (PA)", http_client=self._http_client),
            create_cosmos_rag_tool(self.cosmos_rag.url, name="RAG & Audit (PA)", http_client=self._http_client),
        ]

    def clinical_trial_protocol_tools(self) -> list[MCPStreamableHTTPTool]:
        """Tools for the Clinical Trial Protocol Orchestrator: Trials + PubMed."""
        return [
            create_clinical_trials_tool(
                self.clinical_trials.url, name="Trials (Protocol)", http_client=self._http_client
            ),
            create_pubmed_tool(self.pubmed.url, name="PubMed (Protocol)", http_client=self._http_client),
        ]

    def literature_evidence_tools(self) -> list[MCPStreamableHTTPTool]:
        """Tools for the Literature & Evidence Orchestrator: PubMed + Trials."""
        return [
            create_pubmed_tool(self.pubmed.url, name="PubMed (Evidence)", http_client=self._http_client),
            create_clinical_trials_tool(
                self.clinical_trials.url, name="Trials (Evidence)", http_client=self._http_client
            ),
        ]
