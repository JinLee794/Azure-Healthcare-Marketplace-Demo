"""Azure deployment walkthrough — azd provision, container deploy, post-deploy validation."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Confirm, Prompt
from rich.table import Table

from .checks import EnvironmentReport, _run, scan_environment
from .styles import THEME

console = Console(theme=THEME)


# ---------------------------------------------------------------------------
# Prerequisite checks for deployment
# ---------------------------------------------------------------------------


def _check_az_logged_in() -> tuple[bool, str]:
    """Check if az CLI is logged in and return subscription info."""
    ok, out = _run(["az", "account", "show", "--query", "{name:name, id:id, state:state}", "-o", "json"], timeout=10)
    if ok:
        try:
            info = json.loads(out)
            return True, f"{info.get('name', '?')} ({info.get('id', '?')[:8]}…)"
        except json.JSONDecodeError:
            return True, out.strip()[:60]
    return False, ""


def _check_azd_env() -> tuple[bool, str]:
    """Check if azd environment is initialised."""
    ok, out = _run(["azd", "env", "list", "-o", "json"], timeout=10)
    if ok and out.strip():
        try:
            envs = json.loads(out)
            if envs:
                default = next((e for e in envs if e.get("IsDefault")), envs[0])
                return True, default.get("Name", "?")
        except (json.JSONDecodeError, TypeError):
            pass
    return False, ""


def _get_azd_value(key: str) -> str:
    """Fetch a single value from the current azd environment."""
    ok, val = _run(["azd", "env", "get-value", key], timeout=8)
    return val.strip() if ok else ""


# ---------------------------------------------------------------------------
# Deploy readiness check
# ---------------------------------------------------------------------------


def check_deploy_readiness(report: EnvironmentReport | None = None) -> dict:
    """Check all prerequisites for Azure deployment."""
    if report is None:
        report = scan_environment()

    results = {}

    # az CLI
    results["az_installed"] = bool(report.az_cli and report.az_cli.found)
    az_ok, az_sub = _check_az_logged_in()
    results["az_logged_in"] = az_ok
    results["az_subscription"] = az_sub

    # azd CLI
    results["azd_installed"] = bool(report.azd_cli and report.azd_cli.found)
    azd_ok, azd_env = _check_azd_env()
    results["azd_env_ready"] = azd_ok
    results["azd_env_name"] = azd_env

    # Docker
    results["docker_installed"] = bool(report.docker and report.docker.found)
    dock_ok, _ = _run(["docker", "info"], timeout=10)
    results["docker_running"] = dock_ok

    # Project files
    root = report.project_root or Path.cwd()
    results["azure_yaml"] = (root / "azure.yaml").is_file()
    results["bicep_main"] = (root / "deploy" / "infra" / "main.bicep").is_file()
    results["deploy_script"] = (root / "scripts" / "deploy-mcp-containers.sh").is_file()

    results["project_root"] = root
    results["report"] = report

    return results


def print_deploy_readiness(results: dict) -> None:
    """Display deploy readiness as a table."""
    table = Table(title="Azure Deployment Readiness", show_lines=True)
    table.add_column("Requirement", style="bold")
    table.add_column("Status", justify="center")
    table.add_column("Details")

    rows = [
        ("Azure CLI installed", results["az_installed"], ""),
        ("Azure CLI logged in", results["az_logged_in"], results.get("az_subscription", "")),
        ("Azure Developer CLI (azd)", results["azd_installed"], ""),
        ("azd environment configured", results["azd_env_ready"], results.get("azd_env_name", "")),
        ("Docker installed", results["docker_installed"], ""),
        ("Docker daemon running", results["docker_running"], ""),
        ("azure.yaml present", results["azure_yaml"], ""),
        ("Bicep templates present", results["bicep_main"], "deploy/infra/main.bicep"),
        ("Deploy script present", results["deploy_script"], "scripts/deploy-mcp-containers.sh"),
    ]

    for name, ok, detail in rows:
        mark = "[success]✓[/success]" if ok else "[error]✗[/error]"
        table.add_row(name, mark, detail)

    console.print()
    console.print(table)


# ---------------------------------------------------------------------------
# Guided deployment walkthrough
# ---------------------------------------------------------------------------


def cmd_deploy_walkthrough(report: EnvironmentReport | None = None) -> None:
    """Interactive azd deployment with pre-checks, provision, deploy, and post-deploy."""
    console.print()
    console.print(
        Panel(
            "[header]☁️  Azure Deployment Walkthrough[/header]\n\n"
            "This wizard will guide you through:\n"
            "  1. Pre-flight checks (az, azd, Docker, Bicep)\n"
            "  2. azd environment init (if needed)\n"
            "  3. Configure deployment parameters\n"
            "  4. Provision infrastructure (azd provision)\n"
            "  5. Build & deploy MCP server containers\n"
            "  6. Post-deploy validation & MCP config\n"
            "  7. Test with GitHub Copilot (prior-auth demo)\n\n"
            "[warning]⚠  This creates Azure resources that cost ~$660/month.[/warning]\n"
            "[muted]See deploy/README.md for full cost breakdown.[/muted]",
            expand=False,
        )
    )
    console.print()
    if not Confirm.ask("Ready to start?", default=True):
        return

    root = (report.project_root if report else None) or Path.cwd()

    # ── Step 1: Pre-flight ──────────────────────────────────────────────
    console.print()
    console.print("[step]━━━ Step 1/7: Pre-flight Checks ━━━[/step]")
    results = check_deploy_readiness(report)
    print_deploy_readiness(results)

    blockers = []
    if not results["az_installed"]:
        blockers.append("Azure CLI not installed → brew install azure-cli")
    if not results["az_logged_in"]:
        blockers.append("Not logged in → az login")
    if not results["azd_installed"]:
        blockers.append("azd not installed → brew install azd")
    if not results["docker_installed"]:
        blockers.append("Docker not installed → https://docker.com/get-docker")
    if not results["docker_running"]:
        blockers.append("Docker daemon not running → start Docker Desktop")

    if blockers:
        console.print()
        console.print("[error]Blockers found:[/error]")
        for b in blockers:
            console.print(f"  [error]•[/error] {b}")
        console.print()
        console.print(
            "[bold]💡 Copilot Tip:[/bold] Ask GitHub Copilot:\n"
            '  [italic]"Help me install the prerequisites for deploying Azure Functions with azd"[/italic]'
        )
        if not Confirm.ask("Continue anyway?", default=False):
            return

    # ── Step 2: azd environment ─────────────────────────────────────────
    console.print()
    console.print("[step]━━━ Step 2/7: azd Environment ━━━[/step]")

    if results["azd_env_ready"]:
        console.print(f"  [success]✓[/success] azd environment: [bold]{results['azd_env_name']}[/bold]")
        use_existing = Confirm.ask("Use this environment?", default=True)
        if not use_existing:
            env_name = Prompt.ask("New environment name", default="dev")
            console.print(f"  [step]Running: azd env new {env_name}[/step]")
            subprocess.run(["azd", "env", "new", env_name], cwd=str(root))
    else:
        console.print("  [muted]No azd environment found. Let's create one.[/muted]")
        env_name = Prompt.ask("Environment name", default="dev")
        console.print(f"  [step]Running: azd init (environment: {env_name})[/step]")
        subprocess.run(["azd", "init", "--environment", env_name], cwd=str(root))

    # ── Step 3: Configure parameters ────────────────────────────────────
    console.print()
    console.print("[step]━━━ Step 3/7: Configuration ━━━[/step]")
    console.print()

    # Check for key azd env values
    location = _get_azd_value("AZURE_LOCATION")
    if location:
        console.print(f"  AZURE_LOCATION: [bold]{location}[/bold]")
    else:
        location = Prompt.ask("  Azure region", default="eastus2")
        subprocess.run(["azd", "env", "set", "AZURE_LOCATION", location], cwd=str(root))
        console.print(f"  [success]✓[/success] Set AZURE_LOCATION={location}")

    console.print()
    console.print(
        Panel(
            "[info]Key parameters (edit deploy/infra/main.bicepparam):[/info]\n\n"
            "  • [bold]baseName[/bold]             — Resource name prefix (3-15 chars)\n"
            "  • [bold]apimPublisherEmail[/bold]   — Required for APIM\n"
            "  • [bold]apimSku[/bold]              — StandardV2 (default) or Premium\n"
            "  • [bold]enablePublicAccess[/bold]   — true for dev, false for prod\n\n"
            "[muted]The wizard will continue with your current parameter file values.[/muted]",
            expand=False,
        )
    )
    _edit = Confirm.ask("Open main.bicepparam in editor first?", default=False)
    if _edit:
        param_file = root / "deploy" / "infra" / "main.bicepparam"
        import platform
        import shutil

        editor = shutil.which("code") or shutil.which("code-insiders")
        if editor:
            subprocess.run([editor, str(param_file)])
        elif platform.system() == "Darwin":
            subprocess.run(["open", str(param_file)])
        else:
            subprocess.run(["xdg-open", str(param_file)], stderr=subprocess.DEVNULL)
        console.print("  [muted]Edit the file, save, then press Enter to continue.[/muted]")
        Prompt.ask("", default="")

    # ── Step 4: Provision ───────────────────────────────────────────────
    console.print()
    console.print("[step]━━━ Step 4/7: Provision Infrastructure ━━━[/step]")
    console.print()
    console.print(
        Panel(
            "[warning]This step creates Azure resources:[/warning]\n\n"
            "  • APIM Standard v2          (~$175/mo)\n"
            "  • 6x Function Apps (EP1)    (~$150/mo)\n"
            "  • AI Services (GPT-4o)      (pay-per-use)\n"
            "  • Container Registry, VNet, Private Endpoints, etc.\n\n"
            "[bold]Estimated total: ~$660/month[/bold] (excluding AI token usage)\n"
            "[warning]⏱  APIM provisioning takes 30-45 minutes.[/warning]",
            expand=False,
        )
    )

    if Confirm.ask("Run [bold]azd provision[/bold] now?", default=True):
        console.print()
        console.print("[step]Running azd provision… (this will take 30-45 minutes)[/step]")
        console.print("[muted]You can monitor progress in Azure Portal → Resource Groups → Deployments[/muted]")
        console.print()
        result = subprocess.run(["azd", "provision"], cwd=str(root))
        if result.returncode != 0:
            console.print()
            console.print("[error]azd provision failed.[/error]")
            console.print(
                "[bold]💡 Copilot Tip:[/bold] Ask GitHub Copilot:\n"
                '  [italic]"azd provision failed — how do I troubleshoot Bicep deployment errors?"[/italic]'
            )
            if not Confirm.ask("Continue to container deployment anyway?", default=False):
                return
        else:
            console.print("[success]✓ Infrastructure provisioned successfully![/success]")
    else:
        console.print("  [muted]Skipped — make sure infrastructure is already provisioned.[/muted]")

    # ── Step 5: Build & deploy containers ───────────────────────────────
    console.print()
    console.print("[step]━━━ Step 5/7: Build & Deploy MCP Containers ━━━[/step]")
    console.print()
    console.print("  This builds Docker images for all 6 MCP servers, pushes to ACR,")
    console.print("  and updates each Function App's container configuration.")

    if Confirm.ask("Deploy MCP server containers now?", default=True):
        console.print()
        deploy_script = root / "scripts" / "deploy-mcp-containers.sh"
        result = subprocess.run(["bash", str(deploy_script)], cwd=str(root))
        if result.returncode != 0:
            console.print("[warning]⚠  Some container deployments may have failed. Check output above.[/warning]")
            console.print(
                "[bold]💡 Copilot Tip:[/bold] Ask GitHub Copilot:\n"
                '  [italic]"My MCP container deploy to Azure Functions failed — help me debug"[/italic]'
            )
        else:
            console.print("[success]✓ All MCP containers deployed![/success]")
    else:
        console.print("  [muted]Skipped — run manually: make azure-deploy[/muted]")

    # ── Step 6: Post-deploy validation ──────────────────────────────────
    console.print()
    console.print("[step]━━━ Step 6/7: Post-Deploy Validation ━━━[/step]")
    console.print()

    # Try to fetch APIM URL from azd env
    apim_url = _get_azd_value("SERVICE_APIM_GATEWAY_URL")
    if apim_url:
        console.print(f"  APIM Gateway: [bold]{apim_url}[/bold]")
    else:
        console.print("  [warning]Could not read APIM URL from azd environment.[/warning]")
        apim_url = Prompt.ask("  Enter APIM gateway URL", default="https://<your-apim>.azure-api.net")

    # Generate MCP config
    if Confirm.ask("Run post-deploy script (generates .vscode/mcp.json)?", default=True):
        postdeploy = root / "scripts" / "postdeploy.sh"
        subprocess.run(["bash", str(postdeploy)], cwd=str(root))

    # Test APIM passthrough
    if Confirm.ask("Run APIM passthrough connectivity tests?", default=True):
        test_script = root / "scripts" / "test-apim-passthrough.sh"
        if test_script.is_file():
            subprocess.run(["bash", str(test_script), "--all"], cwd=str(root))
        else:
            console.print("  [warning]test-apim-passthrough.sh not found[/warning]")

    # ── Step 7: Try it with Copilot ─────────────────────────────────────
    console.print()
    console.print("[step]━━━ Step 7/7: Test with GitHub Copilot ━━━[/step]")
    _show_post_deploy_copilot_guide(root, apim_url)


# ---------------------------------------------------------------------------
# Post-deploy Copilot guide
# ---------------------------------------------------------------------------


def _show_post_deploy_copilot_guide(project_root: Path, apim_url: str = "") -> None:
    """Show the post-deployment Copilot testing guide."""
    console.print()
    console.print(
        Panel(
            "[header]🧪 Test Your Deployment with GitHub Copilot[/header]\n\n"
            "Now that your MCP servers are deployed, you can test the full stack\n"
            "directly from VS Code using GitHub Copilot Chat + MCP tools.\n\n"
            "[bold]The easiest demo: Prior Authorization Review[/bold]",
            expand=False,
        )
    )

    # PA test walkthrough
    console.print()
    console.print("[step]🩺 Prior Authorization Demo — Step by Step[/step]")
    console.print()
    console.print("  [bold]1.[/bold] Make sure [info].vscode/mcp.json[/info] is configured")
    console.print("     (The post-deploy script should have generated this)")
    console.print()
    console.print(
        "  [bold]2.[/bold] Open GitHub Copilot Chat in VS Code ([bold]⌘⇧I[/bold] or [bold]Ctrl+Shift+I[/bold])"
    )
    console.print()
    console.print("  [bold]3.[/bold] Attach the sample prior-auth files to the chat:")
    console.print()

    sample_dir = project_root / "data" / "sample_cases" / "prior_auth_baseline"
    if sample_dir.is_dir():
        files = sorted(sample_dir.iterdir())
        for f in files:
            console.print(f"     📎 [info]{f.relative_to(project_root)}[/info]")
    else:
        console.print("     📎 data/sample_cases/prior_auth_baseline/pa_request.json")
        console.print("     📎 data/sample_cases/prior_auth_baseline/ct_chest_report.txt")
        console.print("     📎 data/sample_cases/prior_auth_baseline/pulmonology_consultation.txt")

    console.print()
    console.print("     [muted]Tip: In Copilot Chat, click the 📎 (Attach) button or drag files into the chat[/muted]")

    console.print()
    console.print("  [bold]4.[/bold] Also attach the decision rubric:")
    console.print("     📎 [info].github/skills/prior-auth-azure/references/rubric.md[/info]")
    console.print()
    console.print("  [bold]5.[/bold] Send one of these prompts:")
    console.print()
    console.print(
        Panel(
            "[italic]@healthcare /pa Review the attached PA request and clinical documents.\n"
            "Use rubric.md as the decision policy. Validate the provider NPI, ICD-10 codes,\n"
            "and CPT codes using MCP tools. Return a draft assessment with APPROVE or PEND.[/italic]",
            title="[highlight]Example Prompt 1 — Full PA Review[/highlight]",
            expand=False,
            border_style="green",
        )
    )
    console.print()
    console.print(
        Panel(
            "[italic]@healthcare /pa Map each policy criterion in rubric.md to evidence from\n"
            "the attached clinical documents. List missing evidence and what additional\n"
            "documentation would be needed to support an APPROVE recommendation.[/italic]",
            title="[highlight]Example Prompt 2 — Evidence Mapping[/highlight]",
            expand=False,
            border_style="green",
        )
    )
    console.print()
    console.print(
        Panel(
            "[italic]Look up NPI 1234567890 and validate ICD-10 codes R91.1 and Z87.891.\n"
            "Then check Medicare coverage for CPT 32405. Summarize whether this procedure\n"
            "is likely to be covered.[/italic]",
            title="[highlight]Example Prompt 3 — Quick MCP Tool Validation[/highlight]",
            expand=False,
            border_style="cyan",
        )
    )

    # What happens behind the scenes
    console.print()
    console.print("[step]🔎 What happens behind the scenes:[/step]")
    console.print()
    console.print("  Copilot reads the attached files + your prompt, then:")
    console.print("  [muted]1.[/muted] Calls [server]npi-lookup[/server] MCP → validates provider NPI")
    console.print("  [muted]2.[/muted] Calls [server]icd10-validation[/server] MCP → validates diagnosis codes")
    console.print(
        "  [muted]3.[/muted] Calls [server]cms-coverage[/server] MCP → checks Medicare coverage for CPT 32405"
    )
    console.print("  [muted]4.[/muted] Cross-references clinical evidence against rubric criteria")
    console.print("  [muted]5.[/muted] Returns a structured draft assessment (APPROVE/PEND + justification)")
    console.print()
    console.print("  All MCP tool calls go through APIM → Azure Function containers")
    console.print("  that you just deployed. The skills in [info].github/skills/[/info] guide")
    console.print("  Copilot's reasoning and output structure.")

    # More things to try
    console.print()
    console.print("[step]🚀 More things to try after deployment:[/step]")
    console.print()

    more_table = Table(show_header=True, show_lines=True)
    more_table.add_column("Use Case", style="bold")
    more_table.add_column("Example Prompt")
    more_table.add_row(
        "FHIR Patient Lookup",
        '[italic]"Search for patient Jane Doe born 1965-03-15\nand retrieve her recent observations"[/italic]',
    )
    more_table.add_row(
        "Literature Search",
        '[italic]"Search PubMed for recent studies on CT-guided\nlung biopsy complications and summarize findings"[/italic]',
    )
    more_table.add_row(
        "Clinical Trial Match",
        '[italic]"Find recruiting clinical trials for lung cancer\nnear San Francisco, CA"[/italic]',
    )
    more_table.add_row(
        "Coverage Policy Check",
        '[italic]"What are the Medicare coverage requirements for\nCPT 32405 (lung biopsy)? Any LCD restrictions?"[/italic]',
    )
    more_table.add_row(
        "Agent Workflow (CLI)",
        "[bold]cd src && source agents/.venv/bin/activate[/bold]\n"
        "[bold]python -m agents --workflow prior-auth --demo --local[/bold]",
    )
    console.print(more_table)

    console.print()
    console.print(
        Panel(
            "[bold]💡 Key Insight:[/bold]\n\n"
            "The sample files in [info]data/sample_cases/prior_auth_baseline/[/info]\n"
            "are designed to work together as a complete prior-auth test case:\n\n"
            "  • [bold]pa_request.json[/bold]              — The PA request (patient, CPT, ICD-10, provider)\n"
            "  • [bold]ct_chest_report.txt[/bold]          — CT imaging report (clinical evidence)\n"
            "  • [bold]pet_scan_report.txt[/bold]          — PET scan results (additional evidence)\n"
            "  • [bold]pulmonology_consultation.txt[/bold] — Specialist consultation note\n\n"
            "Upload all of them to Copilot Chat for the most complete PA review demo.\n"
            "Copilot + MCP tools will validate codes, check coverage, and cross-reference\n"
            "the clinical documents against policy criteria — all automatically.",
            title="[header]Sample Files Explained[/header]",
            expand=False,
        )
    )


# ---------------------------------------------------------------------------
# Standalone post-deploy guide (accessible from menu without running deploy)
# ---------------------------------------------------------------------------


def cmd_post_deploy_guide(report: EnvironmentReport | None = None) -> None:
    """Show the Copilot testing guide without running deployment."""
    if report is None:
        report = scan_environment()
    root = report.project_root or Path.cwd()
    apim_url = _get_azd_value("SERVICE_APIM_GATEWAY_URL") or "https://<your-apim>.azure-api.net"
    _show_post_deploy_copilot_guide(root, apim_url)
