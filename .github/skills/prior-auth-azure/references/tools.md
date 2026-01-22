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
| `cms_search_all` | Unified search across NCDs, LCDs, and Articles. Good starting point when document type is unknown. |
| `cms_search_ncds` | Search National Coverage Determinations (national-level Medicare policies that apply uniformly across all states). |
| `cms_search_lcds` | Search Local Coverage Determinations (regional policies by Medicare Administrative Contractors). Filter by state or contractor. |
| `cms_search_articles` | Search billing and coding guidance documents related to LCDs. |
| `cms_lcd_details` | Get full LCD details including policy text, HCPC codes, ICD-10 codes, and related documents. |
| `cms_article_details` | Get complete article details with codes, modifiers, bill types, and revenue codes. |
| `cms_search_medcac` | Search MEDCAC (Medicare Evidence Development & Coverage Advisory Committee) meetings. |
| `cms_contractors` | List Medicare Administrative Contractors and their jurisdictions. Filter by state or contract type. |
| `cms_states` | List valid state codes for use in other CMS tools. |
| `cms_whats_new` | Find recently updated or newly published coverage determinations (last 30 days by default). |

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
| `npi_lookup_provider` | Look up a specific provider by their 10-digit NPI number. Returns demographics, addresses, specialties, and identifiers. |
| `npi_search_providers` | Search providers by name, location, specialty, or organization. Supports wildcards. Filter by individual (NPI-1) or organization (NPI-2). |
| `npi_verify_credentials` | Batch validate NPIs: checks format validity and confirms registration status in NPPES. |

---

## PubMed

| Tool | Purpose |
|------|---------|
| `search_pubmed` | Search PubMed/MEDLINE for biomedical literature. Returns article summaries with PMIDs. |
| `get_article` | Get full article details including abstract, authors, journal, and MeSH terms. |
| `get_citations` | Get articles that cite a specific PMID. Useful for finding related research. |

---

## FHIR Operations (Azure API for FHIR)

| Tool | Purpose |
|------|---------|
| `fhir_search` | Search FHIR resources with parameters. Supports Patient, Observation, Condition, etc. |
| `fhir_read` | Read a specific FHIR resource by type and ID. |
| `fhir_create` | Create a new FHIR resource. Validates against profiles. |
| `fhir_validate` | Validate a FHIR resource against a profile without persisting. |

---

## Azure APIM Endpoints

All MCP servers are accessible via Azure API Management:

| Server | Endpoint |
|--------|----------|
| CMS Coverage | `https://healthcare-mcp.azure-api.net/cms-coverage/mcp` |
| NPI Registry | `https://healthcare-mcp.azure-api.net/npi-registry/mcp` |
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
