"""MCP server venv setup, dependency install, and lifecycle management."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.table import Table

from .checks import _run
from .styles import COPILOT_TIPS, MCP_SERVERS, THEME

console = Console(theme=THEME)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _server_dir(project_root: Path, name: str) -> Path:
    return project_root / "src" / "mcp-servers" / name


def _venv_python(server_dir: Path) -> Path:
    return server_dir / ".venv" / "bin" / "python"


def _venv_exists(server_dir: Path) -> bool:
    vpy = _venv_python(server_dir)
    return vpy.is_file() and os.access(str(vpy), os.X_OK)


def _port_in_use(port: int) -> bool:
    ok, out = _run(["lsof", "-ti", f"tcp:{port}", "-sTCP:LISTEN"])
    return ok and bool(out.strip())


# ---------------------------------------------------------------------------
# Setup individual server
# ---------------------------------------------------------------------------


def setup_server_venv(
    project_root: Path,
    server_name: str,
    python_cmd: str = "python3",
    *,
    force: bool = False,
) -> bool:
    """Create venv and install deps for one MCP server. Returns True on success."""
    sdir = _server_dir(project_root, server_name)
    if not sdir.is_dir():
        console.print(f"[error]Server directory not found:[/error] {sdir}")
        return False

    req_file = sdir / "requirements.txt"
    if not req_file.is_file():
        console.print(f"[error]No requirements.txt in[/error] {sdir}")
        return False

    venv_dir = sdir / ".venv"

    # Create venv
    if force or not _venv_exists(sdir):
        with Progress(SpinnerColumn(), TextColumn("[step]{task.description}"), console=console) as prog:
            prog.add_task(f"Creating venv for {server_name}…", total=None)
            if venv_dir.exists():
                subprocess.run(["rm", "-rf", str(venv_dir)], check=False)
            result = subprocess.run(
                [python_cmd, "-m", "venv", str(venv_dir)],
                capture_output=True,
                text=True,
            )
        if result.returncode != 0:
            console.print(f"[error]Failed to create venv:[/error] {result.stderr}")
            console.print(COPILOT_TIPS["venv_fail"])
            return False
        console.print("  [success]✓[/success] venv created")
    else:
        console.print("  [muted]venv already exists — skipping (use --force to recreate)[/muted]")

    # Install deps
    pip = str(venv_dir / "bin" / "pip")
    with Progress(SpinnerColumn(), TextColumn("[step]{task.description}"), console=console) as prog:
        prog.add_task(f"Installing dependencies for {server_name}…", total=None)
        result = subprocess.run(
            [pip, "install", "-q", "-r", str(req_file)],
            capture_output=True,
            text=True,
        )
    if result.returncode != 0:
        console.print(f"[error]pip install failed for {server_name}:[/error]")
        console.print(result.stderr[-500:] if result.stderr else "(no output)")
        console.print(COPILOT_TIPS["pip_fail"])
        return False

    # Also install to .python_packages for Azure Functions worker
    pkg_target = sdir / ".python_packages" / "lib" / "site-packages"
    with Progress(SpinnerColumn(), TextColumn("[step]{task.description}"), console=console) as prog:
        prog.add_task(f"Installing Azure Functions packages for {server_name}…", total=None)
        result = subprocess.run(
            [pip, "install", "-q", "-r", str(req_file), "--target", str(pkg_target), "--upgrade"],
            capture_output=True,
            text=True,
        )
    if result.returncode != 0:
        console.print("[warning]⚠  .python_packages install had issues (non-fatal):[/warning]")
        console.print(result.stderr[-300:] if result.stderr else "")

    console.print("  [success]✓[/success] dependencies installed")
    return True


# ---------------------------------------------------------------------------
# Setup all servers
# ---------------------------------------------------------------------------


def setup_all_servers(
    project_root: Path,
    python_cmd: str = "python3",
    *,
    force: bool = False,
    servers: list[str] | None = None,
) -> dict[str, bool]:
    """Setup venvs for selected (or all) MCP servers."""
    targets = servers or list(MCP_SERVERS.keys())
    results: dict[str, bool] = {}

    for name in targets:
        console.print()
        console.print(f"[server]━━━ {name} ━━━[/server]")
        results[name] = setup_server_venv(project_root, name, python_cmd, force=force)

    return results


# ---------------------------------------------------------------------------
# Agents venv
# ---------------------------------------------------------------------------


def setup_agents_venv(project_root: Path, python_cmd: str = "python3") -> bool:
    """Create and install the agents layer venv."""
    agents_dir = project_root / "src" / "agents"
    req_file = agents_dir / "requirements.txt"
    venv_dir = agents_dir / ".venv"

    if not agents_dir.is_dir():
        console.print("[error]src/agents directory not found.[/error]")
        return False

    if not _venv_exists(agents_dir):
        with Progress(SpinnerColumn(), TextColumn("[step]{task.description}"), console=console) as prog:
            prog.add_task("Creating agents venv…", total=None)
            result = subprocess.run(
                [python_cmd, "-m", "venv", str(venv_dir)],
                capture_output=True,
                text=True,
            )
        if result.returncode != 0:
            console.print(f"[error]Failed to create agents venv:[/error] {result.stderr}")
            return False
    else:
        console.print("  [muted]agents venv already exists[/muted]")

    if req_file.is_file():
        pip = str(venv_dir / "bin" / "pip")
        with Progress(SpinnerColumn(), TextColumn("[step]{task.description}"), console=console) as prog:
            prog.add_task("Installing agent dependencies…", total=None)
            result = subprocess.run(
                [pip, "install", "-q", "-r", str(req_file)],
                capture_output=True,
                text=True,
            )
        if result.returncode != 0:
            console.print(f"[error]pip install failed:[/error] {result.stderr[-500:]}")
            return False

    console.print("  [success]✓[/success] agents venv ready")
    return True


# ---------------------------------------------------------------------------
# Server status
# ---------------------------------------------------------------------------


def check_server_status(project_root: Path | None = None) -> None:
    """Print a table showing which MCP servers are running."""
    table = Table(title="MCP Server Status", show_lines=True)
    table.add_column("Server", style="server")
    table.add_column("Port", justify="center")
    table.add_column("Status", justify="center")
    table.add_column("Venv", justify="center")

    root = project_root or Path.cwd()

    for name, info in MCP_SERVERS.items():
        port = info["port"]
        running = _port_in_use(port)

        sdir = _server_dir(root, name)
        has_venv = _venv_exists(sdir) if sdir.is_dir() else False

        status = "[success]● running[/success]" if running else "[muted]○ stopped[/muted]"
        venv_status = "[success]✓[/success]" if has_venv else "[warning]—[/warning]"

        table.add_row(name, str(port), status, venv_status)

    console.print()
    console.print(table)
