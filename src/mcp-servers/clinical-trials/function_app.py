"""
Clinical Trials MCP Server - Azure Function App
Provides ClinicalTrials.gov search and data access capabilities.
"""
import os
import json
import logging
import azure.functions as func
import httpx
from typing import Optional

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

logger = logging.getLogger(__name__)

MCP_PROTOCOL_VERSION = os.environ.get("MCP_PROTOCOL_VERSION", "2025-06-18")

# ClinicalTrials.gov API v2
CT_API_BASE = "https://clinicaltrials.gov/api/v2"

SERVER_INFO = {
    "name": "clinical-trials",
    "version": "1.0.0",
    "description": "Healthcare MCP server for ClinicalTrials.gov data access"
}

TOOLS = [
    {
        "name": "search_trials",
        "description": "Search for clinical trials by condition, intervention, location, or keywords.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search query (condition, drug, device, or keywords)"
                },
                "condition": {
                    "type": "string",
                    "description": "Filter by condition/disease (e.g., 'diabetes', 'breast cancer')"
                },
                "intervention": {
                    "type": "string",
                    "description": "Filter by intervention (drug, device, procedure name)"
                },
                "status": {
                    "type": "array",
                    "items": {
                        "type": "string",
                        "enum": ["RECRUITING", "NOT_YET_RECRUITING", "ACTIVE_NOT_RECRUITING", "COMPLETED", "ENROLLING_BY_INVITATION", "SUSPENDED", "TERMINATED", "WITHDRAWN"]
                    },
                    "description": "Filter by recruitment status"
                },
                "phase": {
                    "type": "array",
                    "items": {
                        "type": "string",
                        "enum": ["EARLY_PHASE1", "PHASE1", "PHASE2", "PHASE3", "PHASE4", "NA"]
                    },
                    "description": "Filter by trial phase"
                },
                "location_country": {
                    "type": "string",
                    "description": "Filter by country (e.g., 'United States')"
                },
                "location_state": {
                    "type": "string",
                    "description": "Filter by US state (e.g., 'California')"
                },
                "location_city": {
                    "type": "string",
                    "description": "Filter by city"
                },
                "page_size": {
                    "type": "integer",
                    "description": "Number of results (1-100, default 20)",
                    "minimum": 1,
                    "maximum": 100,
                    "default": 20
                }
            }
        }
    },
    {
        "name": "get_trial",
        "description": "Get detailed information about a specific clinical trial by NCT ID.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "nct_id": {
                    "type": "string",
                    "description": "NCT identifier (e.g., 'NCT04280705')"
                }
            },
            "required": ["nct_id"]
        }
    },
    {
        "name": "get_trial_eligibility",
        "description": "Get eligibility criteria for a clinical trial.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "nct_id": {"type": "string", "description": "NCT identifier"}
            },
            "required": ["nct_id"]
        }
    },
    {
        "name": "get_trial_locations",
        "description": "Get recruiting locations for a clinical trial.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "nct_id": {"type": "string", "description": "NCT identifier"}
            },
            "required": ["nct_id"]
        }
    },
    {
        "name": "search_by_condition",
        "description": "Find recruiting clinical trials for a specific condition near a location.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "condition": {"type": "string", "description": "Disease or condition"},
                "location": {"type": "string", "description": "City, state, or country"},
                "distance_miles": {"type": "integer", "description": "Search radius in miles", "default": 50}
            },
            "required": ["condition"]
        }
    },
    {
        "name": "get_trial_results",
        "description": "Get results summary for a completed clinical trial (if available).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "nct_id": {"type": "string", "description": "NCT identifier"}
            },
            "required": ["nct_id"]
        }
    }
]


async def search_trials(
    query: str = None,
    condition: str = None,
    intervention: str = None,
    status: list[str] = None,
    phase: list[str] = None,
    location_country: str = None,
    location_state: str = None,
    location_city: str = None,
    page_size: int = 20
) -> dict:
    """Search for clinical trials."""
    
    params = {
        "format": "json",
        "pageSize": min(page_size, 100)
    }
    
    # Build query string
    query_parts = []
    if query:
        query_parts.append(query)
    if condition:
        params["query.cond"] = condition
    if intervention:
        params["query.intr"] = intervention
    
    if query_parts:
        params["query.term"] = " ".join(query_parts)
    
    # Filters
    if status:
        params["filter.overallStatus"] = ",".join(status)
    if phase:
        params["filter.phase"] = ",".join(phase)
    
    # Location filters
    if location_country:
        params["query.locn"] = location_country
    if location_state:
        params["query.locn"] = f"{location_state}, {location_country or 'United States'}"
    if location_city:
        loc_parts = [location_city]
        if location_state:
            loc_parts.append(location_state)
        if location_country:
            loc_parts.append(location_country)
        params["query.locn"] = ", ".join(loc_parts)
    
    # Request fields
    params["fields"] = "NCTId,BriefTitle,OverallStatus,Phase,Condition,InterventionName,LocationCity,LocationState,LocationCountry,StartDate,CompletionDate,EnrollmentCount,StudyType,LeadSponsorName"
    
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{CT_API_BASE}/studies", params=params)
        response.raise_for_status()
        data = response.json()
        
        studies = data.get("studies", [])
        
        return {
            "total_count": data.get("totalCount", 0),
            "returned_count": len(studies),
            "trials": [_format_trial_summary(s) for s in studies]
        }


async def get_trial(nct_id: str) -> dict:
    """Get detailed trial information."""
    nct_id = nct_id.upper().strip()
    
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{CT_API_BASE}/studies/{nct_id}")
        
        if response.status_code == 404:
            return {"found": False, "nct_id": nct_id}
        
        response.raise_for_status()
        data = response.json()
        
        return {
            "found": True,
            "trial": _format_trial_detail(data)
        }


async def get_trial_eligibility(nct_id: str) -> dict:
    """Get trial eligibility criteria."""
    result = await get_trial(nct_id)
    
    if not result.get("found"):
        return result
    
    trial = result["trial"]
    
    return {
        "nct_id": nct_id,
        "title": trial.get("title"),
        "eligibility": trial.get("eligibility", {}),
        "healthy_volunteers": trial.get("healthy_volunteers")
    }


async def get_trial_locations(nct_id: str) -> dict:
    """Get trial locations."""
    nct_id = nct_id.upper().strip()
    
    params = {
        "fields": "NCTId,BriefTitle,LocationFacility,LocationCity,LocationState,LocationCountry,LocationStatus,LocationContactName,LocationContactPhone,LocationContactEMail"
    }
    
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{CT_API_BASE}/studies/{nct_id}", params=params)
        
        if response.status_code == 404:
            return {"found": False, "nct_id": nct_id}
        
        response.raise_for_status()
        data = response.json()
        
        protocol = data.get("protocolSection", {})
        contacts_locations = protocol.get("contactsLocationsModule", {})
        locations = contacts_locations.get("locations", [])
        
        return {
            "nct_id": nct_id,
            "title": protocol.get("identificationModule", {}).get("briefTitle"),
            "location_count": len(locations),
            "locations": [_format_location(loc) for loc in locations]
        }


async def search_by_condition(condition: str, location: str = None, distance_miles: int = 50) -> dict:
    """Search for recruiting trials by condition."""
    params = {
        "query.cond": condition,
        "filter.overallStatus": "RECRUITING,NOT_YET_RECRUITING,ENROLLING_BY_INVITATION",
        "pageSize": 25,
        "fields": "NCTId,BriefTitle,Phase,Condition,InterventionName,LocationFacility,LocationCity,LocationState,LocationCountry,EnrollmentCount"
    }
    
    if location:
        params["query.locn"] = location
        params["filter.geo"] = f"distance({distance_miles}mi)"
    
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{CT_API_BASE}/studies", params=params)
        response.raise_for_status()
        data = response.json()
        
        return {
            "condition": condition,
            "location": location,
            "total_recruiting": data.get("totalCount", 0),
            "trials": [_format_trial_summary(s) for s in data.get("studies", [])]
        }


async def get_trial_results(nct_id: str) -> dict:
    """Get trial results if available."""
    nct_id = nct_id.upper().strip()
    
    params = {
        "fields": "NCTId,BriefTitle,OverallStatus,ResultsFirstPostDate,PrimaryOutcomeMeasure,PrimaryOutcomeDescription,OutcomeMeasureTitle,OutcomeMeasureType"
    }
    
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{CT_API_BASE}/studies/{nct_id}", params=params)
        
        if response.status_code == 404:
            return {"found": False, "nct_id": nct_id}
        
        response.raise_for_status()
        data = response.json()
        
        protocol = data.get("protocolSection", {})
        results = data.get("resultsSection", {})
        
        has_results = bool(results)
        
        return {
            "nct_id": nct_id,
            "title": protocol.get("identificationModule", {}).get("briefTitle"),
            "status": protocol.get("statusModule", {}).get("overallStatus"),
            "has_results": has_results,
            "results_posted_date": protocol.get("statusModule", {}).get("resultsFirstPostDateStruct", {}).get("date") if has_results else None,
            "primary_outcomes": _extract_outcomes(protocol, results) if has_results else "Results not yet posted"
        }


def _format_trial_summary(study: dict) -> dict:
    """Format a trial summary from search results."""
    protocol = study.get("protocolSection", {})
    id_module = protocol.get("identificationModule", {})
    status_module = protocol.get("statusModule", {})
    design = protocol.get("designModule", {})
    conditions = protocol.get("conditionsModule", {})
    interventions = protocol.get("armsInterventionsModule", {})
    contacts = protocol.get("contactsLocationsModule", {})
    sponsor = protocol.get("sponsorCollaboratorsModule", {})
    
    locations = contacts.get("locations", [])
    location_summary = []
    for loc in locations[:3]:
        city = loc.get("city", "")
        state = loc.get("state", "")
        country = loc.get("country", "")
        location_summary.append(f"{city}, {state}, {country}".strip(", "))
    
    return {
        "nct_id": id_module.get("nctId"),
        "title": id_module.get("briefTitle"),
        "status": status_module.get("overallStatus"),
        "phase": design.get("phases", ["N/A"]),
        "study_type": design.get("studyType"),
        "conditions": conditions.get("conditions", [])[:5],
        "interventions": [i.get("name") for i in interventions.get("interventions", [])][:5],
        "enrollment": design.get("enrollmentInfo", {}).get("count"),
        "sponsor": sponsor.get("leadSponsor", {}).get("name"),
        "locations_preview": location_summary if location_summary else ["See trial for locations"]
    }


def _format_trial_detail(data: dict) -> dict:
    """Format detailed trial information."""
    protocol = data.get("protocolSection", {})
    
    id_module = protocol.get("identificationModule", {})
    status_module = protocol.get("statusModule", {})
    desc_module = protocol.get("descriptionModule", {})
    design = protocol.get("designModule", {})
    eligibility = protocol.get("eligibilityModule", {})
    outcomes = protocol.get("outcomesModule", {})
    sponsor = protocol.get("sponsorCollaboratorsModule", {})
    contacts = protocol.get("contactsLocationsModule", {})
    conditions = protocol.get("conditionsModule", {})
    interventions = protocol.get("armsInterventionsModule", {})
    
    return {
        "nct_id": id_module.get("nctId"),
        "title": id_module.get("briefTitle"),
        "official_title": id_module.get("officialTitle"),
        "status": status_module.get("overallStatus"),
        "start_date": status_module.get("startDateStruct", {}).get("date"),
        "completion_date": status_module.get("completionDateStruct", {}).get("date"),
        "description": desc_module.get("briefSummary"),
        "detailed_description": desc_module.get("detailedDescription"),
        "study_type": design.get("studyType"),
        "phase": design.get("phases", []),
        "enrollment": design.get("enrollmentInfo", {}).get("count"),
        "conditions": conditions.get("conditions", []),
        "interventions": [
            {
                "type": i.get("type"),
                "name": i.get("name"),
                "description": i.get("description")
            }
            for i in interventions.get("interventions", [])
        ],
        "eligibility": {
            "criteria": eligibility.get("eligibilityCriteria"),
            "gender": eligibility.get("sex"),
            "min_age": eligibility.get("minimumAge"),
            "max_age": eligibility.get("maximumAge"),
            "healthy_volunteers": eligibility.get("healthyVolunteers")
        },
        "primary_outcomes": [
            {
                "measure": o.get("measure"),
                "time_frame": o.get("timeFrame"),
                "description": o.get("description")
            }
            for o in outcomes.get("primaryOutcomes", [])
        ],
        "sponsor": sponsor.get("leadSponsor", {}).get("name"),
        "collaborators": [c.get("name") for c in sponsor.get("collaborators", [])],
        "central_contacts": [
            {
                "name": c.get("name"),
                "role": c.get("role"),
                "phone": c.get("phone"),
                "email": c.get("email")
            }
            for c in contacts.get("centralContacts", [])
        ]
    }


def _format_location(loc: dict) -> dict:
    """Format a trial location."""
    return {
        "facility": loc.get("facility"),
        "city": loc.get("city"),
        "state": loc.get("state"),
        "country": loc.get("country"),
        "status": loc.get("status"),
        "contact": {
            "name": loc.get("contacts", [{}])[0].get("name") if loc.get("contacts") else None,
            "phone": loc.get("contacts", [{}])[0].get("phone") if loc.get("contacts") else None,
            "email": loc.get("contacts", [{}])[0].get("email") if loc.get("contacts") else None
        }
    }


def _extract_outcomes(protocol: dict, results: dict) -> list:
    """Extract primary outcome measures."""
    outcomes_module = results.get("outcomeMeasuresModule", {})
    outcome_measures = outcomes_module.get("outcomeMeasures", [])
    
    primary = [o for o in outcome_measures if o.get("type") == "PRIMARY"]
    
    return [
        {
            "title": o.get("title"),
            "description": o.get("description"),
            "time_frame": o.get("timeFrame")
        }
        for o in primary[:5]
    ]


# ============================================================================
# Azure Function Endpoints
# ============================================================================

@app.route(route=".well-known/mcp", methods=["GET"])
async def mcp_discovery(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps({
            **SERVER_INFO,
            "protocol_version": MCP_PROTOCOL_VERSION,
            "capabilities": {"tools": True, "resources": False, "prompts": False},
            "tools": TOOLS
        }),
        mimetype="application/json",
        headers={"X-MCP-Protocol-Version": MCP_PROTOCOL_VERSION}
    )


@app.route(route="mcp", methods=["POST"])
async def mcp_message(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}),
            status_code=400, mimetype="application/json"
        )
    
    method = body.get("method")
    params = body.get("params", {})
    msg_id = body.get("id")
    
    try:
        if method == "initialize":
            result = {
                "protocolVersion": MCP_PROTOCOL_VERSION,
                "serverInfo": {"name": SERVER_INFO["name"], "version": SERVER_INFO["version"]},
                "capabilities": {"tools": {"listChanged": False}}
            }
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call":
            tool_name = params.get("name")
            args = params.get("arguments", {})
            
            if tool_name == "search_trials":
                tool_result = await search_trials(
                    query=args.get("query"),
                    condition=args.get("condition"),
                    intervention=args.get("intervention"),
                    status=args.get("status"),
                    phase=args.get("phase"),
                    location_country=args.get("location_country"),
                    location_state=args.get("location_state"),
                    location_city=args.get("location_city"),
                    page_size=args.get("page_size", 20)
                )
            elif tool_name == "get_trial":
                tool_result = await get_trial(args.get("nct_id", ""))
            elif tool_name == "get_trial_eligibility":
                tool_result = await get_trial_eligibility(args.get("nct_id", ""))
            elif tool_name == "get_trial_locations":
                tool_result = await get_trial_locations(args.get("nct_id", ""))
            elif tool_name == "search_by_condition":
                tool_result = await search_by_condition(args.get("condition", ""), args.get("location"), args.get("distance_miles", 50))
            elif tool_name == "get_trial_results":
                tool_result = await get_trial_results(args.get("nct_id", ""))
            else:
                return func.HttpResponse(
                    json.dumps({"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32602, "message": f"Unknown tool: {tool_name}"}}),
                    mimetype="application/json"
                )
            
            result = {"content": [{"type": "text", "text": json.dumps(tool_result)}]}
        elif method == "ping":
            result = {}
        else:
            return func.HttpResponse(
                json.dumps({"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32601, "message": f"Method not found: {method}"}}),
                mimetype="application/json"
            )
        
        return func.HttpResponse(
            json.dumps({"jsonrpc": "2.0", "id": msg_id, "result": result}),
            mimetype="application/json",
            headers={"X-MCP-Protocol-Version": MCP_PROTOCOL_VERSION}
        )
    except Exception as e:
        logger.exception("Error handling MCP message")
        return func.HttpResponse(
            json.dumps({"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32603, "message": str(e)}}),
            status_code=500, mimetype="application/json"
        )


@app.route(route="health", methods=["GET"])
async def health_check(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(
        json.dumps({"status": "healthy", "server": SERVER_INFO["name"], "version": SERVER_INFO["version"]}),
        mimetype="application/json"
    )
