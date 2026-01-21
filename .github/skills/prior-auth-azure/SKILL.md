---
name: prior-auth-azure
description: "Demo skill that processes prior authorization requests, performs initial validation checks (NPI, ICD-10, CMS Coverage, CPT), and generates medical necessity assessments using Azure MCP servers."
---

# Prior Authorization Review Skill (Azure)

Process prior authorization requests using AI-assisted review with MCP connectors for NPI Registry, ICD-10 codes, and CMS Coverage policies. This skill generates draft recommendations for human review.

**Target Users:** Prior authorization specialists, utilization management nurses, medical directors

**Key Features:**
- Two-subskill workflow (Intake & Assessment → Decision & Notification)
- Parallel MCP validation for optimal performance
- Structured waypoint files for audit trail
- Human-in-the-loop decision confirmation
- Azure APIM integration for secure MCP access

---

## Important Disclaimers

> **DRAFT RECOMMENDATIONS ONLY:** This skill generates draft recommendations only. The payer organization remains fully responsible for all final authorization decisions.
>
> **HUMAN REVIEW REQUIRED:** All AI-generated recommendations require review and confirmation by appropriate professionals before becoming final decisions. Users may accept, reject, or override any recommendation with documented justification.
>
> **AI DECISION BEHAVIOR:** In default mode, AI recommends APPROVE or PEND only - never recommends DENY. Decision logic is configurable in the skill's rubric.md file.
>
> **COVERAGE POLICY LIMITATIONS:** Coverage policies are sourced from Medicare LCDs/NCDs via CMS Coverage MCP Connector. If this review is for a commercial or Medicare Advantage plan, payer-specific policies may differ and were not applied.

---

## Prerequisites

### Required MCP Servers (via Azure APIM)

1. **NPI MCP Connector** - Provider verification
   - **Endpoint:** `https://healthcare-mcp.azure-api.net/npi-registry`
   - **Tools:** `npi_lookup_provider(npi="...")`, `npi_verify_credentials(...)`
   - **Use Cases:** Verify provider credentials, specialty, license state, active status

2. **ICD-10 MCP Connector** - Diagnosis code validation
   - **Endpoint:** `https://healthcare-mcp.azure-api.net/icd10`
   - **Tools:** `icd10_validate(codes=[...])`, `icd10_get_details(code="...")`
   - **Use Cases:** Batch validate ICD-10 codes, get detailed code information

3. **CMS Coverage MCP Connector** - Policy lookup
   - **Endpoint:** `https://healthcare-mcp.azure-api.net/cms-coverage`
   - **Tools:** `cms_search_all(search_term="...", state="...", max_results=10)`
   - **Use Cases:** Find applicable LCDs/NCDs for service

---

## Workflow Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                 PRIOR AUTHORIZATION WORKFLOW                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ SUBSKILL 1: INTAKE & ASSESSMENT (3-4 minutes)              │ │
│  │                                                             │ │
│  │  1. Collect request details (member, service, provider)    │ │
│  │  2. Parallel MCP validation:                               │ │
│  │     • NPI Registry → Provider credentials                  │ │
│  │     • ICD-10 → Diagnosis codes                             │ │
│  │     • CMS Coverage → Applicable policies                   │ │
│  │  3. Extract clinical data from documentation               │ │
│  │  4. Map evidence to policy criteria                        │ │
│  │  5. Generate recommendation (APPROVE/PEND)                 │ │
│  │                                                             │ │
│  │  OUTPUT: waypoints/assessment.json                         │ │
│  └────────────────────────────────────────────────────────────┘ │
│                            │                                    │
│                            ▼                                    │
│                 ┌──────────────────────┐                        │
│                 │ HUMAN DECISION POINT │                        │
│                 │  Review AI findings  │                        │
│                 └──────────────────────┘                        │
│                            │                                    │
│                            ▼                                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ SUBSKILL 2: DECISION & NOTIFICATION (1-2 minutes)          │ │
│  │                                                             │ │
│  │  1. Human confirms/overrides recommendation                │ │
│  │  2. Generate authorization number (if approved)            │ │
│  │  3. Create decision documentation                          │ │
│  │  4. Generate notification letters                          │ │
│  │                                                             │ │
│  │  OUTPUT: waypoints/decision.json, outputs/letters/         │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Subskill Descriptions

### Subskill 1: Intake & Assessment (3-4 minutes)
- Collects PA request details (member, service, provider, clinical docs)
- Validates provider credentials via **NPI MCP**
- Validates and retrieves ICD-10 code details via **ICD-10 MCP** (single batch call)
- Validates CPT/HCPCS codes via **WebFetch to CMS Fee Schedule**
- Searches coverage policies via **CMS Coverage MCP**
- Extracts structured clinical data from documentation
- Maps clinical evidence to policy criteria
- Performs medical necessity assessment
- Generates recommendation (APPROVE/PEND)
- **Output:** `waypoints/assessment.json` (consolidated)
- **Data Sources:** NPI MCP, ICD-10 MCP, CMS Coverage MCP (parallel), CMS Fee Schedule (web)

### Subskill 2: Decision & Notification (1-2 minutes)
- Reads assessment from Subskill 1
- Presents findings for human review
- Accepts human confirmation or override
- Generates authorization number (if approved)
- Creates decision waypoint
- Generates notification letters (approval/denial/pend)
- **Output:** `waypoints/decision.json`, `outputs/approval_letter.md` or `outputs/pend_letter.md`

---

## Execution Flow

### Startup: Request Input Files

**Option A: User provides files**
```
To begin a prior authorization review, I need:
  1. PA Request Form (member info, service details)
  2. Clinical Documentation (progress notes, test results)
  3. Provider Information (NPI, credentials)

Please provide the file paths or paste the content.
```

**Option B: Demo mode**
```
Would you like to use sample PA request files for demonstration?
Sample files are in: assets/sample/
```

- **Demo mode note:** When sample files are used, the sample data contains demo NPI and sample member ID. This combination triggers demo mode, which skips the NPI MCP lookup for this specific provider only. All other MCP calls execute normally.

---

## Implementation Requirements

1. **Always read subskill files:** Don't execute from memory. Read the actual subskill markdown file and follow instructions.

2. **Auto-detect resume:** Check for existing `waypoints/assessment.json` on startup. If found and status is not "assessment_complete", offer to resume.

3. **Parallel MCP execution:** In Subskill 1, execute NPI, ICD-10, and Coverage MCP calls in parallel for optimal performance.

4. **Preserve user data:** Never overwrite waypoint files without asking confirmation or backing up.

5. **Clear progress indicators:** Show users what's happening during operations (MCP queries, data analysis).

6. **Graceful degradation:** If optional data missing, continue with available data and note limitations.

7. **Validate outputs:** Check that waypoint files have expected structure before proceeding.

### MCP Tool Call Transparency (REQUIRED)

When invoking MCP tools, always inform the user:
- BEFORE: What tool is being called and why
- AFTER: Success notification with summary of results

**Example:**
```
Searching CMS Coverage MCP for applicable policies...
✅ CMS Coverage MCP completed - Found policy: L34567 - Knee Arthroplasty LCD
```

### Common Mistakes to Avoid

**MCP and Validation:**
- ❌ Don't call `icd10_validate()` multiple times - validate all codes in one batch
- ❌ Don't call `icd10_get_details()` with array parameter - it takes single code only
- ❌ Don't skip CPT/HCPCS validation - it's required even though no MCP exists
- ❌ Don't forget to display MCP success notifications after each connector invocation

**Decision Policy Enforcement (CRITICAL):**
- ❌ Don't ignore provider verification status when calculating recommendation
- ❌ Don't make decisions without first reading rubric.md
- ✅ DO read rubric.md FIRST to understand current policy
- ✅ DO apply the decision rules specified in rubric.md

---

## Error Handling

**Missing MCP Servers:**
If required MCP connectors not available, display error listing missing connectors.

**Missing Subskill Prerequisites:**
If Subskill 2 invoked without `waypoints/assessment.json`, notify user to complete Subskill 1 first.

**File Write Errors:**
If unable to write waypoint files, display error with file path, check permissions/disk space, and offer retry.

**Data Quality Issues:**
If clinical data extraction confidence <60%, warn user with confidence score and low-confidence areas. Offer options to: continue, request additional documentation, or abort.

---

## Quality Checks

Before completing workflow, verify:

- [ ] All required waypoint files created
- [ ] Decision has clear rationale documented
- [ ] All required fields populated
- [ ] Output files generated successfully

---

## Sample Data

Sample case files are included in `assets/sample/` for demonstration purposes. When using sample files, the skill operates in demo mode which:

- Skips NPI MCP lookup for the sample provider only
- Executes all other MCP calls (ICD-10, CMS Coverage) normally
- Demonstrates the complete workflow with a pre-configured case

---

## Azure-Specific Integration

### Azure APIM Endpoint Configuration

```yaml
mcp_servers:
  npi-registry:
    url: https://healthcare-mcp.azure-api.net/npi-registry
    auth: azure_ad_token
  icd10-codes:
    url: https://healthcare-mcp.azure-api.net/icd10
    auth: azure_ad_token
  cms-coverage:
    url: https://healthcare-mcp.azure-api.net/cms-coverage
    auth: azure_ad_token
```

### FHIR Integration

Assessment data can be stored as FHIR resources:

```json
{
  "resourceType": "Claim",
  "use": "preauthorization",
  "status": "active",
  "patient": { "reference": "Patient/123" },
  "insurance": [{ "coverage": { "reference": "Coverage/456" }}]
}
```
