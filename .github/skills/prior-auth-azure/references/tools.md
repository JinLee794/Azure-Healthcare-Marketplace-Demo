# Healthcare MCP Tool Reference

A quick reference guide for the Clinical Trials, CMS Coverage, ICD-10, NPI, and FHIR MCP connectors available via Azure APIM.

---

## Clinical Trials

| Tool | Purpose |
|------|---------|
| `search_trials` | Search ClinicalTrials.gov by condition, intervention, sponsor, location, status, or phase. Returns up to 100 results. |
| `get_trial` | Get comprehensive details for a specific trial by NCT ID, including eligibility criteria, outcomes, study design, and contact information. |
| `get_trial_eligibility` | Get eligibility criteria (inclusion/exclusion) for a clinical trial. |
| `get_trial_locations` | Get recruiting locations for a clinical trial with contact information. |
| `search_by_condition` | Find recruiting clinical trials for a specific condition near a location. |
| `get_trial_results` | Get results summary for a completed clinical trial (if available). |

---

## CMS Coverage

| Tool | Purpose |
|------|---------|
| `search_coverage` | Search Medicare coverage determinations (LCD/NCD). |
| `get_coverage_by_cpt` | Get Medicare coverage details for a CPT/HCPCS code. |
| `get_coverage_by_icd10` | Get Medicare coverage details related to an ICD-10 code. |
| `check_medical_necessity` | Check likely medical necessity for CPT + ICD-10 combinations. |
| `get_mac_jurisdiction` | Resolve MAC jurisdiction by state/ZIP for regional policy context. |

---

## ICD-10

| Tool | Purpose |
|------|---------|
| `validate_icd10` | Validate an ICD-10-CM code for format correctness and existence in official code set. |
| `lookup_icd10` | Get comprehensive info for a specific code: description, chapter, billability status. |
| `search_icd10` | Search diagnosis codes by clinical description, symptom, condition, or partial code. |
| `get_icd10_chapter` | Get chapter information and example codes for a code prefix (e.g., 'E11' for diabetes). |

---

## NPI

| Tool | Purpose |
|------|---------|
| `lookup_npi` | Look up a specific provider by their 10-digit NPI number. Returns name, specialty, address, credentials. |
| `search_providers` | Search providers by name, location, specialty, or organization. Supports wildcards. Filter by individual (NPI-1) or organization (NPI-2). |
| `validate_npi` | Validate NPI format (Luhn check with 80840 prefix) and existence in CMS registry. |

---

## PubMed

| Tool | Purpose |
|------|---------|
| `search_pubmed` | Search PubMed/MEDLINE for biomedical literature. Returns article IDs and metadata. Supports MeSH and boolean queries. |
| `get_article` | Get detailed info about a specific PubMed article (title, abstract, authors, MeSH terms, keywords). |
| `get_articles_batch` | Get details for multiple articles at once (up to 50 PMIDs). |
| `get_article_abstract` | Get the abstract text for a PubMed article. |
| `find_related_articles` | Find articles related to a specific PubMed article. |
| `search_clinical_queries` | Search using clinical study category filters (therapy, diagnosis, prognosis, etiology, clinical prediction guides). |

---

## FHIR Operations (Azure API for FHIR)

| Tool | Purpose |
|------|---------|
| `search_patients` | Search patients by name, DOB, identifier, gender. |
| `get_patient` | Retrieve a specific patient by FHIR resource ID. |
| `get_patient_conditions` | Get all conditions/diagnoses for a patient. Filter by `clinical_status`. |
| `get_patient_medications` | Get medications for a patient. Filter by `status` (active/completed/stopped). |
| `get_patient_observations` | Get observations (vitals, lab results) for a patient. Filter by `category` or LOINC `code`. |
| `get_patient_encounters` | Get encounters (visits) for a patient. Filter by `status` or `date`. |
| `search_practitioners` | Search for practitioners/providers by name, identifier, or specialty. |
| `validate_resource` | Validate a FHIR resource against the server's profiles without persisting. |

---

## Azure APIM Endpoints

All MCP servers are accessible via Azure API Management:

> **Note:** Route shape may vary by deployment profile. Use configured `MCP_*_URL` values as source of truth.

| Server | Endpoint |
|--------|----------|
| CMS Coverage | `https://healthcare-mcp.azure-api.net/cms/mcp` (or `/cms-coverage/mcp`) |
| NPI Registry | `https://healthcare-mcp.azure-api.net/npi/mcp` (or `/npi-registry/mcp`) |
| ICD-10 Codes | `https://healthcare-mcp.azure-api.net/icd10/mcp` |
| Clinical Trials | `https://healthcare-mcp.azure-api.net/clinical-trials/mcp` |
| PubMed | `https://healthcare-mcp.azure-api.net/pubmed/mcp` |
| FHIR Operations | `https://healthcare-mcp.azure-api.net/fhir/mcp` |

### Authentication

All endpoints require Azure AD authentication:

```bash
# Get access token
az account get-access-token --scope api://healthcare-mcp/.default

# Use with MCP request
curl -X POST https://healthcare-mcp.azure-api.net/cms-coverage/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

---

## Error Handling

All tools return structured errors:

```json
{
  "error": {
    "code": "PROVIDER_NOT_FOUND",
    "message": "NPI 1234567890 not found in NPPES registry",
    "details": {
      "searched_npi": "1234567890",
      "suggestion": "Verify NPI is correct and provider is enrolled"
    }
  }
}
```

Common error codes:
- `INVALID_INPUT` - Bad parameter format
- `NOT_FOUND` - Resource not found
- `RATE_LIMITED` - Too many requests
- `SERVICE_UNAVAILABLE` - Backend service down
