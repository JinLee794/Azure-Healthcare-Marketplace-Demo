# Subskill 1: Intake & Assessment

## Purpose
Collect prior authorization request information, validate credentials and codes, extract clinical data, identify applicable coverage policies, assess medical necessity, and generate approval recommendation.

## Prerequisites

### Required MCP Servers (via Azure APIM)

This subskill uses 3 MCP connectors for healthcare data validation:

1. **NPI MCP Connector** - Provider verification
   - **Tools:** `npi_lookup_provider(npi="...")`, `npi_verify_credentials(...)`
   - **Use Cases:** Verify provider credentials, specialty, license state, active status
   - **Success Notification:** `✅👨‍⚕️ NPI MCP Connector invoked successfully`

2. **ICD-10 MCP Connector** - Diagnosis code validation
   - **Tools:** `icd10_validate(codes=[...])`, `icd10_get_details(code="...")`
   - **Use Cases:** Batch validate ICD-10 codes, get detailed code information
   - **Success Notification:** `✅🔢 ICD-10 MCP Connector invoked successfully`

3. **CMS Coverage MCP Connector** - Policy lookup
   - **Tools:** `cms_search_all(search_term="...", state="...", max_results=10)`
   - **Use Cases:** Find applicable LCDs/NCDs for service
   - **Success Notification:** `✅📋 CMS Coverage MCP Connector invoked successfully`

---

## What This Subskill Does

1. Collects PA request details (member, service, provider, clinical documentation)
2. Validates provider credentials and medical codes via MCP connectors (parallel execution)
3. Searches for applicable coverage policies
4. Extracts clinical data and maps to policy criteria
5. Performs medical necessity assessment
6. Generates recommendation (APPROVE/PEND)

---

## Execution Flow

### Step 1: Collect Request Information

Request PA details from user:

```
Prior Authorization Request Information:

1. Member Information
   - Member Name: 
   - Member ID:
   - Date of Birth:
   - State:

2. Service Information
   - Service Description:
   - CPT/HCPCS Code(s):
   - ICD-10 Diagnosis Code(s):
   - Requested Date of Service:

3. Provider Information
   - Provider Name:
   - NPI:
   - Specialty:

4. Clinical Documentation
   - Please provide or paste clinical notes/documentation
```

**Or if using sample files:**
Read from `assets/sample/` directory.

---

### Step 2: Parallel MCP Validation

Execute MCP calls in parallel for optimal performance:

**2a. NPI Validation**

Display: "Verifying provider credentials via NPI MCP Connector..."

```python
npi_lookup_provider(npi="[provider_npi]")
```
- Verify NPI is active
- Confirm specialty matches service
- Check license state

After successful call, display: "✅👨‍⚕️ NPI MCP Connector completed successfully - Provider: [Name], Specialty: [Specialty], Status: Active"

**If provider not found:**
Display error: "Provider NPI [number] not found or inactive. Per rubric.md policy, requests without verified provider will result in PENDING status (request credentialing documentation)."

**2b. ICD-10 Validation**

Display: "Validating diagnosis codes via ICD-10 MCP Connector..."

```python
icd10_validate(codes=["E11.9", "J06.9", ...])  # Batch validate ALL codes
```

For each valid code, get details:
```python
icd10_get_details(code="E11.9")  # Single code only
```

After successful call, display: "✅🔢 ICD-10 MCP Connector completed successfully - Validated [N] codes"

**2c. CMS Coverage Policy Search**

Display: "Searching coverage policies via CMS Coverage MCP Connector..."

```python
cms_search_all(
    search_term="[service description]",
    state="[member_state]",
    max_results=10
)
```
- Find applicable LCDs/NCDs for service

After successful call, display: "✅📋 CMS Coverage MCP Connector completed successfully - Found policy: [Policy ID] - [Title]"

**Important:** Also display contextual limitation notice:
> "Note: Coverage policies are sourced from Medicare LCDs/NCDs. If this review is for a commercial or Medicare Advantage plan, payer-specific policies may differ."

---

### Step 3: CPT/HCPCS Validation (WebFetch)

Display: "Validating CPT/HCPCS codes via CMS Fee Schedule..."

For each CPT/HCPCS code:
- WebFetch to CMS Medicare Physician Fee Schedule
- Verify code is valid and active
- Get code description

Display: "✅ CPT validation completed - [Code]: [Description]"

---

### Step 4: Extract Clinical Data

Parse clinical documentation to extract:
- Chief complaint
- Relevant diagnoses
- Prior treatments tried
- Current symptoms/findings
- Test results (labs, imaging)
- Clinical justification for service

Calculate extraction confidence (0-100%):
- High confidence (>80%): Clear, structured documentation
- Medium confidence (60-80%): Some inference required
- Low confidence (<60%): Significant gaps

---

### Step 5: Read Rubric

**CRITICAL:** Before making any recommendation, read `references/rubric.md` to understand:
- Current decision policy
- Criteria evaluation order
- Override rules
- Confidence thresholds

---

### Step 6: Map Evidence to Policy Criteria

For each criterion in the applicable policy:
1. Search clinical data for supporting evidence
2. Mark as MET, NOT_MET, or INSUFFICIENT
3. Document specific evidence supporting determination
4. Assign confidence score (0-100)

---

### Step 7: Generate Recommendation

Apply rubric.md decision rules:

**APPROVE** (must meet ALL):
- Provider verified (NPI valid and active)
- All ICD-10 codes valid
- All CPT codes valid
- Coverage policy found
- ≥80% of required criteria MET
- Overall confidence ≥70%

**PEND** (any of these):
- Provider not verified → Request credentialing docs
- Missing criteria evidence → Request additional documentation
- Confidence <70% → Request clarification
- Borderline case → Request medical director review

**Note:** AI never recommends DENY in default mode.

---

### Step 8: Create Assessment Waypoint

**File:** `waypoints/assessment.json`

**Consolidated structure:**
```json
{
  "request_id": "...",
  "created": "ISO datetime",
  "status": "assessment_complete",

  "request": {
    "member": {"name": "...", "id": "...", "dob": "...", "state": "..."},
    "service": {"type": "...", "description": "...", "cpt_codes": [...], "icd10_codes": [...]},
    "provider": {"npi": "...", "name": "...", "specialty": "...", "verified": true/false}
  },

  "clinical": {
    "chief_complaint": "...",
    "key_findings": ["...", "..."],
    "prior_treatments": ["..."],
    "extraction_confidence": 0-100
  },

  "policy": {
    "policy_id": "...",
    "policy_title": "...",
    "policy_type": "LCD/NCD",
    "contractor": "...",
    "covered_indications": ["...", "..."]
  },

  "criteria_evaluation": [
    {"criterion": "...", "status": "MET/NOT_MET/INSUFFICIENT", "evidence": [...], "notes": "...", "confidence": 0-100}
  ],

  "recommendation": {
    "decision": "APPROVE/PEND",
    "confidence": "HIGH/MEDIUM/LOW",
    "confidence_score": 0-100,
    "rationale": "...",
    "criteria_met": "N/N",
    "gaps": [{"what": "...", "critical": true/false, "request": "..."}]
  }
}
```

**Write file.**

---

### Step 9: Generate Audit Justification Document

**Purpose:** Create a detailed, human-readable audit justification document for regulatory compliance and review.

**File:** `outputs/audit_justification.md`

Inform user: "Generating audit justification document..."

**Generate comprehensive Markdown report with the following sections:**

**0. Disclaimer Header (REQUIRED - must appear at top of document)**

```
⚠️ AI-ASSISTED DRAFT - REVIEW REQUIRED
Coverage policies reflect Medicare LCDs/NCDs only. If this review is for a
commercial or Medicare Advantage plan, payer-specific policies were not applied.
All decisions require human clinical review before finalization.
```

1. **Executive Summary**
   - Request ID, review date, reviewed by
   - Member details (name, ID, DOB)
   - Service description
   - Provider details (name, NPI, specialty)
   - Decision (APPROVE/PEND)
   - Overall confidence (percentage and level)

2. **Clinical Synopsis**
   - Chief complaint
   - Relevant diagnoses with ICD-10 codes
   - Key clinical findings
   - Prior treatments

3. **Policy Analysis**
   - Applicable policy (LCD/NCD)
   - Coverage criteria
   - Criteria evaluation (met/not met)

4. **Recommendation Details**
   - Decision rationale
   - Supporting evidence
   - Gaps identified (if any)

---

### Step 10: Display Summary

```
✅ INTAKE & ASSESSMENT COMPLETE

📋 Request Summary:
   Member: [Name] ([ID])
   Service: [Description] ([CPT Code])
   Provider: [Name] ([NPI]) - [Verified/Not Verified]

📊 Validation Results:
   NPI: ✅ Verified
   ICD-10 Codes: ✅ [N] codes validated
   CPT Codes: ✅ [N] codes validated
   Coverage Policy: ✅ Found - [Policy ID]

🔍 Clinical Assessment:
   Criteria Met: [N]/[Total]
   Confidence: [Percentage]% ([Level])

📝 RECOMMENDATION: [APPROVE/PEND]
   Rationale: [Brief rationale]

📁 Files Created:
   • waypoints/assessment.json
   • outputs/audit_justification.md

---

⚠️ HUMAN REVIEW REQUIRED
This is a draft recommendation. Please review the assessment
and proceed to Subskill 2 for final decision.

Ready to continue? (Yes/No)
```

---

## Output Files

| File | Content |
|------|---------|
| `waypoints/assessment.json` | Structured assessment data |
| `outputs/audit_justification.md` | Human-readable audit document |

---

## Error Handling

### MCP Connector Unavailable

Display error: "MCP Connector Unavailable - Cannot access required healthcare data connectors. This skill requires all three MCP connectors (CMS Coverage, ICD-10, NPI) to function. Please configure the missing connectors and try again."

Exit subskill and return to main menu.

### Low Confidence Clinical Extraction

If overall confidence < 60%:

Display warning: "LOW CONFIDENCE WARNING - Extraction Confidence: [X]%"

List low confidence areas and offer options:
1. Continue (may result in pend)
2. Request additional documentation
3. Abort

---

## Quality Checks

Before completing Subskill 1:
- [ ] All MCP validations completed
- [ ] Coverage policy identified
- [ ] Clinical data extracted
- [ ] Criteria evaluation complete
- [ ] Recommendation generated
- [ ] Assessment waypoint created
- [ ] Audit document generated

---

## Notes for Claude/Copilot

### Implementation Hints

1. **Parallel MCP calls save time:** Execute NPI, ICD-10, and Coverage searches concurrently in Step 2
2. **ICD-10 batch validation:** Use `icd10_validate(codes=[...])` for all codes at once, then `icd10_get_details(code=...)` for each individual code
3. **CPT validation is sequential:** WebFetch each CPT/HCPCS code to CMS Fee Schedule in Step 3 (no MCP available)
4. **Display MCP notifications:** Show success notifications after each MCP connector invocation for user visibility
5. **Policy-aware extraction:** Focus clinical extraction on what policy criteria need
6. **Be specific with evidence:** Document exact clinical facts supporting each criterion
7. **Honest confidence:** Low confidence should trigger warnings/human review

**Display notifications:**
- BEFORE each MCP/WebFetch call: Inform user which connector is being used and what data is being queried
- AFTER each successful call: Display success notification with summary

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
- ✅ DO store validation failure status for Step 2

**Clinical Assessment:**
- ❌ Don't mark criteria as "MET" without specific evidence
- ✅ DO check validation status per rubric.md rules
- ✅ DO follow the evaluation order specified in rubric.md
- ✅ DO execute MCP calls in parallel where possible
- ✅ DO validate CPT codes via WebFetch to CMS Fee Schedule
- ✅ DO provide clear, specific evidence for each criterion
- ✅ DO flag borderline cases for human review
