---
name: clinical-trial-protocol
description: "Generate FDA/NIH-compliant clinical trial protocols for medical devices (IDE) or drugs (IND) using a waypoint-based architecture with Azure integration."
---

# Clinical Trial Protocol Skill

Generate comprehensive clinical trial protocols based on NIH/FDA guidelines and similar trials research. Supports both medical devices (IDE pathway) and drugs (IND pathway) with appropriate regulatory terminology.

**Target Users:** Clinical researchers, regulatory affairs professionals, protocol writers

**Key Features:**
- Device & Drug Support - Handles both medical devices (IDE) and drugs (IND)
- Token-Efficient - Modular protocol development to stay within output limits
- Resume from Any Step - Interrupted workflows can continue from any step
- Sample Size Calculation - Interactive statistical power analysis
- Research-Driven - Leverages ClinicalTrials.gov and FDA guidance documents
- Azure Integration - Uses Azure Health Data Services and AI Foundry for enhanced capabilities

---

## Beads (bd) Task Tracking

Use **beads** to track progress through the clinical trial protocol workflow. Each step is a bead with a unique ID, status, and checklist. Update bead status as work progresses to enable reliable resume and provide an auditable trail.

### Bead Definitions

| Bead ID | Step | Description |
|---------|------|-------------|
| `bd-ct-000-init` | Step 0 | Initialize intervention (collect device/drug info) |
| `bd-ct-001-research` | Step 1 | Research similar protocols via Clinical Trials MCP |
| `bd-ct-002-foundation` | Step 2 | Protocol foundation (Sections 1-6) |
| `bd-ct-003-intervention` | Step 3 | Intervention details (Sections 7-8) |
| `bd-ct-004-operations` | Step 4 | Operations & statistics (Sections 9-12) |
| `bd-ct-005-concatenate` | Step 5 | Concatenate final protocol |

### Bead Lifecycle

```
not-started → in-progress → completed
```

- **not-started**: Bead has not begun (default)
- **in-progress**: Actively executing this step (only ONE bead active at a time)
- **completed**: All outputs verified for this step

### Tracking Rules

1. **Mark bead in-progress** before starting its step
2. **Check off items** as each substep completes
3. **Mark bead completed** only after outputs are verified
4. **Never skip beads** — execute in order (`bd-ct-000` → `bd-ct-005`)
5. **On resume**, scan bead statuses in `waypoints/intervention_metadata.json` to find the first non-completed bead
6. **Persist bead state** in waypoint files under a `"beads"` key

### Bead State in Waypoint Files

Include bead tracking in `waypoints/intervention_metadata.json`:

```json
{
  "beads": [
    {"id": "bd-ct-000-init",         "status": "completed", "completed_at": "ISO datetime"},
    {"id": "bd-ct-001-research",      "status": "completed", "completed_at": "ISO datetime"},
    {"id": "bd-ct-002-foundation",    "status": "in-progress", "started_at": "ISO datetime"},
    {"id": "bd-ct-003-intervention",  "status": "not-started"},
    {"id": "bd-ct-004-operations",    "status": "not-started"},
    {"id": "bd-ct-005-concatenate",   "status": "not-started"}
  ]
}
```

### Resume via Beads

On startup, if `waypoints/intervention_metadata.json` exists:
1. Read the `"beads"` array
2. Find the first bead that is NOT `"completed"`
3. Display bead progress summary to user
4. Offer to resume from that bead's corresponding step

This replaces the file-existence-based resume logic with explicit bead state tracking.

---

## Prerequisites

### 1. Clinical Trials MCP Server (Required)

**Installation via Azure APIM:**
```bash
# Configure Azure MCP endpoint
export AZURE_MCP_ENDPOINT="https://healthcare-mcp.azure-api.net/clinical-trials"
```

**Available Tools:**

| Tool | Purpose |
|------|---------|
| `trials_search` | Search ClinicalTrials.gov by condition, intervention, sponsor, location, status, or phase. Supports geographic radius search. Returns up to 100 results, sorted by most recently updated. |
| `trials_details` | Get comprehensive details for a specific trial by NCT ID, including eligibility criteria, outcomes, study design, and contact information. |

### 2. Python Environment (Required for Sample Size Calculation)

```bash
# Install required packages
pip install scipy numpy
```

### 3. Azure Health Data Services (Optional)

For enhanced FHIR-based protocol data management:
- Azure API for FHIR R4
- Azure Health Data Services workspace

---

## Workflow Overview

| Step | Name | Description | Output |
|------|------|-------------|--------|
| 0 | Initialize | Collect intervention info (device/drug, indication) | `intervention_metadata.json` |
| 1 | Research | Search ClinicalTrials.gov, find FDA guidance | `01_clinical_research_summary.json` |
| 2 | Foundation | Sections 1-6: Summary, Objectives, Design, Population | `02_protocol_foundation.md` |
| 3 | Intervention | Sections 7-8: Administration, Dose Modifications | `03_protocol_intervention.md` |
| 4 | Operations | Sections 9-12: Assessments, Statistics, Regulatory | `04_protocol_operations.md` |
| 5 | Concatenate | Combine all sections into final protocol | `protocol_complete.md` |

---

## Execution Flow

### Mode Selection

When invoked, offer the user two modes:

```
How would you like to proceed?

1. Research Only - Search similar trials and FDA guidance, generate research summary
2. Full Protocol - Complete protocol generation (Steps 0-5)

Enter choice (1 or 2):
```

### Research Only Workflow

1. Run Step 0 (Initialize Intervention)
2. Run Step 1 (Research)
3. Generate research summary artifact
4. Offer option to continue to full protocol or exit

### Full Protocol Workflow

Execute steps 0-5 sequentially:

```
Step 0: Initialize Intervention
  ↓
Step 1: Research Similar Protocols (MCP: trials_search, trials_details)
  ↓
Step 2: Protocol Foundation (Sections 1-6)
  ↓
Step 3: Intervention Details (Sections 7-8)
  ↓
Step 4: Operations & Statistics (Sections 9-12, sample size calculation)
  ↓
Step 5: Concatenate Final Protocol
```

### Resume Logic

On startup, check for existing waypoint files and bead state:

1. If `waypoints/intervention_metadata.json` exists:
   - Read the `"beads"` array for explicit status tracking
   - Display intervention details and bead progress
   - Offer to resume from the first non-completed bead

2. Resume detection (bead-first, fallback to file detection):
   ```
   Check beads array first. If no beads key, fall back to file detection:
   protocol_complete.md exists? → Complete
   04_protocol_operations.md exists? → Resume at Step 5 (bd-ct-005)
   03_protocol_intervention.md exists? → Resume at Step 4 (bd-ct-004)
   02_protocol_foundation.md exists? → Resume at Step 3 (bd-ct-003)
   01_clinical_research_summary.json exists? → Resume at Step 2 (bd-ct-002)
   intervention_metadata.json exists? → Resume at Step 1 (bd-ct-001)
   Nothing exists? → Start at Step 0 (bd-ct-000)
   ```

---

## Step Execution

### Critical Rule: Read Subskill Files Just-In-Time

**IMPORTANT:** Do NOT pre-read all subskill files. Read each subskill file ONLY when that specific step is about to execute:

1. Do NOT read subskill files in advance or "to prepare"
2. Example: When Step 1 needs to run, THEN read `references/01-research-protocols.md` and follow its instructions
3. **For protocol development:** Execute Steps 2, 3, 4 sequentially in order
4. Do NOT try to execute multiple steps in parallel - run sequentially
5. Read each step's subskill file only when that specific step is about to execute

### Step 0: Initialize Intervention
- **Bead:** `bd-ct-000-init` — mark **in-progress** before starting, **completed** after output verified
- **Read:** `references/00-initialize-intervention.md`
- **Output:** `waypoints/intervention_metadata.json`

### Step 1: Research Protocols
- **Bead:** `bd-ct-001-research` — mark **in-progress** before starting, **completed** after output verified
- **Read:** `references/01-research-protocols.md`
- **MCP Required:** `trials_search`, `trials_details`
- **Output:** `waypoints/01_clinical_research_summary.json`

### Step 2: Protocol Foundation
- **Bead:** `bd-ct-002-foundation` — mark **in-progress** before starting, **completed** after output verified
- **Read:** `references/02-protocol-foundation.md`
- **Input:** Intervention metadata, research summary
- **Output:** `waypoints/02_protocol_foundation.md`, `waypoints/02_protocol_metadata.json`

### Step 3: Intervention Details
- **Bead:** `bd-ct-003-intervention` — mark **in-progress** before starting, **completed** after output verified
- **Read:** `references/03-protocol-intervention.md`
- **Input:** Protocol foundation, research summary
- **Output:** `waypoints/03_protocol_intervention.md`

### Step 4: Operations & Statistics
- **Bead:** `bd-ct-004-operations` — mark **in-progress** before starting, **completed** after output verified
- **Read:** `references/04-protocol-operations.md`
- **Script:** `scripts/sample_size_calculator.py`
- **Output:** `waypoints/04_protocol_operations.md`, `waypoints/02_sample_size_calculation.json`

### Step 5: Concatenate Protocol
- **Bead:** `bd-ct-005-concatenate` — mark **in-progress** before starting, **completed** after output verified
- **Read:** `references/05-concatenate-protocol.md`
- **Input:** All protocol section files
- **Output:** `waypoints/protocol_complete.md`

---

## Technical Details

### Waypoint File Formats

**JSON Waypoints** (Steps 0, 1):
- Structured data for programmatic access
- Small file sizes (1-15KB)
- Easy to parse and reference

**Markdown Waypoints** (Steps 2, 3, 4):
- Step 2: `02_protocol_foundation.md` (Sections 1-6)
- Step 3: `03_protocol_intervention.md` (Sections 7-8)
- Step 4: `04_protocol_operations.md` (Sections 9-12)
- Human-readable protocol documents
- Can be directly edited by users
- Individual section files preserved for easier regeneration

### Sample Size Calculator

Interactive Python script for statistical power analysis:

```bash
python scripts/sample_size_calculator.py \
  --endpoint-type continuous \
  --effect-size 0.5 \
  --std-dev 1.0 \
  --alpha 0.05 \
  --power 0.80 \
  --dropout 0.15
```

---

## Error Handling

### MCP Server Unavailable
- Detected in: Step 1
- Action: Display error with installation instructions
- Allow user to retry after installing MCP server
- No fallback available - MCP server is required for protocol research

### Step Fails or Returns Error
- Action: Display error message from subskill
- Ask user: "Retry step? (Yes/No)"
  - Yes: Re-run step
  - No: Save current state, exit orchestrator

### User Interruption
- All progress saved in waypoint files
- User can resume anytime by restarting the skill
- Workflow automatically detects completed steps and resumes from next step
- No data loss

---

## Implementation Requirements

1. **Always read subskill files:** Don't execute from memory. Read the actual subskill markdown file and follow instructions.

2. **Auto-detect resume:** Check for existing waypoint files on startup. Offer to resume if incomplete workflow found.

3. **Sequential execution:** Execute steps 0-5 in order for full protocol mode.

4. **Research summary artifact generation:** After Step 1 completes, generate comprehensive research summary if in research-only mode.

5. **Handle errors gracefully:** If a step fails, give user option to retry or exit.

6. **Track progress with beads:** Update bead status at every step transition. Persist bead state in `waypoints/intervention_metadata.json`. Mark bead in-progress before starting, completed after outputs verified.

7. **Resume from beads:** On startup, read bead state from waypoints before falling back to file-existence detection.

### MCP Tool Call Transparency (REQUIRED)

When invoking MCP tools, always inform the user:
- BEFORE: What tool is being called and why
- AFTER: Success notification with summary of results

**Display notifications:**
```
Searching ClinicalTrials.gov via Clinical Trials MCP...
✅ Clinical Trials MCP completed successfully - Found 15 similar trials
```

---

## Azure-Specific Enhancements

### Azure Health Data Services Integration

Store protocol metadata in FHIR format for interoperability:

```json
{
  "resourceType": "ResearchStudy",
  "status": "draft",
  "title": "[Protocol Title]",
  "protocol": [{
    "display": "Clinical Trial Protocol v1.0"
  }]
}
```

### Azure AI Foundry Agent Support

This skill can be registered as an Azure AI Foundry agent tool:

```yaml
tool:
  name: clinical-trial-protocol
  description: Generate FDA/NIH-compliant clinical trial protocols
  parameters:
    - name: intervention_type
      type: string
      enum: [device, drug]
    - name: intervention_name
      type: string
    - name: indication
      type: string
```

---

## Quality Checks

Before completing each step, verify:

- [ ] Bead for current step marked completed
- [ ] Bead state persisted in waypoint file
- [ ] All required waypoint files created
- [ ] JSON files have valid structure
- [ ] Markdown files follow protocol template format
- [ ] Research data properly cited
- [ ] No placeholder text remaining

Before completing entire workflow, verify:
- [ ] All beads (`bd-ct-000` through `bd-ct-005`) marked completed

---

## Notes for Claude/Copilot

1. **Be conversational:** Guide users through the process with clear explanations
2. **Validate inputs:** Ensure intervention details are complete before proceeding
3. **Cite sources:** Reference specific NCT IDs and FDA guidance documents
4. **Respect token limits:** Use modular approach to stay within output limits
5. **Preserve context:** Each waypoint file should be self-contained for resume capability
