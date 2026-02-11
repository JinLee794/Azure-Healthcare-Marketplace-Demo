# MCP Servers Beginner Guide

This guide explains each MCP server in this repo in junior-developer terms: what it does, when to use it, and how to test it.

## 1) What an MCP Server Is

Each MCP server is an HTTP endpoint that speaks JSON-RPC over `POST /mcp` and publishes discovery metadata at `GET /.well-known/mcp`.

In this repo, servers are Azure Functions under `src/mcp-servers/`.

## 2) Shared Local Ports

| Server | Folder | Default Local Port |
|--------|--------|--------------------|
| NPI Lookup | `src/mcp-servers/npi-lookup` | `7071` |
| ICD-10 Validation | `src/mcp-servers/icd10-validation` | `7072` |
| CMS Coverage | `src/mcp-servers/cms-coverage` | `7073` |
| FHIR Operations | `src/mcp-servers/fhir-operations` | `7074` |
| PubMed | `src/mcp-servers/pubmed` | `7075` |
| Clinical Trials | `src/mcp-servers/clinical-trials` | `7076` |

Start one server:

```bash
./scripts/local-test.sh npi-lookup 7071
```

Common smoke tests:

```bash
curl http://localhost:7071/.well-known/mcp | jq
curl -X POST http://localhost:7071/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | jq
```

## 3) Server-by-Server Guide

### A. NPI Lookup MCP

- Folder: `src/mcp-servers/npi-lookup`
- Use it for: provider identity checks and NPI validation.
- Upstream data source: CMS NPI Registry (`npiregistry.cms.hhs.gov`).
- Main tools:
  - `lookup_npi`
  - `search_providers`
  - `validate_npi`

Quick test:

```bash
curl -X POST http://localhost:7071/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":2,
    "method":"tools/call",
    "params":{"name":"lookup_npi","arguments":{"npi":"1234567890"}}
  }' | jq
```

### B. ICD-10 Validation MCP

- Folder: `src/mcp-servers/icd10-validation`
- Use it for: diagnosis code validation and lookup.
- Upstream data source: NLM Clinical Tables ICD-10-CM API.
- Main tools:
  - `validate_icd10`
  - `lookup_icd10`
  - `search_icd10`
  - `get_icd10_chapter`

Quick test:

```bash
curl -X POST http://localhost:7072/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":2,
    "method":"tools/call",
    "params":{"name":"validate_icd10","arguments":{"code":"E11.9"}}
  }' | jq
```

### C. CMS Coverage MCP

- Folder: `src/mcp-servers/cms-coverage`
- Use it for: Medicare coverage lookups and medical-necessity checks.
- Data behavior: current implementation uses a simplified local knowledge base and simulated search responses for common scenarios.
- Main tools:
  - `search_coverage`
  - `get_coverage_by_cpt`
  - `get_coverage_by_icd10`
  - `check_medical_necessity`
  - `get_mac_jurisdiction`

Quick test:

```bash
curl -X POST http://localhost:7073/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":2,
    "method":"tools/call",
    "params":{"name":"get_coverage_by_cpt","arguments":{"cpt_code":"27447"}}
  }' | jq
```

### D. FHIR Operations MCP

- Folder: `src/mcp-servers/fhir-operations`
- Use it for: patient-centric FHIR queries and resource validation.
- Upstream target:
  - Primary: Azure Health Data Services FHIR service via `FHIR_SERVER_URL`.
  - Fallback: public HAPI FHIR server demo behavior when `FHIR_SERVER_URL` is not set.
- Main tools:
  - `search_patients`
  - `get_patient`
  - `get_patient_conditions`
  - `get_patient_medications`
  - `get_patient_observations`
  - `get_patient_encounters`
  - `search_practitioners`
  - `validate_resource`

Environment note:

- Set `FHIR_SERVER_URL` in `src/mcp-servers/fhir-operations/local.settings.json` or app settings for real AHDS-backed data.

Quick test:

```bash
curl -X POST http://localhost:7074/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":2,
    "method":"tools/call",
    "params":{"name":"search_patients","arguments":{"family":"Smith","count":5}}
  }' | jq
```

### E. PubMed MCP

- Folder: `src/mcp-servers/pubmed`
- Use it for: literature search and article retrieval.
- Upstream data source: NCBI E-utilities (PubMed).
- Optional env var: `NCBI_API_KEY` (recommended for higher throughput).
- Main tools:
  - `search_pubmed`
  - `get_article`
  - `get_articles_batch`
  - `get_article_abstract`
  - `find_related_articles`
  - `search_clinical_queries`

Quick test:

```bash
curl -X POST http://localhost:7075/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":2,
    "method":"tools/call",
    "params":{"name":"search_pubmed","arguments":{"query":"type 2 diabetes glp-1 cardiovascular outcomes","max_results":5}}
  }' | jq
```

### F. Clinical Trials MCP

- Folder: `src/mcp-servers/clinical-trials`
- Use it for: searching ClinicalTrials.gov and retrieving trial details.
- Upstream data source: ClinicalTrials.gov API v2.
- Main tools:
  - `search_trials`
  - `get_trial`
  - `get_trial_eligibility`
  - `get_trial_locations`
  - `search_by_condition`
  - `get_trial_results`

Quick test:

```bash
curl -X POST http://localhost:7076/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":2,
    "method":"tools/call",
    "params":{"name":"search_trials","arguments":{"condition":"non-small cell lung cancer","page_size":5}}
  }' | jq
```

## 4) APIM vs Local (How to Choose)

- Use local (`localhost`) when developing/debugging quickly.
- Use direct Function App endpoint when validating deployed app behavior without APIM policies.
- Use APIM endpoint when validating production-like auth, policy, and routing behavior.

If using APIM passthrough, include:

- Header: `Ocp-Apim-Subscription-Key: <key>`

## 5) Common Beginner Pitfalls

1. Port mismatch:
- If `tools/list` fails, verify the server port and that `func start` is running.
2. Missing `FHIR_SERVER_URL`:
- FHIR server may return demo/fallback behavior; set AHDS FHIR URL for real data.
3. APIM 401/403:
- Usually missing/invalid subscription key or OAuth token mismatch.
4. Network restrictions:
- Direct Function App access can fail if public network access or IP rules block your client.
