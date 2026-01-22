#!/usr/bin/env python3
"""
Setup MCP Servers in Azure API Management

This script configures deployed Function App MCP servers as proper
MCP-compatible APIs in Azure API Management using the Azure SDK.

Prerequisites:
    - Azure CLI installed and logged in (az login)
    - Python 3.8+ with azure-mgmt-apimanagement, azure-identity
    - Infrastructure deployed via azd provision
    - Function Apps deployed via azd deploy

Usage:
    python setup_mcp_servers.py [--resource-group RG] [--apim-name NAME] [--function-base BASENAME]

Example:
    python setup_mcp_servers.py --resource-group rg-healthcare-mcp --apim-name healthcare-mcp-apim
"""

import argparse
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from typing import Optional

try:
    from azure.identity import DefaultAzureCredential
    from azure.mgmt.apimanagement import ApiManagementClient
    from azure.mgmt.apimanagement.models import (
        ApiContract,
        ApiCreateOrUpdateParameter,
        BackendContract,
        OperationContract,
        PolicyContract,
        ProductContract,
    )
except ImportError:
    print("Required packages not installed. Install with:")
    print("  pip install azure-identity azure-mgmt-apimanagement azure-mgmt-web")
    sys.exit(1)

# MCP Protocol version
MCP_PROTOCOL_VERSION = "2025-06-18"

# MCP Servers configuration
MCP_SERVERS = [
    {
        "name": "npi-lookup",
        "display_name": "NPI Lookup",
        "description": "National Provider Identifier lookup and validation",
    },
    {
        "name": "icd10-validation",
        "display_name": "ICD-10 Validation",
        "description": "ICD-10-CM diagnosis code validation and search",
    },
    {
        "name": "cms-coverage",
        "display_name": "CMS Coverage",
        "description": "CMS coverage policy lookup and determination",
    },
    {
        "name": "fhir-operations",
        "display_name": "FHIR Operations",
        "description": "FHIR R4 resource operations",
    },
    {
        "name": "pubmed",
        "display_name": "PubMed",
        "description": "PubMed medical literature search",
    },
    {
        "name": "clinical-trials",
        "display_name": "Clinical Trials",
        "description": "ClinicalTrials.gov data access",
    },
]

# MCP API Policy template
MCP_POLICY_TEMPLATE = """<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="{backend_id}" />
    <set-header name="X-MCP-Protocol-Version" exists-action="override">
      <value>{protocol_version}</value>
    </set-header>
    <set-header name="Cache-Control" exists-action="override">
      <value>no-cache</value>
    </set-header>
    <cors allow-credentials="false">
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>POST</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>*</header>
      </allowed-headers>
    </cors>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <set-header name="X-Content-Type-Options" exists-action="override">
      <value>nosniff</value>
    </set-header>
    <set-header name="Content-Type" exists-action="override">
      <value>application/json</value>
    </set-header>
  </outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="500" reason="Internal Server Error" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>{{"jsonrpc": "2.0", "error": {{"code": -32603, "message": "Internal error"}}, "id": null}}</set-body>
    </return-response>
  </on-error>
</policies>"""


class MCPServerSetup:
    """Configure MCP servers in Azure API Management."""

    def __init__(
        self,
        subscription_id: str,
        resource_group: str,
        apim_name: str,
        function_base_name: str,
    ):
        self.subscription_id = subscription_id
        self.resource_group = resource_group
        self.apim_name = apim_name
        self.function_base_name = function_base_name

        self.credential = DefaultAzureCredential()
        self.apim_client = ApiManagementClient(
            credential=self.credential,
            subscription_id=subscription_id,
        )
        self.gateway_url = None

    def get_gateway_url(self) -> str:
        """Get APIM gateway URL."""
        if self.gateway_url:
            return self.gateway_url

        apim = self.apim_client.api_management_service.get(
            self.resource_group, self.apim_name
        )
        self.gateway_url = apim.gateway_url
        return self.gateway_url

    def get_function_url(self, server_name: str) -> Optional[str]:
        """Get Function App URL for an MCP server."""
        func_app_name = f"{self.function_base_name}-{server_name}-func"

        try:
            result = subprocess.run(
                [
                    "az",
                    "functionapp",
                    "show",
                    "-g",
                    self.resource_group,
                    "-n",
                    func_app_name,
                    "--query",
                    "defaultHostName",
                    "-o",
                    "tsv",
                ],
                capture_output=True,
                text=True,
                check=True,
            )
            hostname = result.stdout.strip()
            if hostname:
                return f"https://{hostname}/api"
        except subprocess.CalledProcessError:
            print(f"  ⚠️  Function App not found: {func_app_name}")
            return None

        return None

    def create_backend(self, server: dict, backend_url: str) -> None:
        """Create or update APIM backend for MCP server."""
        backend_id = f"{server['name']}-backend"
        print(f"  Creating backend: {backend_id}")

        # Use begin_create_or_update for newer SDK versions, fallback to create_or_update
        backend_op = getattr(self.apim_client.backend, 'begin_create_or_update', None) or self.apim_client.backend.create_or_update
        result = backend_op(
            resource_group_name=self.resource_group,
            service_name=self.apim_name,
            backend_id=backend_id,
            parameters=BackendContract(
                url=backend_url,
                protocol="http",
                title=f"{server['display_name']} Backend",
                description=f"Backend for {server['description']}",
                tls={
                    "validate_certificate_chain": True,
                    "validate_certificate_name": True,
                },
            ),
        )
        # Wait for completion if it's a long-running operation
        if hasattr(result, 'result'):
            result.result()

    def create_api(self, server: dict, backend_url: str) -> None:
        """Create or update APIM API for MCP server."""
        api_id = f"{server['name']}-mcp"
        api_path = f"mcp/{server['name']}"
        print(f"  Creating API: {api_id}")

        # Use begin_create_or_update for newer SDK versions, fallback to create_or_update
        api_op = getattr(self.apim_client.api, 'begin_create_or_update', None) or self.apim_client.api.create_or_update
        result = api_op(
            resource_group_name=self.resource_group,
            service_name=self.apim_name,
            api_id=api_id,
            parameters=ApiCreateOrUpdateParameter(
                display_name=f"{server['display_name']} MCP Server",
                description=f"{server['description']} - MCP Protocol {MCP_PROTOCOL_VERSION}",
                path=api_path,
                protocols=["https"],
                service_url=backend_url,
                subscription_required=False,
                api_type="http",
            ),
        )
        # Wait for completion if it's a long-running operation
        if hasattr(result, 'result'):
            result.result()

    def create_operations(self, server: dict) -> None:
        """Create MCP operations for an API."""
        api_id = f"{server['name']}-mcp"
        print(f"  Creating operations for: {api_id}")

        # Get the correct method (begin_create_or_update or create_or_update)
        op_create = getattr(self.apim_client.api_operation, 'begin_create_or_update', None) or self.apim_client.api_operation.create_or_update

        # MCP Discovery endpoint
        try:
            result = op_create(
                resource_group_name=self.resource_group,
                service_name=self.apim_name,
                api_id=api_id,
                operation_id="mcp-discovery",
                parameters=OperationContract(
                    display_name="MCP Discovery",
                    method="GET",
                    url_template="/.well-known/mcp",
                    description="Returns MCP server capabilities and tools",
                ),
            )
            if hasattr(result, 'result'):
                result.result()
        except Exception as e:
            print(f"    Note: Discovery operation: {e}")

        # MCP Message endpoint (Streamable HTTP)
        try:
            result = op_create(
                resource_group_name=self.resource_group,
                service_name=self.apim_name,
                api_id=api_id,
                operation_id="mcp-message",
                parameters=OperationContract(
                    display_name="MCP Message",
                    method="POST",
                    url_template="/mcp",
                    description="Handle MCP JSON-RPC messages (Streamable HTTP transport)",
                ),
            )
            if hasattr(result, 'result'):
                result.result()
        except Exception as e:
            print(f"    Note: Message operation: {e}")

    def apply_policy(self, server: dict) -> None:
        """Apply MCP policy to an API."""
        api_id = f"{server['name']}-mcp"
        backend_id = f"{server['name']}-backend"
        print(f"  Applying policy for: {api_id}")

        policy_content = MCP_POLICY_TEMPLATE.format(
            backend_id=backend_id,
            protocol_version=MCP_PROTOCOL_VERSION,
        )

        # Use begin_create_or_update for newer SDK versions
        policy_op = getattr(self.apim_client.api_policy, 'begin_create_or_update', None) or self.apim_client.api_policy.create_or_update
        result = policy_op(
            resource_group_name=self.resource_group,
            service_name=self.apim_name,
            api_id=api_id,
            policy_id="policy",
            parameters=PolicyContract(
                value=policy_content,
                format="xml",
            ),
        )
        if hasattr(result, 'result'):
            result.result()

    def ensure_product(self) -> None:
        """Ensure healthcare-mcp product exists."""
        product_id = "healthcare-mcp"
        print(f"  Ensuring product: {product_id}")

        try:
            self.apim_client.product.get(
                self.resource_group, self.apim_name, product_id
            )
        except Exception:
            # Use begin_create_or_update for newer SDK versions
            product_op = getattr(self.apim_client.product, 'begin_create_or_update', None) or self.apim_client.product.create_or_update
            result = product_op(
                resource_group_name=self.resource_group,
                service_name=self.apim_name,
                product_id=product_id,
                parameters=ProductContract(
                    display_name="Healthcare MCP APIs",
                    description="Healthcare Model Context Protocol servers",
                    subscription_required=True,
                    approval_required=False,
                    state="published",
                ),
            )
            if hasattr(result, 'result'):
                result.result()

    def add_api_to_product(self, server: dict) -> None:
        """Add API to healthcare-mcp product."""
        api_id = f"{server['name']}-mcp"
        product_id = "healthcare-mcp"
        print(f"  Adding {api_id} to product: {product_id}")

        try:
            # Use begin_create_or_update for newer SDK versions
            product_api_op = getattr(self.apim_client.product_api, 'begin_create_or_update', None) or self.apim_client.product_api.create_or_update
            result = product_api_op(
                resource_group_name=self.resource_group,
                service_name=self.apim_name,
                product_id=product_id,
                api_id=api_id,
            )
            if hasattr(result, 'result'):
                result.result()
        except Exception as e:
            # API might already be in product
            pass

    def setup_server(self, server: dict) -> bool:
        """Setup a single MCP server."""
        print(f"\n{'=' * 50}")
        print(f"Setting up: {server['display_name']}")
        print(f"{'=' * 50}")

        backend_url = self.get_function_url(server["name"])
        if not backend_url:
            print(f"  ⚠️  Skipping - Function App not deployed")
            return False

        print(f"  Backend URL: {backend_url}")

        try:
            self.create_backend(server, backend_url)
            self.create_api(server, backend_url)
            self.create_operations(server)
            self.apply_policy(server)
            self.add_api_to_product(server)
            print(f"  ✅ {server['display_name']} configured successfully")
            return True
        except Exception as e:
            print(f"  ❌ Error configuring {server['display_name']}: {e}")
            return False

    def setup_all(self) -> None:
        """Setup all MCP servers."""
        print("\n" + "=" * 60)
        print("  Healthcare MCP Server Setup for Azure APIM")
        print("=" * 60)
        print(f"\nResource Group: {self.resource_group}")
        print(f"APIM Name: {self.apim_name}")
        print(f"Function Base: {self.function_base_name}")

        self.ensure_product()

        success_count = 0
        for server in MCP_SERVERS:
            if self.setup_server(server):
                success_count += 1

        # Print summary
        gateway_url = self.get_gateway_url()
        print("\n" + "=" * 60)
        print(f"  Setup Complete: {success_count}/{len(MCP_SERVERS)} servers")
        print("=" * 60)
        print(f"\nAPIM Gateway URL: {gateway_url}")
        print("\nMCP Server URLs:")
        for server in MCP_SERVERS:
            print(f"  - {server['display_name']}: {gateway_url}/mcp/{server['name']}/mcp")

        # Generate VS Code config
        self.generate_vscode_config(gateway_url)

    def generate_vscode_config(self, gateway_url: str) -> None:
        """Generate VS Code MCP configuration."""
        print("\n" + "-" * 60)
        print("VS Code MCP Configuration (.vscode/mcp.json)")
        print("-" * 60)

        config = {
            "servers": {},
            "inputs": [
                {
                    "id": "apimSubscriptionKey",
                    "type": "promptString",
                    "description": "APIM Subscription Key for Healthcare MCP APIs",
                    "password": True,
                }
            ],
        }

        for server in MCP_SERVERS:
            config["servers"][f"healthcare-{server['name']}"] = {
                "type": "http",
                "url": f"{gateway_url}/mcp/{server['name']}/mcp",
                "headers": {
                    "Ocp-Apim-Subscription-Key": "${input:apimSubscriptionKey}"
                },
            }

        print(json.dumps(config, indent=2))

        # Save to file
        vscode_dir = os.path.join(os.path.dirname(__file__), "..", ".vscode")
        os.makedirs(vscode_dir, exist_ok=True)
        config_path = os.path.join(vscode_dir, "mcp.json")

        with open(config_path, "w") as f:
            json.dump(config, f, indent=2)

        print(f"\n✅ Configuration saved to: {config_path}")


def get_subscription_id() -> str:
    """Get current Azure subscription ID."""
    result = subprocess.run(
        ["az", "account", "show", "--query", "id", "-o", "tsv"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def get_azd_env_value(key: str) -> Optional[str]:
    """Get value from azd environment."""
    try:
        result = subprocess.run(
            ["azd", "env", "get-values"],
            capture_output=True,
            text=True,
            check=True,
        )
        for line in result.stdout.split("\n"):
            if line.startswith(f"{key}="):
                return line.split("=", 1)[1].strip('"')
    except Exception:
        pass
    return None


def find_apim_name(resource_group: str) -> Optional[str]:
    """Find APIM instance in resource group."""
    try:
        result = subprocess.run(
            [
                "az",
                "apim",
                "list",
                "-g",
                resource_group,
                "--query",
                "[0].name",
                "-o",
                "tsv",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip() or None
    except Exception:
        return None


def find_function_base_name(resource_group: str) -> Optional[str]:
    """Find Function App base name from deployed apps."""
    try:
        result = subprocess.run(
            [
                "az",
                "functionapp",
                "list",
                "-g",
                resource_group,
                "--query",
                "[0].name",
                "-o",
                "tsv",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        func_name = result.stdout.strip()
        if func_name:
            # Extract base name (e.g., "hcmcp" from "hcmcp-npi-lookup-func")
            for suffix in [
                "-npi-lookup-func",
                "-icd10-validation-func",
                "-cms-coverage-func",
                "-fhir-operations-func",
                "-pubmed-func",
                "-clinical-trials-func",
            ]:
                if func_name.endswith(suffix):
                    return func_name[: -len(suffix)]
        return None
    except Exception:
        return None


def main():
    parser = argparse.ArgumentParser(
        description="Setup MCP Servers in Azure API Management"
    )
    parser.add_argument(
        "--resource-group", "-g", help="Azure resource group name"
    )
    parser.add_argument("--apim-name", "-n", help="API Management instance name")
    parser.add_argument(
        "--function-base", "-f", help="Function App base name (e.g., 'hcmcp')"
    )
    parser.add_argument(
        "--subscription", "-s", help="Azure subscription ID"
    )

    args = parser.parse_args()

    # Get subscription ID
    subscription_id = args.subscription or get_subscription_id()
    print(f"Using subscription: {subscription_id}")

    # Get resource group
    resource_group = (
        args.resource_group
        or get_azd_env_value("AZURE_RESOURCE_GROUP")
        or os.environ.get("AZURE_RESOURCE_GROUP")
    )
    if not resource_group:
        print("❌ Resource group not found. Use --resource-group or run in azd environment.")
        sys.exit(1)

    # Get APIM name
    apim_name = args.apim_name or find_apim_name(resource_group)
    if not apim_name:
        print(f"❌ API Management instance not found in: {resource_group}")
        sys.exit(1)

    # Get Function base name
    function_base = args.function_base or find_function_base_name(resource_group)
    if not function_base:
        print(f"❌ Could not determine Function App base name. Use --function-base.")
        sys.exit(1)

    # Run setup
    setup = MCPServerSetup(
        subscription_id=subscription_id,
        resource_group=resource_group,
        apim_name=apim_name,
        function_base_name=function_base,
    )
    setup.setup_all()


if __name__ == "__main__":
    main()
