---
name: azure-fhir-developer
description: "Azure API for FHIR development including resource management, SMART on FHIR authentication, bulk data export, and integration with Azure Health Data Services. Use when building FHIR apps on Azure."
triggers:
  - "FHIR"
  - "Azure Health"
  - "healthcare API"
  - "patient data"
  - "clinical data"
---

# Azure FHIR Developer Skill

## Overview
This skill provides comprehensive guidance for developing healthcare applications using Azure API for FHIR and Azure Health Data Services.

## Authentication Patterns

### SMART on FHIR with Azure AD B2C
When implementing patient-facing apps, use the SMART on FHIR launch sequence:

1. **Register app in Azure AD B2C**
   - Configure redirect URIs for your app
   - Set up API permissions for FHIR scopes

2. **Configure FHIR server**
   ```bash
   az healthcareapis service update \
     --resource-group <rg-name> \
     --name <fhir-service-name> \
     --authentication-audience "https://<fhir-service-name>.azurehealthcareapis.com"
   ```

3. **Implement authorization code flow with PKCE**
   ```typescript
   const authConfig = {
     authority: `https://${tenantName}.b2clogin.com/${tenantName}.onmicrosoft.com/${policyName}`,
     clientId: '<your-client-id>',
     scopes: ['patient/*.read', 'launch/patient']
   };
   ```

### Service-to-Service with Managed Identity
For backend services, use managed identity:

```typescript
import { DefaultAzureCredential } from '@azure/identity';

const credential = new DefaultAzureCredential();
const token = await credential.getToken('https://<fhir-server>.azurehealthcareapis.com/.default');
```

## Common FHIR Operations

### Creating a Patient Resource
```http
POST https://{fhir-server}.azurehealthcareapis.com/Patient
Authorization: Bearer {token}
Content-Type: application/fhir+json

{
  "resourceType": "Patient",
  "identifier": [{
    "system": "http://hospital.example.org/patients",
    "value": "12345"
  }],
  "name": [{
    "family": "Smith",
    "given": ["John"]
  }],
  "gender": "male",
  "birthDate": "1970-01-01"
}
```

### Searching for Patients
```http
GET https://{fhir-server}.azurehealthcareapis.com/Patient?name=Smith&birthdate=1970-01-01
Authorization: Bearer {token}
```

### Creating an Observation
```http
POST https://{fhir-server}.azurehealthcareapis.com/Observation
Authorization: Bearer {token}
Content-Type: application/fhir+json

{
  "resourceType": "Observation",
  "status": "final",
  "code": {
    "coding": [{
      "system": "http://loinc.org",
      "code": "8867-4",
      "display": "Heart rate"
    }]
  },
  "subject": {
    "reference": "Patient/12345"
  },
  "valueQuantity": {
    "value": 72,
    "unit": "beats/minute",
    "system": "http://unitsofmeasure.org",
    "code": "/min"
  }
}
```

## Bulk Data Export

### Initiate System-Level Export
```http
GET https://{fhir-server}.azurehealthcareapis.com/$export
Authorization: Bearer {token}
Accept: application/fhir+json
Prefer: respond-async
```

### Check Export Status
```http
GET {content-location-from-header}
Authorization: Bearer {token}
```

## Azure-Specific Considerations

### HIPAA Compliance Checklist
- Enable Azure Private Link for FHIR endpoints
- Configure diagnostic settings for audit logging
- Use Azure Key Vault for secrets management
- Implement VNET integration
- Enable customer-managed keys for encryption at rest

### Performance Optimization
- Use `_include` and `_revinclude` to reduce round trips
- Implement pagination with `_count` parameter
- Cache frequently accessed reference data
- Use bulk import for large data migrations

### Monitoring
```kusto
// Log Analytics query for FHIR API latency
AzureDiagnostics
| where ResourceType == "MICROSOFT.HEALTHCAREAPIS/WORKSPACES"
| summarize avg(DurationMs) by OperationName, bin(TimeGenerated, 5m)
| render timechart
```

## Code Systems Reference

| System | URL | Use Case |
|--------|-----|----------|
| LOINC | http://loinc.org | Lab observations, vital signs |
| SNOMED CT | http://snomed.info/sct | Clinical findings, procedures |
| RxNorm | http://www.nlm.nih.gov/research/umls/rxnorm | Medications |
| ICD-10-CM | http://hl7.org/fhir/sid/icd-10-cm | Diagnoses |
| CPT | http://www.ama-assn.org/go/cpt | Procedures (billing) |

## Related Skills
- `azure-health-data-services` - DICOM and MedTech integration
- `prior-auth-azure` - Prior authorization workflows
