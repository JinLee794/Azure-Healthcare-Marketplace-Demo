#!/usr/bin/env python3
"""Validate MCP tool contract consistency across canonical docs/config files.

This script prevents drift between implemented MCP tool names and downstream
consumers (README, Foundry configs, beginner guide).
"""

from __future__ import annotations

import ast
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SERVER_FILES = {
    "npi-lookup": ROOT / "src/mcp-servers/npi-lookup/function_app.py",
    "icd10-validation": ROOT / "src/mcp-servers/icd10-validation/function_app.py",
    "cms-coverage": ROOT / "src/mcp-servers/cms-coverage/function_app.py",
    "fhir-operations": ROOT / "src/mcp-servers/fhir-operations/function_app.py",
    "pubmed": ROOT / "src/mcp-servers/pubmed/function_app.py",
    "clinical-trials": ROOT / "src/mcp-servers/clinical-trials/function_app.py",
}


def _tool_names_from_literal(node: ast.AST | None) -> set[str]:
    names: set[str] = set()
    if not isinstance(node, (ast.List, ast.Tuple)):
        return names

    for elt in node.elts:
        if not isinstance(elt, ast.Dict):
            continue
        for key, value in zip(elt.keys, elt.values):
            if isinstance(key, ast.Constant) and key.value == "name":
                if isinstance(value, ast.Constant) and isinstance(value.value, str):
                    names.add(value.value)
    return names


def _extract_server_tools(file_path: Path) -> set[str]:
    tree = ast.parse(file_path.read_text(encoding="utf-8"), filename=str(file_path))
    names: set[str] = set()

    for node in ast.walk(tree):
        # TOOLS = [ ... ]
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "TOOLS":
                    names.update(_tool_names_from_literal(node.value))

        # def get_tools(...): return [ ... ]
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "get_tools":
            for sub in ast.walk(node):
                if isinstance(sub, ast.Return):
                    names.update(_tool_names_from_literal(sub.value))

    return names


def _extract_readme_tools(path: Path) -> set[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    tools: set[str] = set()
    in_section = False

    for line in lines:
        stripped = line.strip()
        if stripped == "**Available Tools:**":
            in_section = True
            continue
        if in_section and stripped.startswith("### "):
            break
        if in_section:
            m = re.match(r"^- `([a-z0-9_]+)`", stripped)
            if m:
                tools.add(m.group(1))
    return tools


def _extract_agent_setup_tools(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    names: set[str] = set()

    for node in ast.walk(tree):
        if not isinstance(node, ast.Dict):
            continue
        for key, value in zip(node.keys, node.values):
            if isinstance(key, ast.Constant) and key.value == "allowed_tools":
                if isinstance(value, (ast.List, ast.Tuple)):
                    for elt in value.elts:
                        if isinstance(elt, ast.Constant) and isinstance(elt.value, str):
                            names.add(elt.value)
    return names


def _extract_yaml_allowed_tools(path: Path) -> set[str]:
    names: set[str] = set()
    lines = path.read_text(encoding="utf-8").splitlines()

    in_allowed = False
    allowed_indent = 0

    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()

        if stripped == "allowed_tools:":
            in_allowed = True
            allowed_indent = indent
            continue

        if in_allowed:
            if indent <= allowed_indent:
                in_allowed = False
                continue
            m = re.match(r"^-\s*([a-z0-9_]+)\s*$", stripped)
            if m:
                names.add(m.group(1))

    return names


def _extract_tools_catalog_names(path: Path) -> set[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    names: set[str] = set()

    for tool in data.get("tools", []):
        for capability in tool.get("capabilities", []):
            name = capability.get("name")
            if isinstance(name, str):
                names.add(name)

    return names


def _extract_beginner_guide_tools(path: Path) -> set[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    tools: set[str] = set()

    in_main_tools = False
    for line in lines:
        stripped = line.strip()
        if stripped == "- Main tools:":
            in_main_tools = True
            continue
        if in_main_tools and (stripped.startswith("Quick test:") or stripped.startswith("### ") or not stripped):
            in_main_tools = False
            continue
        if in_main_tools:
            m = re.match(r"^- `([a-z0-9_]+)`", stripped)
            if m:
                tools.add(m.group(1))

    return tools


def _report_invalid(source: str, declared: set[str], canonical: set[str]) -> tuple[bool, list[str]]:
    invalid = sorted(name for name in declared if name not in canonical)
    if not invalid:
        return True, [f"PASS {source}: {len(declared)} tool references valid"]
    lines = [f"FAIL {source}: {len(invalid)} invalid tool reference(s)"]
    for name in invalid:
        lines.append(f"  - {name}")
    return False, lines


def main() -> int:
    actual_by_server: dict[str, set[str]] = {}
    for server, file_path in SERVER_FILES.items():
        actual_by_server[server] = _extract_server_tools(file_path)

    canonical = set().union(*actual_by_server.values())

    print("Canonical MCP tools from implementation:")
    for server in sorted(actual_by_server):
        names = sorted(actual_by_server[server])
        print(f"  - {server}: {len(names)} tools")
        print(f"    {', '.join(names)}")
    print(f"Total canonical tools: {len(canonical)}\n")

    checks = [
        ("README", _extract_readme_tools(ROOT / "README.md")),
        ("foundry-integration/agent_setup.py", _extract_agent_setup_tools(ROOT / "foundry-integration/agent_setup.py")),
        ("foundry-integration/agent_config.yaml", _extract_yaml_allowed_tools(ROOT / "foundry-integration/agent_config.yaml")),
        ("foundry-integration/tools_catalog.json", _extract_tools_catalog_names(ROOT / "foundry-integration/tools_catalog.json")),
        ("docs/MCP-SERVERS-BEGINNER-GUIDE.md", _extract_beginner_guide_tools(ROOT / "docs/MCP-SERVERS-BEGINNER-GUIDE.md")),
    ]

    ok = True
    for source, declared in checks:
        passed, lines = _report_invalid(source, declared, canonical)
        ok = ok and passed
        for line in lines:
            print(line)

    if not ok:
        print("\nContract eval failed: fix invalid tool names in the files above.")
        return 1

    print("\nContract eval passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
