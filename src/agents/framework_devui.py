"""
Agent Framework DevUI integration — serves actual multi-agent workflow
orchestrations via the official Microsoft Agent Framework Developer UI.

Instead of monolithic single agents, the DevUI presents the real
workflow compositions using SequentialBuilder and ConcurrentBuilder,
matching the multi-agent patterns in src/agents/workflows/:

  1. HealthcareOrchestrator  → top-level triage (single agent, all 6 MCP tools)
  2. Prior Auth Workflow     → Sequential(Compliance → Concurrent(Clinical, Coverage) → Synthesis)
  3. Clinical Trial Protocol → Sequential(TrialsResearch → ProtocolDraft)
  4. PatientDataAgent        → single agent (FHIR + NPI)
  5. Literature & Evidence   → Concurrent(Literature, TrialsCorrelation)

The framework DevUI provides:
  - React-based chat interface with debug panel
  - Real-time event/trace streaming (OpenTelemetry)
  - Entity discovery showing workflow composition
  - Hot-reload and deployment support

Usage:
    python -m agents --framework-devui
    python -m agents --framework-devui --local --port 8080
"""

from __future__ import annotations

import logging
import os
from pathlib import Path

from dotenv import load_dotenv

logger = logging.getLogger(__name__)

# Load .env from the agents directory (same as the Gradio DevUI)
_ENV_FILE = Path(__file__).parent / ".env"
if _ENV_FILE.exists():
    load_dotenv(_ENV_FILE, override=True)


def _create_entities(local: bool = False) -> list:
    """
    Build actual multi-agent workflow orchestrations for the framework DevUI.

    Instead of monolithic single agents with giant instruction prompts,
    this creates the real workflow compositions using SequentialBuilder
    and ConcurrentBuilder — matching the patterns in src/agents/workflows/:

      1. HealthcareOrchestrator      → single agent, all 6 MCP tools (triage)
      2. Prior Auth Workflow          → Sequential → Concurrent → Sequential
      3. Clinical Trial Protocol      → Sequential (Research → Draft)
      4. PatientDataAgent             → single agent, FHIR + NPI
      5. Literature & Evidence        → Concurrent (Literature ‖ Trials)

    The DevUI discovers entities and shows their composition structure.
    """
    from azure.identity import AzureCliCredential, DefaultAzureCredential

    from agent_framework import Agent, MCPStreamableHTTPTool
    from agent_framework.azure import AzureOpenAIResponsesClient
    from agent_framework_orchestrations import ConcurrentBuilder, SequentialBuilder

    from .agents import (
        create_compliance_agent,
        create_clinical_reviewer_agent,
        create_coverage_agent,
        create_synthesis_agent,
        create_healthcare_triage_orchestrator,
        create_patient_summary_agent,
        create_literature_search_agent,
        create_trials_research_agent,
        create_trials_correlation_agent,
        create_protocol_draft_agent,
    )
    from .config import AgentConfig
    from .tools import (
        create_npi_tool,
        create_icd10_tool,
        create_cms_tool,
        create_fhir_tool,
        create_pubmed_tool,
        create_clinical_trials_tool,
        NPI_TOOLS_COMPLIANCE,
        NPI_TOOLS_SEARCH,
        ICD10_TOOLS_COMPLIANCE,
        ICD10_TOOLS_SEARCH,
    )

    # ── Resolve endpoints ──────────────────────────────────────────
    config = AgentConfig.load(local=local)
    endpoints = config.endpoints
    subscription_key = config.apim_subscription_key
    logger.info(
        "MCP mode: %s  NPI→%s  APIM key: %s",
        "local" if local else "APIM passthrough",
        endpoints.npi,
        "set" if subscription_key else "NOT SET",
    )

    # ── Azure OpenAI client ────────────────────────────────────────
    endpoint = os.getenv("AZURE_OPENAI_ENDPOINT", "")
    deployment = os.getenv("AZURE_OPENAI_DEPLOYMENT_NAME", "gpt-4o")
    api_version = os.getenv("AZURE_OPENAI_API_VERSION", "preview")

    if not endpoint:
        raise EnvironmentError(
            "AZURE_OPENAI_ENDPOINT is not set. "
            "Create src/agents/.env with:\n"
            "  AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com\n"
            "  AZURE_OPENAI_DEPLOYMENT_NAME=gpt-4o"
        )

    try:
        credential = DefaultAzureCredential()
        client = AzureOpenAIResponsesClient(
            azure_endpoint=endpoint,
            azure_deployment=deployment,
            credential=credential,
            api_version=api_version,
        )
    except Exception:
        # Fall back to AzureCliCredential if DefaultAzureCredential fails
        logger.warning("DefaultAzureCredential failed, trying AzureCliCredential")
        credential = AzureCliCredential()
        client = AzureOpenAIResponsesClient(
            azure_endpoint=endpoint,
            azure_deployment=deployment,
            credential=credential,
            api_version=api_version,
        )

    # ── Shared HTTP client for APIM subscription key ───────────────
    import httpx
    from .config import APIM_SUBSCRIPTION_KEY_HEADER

    _shared_http: httpx.AsyncClient | None = None
    if subscription_key:
        _shared_http = httpx.AsyncClient(
            headers={APIM_SUBSCRIPTION_KEY_HEADER: subscription_key},
            timeout=httpx.Timeout(60.0, connect=30.0),
        )

    # ── Tool factory helpers ───────────────────────────────────────
    def npi(name: str = "NPI Lookup", allowed: list[str] | None = None):
        return create_npi_tool(endpoints.npi, name=name, allowed_tools=allowed, http_client=_shared_http)

    def icd10(name: str = "ICD-10 Validation", allowed: list[str] | None = None):
        return create_icd10_tool(endpoints.icd10, name=name, allowed_tools=allowed, http_client=_shared_http)

    def cms(name: str = "CMS Coverage"):
        return create_cms_tool(endpoints.cms, name=name, http_client=_shared_http)

    def fhir(name: str = "FHIR Operations"):
        return create_fhir_tool(endpoints.fhir, name=name, http_client=_shared_http)

    def pubmed(name: str = "PubMed"):
        return create_pubmed_tool(endpoints.pubmed, name=name, http_client=_shared_http)

    def trials(name: str = "Clinical Trials"):
        return create_clinical_trials_tool(endpoints.clinical_trials, name=name, http_client=_shared_http)

    entities: list = []

    # ── 1. Healthcare Triage Orchestrator (single agent, all tools) ─
    entities.append(create_healthcare_triage_orchestrator(
        client=client,
        tools=[npi(), icd10(), cms(), fhir(), pubmed(), trials()],
    ))

    # ── 2. Prior Auth Workflow ─────────────────────────────────────
    # Matches src/agents/workflows/prior_auth.py:
    #   Phase 1: Compliance gate (NPI + ICD-10 validation)
    #   Phase 2: Concurrent(Clinical Reviewer + Coverage)
    #   Phase 3: Synthesis (aggregation → APPROVE/PEND)
    compliance_agent = create_compliance_agent(
        client=client,
        tools=[
            npi("NPI (Compliance)", NPI_TOOLS_COMPLIANCE),
            icd10("ICD-10 (Compliance)", ICD10_TOOLS_COMPLIANCE),
        ],
    )
    clinical_reviewer_agent = create_clinical_reviewer_agent(
        client=client,
        tools=[
            fhir("FHIR (Clinical)"),
            pubmed("PubMed (Clinical)"),
            trials("Trials (Clinical)"),
        ],
    )
    coverage_agent = create_coverage_agent(
        client=client,
        tools=[
            cms("CMS (Coverage)"),
            icd10("ICD-10 (Coverage)", ICD10_TOOLS_SEARCH),
        ],
    )
    synthesis_agent = create_synthesis_agent(client=client)

    pa_concurrent = ConcurrentBuilder(
        participants=[clinical_reviewer_agent, coverage_agent],
    ).build()
    # Convert the concurrent Workflow to a SupportsAgentRun so
    # SequentialBuilder wraps it as an AgentExecutor with compatible types
    pa_concurrent_agent = pa_concurrent.as_agent(name="ClinicalAndCoverageReview")
    pa_workflow = SequentialBuilder(
        participants=[compliance_agent, pa_concurrent_agent, synthesis_agent],
    ).build()
    entities.append(pa_workflow)

    # ── 3. Clinical Trial Protocol Workflow ────────────────────────
    # Matches src/agents/workflows/clinical_trials.py:
    #   Step 1: Trials Research Agent (ClinicalTrials.gov + PubMed)
    #   Step 2: Protocol Draft Agent (LLM generation)
    research_agent = create_trials_research_agent(
        client=client,
        tools=[
            trials("Trials (Research)"),
            pubmed("PubMed (Research)"),
        ],
    )
    draft_agent = create_protocol_draft_agent(client=client)

    trial_workflow = SequentialBuilder(
        participants=[research_agent, draft_agent],
    ).build()
    entities.append(trial_workflow)

    # ── 4. Patient Data Agent (single agent) ───────────────────────
    # Matches src/agents/workflows/patient_data.py:
    #   Single agent with FHIR + NPI tools
    entities.append(create_patient_summary_agent(
        client=client,
        tools=[
            fhir("FHIR (Patient)"),
            npi("NPI (Patient)", NPI_TOOLS_SEARCH),
        ],
    ))

    # ── 5. Literature & Evidence Workflow ──────────────────────────
    # Matches src/agents/workflows/literature_search.py:
    #   Concurrent: Literature Agent (PubMed) ‖ Trials Correlation (ClinicalTrials.gov)
    lit_agent = create_literature_search_agent(
        client=client,
        tools=[pubmed("PubMed (Literature)")],
    )
    trials_corr_agent = create_trials_correlation_agent(
        client=client,
        tools=[trials("Trials (Correlation)")],
    )

    lit_workflow = ConcurrentBuilder(
        participants=[lit_agent, trials_corr_agent],
    ).build()
    entities.append(lit_workflow)

    logger.info("Created %d workflow entities for framework DevUI", len(entities))
    return entities


def launch(
    local: bool = False,
    port: int = 8080,
    auto_open: bool = True,
    instrumentation: bool = False,
) -> None:
    """
    Build all healthcare workflow entities and launch the framework's native DevUI.

    Args:
        local: Use localhost MCP endpoints (for local development)
        port: Server port (default 8080)
        auto_open: Automatically open browser
        instrumentation: Enable OpenTelemetry tracing
    """
    from agent_framework_devui import serve

    entities = _create_entities(local=local)

    # Entity metadata for display
    ENTITY_INFO = [
        ("HealthcareOrchestrator", "Triage", "single agent — all tools", 6),
        ("Prior Auth Workflow",    "prior-auth-azure", "Sequential → Concurrent → Sequential", 6),
        ("Clinical Trial Protocol","clinical-trial-protocol", "Sequential (Research → Draft)", 2),
        ("PatientDataAgent",       "azure-fhir-developer", "single agent", 2),
        ("Literature & Evidence",  "literature-search", "Concurrent (Literature ‖ Trials)", 2),
    ]

    print(f"\n{'='*64}")
    print("  Healthcare Agent Orchestration — Framework DevUI")
    print(f"  Mode: {'local' if local else 'APIM passthrough'}")
    print(f"  Workflow entities: {len(entities)}")
    print(f"  MCP servers: npi-lookup · icd10-validation · cms-coverage")
    print(f"               fhir-operations · pubmed · clinical-trials")
    print(f"  URL: http://127.0.0.1:{port}")
    print(f"{'='*64}\n")

    for i, (name, skill, pattern, tools) in enumerate(ENTITY_INFO):
        entity = entities[i] if i < len(entities) else None
        entity_name = getattr(entity, 'name', name) if entity else name
        print(f"  • {entity_name}")
        print(f"    Skill: {skill}  |  Pattern: {pattern}  |  MCP tools: {tools}")
    print()

    serve(
        entities=entities,
        port=port,
        host="127.0.0.1",
        auto_open=auto_open,
        ui_enabled=True,
        instrumentation_enabled=instrumentation,
        mode="developer",
    )
