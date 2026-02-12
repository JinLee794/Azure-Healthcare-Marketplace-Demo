"""
NPI Lookup MCP Server - Azure Function App
Provides National Provider Identifier lookup capabilities via the NPI Registry API.

Supports MCP Protocol 2025-06-18 with Streamable HTTP transport for APIM integration.
"""

import json
import logging
import os
import uuid
from dataclasses import dataclass

import azure.functions as func
import httpx

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

logger = logging.getLogger(__name__)

# MCP Protocol version 2025-06-18 required for Azure APIM MCP Server feature
MCP_PROTOCOL_VERSION = os.environ.get("MCP_PROTOCOL_VERSION", "2025-06-18")
NPI_REGISTRY_URL = "https://npiregistry.cms.hhs.gov/api/"


@dataclass
class NPILookupServer:
    """MCP Server for NPI Registry lookups."""

    name: str = "npi-lookup"
    version: str = "1.0.0"
    description: str = "Healthcare MCP server for National Provider Identifier (NPI) lookups"

    def get_tools(self) -> list[dict]:
        return [
            {
                "name": "lookup_npi",
                "description": "Look up a healthcare provider by their NPI number. Returns provider details including name, specialty, address, and credentials.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "npi": {
                            "type": "string",
                            "description": "The 10-digit National Provider Identifier number",
                            "pattern": "^[0-9]{10}$",
                        }
                    },
                    "required": ["npi"],
                },
            },
            {
                "name": "search_providers",
                "description": "Search for healthcare providers by name, specialty, or location. Returns a list of matching providers with their NPI numbers.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "first_name": {
                            "type": "string",
                            "description": "Provider's first name (for individual providers)",
                        },
                        "last_name": {
                            "type": "string",
                            "description": "Provider's last name (for individual providers)",
                        },
                        "organization_name": {
                            "type": "string",
                            "description": "Organization name (for organizational providers)",
                        },
                        "taxonomy_description": {
                            "type": "string",
                            "description": "Provider specialty/taxonomy (e.g., 'Family Medicine', 'Cardiology')",
                        },
                        "city": {"type": "string", "description": "City where provider practices"},
                        "state": {
                            "type": "string",
                            "description": "Two-letter state code (e.g., 'CA', 'NY')",
                            "pattern": "^[A-Z]{2}$",
                        },
                        "postal_code": {"type": "string", "description": "5-digit ZIP code"},
                        "limit": {
                            "type": "integer",
                            "description": "Maximum number of results (1-200, default 10)",
                            "minimum": 1,
                            "maximum": 200,
                            "default": 10,
                        },
                    },
                },
            },
            {
                "name": "validate_npi",
                "description": "Validate that an NPI number is correctly formatted and exists in the NPI Registry.",
                "inputSchema": {
                    "type": "object",
                    "properties": {"npi": {"type": "string", "description": "The NPI number to validate"}},
                    "required": ["npi"],
                },
            },
        ]

    def get_discovery_response(self) -> dict:
        return {
            "name": self.name,
            "version": self.version,
            "description": self.description,
            "protocol_version": MCP_PROTOCOL_VERSION,
            "capabilities": {"tools": True, "resources": False, "prompts": False},
            "tools": self.get_tools(),
        }


server = NPILookupServer()


async def lookup_npi(npi: str) -> dict:
    """Look up provider by NPI number."""
    async with httpx.AsyncClient() as client:
        response = await client.get(NPI_REGISTRY_URL, params={"number": npi, "version": "2.1"})
        response.raise_for_status()
        data = response.json()

        if data.get("result_count", 0) == 0:
            return {"found": False, "npi": npi, "message": "NPI not found in registry"}

        result = data["results"][0]
        return {
            "found": True,
            "npi": npi,
            "provider_type": "Individual" if result.get("enumeration_type") == "NPI-1" else "Organization",
            "basic": result.get("basic", {}),
            "addresses": result.get("addresses", []),
            "taxonomies": result.get("taxonomies", []),
            "identifiers": result.get("identifiers", []),
        }


async def search_providers(params: dict) -> dict:
    """Search for providers by various criteria."""
    query_params = {"version": "2.1"}

    param_mapping = {
        "first_name": "first_name",
        "last_name": "last_name",
        "organization_name": "organization_name",
        "taxonomy_description": "taxonomy_description",
        "city": "city",
        "state": "state",
        "postal_code": "postal_code",
        "limit": "limit",
    }

    for key, api_key in param_mapping.items():
        if params.get(key):
            query_params[api_key] = params[key]

    if "limit" not in query_params:
        query_params["limit"] = 10

    async with httpx.AsyncClient() as client:
        response = await client.get(NPI_REGISTRY_URL, params=query_params)
        response.raise_for_status()
        data = response.json()

        return {
            "result_count": data.get("result_count", 0),
            "providers": [
                {
                    "npi": r.get("number"),
                    "provider_type": "Individual" if r.get("enumeration_type") == "NPI-1" else "Organization",
                    "name": _format_provider_name(r),
                    "specialty": _get_primary_taxonomy(r),
                    "address": _format_primary_address(r),
                }
                for r in data.get("results", [])
            ],
        }


async def validate_npi(npi: str) -> dict:
    """Validate NPI number format and existence."""
    # Check format
    if not npi or len(npi) != 10 or not npi.isdigit():
        return {"valid": False, "npi": npi, "reason": "NPI must be exactly 10 digits"}

    # Luhn algorithm check (NPI uses Luhn with prefix 80840)
    if not _luhn_check(f"80840{npi}"):
        return {"valid": False, "npi": npi, "reason": "NPI fails checksum validation"}

    # Check registry
    result = await lookup_npi(npi)
    if not result.get("found"):
        return {"valid": False, "npi": npi, "reason": "NPI not found in CMS registry"}

    return {
        "valid": True,
        "npi": npi,
        "provider_name": _format_provider_name_from_basic(result.get("basic", {})),
        "provider_type": result.get("provider_type"),
    }


def _luhn_check(number: str) -> bool:
    """Validate number using Luhn algorithm."""
    digits = [int(d) for d in number]
    odd_digits = digits[-1::-2]
    even_digits = digits[-2::-2]
    checksum = sum(odd_digits)
    for d in even_digits:
        checksum += sum(divmod(d * 2, 10))
    return checksum % 10 == 0


def _format_provider_name(result: dict) -> str:
    """Format provider name from NPI result."""
    basic = result.get("basic", {})
    return _format_provider_name_from_basic(basic)


def _format_provider_name_from_basic(basic: dict) -> str:
    """Format provider name from basic info."""
    if basic.get("organization_name"):
        return basic["organization_name"]
    parts = []
    if basic.get("first_name"):
        parts.append(basic["first_name"])
    if basic.get("last_name"):
        parts.append(basic["last_name"])
    if basic.get("credential"):
        parts.append(f", {basic['credential']}")
    return " ".join(parts) if parts else "Unknown"


def _get_primary_taxonomy(result: dict) -> str:
    """Get primary taxonomy/specialty."""
    taxonomies = result.get("taxonomies", [])
    for t in taxonomies:
        if t.get("primary"):
            return t.get("desc", "Unknown")
    return taxonomies[0].get("desc", "Unknown") if taxonomies else "Unknown"


def _format_primary_address(result: dict) -> str:
    """Format primary practice address."""
    addresses = result.get("addresses", [])
    for addr in addresses:
        if addr.get("address_purpose") == "LOCATION":
            parts = [
                addr.get("address_1", ""),
                addr.get("city", ""),
                addr.get("state", ""),
                addr.get("postal_code", "")[:5] if addr.get("postal_code") else "",
            ]
            return ", ".join(p for p in parts if p)
    return "Address not available"


# ============================================================================
# Azure Function Endpoints
# ============================================================================


@app.route(route=".well-known/mcp", methods=["GET"])
async def mcp_discovery(req: func.HttpRequest) -> func.HttpResponse:
    """MCP Discovery endpoint - returns server capabilities and tools."""
    return func.HttpResponse(
        json.dumps(server.get_discovery_response()),
        mimetype="application/json",
        headers={"X-MCP-Protocol-Version": MCP_PROTOCOL_VERSION, "Cache-Control": "no-cache"},
    )


@app.route(route="mcp", methods=["GET"])
async def mcp_get(req: func.HttpRequest) -> func.HttpResponse:
    """MCP GET endpoint - used for SSE transport negotiation and capability discovery.

    Returns 405 Method Not Allowed directing clients to use POST for Streamable HTTP.
    """
    session_id = req.headers.get("Mcp-Session-Id", str(uuid.uuid4()))

    # For SSE requests, return 405 indicating POST is required
    accept = req.headers.get("Accept", "")
    if "text/event-stream" in accept:
        return func.HttpResponse(
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": -32600,
                        "message": "SSE transport not supported. Use POST for Streamable HTTP transport.",
                    },
                    "id": None,
                }
            ),
            status_code=405,
            mimetype="application/json",
            headers={"Allow": "POST", "X-MCP-Protocol-Version": MCP_PROTOCOL_VERSION, "Mcp-Session-Id": session_id},
        )

    # For other GET requests, return server info
    return func.HttpResponse(
        json.dumps(
            {
                "name": server.name,
                "version": server.version,
                "protocol_version": MCP_PROTOCOL_VERSION,
                "transport": "streamable-http",
                "endpoint": "/mcp",
                "methods_supported": ["POST"],
            }
        ),
        mimetype="application/json",
        headers={"X-MCP-Protocol-Version": MCP_PROTOCOL_VERSION, "Cache-Control": "no-cache"},
    )


@app.route(route="mcp", methods=["POST"])
async def mcp_message(req: func.HttpRequest) -> func.HttpResponse:
    """MCP Message endpoint - handles JSON-RPC messages via Streamable HTTP transport.

    Supports MCP 2025-06-18 for Azure APIM MCP Server integration.
    """
    # Get or generate session ID for APIM MCP tracking
    session_id = req.headers.get("Mcp-Session-Id", str(uuid.uuid4()))

    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            json.dumps({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}),
            status_code=400,
            mimetype="application/json",
        )

    method = body.get("method")
    params = body.get("params", {})
    msg_id = body.get("id")

    try:
        if method == "initialize":
            result = {
                "protocolVersion": MCP_PROTOCOL_VERSION,
                "serverInfo": {"name": server.name, "version": server.version},
                "capabilities": {"tools": {"listChanged": False}},
            }

        elif method == "tools/list":
            result = {"tools": server.get_tools()}

        elif method == "tools/call":
            tool_name = params.get("name")
            tool_args = params.get("arguments", {})

            if tool_name == "lookup_npi":
                tool_result = await lookup_npi(tool_args.get("npi", ""))
            elif tool_name == "search_providers":
                tool_result = await search_providers(tool_args)
            elif tool_name == "validate_npi":
                tool_result = await validate_npi(tool_args.get("npi", ""))
            else:
                return func.HttpResponse(
                    json.dumps(
                        {
                            "jsonrpc": "2.0",
                            "id": msg_id,
                            "error": {"code": -32602, "message": f"Unknown tool: {tool_name}"},
                        }
                    ),
                    mimetype="application/json",
                )

            result = {"content": [{"type": "text", "text": json.dumps(tool_result)}]}

        elif method == "ping":
            result = {}

        else:
            return func.HttpResponse(
                json.dumps(
                    {
                        "jsonrpc": "2.0",
                        "id": msg_id,
                        "error": {"code": -32601, "message": f"Method not found: {method}"},
                    }
                ),
                mimetype="application/json",
            )

        return func.HttpResponse(
            json.dumps({"jsonrpc": "2.0", "id": msg_id, "result": result}),
            mimetype="application/json",
            headers={
                "X-MCP-Protocol-Version": MCP_PROTOCOL_VERSION,
                "Mcp-Session-Id": session_id,
                "Cache-Control": "no-cache",
            },
        )

    except Exception as e:
        logger.exception("Error handling MCP message")
        return func.HttpResponse(
            json.dumps(
                {"jsonrpc": "2.0", "id": msg_id, "error": {"code": -32603, "message": f"Internal error: {e!s}"}}
            ),
            status_code=500,
            mimetype="application/json",
            headers={"Mcp-Session-Id": session_id},
        )


@app.route(route="health", methods=["GET"])
async def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint."""
    return func.HttpResponse(
        json.dumps({"status": "healthy", "server": server.name, "version": server.version}), mimetype="application/json"
    )
