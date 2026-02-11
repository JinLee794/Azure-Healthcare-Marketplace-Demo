# Agent.md - Healthcare Marketplace for Azure

## Purpose
Operational guide for coding agents working in this repository. Keep this file concise, action-oriented, and specific to this project.

## Scope
Build and maintain an Azure-native healthcare marketplace across:
- Skills (`.github/skills/`)
- MCP servers (`src/mcp-servers/`)
- Agent workflows (`src/agents/`)
- Infra and integration surfaces (`deploy/`, `vscode-extension/`, `foundry-integration/`)

## Do
- Keep changes small and focused on the requested task.
- Follow existing patterns before introducing new abstractions.
- Validate locally first (single server/workflow), then expand scope.
- Use de-identified/sample data only; never commit PHI or secrets.
- Update docs when behavior or commands change.
- Prefer references to canonical docs instead of duplicating long explanations.

## Do Not
- Do not run cloud-destructive or expensive commands (`azd up`, resource deletes) without explicit user approval.
- Do not rewrite unrelated files during a targeted fix.
- Do not add new dependencies unless required for the task.
- Do not hardcode credentials, API keys, tenant IDs, or endpoint secrets.

## Project Map
- `.github/skills/`: domain guidance and templates for healthcare workflows.
- `src/mcp-servers/`: Python Azure Function MCP servers:
  - `npi-lookup`, `icd10-validation`, `cms-coverage`, `fhir-operations`, `pubmed`, `clinical-trials`
- `src/agents/`: orchestration CLI and workflows (`prior-auth`, `clinical-trial`, `patient-data`, `literature-search`).
- `scripts/`: local launchers, APIM tests, post-deploy config scripts.
- `deploy/`: Azure Bicep infrastructure and deployment assets.
- `vscode-extension/`: `@healthcare` chat participant implementation.
- `docs/`: operational, architecture, and testing guides.

## Default Workflow
1. Understand the target surface (skill, MCP server, workflow, infra, extension).
2. Edit only the relevant files.
3. Run the smallest useful validation loop.
4. Summarize what changed, why, and how it was validated.

## Commands
### Run MCP servers locally
```bash
make local-start
make local-logs
make local-stop
```

### Run one MCP server
```bash
./scripts/local-test.sh npi-lookup 7071
```

### MCP smoke test
```bash
curl http://localhost:7071/.well-known/mcp | jq
curl -X POST http://localhost:7071/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | jq
```

### Run agent workflows (local MCP mode)
```bash
cd src
source agents/.venv/bin/activate
python -m agents --workflow prior-auth --demo --local
python -m agents --workflow clinical-trial --demo --local
python -m agents --workflow literature-search --demo --local
```

### Run prior-auth sample input
```bash
cd src
source agents/.venv/bin/activate
python -m agents \
  --workflow prior-auth \
  --input ../.github/skills/prior-auth-azure/assets/sample/pa_request.json \
  --local
```

## Safety and Approval Boundaries
Ask before running:
- `azd up`, `az deployment *`, or any command that creates/modifies cloud resources.
- Bulk dependency installs or upgrades across multiple subprojects.
- Potentially destructive operations (mass deletes, force resets, schema drops).

Safe by default:
- Local file edits in scope.
- Local MCP/workflow runs and targeted smoke tests.
- Read-only discovery commands (`rg`, `ls`, `cat`, `git status`, `git diff`).

## Patterns to Reuse
- MCP server shape: `src/mcp-servers/npi-lookup/function_app.py`
- MCP tool wiring: `src/agents/tools.py`
- Hybrid workflow orchestration: `src/agents/workflows/prior_auth.py`
- Sequential workflow orchestration: `src/agents/workflows/clinical_trials.py`
- Skill structure and assets: `.github/skills/prior-auth-azure/SKILL.md`

## Definition of Done
- Code changes are limited to task-relevant files.
- Related local checks/workflow runs complete successfully, or failures are explained.
- No secrets or PHI introduced.
- Documentation updated when commands/behavior changed.

## If Blocked
- State the blocker precisely (missing env var, unavailable service, auth issue, ambiguous requirement).
- Propose the minimum next step and continue once clarified.

## Canonical Docs
- `README.md`
- `docs/DEVELOPER-GUIDE.md`
- `docs/LOCAL-TESTING.md`
- `docs/MCP-SERVERS-BEGINNER-GUIDE.md`
- `docs/MCP-OAUTH-PRM.md`
- `docs/SKILLS-FLOW-MAP.md`
- `docs/architecture/APIM-ARCHITECTURE.md`
- `docs/architecture/RETRIEVAL-ARCHITECTURE.md`
