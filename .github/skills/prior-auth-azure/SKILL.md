---
name: prior-auth-azure
description: "Prior authorization workflows on Azure including coverage verification, PA request submission, and status tracking. Use for healthcare revenue cycle management."
triggers:
  - "prior auth"
  - "prior authorization"
  - "coverage verification"
  - "insurance approval"
  - "PA request"
---

# Prior Authorization on Azure Skill

## Overview
This skill provides guidance for implementing prior authorization workflows using Azure services, including coverage verification, PA request submission, and real-time decision support.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    PRIOR AUTHORIZATION WORKFLOW                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                   │
│  │   EHR/PMS    │───▶│  Azure API   │───▶│  Coverage    │                   │
│  │              │    │  Management  │    │  Lookup      │                   │
│  └──────────────┘    └──────────────┘    └──────────────┘                   │
│                             │                    │                           │
│                             ▼                    ▼                           │
│                      ┌──────────────┐    ┌──────────────┐                   │
│                      │  Logic Apps  │    │  Cosmos DB   │                   │
│                      │  Workflow    │    │  (Policies)  │                   │
│                      └──────────────┘    └──────────────┘                   │
│                             │                                                │
│                             ▼                                                │
│                      ┌──────────────┐    ┌──────────────┐                   │
│                      │  Payer API   │◀──▶│  X12 278     │                   │
│                      │  Integration │    │  Processing  │                   │
│                      └──────────────┘    └──────────────┘                   │
│                             │                                                │
│                             ▼                                                │
│                      ┌──────────────┐                                       │
│                      │   PA Status  │                                       │
│                      │   Tracking   │                                       │
│                      └──────────────┘                                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## X12 278 Transaction

### Request Structure (278 Request)
```
ISA*00*          *00*          *ZZ*SENDER         *ZZ*RECEIVER       *240115*1430*^*00501*000000001*0*P*:~
GS*HI*SENDER*RECEIVER*20240115*1430*1*X*005010X217~
ST*278*0001*005010X217~
BHT*0007*11*REF123*20240115*1430~
HL*1**20*1~
NM1*X3*2*PAYER NAME*****PI*12345~
HL*2*1*21*1~
NM1*1P*2*PROVIDER GROUP*****XX*1234567890~
HL*3*2*22*0~
NM1*IL*1*SMITH*JOHN****MI*MEM123456~
DMG*D8*19700101*M~
TRN*1*PA123456*9012345678~
UM*HS*I*3~
HCR*A1~
DTP*472*RD8*20240201-20240208~
HI*ABK:E11.9~
HI*ABF:J06.9~
SV2*0120**HC:99213~
SE*18*0001~
GE*1*1~
IEA*1*000000001~
```

### Response Structure (278 Response)
```
ST*278*0001*005010X217~
BHT*0007*15*REF123*20240115*1435~
HL*1**20*1~
NM1*X3*2*PAYER NAME*****PI*12345~
HL*2*1*21*1~
NM1*1P*2*PROVIDER GROUP*****XX*1234567890~
HL*3*2*22*0~
NM1*IL*1*SMITH*JOHN****MI*MEM123456~
TRN*2*PA123456*9012345678~
AAA*Y*72*~
HCR*A1*AUTH123456~
REF*BB*AUTH123456~
DTP*472*RD8*20240201-20240208~
SE*14*0001~
```

## FHIR-based Prior Authorization

### CRD (Coverage Requirements Discovery)

**Request Hook: order-sign**
```json
{
  "hookInstance": "abc123",
  "hook": "order-sign",
  "context": {
    "patientId": "Patient/123",
    "encounterId": "Encounter/456",
    "draftOrders": {
      "resourceType": "Bundle",
      "entry": [{
        "resource": {
          "resourceType": "ServiceRequest",
          "status": "draft",
          "intent": "order",
          "code": {
            "coding": [{
              "system": "http://www.ama-assn.org/go/cpt",
              "code": "27447",
              "display": "Total knee arthroplasty"
            }]
          },
          "subject": { "reference": "Patient/123" }
        }
      }]
    }
  },
  "prefetch": {
    "patient": { "resourceType": "Patient", "id": "123" },
    "coverage": { "resourceType": "Coverage", "id": "cov123" }
  }
}
```

**Response with PA Requirement**
```json
{
  "cards": [{
    "uuid": "card-1",
    "summary": "Prior authorization required for Total Knee Arthroplasty",
    "indicator": "warning",
    "source": {
      "label": "Payer Coverage Policy"
    },
    "suggestions": [{
      "label": "Launch Prior Auth Request",
      "actions": [{
        "type": "create",
        "description": "Create prior authorization request",
        "resource": {
          "resourceType": "Task",
          "status": "requested",
          "intent": "order",
          "code": {
            "coding": [{
              "system": "http://hl7.org/fhir/us/davinci-crd/CodeSystem/task-type",
              "code": "pa-request"
            }]
          }
        }
      }]
    }],
    "links": [{
      "label": "SMART App: Prior Auth Request",
      "url": "https://pa-app.azurewebsites.net/launch",
      "type": "smart"
    }]
  }]
}
```

### DTR (Documentation Templates and Rules)

**Questionnaire for PA Documentation**
```json
{
  "resourceType": "Questionnaire",
  "id": "knee-replacement-pa",
  "status": "active",
  "title": "Total Knee Arthroplasty Prior Authorization",
  "item": [
    {
      "linkId": "1",
      "text": "Patient Information",
      "type": "group",
      "item": [
        {
          "linkId": "1.1",
          "text": "Has the patient tried conservative treatment?",
          "type": "boolean",
          "required": true
        },
        {
          "linkId": "1.2",
          "text": "Duration of conservative treatment",
          "type": "choice",
          "answerOption": [
            { "valueString": "Less than 3 months" },
            { "valueString": "3-6 months" },
            { "valueString": "More than 6 months" }
          ],
          "enableWhen": [{
            "question": "1.1",
            "operator": "=",
            "answerBoolean": true
          }]
        }
      ]
    },
    {
      "linkId": "2",
      "text": "Clinical Findings",
      "type": "group",
      "item": [
        {
          "linkId": "2.1",
          "text": "X-ray findings",
          "type": "choice",
          "required": true,
          "answerOption": [
            { "valueString": "Normal" },
            { "valueString": "Mild osteoarthritis" },
            { "valueString": "Moderate osteoarthritis" },
            { "valueString": "Severe osteoarthritis" }
          ]
        }
      ]
    }
  ]
}
```

### PAS (Prior Authorization Support)

**Claim for Prior Auth**
```json
{
  "resourceType": "Claim",
  "id": "pa-claim-001",
  "status": "active",
  "type": {
    "coding": [{
      "system": "http://terminology.hl7.org/CodeSystem/claim-type",
      "code": "institutional"
    }]
  },
  "use": "preauthorization",
  "patient": { "reference": "Patient/123" },
  "created": "2024-01-15",
  "insurer": { "reference": "Organization/payer-001" },
  "provider": { "reference": "Organization/provider-001" },
  "priority": { "coding": [{ "code": "normal" }] },
  "insurance": [{
    "sequence": 1,
    "focal": true,
    "coverage": { "reference": "Coverage/cov-001" }
  }],
  "diagnosis": [{
    "sequence": 1,
    "diagnosisCodeableConcept": {
      "coding": [{
        "system": "http://hl7.org/fhir/sid/icd-10-cm",
        "code": "M17.11",
        "display": "Primary osteoarthritis, right knee"
      }]
    }
  }],
  "procedure": [{
    "sequence": 1,
    "procedureCodeableConcept": {
      "coding": [{
        "system": "http://www.ama-assn.org/go/cpt",
        "code": "27447",
        "display": "Total knee arthroplasty"
      }]
    }
  }],
  "item": [{
    "sequence": 1,
    "productOrService": {
      "coding": [{
        "system": "http://www.ama-assn.org/go/cpt",
        "code": "27447"
      }]
    },
    "servicedDate": "2024-02-01",
    "locationCodeableConcept": {
      "coding": [{
        "system": "https://www.cms.gov/Medicare/Coding/place-of-service-codes",
        "code": "21",
        "display": "Inpatient Hospital"
      }]
    }
  }],
  "supportingInfo": [{
    "sequence": 1,
    "category": {
      "coding": [{
        "system": "http://hl7.org/fhir/us/davinci-pas/CodeSystem/PASSupportingInfoType",
        "code": "questionnaire-response"
      }]
    },
    "valueReference": {
      "reference": "QuestionnaireResponse/qr-001"
    }
  }]
}
```

**ClaimResponse (Authorization)**
```json
{
  "resourceType": "ClaimResponse",
  "id": "pa-response-001",
  "status": "active",
  "type": {
    "coding": [{
      "system": "http://terminology.hl7.org/CodeSystem/claim-type",
      "code": "institutional"
    }]
  },
  "use": "preauthorization",
  "patient": { "reference": "Patient/123" },
  "created": "2024-01-15T14:35:00Z",
  "insurer": { "reference": "Organization/payer-001" },
  "outcome": "complete",
  "preAuthRef": "AUTH123456",
  "preAuthPeriod": {
    "start": "2024-02-01",
    "end": "2024-02-28"
  },
  "item": [{
    "itemSequence": 1,
    "adjudication": [{
      "category": {
        "coding": [{
          "code": "submitted"
        }]
      }
    }]
  }]
}
```

## Azure Implementation

### Logic App Workflow
```json
{
  "definition": {
    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "triggers": {
      "When_PA_Request_Received": {
        "type": "Request",
        "kind": "Http",
        "inputs": {
          "schema": {
            "type": "object",
            "properties": {
              "patientId": { "type": "string" },
              "procedureCode": { "type": "string" },
              "diagnosisCode": { "type": "string" }
            }
          }
        }
      }
    },
    "actions": {
      "Check_Coverage_Policy": {
        "type": "Http",
        "inputs": {
          "method": "GET",
          "uri": "https://coverage-api.azurewebsites.net/api/policy",
          "queries": {
            "procedureCode": "@triggerBody()?['procedureCode']",
            "payerId": "@triggerBody()?['payerId']"
          }
        }
      },
      "Determine_PA_Required": {
        "type": "If",
        "expression": {
          "equals": ["@body('Check_Coverage_Policy')?['paRequired']", true]
        },
        "actions": {
          "Submit_To_Payer": {
            "type": "Http",
            "inputs": {
              "method": "POST",
              "uri": "@body('Check_Coverage_Policy')?['submissionEndpoint']",
              "body": "@triggerBody()"
            }
          }
        }
      }
    }
  }
}
```

### Coverage Policy Database (Cosmos DB)
```json
{
  "id": "policy-001",
  "payerId": "PAYER123",
  "procedureCode": "27447",
  "procedureDescription": "Total Knee Arthroplasty",
  "paRequired": true,
  "criteria": [
    {
      "type": "diagnosis",
      "codes": ["M17.0", "M17.1", "M17.10", "M17.11", "M17.12"],
      "required": true
    },
    {
      "type": "conservative_treatment",
      "minDuration": "3 months",
      "required": true
    },
    {
      "type": "imaging",
      "modality": "X-ray",
      "required": true
    }
  ],
  "turnaroundTime": {
    "urgent": "24 hours",
    "standard": "5 business days"
  },
  "validityPeriod": "30 days",
  "documentation": [
    "History and physical",
    "Conservative treatment records",
    "Imaging reports"
  ]
}
```

## Status Codes

| Code | Description |
|------|-------------|
| A1 | Certified in total |
| A2 | Certified with changes |
| A3 | Pended |
| A4 | Cancelled |
| A6 | Denied |
| CT | Contact payer |

## Best Practices

1. **Real-time eligibility check** before PA submission
2. **Cache coverage policies** to reduce API calls
3. **Implement retry logic** for payer API failures
4. **Track PA status** with Event Grid notifications
5. **Use DTR** to gather required documentation upfront
6. **Store audit trail** for compliance
