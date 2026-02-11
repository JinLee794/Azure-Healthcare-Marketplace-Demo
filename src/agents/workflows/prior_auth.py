"""
Prior Authorization Workflow — Hybrid Sequential / Concurrent / Synthesis

Orchestration pattern (matches the article's architecture):
  Phase 1 (Sequential):  Compliance Agent validates completeness (gate)
  Phase 2 (Concurrent):  Clinical Reviewer + Coverage Agent run in parallel
  Phase 3 (Synthesis):   Synthesis Agent aggregates into APPROVE/PEND recommendation

Uses Microsoft Agent Framework's SequentialBuilder and ConcurrentBuilder
composed into a custom hybrid workflow.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from agent_framework import Agent
from agent_framework.azure import AzureOpenAIResponsesClient
from agent_framework_orchestrations import ConcurrentBuilder, SequentialBuilder
from azure.identity import AzureCliCredential, DefaultAzureCredential

from ..agents import (
    create_clinical_reviewer_agent,
    create_compliance_agent,
    create_coverage_agent,
    create_synthesis_agent,
)
from ..config import AgentConfig
from ..tools import MCPToolKit

logger = logging.getLogger(__name__)


async def run_prior_auth_workflow(
    request_data: dict[str, Any],
    config: AgentConfig | None = None,
    *,
    output_dir: str | None = None,
    local: bool = False,
) -> dict[str, Any]:
    """
    Execute the full Prior Authorization multi-agent workflow.

    Args:
        request_data: PA request containing member info, service details,
                      provider NPI, ICD-10 codes, CPT codes, clinical documentation.
        config: Optional AgentConfig override; loads from env if None.
        output_dir: Directory for waypoint/output files. Defaults to ./waypoints/.
        local: If True, use localhost MCP endpoints.

    Returns:
        Structured assessment dict (also written to waypoints/assessment.json).
    """
    if config is None:
        config = AgentConfig.load(local=local)

    output_path = Path(output_dir or "waypoints")
    output_path.mkdir(parents=True, exist_ok=True)

    # Build the LLM client
    credential = DefaultAzureCredential() if not local else AzureCliCredential()
    client = AzureOpenAIResponsesClient(
        credential=credential,
        endpoint=config.openai.endpoint,
        deployment_name=config.openai.deployment_name,
        api_version=config.openai.api_version,
    )

    # Build MCP tools
    toolkit = MCPToolKit.from_endpoints(config.endpoints, subscription_key=config.apim_subscription_key)

    request_json = json.dumps(request_data, indent=2)

    logger.info("=== Prior Authorization Workflow Started ===")

    async with toolkit:
        # ------------------------------------------------------------------
        # Phase 1: Compliance Check (Sequential gate)
        # ------------------------------------------------------------------
        logger.info("Phase 1: Compliance check (sequential gate)")

        compliance_agent = create_compliance_agent(
            client=client,
            tools=toolkit.compliance_tools(),
        )

        compliance_prompt = (
            f"Validate the following prior authorization request for compliance.\n"
            f"Check provider NPI, validate all ICD-10 codes, and identify any missing fields.\n\n"
            f"PA Request:\n```json\n{request_json}\n```"
        )

        async with compliance_agent:
            compliance_result = await compliance_agent.run(compliance_prompt)

        compliance_text = str(compliance_result)
        logger.info("Phase 1 complete: %s", compliance_text[:200])

        # Parse compliance result to check gate
        can_proceed = _check_compliance_gate(compliance_text)

        if not can_proceed:
            logger.info("Compliance gate FAILED — returning PEND recommendation")
            assessment = _build_gated_assessment(
                request_data=request_data,
                compliance_result=compliance_text,
                phase="compliance_gate",
            )
            _write_waypoint(output_path / "assessment.json", assessment)
            return assessment

        # ------------------------------------------------------------------
        # Phase 2: Clinical Review + Coverage (Concurrent)
        # ------------------------------------------------------------------
        logger.info("Phase 2: Clinical review + Coverage check (concurrent)")

        clinical_agent = create_clinical_reviewer_agent(
            client=client,
            tools=toolkit.clinical_reviewer_tools(),
        )

        coverage_agent = create_coverage_agent(
            client=client,
            tools=toolkit.coverage_tools(),
        )

        clinical_prompt = (
            f"Review the clinical evidence for this prior authorization request.\n"
            f"The compliance check has passed. Extract clinical data, map to criteria, "
            f"and search for supporting literature.\n\n"
            f"PA Request:\n```json\n{request_json}\n```\n\n"
            f"Compliance Results:\n{compliance_text}"
        )

        coverage_prompt = (
            f"Check coverage policies for this prior authorization request.\n"
            f"Search for applicable LCDs/NCDs, check medical necessity for the "
            f"CPT/ICD-10 code combination.\n\n"
            f"PA Request:\n```json\n{request_json}\n```\n\n"
            f"Compliance Results:\n{compliance_text}"
        )

        # Run both agents concurrently
        concurrent_workflow = ConcurrentBuilder(
            participants=[clinical_agent, coverage_agent],
        ).build()

        # The concurrent builder sends the same input to both agents.
        # We craft a combined prompt that both can work from.
        combined_prompt = (
            f"You are part of a prior authorization review team. Below is the PA request "
            f"and compliance results. Perform YOUR specific role as described in your instructions.\n\n"
            f"PA Request:\n```json\n{request_json}\n```\n\n"
            f"Compliance Results:\n{compliance_text}"
        )

        async with clinical_agent, coverage_agent:
            concurrent_results = await concurrent_workflow.run(combined_prompt)

        concurrent_text = str(concurrent_results)
        logger.info("Phase 2 complete: %d chars output", len(concurrent_text))

        # ------------------------------------------------------------------
        # Phase 3: Synthesis (aggregate into recommendation)
        # ------------------------------------------------------------------
        logger.info("Phase 3: Synthesis (aggregation)")

        synthesis_agent = create_synthesis_agent(client=client)

        synthesis_prompt = (
            f"Aggregate the following agent outputs into a final prior authorization assessment.\n"
            f"Apply the decision rubric strictly.\n\n"
            f"## Original PA Request\n```json\n{request_json}\n```\n\n"
            f"## Compliance Agent Output\n{compliance_text}\n\n"
            f"## Clinical Review + Coverage Agent Outputs\n{concurrent_text}\n\n"
            f"Produce your final structured assessment JSON."
        )

        synthesis_result = await synthesis_agent.run(synthesis_prompt)
        synthesis_text = str(synthesis_result)
        logger.info("Phase 3 complete: recommendation generated")

        # ------------------------------------------------------------------
        # Build and persist the assessment
        # ------------------------------------------------------------------
        assessment = {
            "workflow": "prior_authorization",
            "version": "1.0",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "status": "assessment_complete",
            "request": request_data,
            "phases": {
                "compliance": compliance_text,
                "clinical_and_coverage": concurrent_text,
                "synthesis": synthesis_text,
            },
            "recommendation": synthesis_text,
        }

        _write_waypoint(output_path / "assessment.json", assessment)
        logger.info("=== Prior Authorization Workflow Complete ===")
        return assessment


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _check_compliance_gate(compliance_text: str) -> bool:
    """Parse compliance output to determine if we can proceed."""
    lower = compliance_text.lower()
    # Look for explicit compliance pass indicators
    if '"can_proceed_to_clinical_review": true' in lower:
        return True
    if '"compliance_status": "pass"' in lower:
        return True
    if '"can_proceed_to_clinical_review": false' in lower:
        return False
    if '"compliance_status": "fail"' in lower:
        return False
    # If we can't parse, default to proceeding (agent will catch issues)
    logger.warning("Could not parse compliance gate from output — defaulting to proceed")
    return True


def _build_gated_assessment(
    request_data: dict,
    compliance_result: str,
    phase: str,
) -> dict[str, Any]:
    """Build a PEND assessment when the workflow is gated at an early phase."""
    return {
        "workflow": "prior_authorization",
        "version": "1.0",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "status": f"gated_at_{phase}",
        "request": request_data,
        "recommendation": "PEND",
        "pend_reason": f"Workflow gated at {phase}. Review compliance results and resubmit.",
        "phases": {
            "compliance": compliance_result,
            "clinical_and_coverage": None,
            "synthesis": None,
        },
    }


def _write_waypoint(path: Path, data: dict) -> None:
    """Write a waypoint JSON file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2, default=str)
    logger.info("Waypoint written: %s", path)
