#!/usr/bin/env python3
"""
Azure FHIR API Project Scaffold
Creates a working FHIR API project structure with correct Pydantic v2 patterns
and Azure authentication integration.
"""

import argparse
import sys
from pathlib import Path


def create_project(project_dir: Path):
    """Create FHIR API project structure with correct Pydantic v2 patterns."""

    # Create directories
    (project_dir / "app" / "models").mkdir(parents=True, exist_ok=True)
    (project_dir / "app" / "routes").mkdir(parents=True, exist_ok=True)
    (project_dir / "app" / "services").mkdir(parents=True, exist_ok=True)
    (project_dir / "tests").mkdir(parents=True, exist_ok=True)

    # requirements.txt
    (project_dir / "requirements.txt").write_text(
        """fastapi>=0.100.0
uvicorn>=0.23.0
pydantic>=2.0.0
httpx>=0.24.0
pytest>=7.0.0
azure-identity>=1.14.0
python-dotenv>=1.0.0
"""
    )

    # .env.example
    (project_dir / ".env.example").write_text(
        """# Azure FHIR Configuration
FHIR_SERVER_URL=https://{workspace}-{service}.fhir.azurehealthcareapis.com
AZURE_TENANT_ID=your-tenant-id
AZURE_CLIENT_ID=your-client-id
AZURE_CLIENT_SECRET=your-client-secret

# For Managed Identity (leave client_secret empty)
# AZURE_CLIENT_SECRET=
"""
    )

    # app/__init__.py
    (project_dir / "app" / "__init__.py").touch()
    (project_dir / "app" / "models" / "__init__.py").touch()
    (project_dir / "app" / "routes" / "__init__.py").touch()
    (project_dir / "app" / "services" / "__init__.py").touch()

    # Core FHIR types with Pydantic v2 syntax
    (project_dir / "app" / "models" / "fhir_types.py").write_text('''"""FHIR R4 Base Types - Pydantic v2"""
from typing import Literal, Optional, List
from pydantic import BaseModel, Field
from datetime import datetime, date
import uuid


class Meta(BaseModel):
    """FHIR Resource Metadata"""
    versionId: str = "1"
    lastUpdated: str = Field(default_factory=lambda: datetime.utcnow().isoformat() + "Z")


class HumanName(BaseModel):
    """FHIR HumanName datatype"""
    use: Optional[str] = None
    family: Optional[str] = None
    given: Optional[List[str]] = None
    prefix: Optional[List[str]] = None
    suffix: Optional[List[str]] = None


class Coding(BaseModel):
    """FHIR Coding datatype"""
    system: Optional[str] = None
    version: Optional[str] = None
    code: Optional[str] = None
    display: Optional[str] = None
    userSelected: Optional[bool] = None


class CodeableConcept(BaseModel):
    """FHIR CodeableConcept datatype"""
    coding: Optional[List[Coding]] = None
    text: Optional[str] = None


class Reference(BaseModel):
    """FHIR Reference datatype"""
    reference: Optional[str] = None
    type: Optional[str] = None
    display: Optional[str] = None


class Identifier(BaseModel):
    """FHIR Identifier datatype"""
    use: Optional[str] = None
    type: Optional[CodeableConcept] = None
    system: Optional[str] = None
    value: Optional[str] = None


class Quantity(BaseModel):
    """FHIR Quantity datatype"""
    value: Optional[float] = None
    comparator: Optional[str] = None
    unit: Optional[str] = None
    system: Optional[str] = Field(default="http://unitsofmeasure.org")
    code: Optional[str] = None


class Period(BaseModel):
    """FHIR Period datatype"""
    start: Optional[str] = None
    end: Optional[str] = None


class Address(BaseModel):
    """FHIR Address datatype"""
    use: Optional[str] = None
    type: Optional[str] = None
    text: Optional[str] = None
    line: Optional[List[str]] = None
    city: Optional[str] = None
    district: Optional[str] = None
    state: Optional[str] = None
    postalCode: Optional[str] = None
    country: Optional[str] = None


class ContactPoint(BaseModel):
    """FHIR ContactPoint datatype"""
    system: Optional[str] = None  # phone | fax | email | pager | url | sms | other
    value: Optional[str] = None
    use: Optional[str] = None  # home | work | temp | old | mobile
    rank: Optional[int] = None
    period: Optional[Period] = None
''')

    # Patient resource
    (project_dir / "app" / "models" / "patient.py").write_text('''"""FHIR R4 Patient Resource - Pydantic v2"""
from typing import Optional, List, Literal
from pydantic import BaseModel, Field
from datetime import date
from .fhir_types import Meta, HumanName, Identifier, Address, ContactPoint, CodeableConcept, Reference, Period


class PatientContact(BaseModel):
    """Patient contact (next of kin, emergency contact)"""
    relationship: Optional[List[CodeableConcept]] = None
    name: Optional[HumanName] = None
    telecom: Optional[List[ContactPoint]] = None
    address: Optional[Address] = None
    gender: Optional[str] = None
    organization: Optional[Reference] = None
    period: Optional[Period] = None


class PatientCommunication(BaseModel):
    """Patient language communication preferences"""
    language: CodeableConcept
    preferred: Optional[bool] = None


class PatientLink(BaseModel):
    """Link to another Patient resource"""
    other: Reference
    type: Literal["replaced-by", "replaces", "refer", "seealso"]


class Patient(BaseModel):
    """
    FHIR R4 Patient Resource
    
    Demographics and administrative information about an individual receiving care.
    """
    resourceType: Literal["Patient"] = Field(default="Patient", frozen=True)
    id: Optional[str] = None
    meta: Optional[Meta] = None
    identifier: Optional[List[Identifier]] = None
    active: Optional[bool] = True
    name: Optional[List[HumanName]] = None
    telecom: Optional[List[ContactPoint]] = None
    gender: Optional[Literal["male", "female", "other", "unknown"]] = None
    birthDate: Optional[date] = None
    deceasedBoolean: Optional[bool] = None
    deceasedDateTime: Optional[str] = None
    address: Optional[List[Address]] = None
    maritalStatus: Optional[CodeableConcept] = None
    multipleBirthBoolean: Optional[bool] = None
    multipleBirthInteger: Optional[int] = None
    photo: Optional[List[dict]] = None
    contact: Optional[List[PatientContact]] = None
    communication: Optional[List[PatientCommunication]] = None
    generalPractitioner: Optional[List[Reference]] = None
    managingOrganization: Optional[Reference] = None
    link: Optional[List[PatientLink]] = None
    
    model_config = {
        "populate_by_name": True,
        "json_schema_extra": {
            "example": {
                "resourceType": "Patient",
                "id": "example-patient",
                "identifier": [
                    {
                        "system": "http://example.org/mrn",
                        "value": "12345"
                    }
                ],
                "active": True,
                "name": [
                    {
                        "use": "official",
                        "family": "Smith",
                        "given": ["John", "Jacob"]
                    }
                ],
                "gender": "male",
                "birthDate": "1970-01-01"
            }
        }
    }
''')

    # Observation resource
    (project_dir / "app" / "models" / "observation.py").write_text('''"""FHIR R4 Observation Resource - Pydantic v2"""
from typing import Optional, List, Literal, Union
from pydantic import BaseModel, Field
from .fhir_types import Meta, Identifier, CodeableConcept, Reference, Quantity, Period


class ObservationReferenceRange(BaseModel):
    """Reference range for observation values"""
    low: Optional[Quantity] = None
    high: Optional[Quantity] = None
    type: Optional[CodeableConcept] = None
    appliesTo: Optional[List[CodeableConcept]] = None
    age: Optional[dict] = None
    text: Optional[str] = None


class ObservationComponent(BaseModel):
    """Component results within an observation"""
    code: CodeableConcept
    valueQuantity: Optional[Quantity] = None
    valueCodeableConcept: Optional[CodeableConcept] = None
    valueString: Optional[str] = None
    valueBoolean: Optional[bool] = None
    valueInteger: Optional[int] = None
    valueRange: Optional[dict] = None
    valueRatio: Optional[dict] = None
    valueSampledData: Optional[dict] = None
    valueTime: Optional[str] = None
    valueDateTime: Optional[str] = None
    valuePeriod: Optional[Period] = None
    dataAbsentReason: Optional[CodeableConcept] = None
    interpretation: Optional[List[CodeableConcept]] = None
    referenceRange: Optional[List[ObservationReferenceRange]] = None


class Observation(BaseModel):
    """
    FHIR R4 Observation Resource
    
    Measurements and simple assertions made about a patient.
    Used for vital signs, laboratory results, imaging results, clinical findings.
    """
    resourceType: Literal["Observation"] = Field(default="Observation", frozen=True)
    id: Optional[str] = None
    meta: Optional[Meta] = None
    identifier: Optional[List[Identifier]] = None
    basedOn: Optional[List[Reference]] = None
    partOf: Optional[List[Reference]] = None
    status: Literal["registered", "preliminary", "final", "amended", "corrected", "cancelled", "entered-in-error", "unknown"]
    category: Optional[List[CodeableConcept]] = None
    code: CodeableConcept  # Required - what was observed
    subject: Optional[Reference] = None  # Who/what this is about
    focus: Optional[List[Reference]] = None
    encounter: Optional[Reference] = None
    effectiveDateTime: Optional[str] = None
    effectivePeriod: Optional[Period] = None
    effectiveTiming: Optional[dict] = None
    effectiveInstant: Optional[str] = None
    issued: Optional[str] = None
    performer: Optional[List[Reference]] = None
    valueQuantity: Optional[Quantity] = None
    valueCodeableConcept: Optional[CodeableConcept] = None
    valueString: Optional[str] = None
    valueBoolean: Optional[bool] = None
    valueInteger: Optional[int] = None
    valueRange: Optional[dict] = None
    valueRatio: Optional[dict] = None
    valueSampledData: Optional[dict] = None
    valueTime: Optional[str] = None
    valueDateTime: Optional[str] = None
    valuePeriod: Optional[Period] = None
    dataAbsentReason: Optional[CodeableConcept] = None
    interpretation: Optional[List[CodeableConcept]] = None
    note: Optional[List[dict]] = None
    bodySite: Optional[CodeableConcept] = None
    method: Optional[CodeableConcept] = None
    specimen: Optional[Reference] = None
    device: Optional[Reference] = None
    referenceRange: Optional[List[ObservationReferenceRange]] = None
    hasMember: Optional[List[Reference]] = None
    derivedFrom: Optional[List[Reference]] = None
    component: Optional[List[ObservationComponent]] = None
    
    model_config = {
        "populate_by_name": True,
        "json_schema_extra": {
            "example": {
                "resourceType": "Observation",
                "id": "example-obs",
                "status": "final",
                "category": [
                    {
                        "coding": [
                            {
                                "system": "http://terminology.hl7.org/CodeSystem/observation-category",
                                "code": "vital-signs",
                                "display": "Vital Signs"
                            }
                        ]
                    }
                ],
                "code": {
                    "coding": [
                        {
                            "system": "http://loinc.org",
                            "code": "8867-4",
                            "display": "Heart rate"
                        }
                    ]
                },
                "subject": {
                    "reference": "Patient/example-patient"
                },
                "effectiveDateTime": "2024-01-15T10:00:00Z",
                "valueQuantity": {
                    "value": 72,
                    "unit": "beats/minute",
                    "system": "http://unitsofmeasure.org",
                    "code": "/min"
                }
            }
        }
    }
''')

    # Azure FHIR Client Service
    (project_dir / "app" / "services" / "fhir_client.py").write_text('''"""Azure FHIR Client Service"""
import os
import httpx
from azure.identity import DefaultAzureCredential, ClientSecretCredential
from typing import Optional, Any
from dotenv import load_dotenv

load_dotenv()


class AzureFHIRClient:
    """Client for Azure API for FHIR"""
    
    def __init__(self, fhir_url: Optional[str] = None):
        self.fhir_url = fhir_url or os.getenv("FHIR_SERVER_URL")
        if not self.fhir_url:
            raise ValueError("FHIR_SERVER_URL must be set")
        
        # Remove trailing slash
        self.fhir_url = self.fhir_url.rstrip("/")
        
        # Setup credential
        client_secret = os.getenv("AZURE_CLIENT_SECRET")
        if client_secret:
            # Use service principal
            self.credential = ClientSecretCredential(
                tenant_id=os.getenv("AZURE_TENANT_ID"),
                client_id=os.getenv("AZURE_CLIENT_ID"),
                client_secret=client_secret
            )
        else:
            # Use managed identity / CLI / environment
            self.credential = DefaultAzureCredential()
        
        self._token = None
    
    async def _get_token(self) -> str:
        """Get access token for FHIR server"""
        token = self.credential.get_token(f"{self.fhir_url}/.default")
        return token.token
    
    async def _request(
        self,
        method: str,
        path: str,
        **kwargs
    ) -> httpx.Response:
        """Make authenticated request to FHIR server"""
        token = await self._get_token()
        
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/fhir+json",
            "Accept": "application/fhir+json",
            **kwargs.pop("headers", {})
        }
        
        async with httpx.AsyncClient() as client:
            url = f"{self.fhir_url}/{path.lstrip('/')}"
            response = await client.request(
                method,
                url,
                headers=headers,
                **kwargs
            )
            return response
    
    async def read(self, resource_type: str, resource_id: str) -> dict:
        """Read a FHIR resource by ID"""
        response = await self._request("GET", f"{resource_type}/{resource_id}")
        response.raise_for_status()
        return response.json()
    
    async def search(
        self,
        resource_type: str,
        params: Optional[dict] = None
    ) -> dict:
        """Search for FHIR resources"""
        response = await self._request(
            "GET",
            resource_type,
            params=params or {}
        )
        response.raise_for_status()
        return response.json()
    
    async def create(self, resource: dict) -> dict:
        """Create a new FHIR resource"""
        resource_type = resource.get("resourceType")
        if not resource_type:
            raise ValueError("Resource must have resourceType")
        
        response = await self._request(
            "POST",
            resource_type,
            json=resource
        )
        response.raise_for_status()
        return response.json()
    
    async def update(self, resource: dict) -> dict:
        """Update an existing FHIR resource"""
        resource_type = resource.get("resourceType")
        resource_id = resource.get("id")
        if not resource_type or not resource_id:
            raise ValueError("Resource must have resourceType and id")
        
        response = await self._request(
            "PUT",
            f"{resource_type}/{resource_id}",
            json=resource
        )
        response.raise_for_status()
        return response.json()
    
    async def delete(self, resource_type: str, resource_id: str) -> None:
        """Delete a FHIR resource"""
        response = await self._request(
            "DELETE",
            f"{resource_type}/{resource_id}"
        )
        response.raise_for_status()
    
    async def validate(
        self,
        resource: dict,
        profile: Optional[str] = None
    ) -> dict:
        """Validate a FHIR resource"""
        resource_type = resource.get("resourceType")
        
        params = {}
        if profile:
            params["profile"] = profile
        
        response = await self._request(
            "POST",
            f"{resource_type}/$validate",
            json=resource,
            params=params
        )
        return response.json()
''')

    # Main FastAPI app
    (project_dir / "app" / "main.py").write_text('''"""Azure FHIR API - Main Application"""
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional, List
import os

from .models.patient import Patient
from .models.observation import Observation
from .services.fhir_client import AzureFHIRClient


app = FastAPI(
    title="Azure FHIR API",
    description="FHIR R4 API built on Azure Health Data Services",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_fhir_client() -> AzureFHIRClient:
    """Dependency to get FHIR client"""
    return AzureFHIRClient()


@app.get("/")
async def root():
    """API root"""
    return {
        "name": "Azure FHIR API",
        "fhir_version": "R4",
        "supported_resources": ["Patient", "Observation"]
    }


@app.get("/Patient/{patient_id}")
async def get_patient(
    patient_id: str,
    client: AzureFHIRClient = Depends(get_fhir_client)
) -> dict:
    """Get a patient by ID"""
    try:
        return await client.read("Patient", patient_id)
    except Exception as e:
        raise HTTPException(status_code=404, detail=str(e))


@app.get("/Patient")
async def search_patients(
    name: Optional[str] = None,
    identifier: Optional[str] = None,
    birthdate: Optional[str] = None,
    client: AzureFHIRClient = Depends(get_fhir_client)
) -> dict:
    """Search for patients"""
    params = {}
    if name:
        params["name"] = name
    if identifier:
        params["identifier"] = identifier
    if birthdate:
        params["birthdate"] = birthdate
    
    return await client.search("Patient", params)


@app.post("/Patient")
async def create_patient(
    patient: Patient,
    client: AzureFHIRClient = Depends(get_fhir_client)
) -> dict:
    """Create a new patient"""
    return await client.create(patient.model_dump(exclude_none=True))


@app.post("/Patient/$validate")
async def validate_patient(
    patient: Patient,
    profile: Optional[str] = None,
    client: AzureFHIRClient = Depends(get_fhir_client)
) -> dict:
    """Validate a patient resource"""
    return await client.validate(
        patient.model_dump(exclude_none=True),
        profile=profile
    )


@app.get("/Observation/{observation_id}")
async def get_observation(
    observation_id: str,
    client: AzureFHIRClient = Depends(get_fhir_client)
) -> dict:
    """Get an observation by ID"""
    try:
        return await client.read("Observation", observation_id)
    except Exception as e:
        raise HTTPException(status_code=404, detail=str(e))


@app.get("/Observation")
async def search_observations(
    patient: Optional[str] = None,
    code: Optional[str] = None,
    category: Optional[str] = None,
    date: Optional[str] = None,
    client: AzureFHIRClient = Depends(get_fhir_client)
) -> dict:
    """Search for observations"""
    params = {}
    if patient:
        params["patient"] = patient
    if code:
        params["code"] = code
    if category:
        params["category"] = category
    if date:
        params["date"] = date
    
    return await client.search("Observation", params)


@app.post("/Observation")
async def create_observation(
    observation: Observation,
    client: AzureFHIRClient = Depends(get_fhir_client)
) -> dict:
    """Create a new observation"""
    return await client.create(observation.model_dump(exclude_none=True))


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy"}
''')

    # Basic test
    (project_dir / "tests" / "test_models.py").write_text('''"""Test FHIR Models"""
import pytest
from app.models.patient import Patient
from app.models.observation import Observation
from app.models.fhir_types import HumanName, CodeableConcept, Coding, Quantity, Reference


def test_patient_creation():
    """Test creating a Patient resource"""
    patient = Patient(
        id="test-123",
        active=True,
        name=[HumanName(family="Smith", given=["John"])],
        gender="male",
        birthDate="1970-01-01"
    )
    
    assert patient.resourceType == "Patient"
    assert patient.id == "test-123"
    assert patient.name[0].family == "Smith"


def test_observation_creation():
    """Test creating an Observation resource"""
    obs = Observation(
        id="obs-123",
        status="final",
        code=CodeableConcept(
            coding=[Coding(
                system="http://loinc.org",
                code="8867-4",
                display="Heart rate"
            )]
        ),
        subject=Reference(reference="Patient/test-123"),
        valueQuantity=Quantity(
            value=72,
            unit="beats/minute",
            code="/min"
        )
    )
    
    assert obs.resourceType == "Observation"
    assert obs.status == "final"
    assert obs.valueQuantity.value == 72


def test_patient_json_export():
    """Test exporting Patient to JSON"""
    patient = Patient(
        id="test-456",
        name=[HumanName(family="Doe", given=["Jane"])],
        gender="female"
    )
    
    data = patient.model_dump(exclude_none=True)
    
    assert data["resourceType"] == "Patient"
    assert data["id"] == "test-456"
    assert "name" in data


def test_observation_required_fields():
    """Test Observation requires status and code"""
    # Should work with required fields
    obs = Observation(
        status="final",
        code=CodeableConcept(text="Test")
    )
    assert obs.status == "final"
    
    # Should fail without status
    with pytest.raises(Exception):
        Observation(code=CodeableConcept(text="Test"))
''')

    # README
    (project_dir / "README.md").write_text('''# Azure FHIR API Project

FHIR R4 API built on Azure Health Data Services.

## Setup

1. Create virtual environment:
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\\Scripts\\activate
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Configure environment:
```bash
cp .env.example .env
# Edit .env with your Azure FHIR server details
```

4. Run the API:
```bash
uvicorn app.main:app --reload
```

5. Open API docs:
```
http://localhost:8000/docs
```

## Azure Configuration

### Create Azure API for FHIR

```bash
# Create resource group
az group create --name rg-fhir --location eastus

# Create workspace
az healthcareapis workspace create \\
  --name myworkspace \\
  --resource-group rg-fhir

# Create FHIR service
az healthcareapis workspace fhir-service create \\
  --name myfhir \\
  --workspace-name myworkspace \\
  --resource-group rg-fhir \\
  --kind fhir-R4
```

### Authentication

For local development, use Azure CLI:
```bash
az login
```

For production, use Managed Identity:
```bash
# Assign FHIR Data Contributor role
az role assignment create \\
  --assignee <managed-identity-object-id> \\
  --role "FHIR Data Contributor" \\
  --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.HealthcareApis/workspaces/<ws>/fhirservices/<fhir>
```

## Testing

```bash
pytest tests/
```

## Project Structure

```
.
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI application
│   ├── models/
│   │   ├── fhir_types.py    # FHIR datatypes
│   │   ├── patient.py       # Patient resource
│   │   └── observation.py   # Observation resource
│   ├── routes/              # API routes
│   └── services/
│       └── fhir_client.py   # Azure FHIR client
├── tests/
│   └── test_models.py
├── requirements.txt
├── .env.example
└── README.md
```
''')

    print(f"Created Azure FHIR API project: {project_dir}")
    print(f"\nNext steps:")
    print(f"  cd {project_dir}")
    print(f"  python -m venv venv && source venv/bin/activate")
    print(f"  pip install -r requirements.txt")
    print(f"  cp .env.example .env  # Configure Azure FHIR settings")
    print(f"  uvicorn app.main:app --reload")
    print(f"\nOpen http://localhost:8000/docs for API docs")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Create Azure FHIR API project scaffold")
    parser.add_argument("project_name", nargs="?", default="fhir_api", help="Project directory name")
    args = parser.parse_args()
    create_project(Path(args.project_name))
