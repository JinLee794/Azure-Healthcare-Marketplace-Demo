"""
ICD-10 Validation MCP Server - Azure Function App
Provides ICD-10-CM diagnosis code validation and lookup capabilities.
"""
import os
import json
import logging
import re
import azure.functions as func
import httpx
from typing import Optional

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

logger = logging.getLogger(__name__)

MCP_PROTOCOL_VERSION = os.environ.get("MCP_PROTOCOL_VERSION", "2025-06-18")

# CMS ICD-10 API (using clinical tables API as fallback)
ICD10_API_URL = "https://clinicaltables.nlm.nih.gov/api/icd10cm/v3/search"

SERVER_INFO = {
    "name": "icd10-validation",
    "version": "1.0.0",
    "description": "Healthcare MCP server for ICD-10-CM diagnosis code validation and lookup"
}

TOOLS = [
    {
        "name": "validate_icd10",
        "description": "Validate an ICD-10-CM diagnosis code. Checks format and verifies the code exists in the official code set.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "The ICD-10-CM code to validate (e.g., 'E11.9', 'J18.9')"
                }
            },
            "required": ["code"]
        }
    },
    {
        "name": "lookup_icd10",
        "description": "Look up an ICD-10-CM code and return its description, category, and related codes.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "The ICD-10-CM code to look up"
                }
            },
            "required": ["code"]
        }
    },
    {
        "name": "search_icd10",
        "description": "Search for ICD-10-CM codes by description or keyword. Returns matching codes with descriptions.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search term (e.g., 'diabetes', 'pneumonia', 'fracture femur')"
                },
                "limit": {
                    "type": "integer",
                    "description": "Maximum number of results (1-50, default 10)",
                    "minimum": 1,
                    "maximum": 50,
                    "default": 10
                }
            },
            "required": ["query"]
        }
    },
    {
        "name": "get_icd10_chapter",
        "description": "Get information about an ICD-10-CM chapter or category based on a code prefix.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "code_prefix": {
                    "type": "string",
                    "description": "ICD-10 code prefix (e.g., 'E11' for Type 2 diabetes, 'J' for respiratory)"
                }
            },
            "required": ["code_prefix"]
        }
    }
]

# ICD-10 Chapter definitions
ICD10_CHAPTERS = {
    "A": ("A00-B99", "Certain infectious and parasitic diseases"),
    "B": ("A00-B99", "Certain infectious and parasitic diseases"),
    "C": ("C00-D49", "Neoplasms"),
    "D": ("D50-D89", "Diseases of the blood and blood-forming organs"),
    "E": ("E00-E89", "Endocrine, nutritional and metabolic diseases"),
    "F": ("F01-F99", "Mental, behavioral and neurodevelopmental disorders"),
    "G": ("G00-G99", "Diseases of the nervous system"),
    "H": ("H00-H59", "Diseases of the eye and adnexa / ear and mastoid process"),
    "I": ("I00-I99", "Diseases of the circulatory system"),
    "J": ("J00-J99", "Diseases of the respiratory system"),
    "K": ("K00-K95", "Diseases of the digestive system"),
    "L": ("L00-L99", "Diseases of the skin and subcutaneous tissue"),
    "M": ("M00-M99", "Diseases of the musculoskeletal system and connective tissue"),
    "N": ("N00-N99", "Diseases of the genitourinary system"),
    "O": ("O00-O9A", "Pregnancy, childbirth and the puerperium"),
    "P": ("P00-P96", "Certain conditions originating in the perinatal period"),
    "Q": ("Q00-Q99", "Congenital malformations, deformations and chromosomal abnormalities"),
    "R": ("R00-R99", "Symptoms, signs and abnormal clinical and laboratory findings"),
    "S": ("S00-T88", "Injury, poisoning and certain other consequences of external causes"),
    "T": ("S00-T88", "Injury, poisoning and certain other consequences of external causes"),
    "V": ("V00-Y99", "External causes of morbidity"),
    "W": ("V00-Y99", "External causes of morbidity"),
    "X": ("V00-Y99", "External causes of morbidity"),
    "Y": ("V00-Y99", "External causes of morbidity"),
    "Z": ("Z00-Z99", "Factors influencing health status and contact with health services"),
}


def _validate_icd10_format(code: str) -> tuple[bool, str]:
    """Validate ICD-10-CM code format."""
    # Remove any dots for validation
    clean_code = code.upper().replace(".", "")
    
    # ICD-10-CM format: Letter + 2-6 alphanumeric characters
    pattern = r'^[A-Z][0-9][0-9A-Z]{0,5}$'
    
    if not re.match(pattern, clean_code):
        return False, "Invalid format. ICD-10-CM codes start with a letter followed by 2-6 alphanumeric characters"
    
    # Check if first letter is valid
    if clean_code[0] not in ICD10_CHAPTERS and clean_code[0] != 'U':
        return False, f"Invalid category letter: {clean_code[0]}"
    
    return True, "Format valid"


async def validate_icd10(code: str) -> dict:
    """Validate an ICD-10-CM code."""
    # Check format first
    format_valid, format_msg = _validate_icd10_format(code)
    if not format_valid:
        return {
            "valid": False,
            "code": code,
            "reason": format_msg
        }
    
    # Look up in API
    clean_code = code.upper().replace(".", "")
    async with httpx.AsyncClient() as client:
        response = await client.get(
            ICD10_API_URL,
            params={"terms": clean_code, "maxList": 1, "sf": "code"}
        )
        response.raise_for_status()
        data = response.json()
        
        # API returns [count, [codes], null, [descriptions]]
        if data[0] > 0 and clean_code in [c.replace(".", "") for c in data[1]]:
            idx = [c.replace(".", "") for c in data[1]].index(clean_code)
            return {
                "valid": True,
                "code": data[1][idx],  # Return with proper formatting
                "description": data[3][idx][0] if data[3] and data[3][idx] else "Description not available"
            }
        
        return {
            "valid": False,
            "code": code,
            "reason": "Code not found in ICD-10-CM code set"
        }


async def lookup_icd10(code: str) -> dict:
    """Look up an ICD-10-CM code."""
    clean_code = code.upper().replace(".", "")
    
    async with httpx.AsyncClient() as client:
        response = await client.get(
            ICD10_API_URL,
            params={"terms": clean_code, "maxList": 10, "sf": "code"}
        )
        response.raise_for_status()
        data = response.json()
        
        if data[0] == 0:
            return {
                "found": False,
                "code": code,
                "message": "Code not found"
            }
        
        # Find exact match
        codes = data[1]
        descriptions = data[3]
        
        for i, c in enumerate(codes):
            if c.replace(".", "") == clean_code:
                first_letter = clean_code[0]
                chapter_info = ICD10_CHAPTERS.get(first_letter, ("Unknown", "Unknown"))
                
                return {
                    "found": True,
                    "code": c,
                    "description": descriptions[i][0] if descriptions[i] else "N/A",
                    "chapter": {
                        "range": chapter_info[0],
                        "name": chapter_info[1]
                    },
                    "category": clean_code[:3],
                    "is_billable": len(clean_code) >= 4  # Generally codes with 4+ chars are billable
                }
        
        return {
            "found": False,
            "code": code,
            "message": "Exact code not found",
            "similar_codes": [{"code": codes[i], "description": descriptions[i][0]} for i in range(min(5, len(codes)))]
        }


async def search_icd10(query: str, limit: int = 10) -> dict:
    """Search for ICD-10-CM codes by description."""
    async with httpx.AsyncClient() as client:
        response = await client.get(
            ICD10_API_URL,
            params={"terms": query, "maxList": limit}
        )
        response.raise_for_status()
        data = response.json()
        
        if data[0] == 0:
            return {
                "query": query,
                "result_count": 0,
                "results": []
            }
        
        results = []
        for i in range(min(data[0], limit)):
            results.append({
                "code": data[1][i],
                "description": data[3][i][0] if data[3] and i < len(data[3]) else "N/A"
            })
        
        return {
            "query": query,
            "result_count": len(results),
            "results": results
        }


async def get_icd10_chapter(code_prefix: str) -> dict:
    """Get chapter information for a code prefix."""
    prefix = code_prefix.upper().replace(".", "")
    
    if not prefix:
        return {"error": "Code prefix required"}
    
    first_letter = prefix[0]
    if first_letter not in ICD10_CHAPTERS:
        return {
            "prefix": code_prefix,
            "found": False,
            "message": f"Unknown chapter for prefix: {code_prefix}"
        }
    
    chapter_info = ICD10_CHAPTERS[first_letter]
    
    # Get some example codes
    async with httpx.AsyncClient() as client:
        response = await client.get(
            ICD10_API_URL,
            params={"terms": prefix, "maxList": 10, "sf": "code"}
        )
        response.raise_for_status()
        data = response.json()
        
        examples = []
        if data[0] > 0:
            for i in range(min(5, data[0])):
                examples.append({
                    "code": data[1][i],
                    "description": data[3][i][0] if data[3] and i < len(data[3]) else "N/A"
                })
    
    return {
        "prefix": code_prefix,
        "found": True,
        "chapter": {
            "range": chapter_info[0],
            "name": chapter_info[1]
        },
        "example_codes": examples
    }


# ============================================================================
# Azure Function Endpoints
# ============================================================================

@app.route(route=".well-known/mcp", methods=["GET"])
async def mcp_discovery(req: func.HttpRequest) -> func.HttpResponse:
    """MCP Discovery endpoint."""
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
    """MCP Message endpoint."""
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
            
            if tool_name == "validate_icd10":
                tool_result = await validate_icd10(args.get("code", ""))
            elif tool_name == "lookup_icd10":
                tool_result = await lookup_icd10(args.get("code", ""))
            elif tool_name == "search_icd10":
                tool_result = await search_icd10(args.get("query", ""), args.get("limit", 10))
            elif tool_name == "get_icd10_chapter":
                tool_result = await get_icd10_chapter(args.get("code_prefix", ""))
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
    """Health check endpoint."""
    return func.HttpResponse(
        json.dumps({"status": "healthy", "server": SERVER_INFO["name"], "version": SERVER_INFO["version"]}),
        mimetype="application/json"
    )
