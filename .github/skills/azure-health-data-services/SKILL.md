---
name: azure-health-data-services
description: "Azure Health Data Services for DICOM imaging, MedTech device data, and FHIR integration. Use when working with medical imaging, IoT health devices, or unified health data."
triggers:
  - "DICOM"
  - "medical imaging"
  - "MedTech"
  - "IoT health"
  - "health data services"
---

# Azure Health Data Services Skill

## Overview
Azure Health Data Services provides a unified platform for managing healthcare data including FHIR, DICOM (medical imaging), and MedTech (device data) services.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                Azure Health Data Services Workspace              │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ FHIR Service│  │DICOM Service│  │MedTech Svc  │             │
│  │             │  │             │  │             │             │
│  │ • Patient   │  │ • Studies   │  │ • Device    │             │
│  │ • Records   │  │ • Series    │  │ • Telemetry │             │
│  │ • Claims    │  │ • Instances │  │ • Events    │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│         │                │                │                     │
│         └────────────────┼────────────────┘                     │
│                          ▼                                      │
│              ┌─────────────────────┐                           │
│              │   Event Grid        │                           │
│              │   (Change Events)   │                           │
│              └─────────────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

## DICOM Service

### Deploying DICOM Service
```bash
az healthcareapis workspace dicom-service create \
  --resource-group <rg-name> \
  --workspace-name <workspace-name> \
  --dicom-service-name <dicom-service-name>
```

### DICOM Endpoints
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/studies` | POST | Store studies (STOW-RS) |
| `/studies/{studyId}` | GET | Retrieve study (WADO-RS) |
| `/studies?{query}` | GET | Search studies (QIDO-RS) |
| `/changefeed` | GET | Get changes |

### Store DICOM Instance (STOW-RS)
```http
POST /v1/studies
Content-Type: multipart/related; type="application/dicom"
Authorization: Bearer {token}

--boundary
Content-Type: application/dicom

{DICOM binary data}
--boundary--
```

### Retrieve Study (WADO-RS)
```http
GET /v1/studies/{studyInstanceUID}
Accept: multipart/related; type="application/dicom"
Authorization: Bearer {token}
```

### Search Studies (QIDO-RS)
```http
GET /v1/studies?PatientName=Smith&StudyDate=20240101
Accept: application/dicom+json
Authorization: Bearer {token}
```

### Response Format
```json
[{
  "00080020": { "vr": "DA", "Value": ["20240115"] },
  "00080030": { "vr": "TM", "Value": ["143022"] },
  "00080050": { "vr": "SH", "Value": ["ACC123"] },
  "00080061": { "vr": "CS", "Value": ["CT", "MR"] },
  "00100010": { "vr": "PN", "Value": [{ "Alphabetic": "Smith^John" }] },
  "0020000D": { "vr": "UI", "Value": ["1.2.3.4.5.6.7.8.9"] }
}]
```

## MedTech Service

### Overview
MedTech service ingests device telemetry and converts it to FHIR Observations.

### Device Message Format
```json
{
  "deviceId": "device-001",
  "measurementTime": "2024-01-15T14:30:00Z",
  "data": {
    "heartRate": 72,
    "bloodPressure": {
      "systolic": 120,
      "diastolic": 80
    },
    "oxygenSaturation": 98
  }
}
```

### Device Mapping Template
```json
{
  "templateType": "CollectionContent",
  "template": [{
    "templateType": "JsonPathContent",
    "template": {
      "typeName": "heartRate",
      "typeMatchExpression": "$..[?(@heartRate)]",
      "deviceIdExpression": "$.deviceId",
      "timestampExpression": "$.measurementTime",
      "values": [{
        "required": true,
        "valueExpression": "$.data.heartRate",
        "valueName": "heartRate"
      }]
    }
  }]
}
```

### FHIR Destination Mapping
```json
{
  "templateType": "CollectionFhir",
  "template": [{
    "templateType": "CodeValueFhir",
    "template": {
      "typeName": "heartRate",
      "value": {
        "valueName": "heartRate",
        "valueType": "Quantity",
        "unit": "beats/min",
        "system": "http://unitsofmeasure.org",
        "code": "/min"
      },
      "codes": [{
        "system": "http://loinc.org",
        "code": "8867-4",
        "display": "Heart rate"
      }],
      "category": [{
        "system": "http://terminology.hl7.org/CodeSystem/observation-category",
        "code": "vital-signs",
        "display": "Vital Signs"
      }]
    }
  }]
}
```

### Event Hub Integration
```bash
# Create Event Hub namespace for device data
az eventhubs namespace create \
  --resource-group <rg-name> \
  --name <namespace-name> \
  --sku Standard

# Create Event Hub
az eventhubs eventhub create \
  --resource-group <rg-name> \
  --namespace-name <namespace-name> \
  --name device-data \
  --partition-count 4
```

## Integration Patterns

### DICOM to FHIR Linking
```json
{
  "resourceType": "ImagingStudy",
  "id": "example",
  "status": "available",
  "subject": {
    "reference": "Patient/example"
  },
  "endpoint": [{
    "reference": "Endpoint/dicom-endpoint"
  }],
  "series": [{
    "uid": "1.2.3.4.5.6.7.8.9.1",
    "modality": {
      "system": "http://dicom.nema.org/resources/ontology/DCM",
      "code": "CT"
    },
    "numberOfInstances": 120,
    "instance": [{
      "uid": "1.2.3.4.5.6.7.8.9.1.1",
      "sopClass": {
        "system": "urn:ietf:rfc:3986",
        "code": "urn:oid:1.2.840.10008.5.1.4.1.1.2"
      }
    }]
  }]
}
```

### Event Grid Subscriptions
```json
{
  "properties": {
    "topic": "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.HealthcareApis/workspaces/{ws}",
    "eventTypes": [
      "Microsoft.HealthcareApis.FhirResourceCreated",
      "Microsoft.HealthcareApis.FhirResourceUpdated",
      "Microsoft.HealthcareApis.DicomImageCreated"
    ],
    "destination": {
      "endpointType": "WebHook",
      "properties": {
        "endpointUrl": "https://your-function.azurewebsites.net/api/handler"
      }
    }
  }
}
```

## Security

### Private Link Configuration
```bash
# Create private endpoint for DICOM service
az network private-endpoint create \
  --resource-group <rg-name> \
  --name dicom-private-endpoint \
  --vnet-name <vnet-name> \
  --subnet <subnet-name> \
  --private-connection-resource-id <dicom-service-resource-id> \
  --group-id dicom \
  --connection-name dicom-connection
```

### RBAC Roles
| Role | Description |
|------|-------------|
| DICOM Data Owner | Full access to DICOM data |
| DICOM Data Reader | Read access to DICOM data |
| FHIR Data Contributor | Read/write FHIR data |
| FHIR SMART User | SMART on FHIR app access |

## Best Practices

1. **Use workspaces** to group related FHIR, DICOM, and MedTech services
2. **Enable diagnostic logging** for all services
3. **Configure private endpoints** for HIPAA compliance
4. **Use managed identities** for service-to-service auth
5. **Implement change feed processing** for real-time integrations
