# Copilot Instructions for Azure Healthcare Marketplace

These instructions apply to GitHub Copilot Chat and coding assistance in this repository.

## Project Scope

This repository provides an Azure-native healthcare marketplace across:
- Skills in `.github/skills/`
- MCP servers in `src/mcp-servers/`
- Agent workflows in `src/agents/`
- VS Code extension in `vscode-extension/`
- Infrastructure in `deploy/`

Prioritize small, focused changes and follow existing patterns before introducing new abstractions.

## Engineering Guardrails

- Use only de-identified/sample data. Never introduce PHI, credentials, tokens, or secrets.
- Do not run destructive or expensive cloud operations (`azd up`, resource deletes) without explicit user approval.
- Keep edits scoped to the task; do not rewrite unrelated files.
- Update docs when behavior, commands, or workflow contracts change.

## Issue Tracking with `bd` (Required)

This project uses `bd` for all task tracking. Do not create markdown TODO lists.

### Core Commands

```bash
# Find work
bd ready --json
bd stale --days 30 --json

# Create and manage (ALWAYS include --description)
bd create "Title" --description="Detailed context" -t bug|feature|task -p 0-4 --json
bd update <id> --status in_progress --json
bd close <id> --reason "Done" --json

# Search
bd list --status open --priority 1 --json
bd show <id> --json

# Sync at the end of session
bd sync
```

### `bd` Workflow

1. Check ready work: `bd ready --json`
2. Claim task: `bd update <id> --status in_progress --json`
3. Implement and validate
4. If new work is discovered, create linked issue:
   `bd create "Found bug" --description="What was found and why" -p 1 --deps discovered-from:<parent-id> --json`
5. Close task: `bd close <id> --reason "Done" --json`
6. Sync: `bd sync`

### Priorities

- `0` critical (security, data loss, broken builds)
- `1` high (major features, important bugs)
- `2` medium (default)
- `3` low (polish)
- `4` backlog

## Prior Authorization Flow Instructions (for `@healthcare /pa`)

When Copilot is used for prior authorization review, follow the `prior-auth-azure` skill contract:
- `.github/skills/prior-auth-azure/SKILL.md`
- `.github/skills/prior-auth-azure/references/01-intake-assessment.md`
- `.github/skills/prior-auth-azure/references/rubric.md`
- `.github/skills/prior-auth-azure/references/02-decision-notification.md`
- `.github/skills/prior-auth-azure/references/tools.md`

### Required Decision Policy

- AI recommendations are draft-only and require human review.
- In default mode, AI may recommend `APPROVE` or `PEND`; do not recommend `DENY`.
- Read `references/rubric.md` before recommendation generation.
- If criteria are not met or confidence is low, recommend `PEND` with specific missing evidence.

## Beads Tracking for Prior Auth (Required)

Preserve and update bead state for PA workflow execution.

### Bead Registry

- `bd-pa-001-intake`
- `bd-pa-002-clinical`
- `bd-pa-003-recommend`
- `bd-pa-004-decision`
- `bd-pa-005-notify`

### Lifecycle and Rules

- Lifecycle: `not-started -> in-progress -> completed`
- Only one bead may be `in-progress` at a time.
- Execute beads sequentially (no skipping).
- Mark bead `in-progress` before starting its phase.
- Mark bead `completed` only after outputs are written and validated.
- On resume, continue from the first non-completed bead.

### Persistence Contract

Persist bead state under a `"beads"` key in waypoint files:
- Subskill 1 outputs: `waypoints/assessment.json`
- Subskill 2 outputs: `waypoints/decision.json`

Minimum schema:

```json
{
  "beads": [
    {"id": "bd-pa-001-intake", "status": "completed", "completed_at": "ISO datetime"},
    {"id": "bd-pa-002-clinical", "status": "in-progress", "started_at": "ISO datetime"},
    {"id": "bd-pa-003-recommend", "status": "not-started"},
    {"id": "bd-pa-004-decision", "status": "not-started"},
    {"id": "bd-pa-005-notify", "status": "not-started"}
  ]
}
```

## MCP and Validation Behavior for PA

- Run provider, diagnosis, and coverage checks in parallel where supported.
- Validate ICD-10 codes in batch where possible.
- Do not skip CPT/HCPCS validation.
- Display pre/post tool-call status in user-facing outputs (what is being called, then result summary).
- If using sample/demo data, document any demo-mode exceptions clearly.

## Output and Audit Requirements

For PA workflows, maintain auditable artifacts:
- `waypoints/assessment.json`
- `waypoints/decision.json`
- Notification outputs under `outputs/` as applicable

Each recommendation or decision summary should include:
- Evidence-to-criteria mapping
- Missing evidence list
- Confidence statement
- Human decision/override rationale when applicable

## Practical Testing References

- Local server quick start: `docs/LOCAL-TESTING.md`
- MCP overview: `docs/MCP-SERVERS-BEGINNER-GUIDE.md`
- End-to-end skill flow and bead map: `docs/SKILLS-FLOW-MAP.md`
- Developer workflow and Copilot usage: `docs/DEVELOPER-GUIDE.md`
