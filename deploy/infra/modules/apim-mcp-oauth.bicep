// ============================================================================
// APIM MCP OAuth Configuration Module
// Configures a unified MCP API with OAuth protection and routing to Function Apps
// Based on: https://github.com/Azure-Samples/remote-mcp-apim-functions-python
// ============================================================================

@description('Name of the API Management service')
param apimServiceName string

@description('Client ID of the MCP Entra application')
param mcpAppId string

@description('Tenant ID of the MCP Entra application')
param mcpAppTenantId string

@description('Base name for function apps')
param functionAppBaseName string

// ============================================================================
// Reference existing APIM service and Function Apps
// ============================================================================

resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimServiceName
}

// Reference Function Apps to get host keys
resource npiFunctionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: '${functionAppBaseName}-npi-lookup-func'
}

resource icd10FunctionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: '${functionAppBaseName}-icd10-validation-func'
}

resource cmsFunctionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: '${functionAppBaseName}-cms-coverage-func'
}

resource fhirFunctionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: '${functionAppBaseName}-fhir-operations-func'
}

resource pubmedFunctionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: '${functionAppBaseName}-pubmed-func'
}

resource clinicalTrialsFunctionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: '${functionAppBaseName}-clinical-trials-func'
}

// ============================================================================
// Named Values for OAuth Configuration
// ============================================================================

resource mcpTenantIdNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'McpTenantId'
  properties: {
    displayName: 'McpTenantId'
    value: mcpAppTenantId
    secret: false
  }
}

resource mcpClientIdNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'McpClientId'
  properties: {
    displayName: 'McpClientId'
    value: mcpAppId
    secret: false
  }
}

resource apimGatewayUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'APIMGatewayURL'
  properties: {
    displayName: 'APIMGatewayURL'
    value: apimService.properties.gatewayUrl
    secret: false
  }
}

// ============================================================================
// Function Host Keys - Stored as APIM Named Values (Secret)
// ============================================================================

resource npiFunctionKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'npi-function-key'
  properties: {
    displayName: 'npi-function-key'
    secret: true
    value: listKeys('${npiFunctionApp.id}/host/default', npiFunctionApp.apiVersion).functionKeys.default
  }
}

resource icd10FunctionKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'icd10-function-key'
  properties: {
    displayName: 'icd10-function-key'
    secret: true
    value: listKeys('${icd10FunctionApp.id}/host/default', icd10FunctionApp.apiVersion).functionKeys.default
  }
}

resource cmsFunctionKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'cms-function-key'
  properties: {
    displayName: 'cms-function-key'
    secret: true
    value: listKeys('${cmsFunctionApp.id}/host/default', cmsFunctionApp.apiVersion).functionKeys.default
  }
}

resource fhirFunctionKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'fhir-function-key'
  properties: {
    displayName: 'fhir-function-key'
    secret: true
    value: listKeys('${fhirFunctionApp.id}/host/default', fhirFunctionApp.apiVersion).functionKeys.default
  }
}

resource pubmedFunctionKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'pubmed-function-key'
  properties: {
    displayName: 'pubmed-function-key'
    secret: true
    value: listKeys('${pubmedFunctionApp.id}/host/default', pubmedFunctionApp.apiVersion).functionKeys.default
  }
}

resource clinicalTrialsFunctionKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apimService
  name: 'clinical-trials-function-key'
  properties: {
    displayName: 'clinical-trials-function-key'
    secret: true
    value: listKeys('${clinicalTrialsFunctionApp.id}/host/default', clinicalTrialsFunctionApp.apiVersion).functionKeys.default
  }
}

// ============================================================================
// Backend Definitions - One per MCP Server (no /api suffix - routePrefix is "")
// ============================================================================

resource npiBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'npi-backend'
  properties: {
    title: 'NPI Lookup Backend'
    description: 'Backend for NPI Lookup MCP Server'
    url: 'https://${npiFunctionApp.properties.defaultHostName}'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource icd10Backend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'icd10-backend'
  properties: {
    title: 'ICD-10 Validation Backend'
    description: 'Backend for ICD-10 Validation MCP Server'
    url: 'https://${icd10FunctionApp.properties.defaultHostName}'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource cmsBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'cms-backend'
  properties: {
    title: 'CMS Coverage Backend'
    description: 'Backend for CMS Coverage MCP Server'
    url: 'https://${cmsFunctionApp.properties.defaultHostName}'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource fhirBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'fhir-backend'
  properties: {
    title: 'FHIR Operations Backend'
    description: 'Backend for FHIR Operations MCP Server'
    url: 'https://${fhirFunctionApp.properties.defaultHostName}'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource pubmedBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'pubmed-backend'
  properties: {
    title: 'PubMed Backend'
    description: 'Backend for PubMed MCP Server'
    url: 'https://${pubmedFunctionApp.properties.defaultHostName}'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource clinicalTrialsBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apimService
  name: 'clinical-trials-backend'
  properties: {
    title: 'Clinical Trials Backend'
    description: 'Backend for Clinical Trials MCP Server'
    url: 'https://${clinicalTrialsFunctionApp.properties.defaultHostName}'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// ============================================================================
// Unified MCP API with wildcard routing
// All MCP servers accessible under /mcp/{server-name}/*
// Uses name 'mcp-oauth' to match existing API and enable updates
// ============================================================================

resource mcpApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apimService
  name: 'mcp-oauth'
  properties: {
    displayName: 'Healthcare MCP Servers'
    description: 'Unified API for all Healthcare MCP servers with OAuth protection'
    path: 'mcp'
    protocols: ['https']
    subscriptionRequired: false
  }
}

// ----- Global PRM Endpoint -----
resource mcpPrmOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'prm-discovery'
  properties: {
    displayName: 'Protected Resource Metadata'
    method: 'GET'
    urlTemplate: '/.well-known/oauth-protected-resource'
    description: 'OAuth discovery endpoint (RFC 9728)'
  }
}

resource mcpPrmPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: mcpPrmOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/mcp-prm.policy.xml')
  }
  dependsOn: [apimGatewayUrlNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue]
}

// ============================================================================
// Per-Server PRM Endpoints (RFC 9728 compliance)
// Each MCP server needs its own PRM endpoint that returns the correct resource URL
// ============================================================================

// ----- NPI PRM -----
resource npiPrmOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'npi-prm'
  properties: {
    displayName: 'NPI - Protected Resource Metadata'
    method: 'GET'
    urlTemplate: '/npi/.well-known/oauth-protected-resource'
    description: 'OAuth discovery endpoint for NPI server (RFC 9728)'
  }
}

resource npiPrmPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: npiPrmOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/mcp-server-prm.policy.xml')
  }
  dependsOn: [apimGatewayUrlNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue]
}

// ----- ICD-10 PRM -----
resource icd10PrmOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'icd10-prm'
  properties: {
    displayName: 'ICD-10 - Protected Resource Metadata'
    method: 'GET'
    urlTemplate: '/icd10/.well-known/oauth-protected-resource'
    description: 'OAuth discovery endpoint for ICD-10 server (RFC 9728)'
  }
}

resource icd10PrmPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: icd10PrmOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/mcp-server-prm.policy.xml')
  }
  dependsOn: [apimGatewayUrlNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue]
}

// ----- CMS PRM -----
resource cmsPrmOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'cms-prm'
  properties: {
    displayName: 'CMS - Protected Resource Metadata'
    method: 'GET'
    urlTemplate: '/cms/.well-known/oauth-protected-resource'
    description: 'OAuth discovery endpoint for CMS server (RFC 9728)'
  }
}

resource cmsPrmPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: cmsPrmOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/mcp-server-prm.policy.xml')
  }
  dependsOn: [apimGatewayUrlNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue]
}

// ----- FHIR PRM -----
resource fhirPrmOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'fhir-prm'
  properties: {
    displayName: 'FHIR - Protected Resource Metadata'
    method: 'GET'
    urlTemplate: '/fhir/.well-known/oauth-protected-resource'
    description: 'OAuth discovery endpoint for FHIR server (RFC 9728)'
  }
}

resource fhirPrmPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: fhirPrmOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/mcp-server-prm.policy.xml')
  }
  dependsOn: [apimGatewayUrlNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue]
}

// ----- PubMed PRM -----
resource pubmedPrmOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'pubmed-prm'
  properties: {
    displayName: 'PubMed - Protected Resource Metadata'
    method: 'GET'
    urlTemplate: '/pubmed/.well-known/oauth-protected-resource'
    description: 'OAuth discovery endpoint for PubMed server (RFC 9728)'
  }
}

resource pubmedPrmPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: pubmedPrmOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/mcp-server-prm.policy.xml')
  }
  dependsOn: [apimGatewayUrlNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue]
}

// ----- Clinical Trials PRM -----
resource clinicalTrialsPrmOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'clinical-trials-prm'
  properties: {
    displayName: 'Clinical Trials - Protected Resource Metadata'
    method: 'GET'
    urlTemplate: '/clinical-trials/.well-known/oauth-protected-resource'
    description: 'OAuth discovery endpoint for Clinical Trials server (RFC 9728)'
  }
}

resource clinicalTrialsPrmPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: clinicalTrialsPrmOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/mcp-server-prm.policy.xml')
  }
  dependsOn: [apimGatewayUrlNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue]
}

// ============================================================================
// MCP Server Operations
// ============================================================================

// ----- NPI Lookup Operations -----
resource npiGetOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'npi-get'
  properties: {
    displayName: 'NPI Lookup - GET'
    method: 'GET'
    urlTemplate: '/npi/*'
    description: 'MCP GET endpoint for NPI Lookup server'
  }
}

resource npiPostOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'npi-post'
  properties: {
    displayName: 'NPI Lookup - POST'
    method: 'POST'
    urlTemplate: '/npi/*'
    description: 'MCP POST endpoint for NPI Lookup server'
  }
}

resource npiGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: npiGetOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="npi-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{npi-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/npi";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [npiFunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, npiBackend]
}

resource npiPostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: npiPostOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="npi-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{npi-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/npi";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [npiFunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, npiBackend]
}

// ----- ICD-10 Validation Operations -----
resource icd10GetOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'icd10-get'
  properties: {
    displayName: 'ICD-10 Validation - GET'
    method: 'GET'
    urlTemplate: '/icd10/*'
    description: 'MCP GET endpoint for ICD-10 Validation server'
  }
}

resource icd10PostOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'icd10-post'
  properties: {
    displayName: 'ICD-10 Validation - POST'
    method: 'POST'
    urlTemplate: '/icd10/*'
    description: 'MCP POST endpoint for ICD-10 Validation server'
  }
}

resource icd10GetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: icd10GetOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="icd10-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{icd10-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/icd10";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [icd10FunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, icd10Backend]
}

resource icd10PostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: icd10PostOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="icd10-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{icd10-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/icd10";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [icd10FunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, icd10Backend]
}

// ----- CMS Coverage Operations -----
resource cmsGetOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'cms-get'
  properties: {
    displayName: 'CMS Coverage - GET'
    method: 'GET'
    urlTemplate: '/cms/*'
    description: 'MCP GET endpoint for CMS Coverage server'
  }
}

resource cmsPostOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'cms-post'
  properties: {
    displayName: 'CMS Coverage - POST'
    method: 'POST'
    urlTemplate: '/cms/*'
    description: 'MCP POST endpoint for CMS Coverage server'
  }
}

resource cmsGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: cmsGetOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="cms-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{cms-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/cms";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [cmsFunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, cmsBackend]
}

resource cmsPostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: cmsPostOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="cms-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{cms-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/cms";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [cmsFunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, cmsBackend]
}

// ----- FHIR Operations -----
resource fhirGetOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'fhir-get'
  properties: {
    displayName: 'FHIR Operations - GET'
    method: 'GET'
    urlTemplate: '/fhir/*'
    description: 'MCP GET endpoint for FHIR Operations server'
  }
}

resource fhirPostOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'fhir-post'
  properties: {
    displayName: 'FHIR Operations - POST'
    method: 'POST'
    urlTemplate: '/fhir/*'
    description: 'MCP POST endpoint for FHIR Operations server'
  }
}

resource fhirGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: fhirGetOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="fhir-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{fhir-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/fhir";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [fhirFunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, fhirBackend]
}

resource fhirPostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: fhirPostOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="fhir-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{fhir-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/fhir";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [fhirFunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, fhirBackend]
}

// ----- PubMed Operations -----
resource pubmedGetOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'pubmed-get'
  properties: {
    displayName: 'PubMed - GET'
    method: 'GET'
    urlTemplate: '/pubmed/*'
    description: 'MCP GET endpoint for PubMed server'
  }
}

resource pubmedPostOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'pubmed-post'
  properties: {
    displayName: 'PubMed - POST'
    method: 'POST'
    urlTemplate: '/pubmed/*'
    description: 'MCP POST endpoint for PubMed server'
  }
}

resource pubmedGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: pubmedGetOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="pubmed-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{pubmed-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/pubmed";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [pubmedFunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, pubmedBackend]
}

resource pubmedPostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: pubmedPostOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="pubmed-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{pubmed-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/pubmed";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [pubmedFunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, pubmedBackend]
}

// ----- Clinical Trials Operations -----
resource clinicalTrialsGetOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'clinical-trials-get'
  properties: {
    displayName: 'Clinical Trials - GET'
    method: 'GET'
    urlTemplate: '/clinical-trials/*'
    description: 'MCP GET endpoint for Clinical Trials server'
  }
}

resource clinicalTrialsPostOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: mcpApi
  name: 'clinical-trials-post'
  properties: {
    displayName: 'Clinical Trials - POST'
    method: 'POST'
    urlTemplate: '/clinical-trials/*'
    description: 'MCP POST endpoint for Clinical Trials server'
  }
}

resource clinicalTrialsGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: clinicalTrialsGetOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="clinical-trials-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{clinical-trials-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/clinical-trials";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [clinicalTrialsFunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, clinicalTrialsBackend]
}

resource clinicalTrialsPostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: clinicalTrialsPostOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{McpTenantId}}" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <audiences><audience>{{McpClientId}}</audience></audiences>
    </validate-azure-ad-token>
    <set-backend-service backend-id="clinical-trials-backend" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{clinical-trials-function-key}}</value>
    </set-header>
    <rewrite-uri template="@{
      var path = context.Request.Url.Path;
      var prefix = "/mcp/clinical-trials";
      return path.StartsWith(prefix) ? path.Substring(prefix.Length) : path;
    }" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 401)">
        <return-response>
          <set-status code="401" reason="Unauthorized" />
          <set-header name="WWW-Authenticate" exists-action="override">
            <value>Bearer error="invalid_token", resource_metadata="{{APIMGatewayURL}}/mcp/.well-known/oauth-protected-resource"</value>
          </set-header>
          <set-body>{"jsonrpc": "2.0", "error": {"code": -32001, "message": "Authentication required. Please authenticate using OAuth 2.0."}, "id": null}</set-body>
        </return-response>
      </when>
    </choose>
  </on-error>
</policies>
'''
  }
  dependsOn: [clinicalTrialsFunctionKeyNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue, apimGatewayUrlNamedValue, clinicalTrialsBackend]
}

// ============================================================================
// Global PRM Endpoint API (for OAuth discovery at root)
// ============================================================================

resource prmApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apimService
  name: 'mcp-prm'
  properties: {
    displayName: 'MCP Protected Resource Metadata'
    description: 'OAuth discovery endpoint for MCP clients (RFC 9728)'
    path: ''
    protocols: ['https']
    subscriptionRequired: false
  }
}

resource prmOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: prmApi
  name: 'prm-discovery'
  properties: {
    displayName: 'Protected Resource Metadata'
    method: 'GET'
    urlTemplate: '/.well-known/oauth-protected-resource'
    description: 'Returns OAuth configuration for MCP clients'
  }
}

resource prmPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: prmOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../policies/mcp-prm.policy.xml')
  }
  dependsOn: [apimGatewayUrlNamedValue, mcpTenantIdNamedValue, mcpClientIdNamedValue]
}

// ============================================================================
// Outputs
// ============================================================================

output prmEndpoint string = '${apimService.properties.gatewayUrl}/.well-known/oauth-protected-resource'
output mcpApiId string = mcpApi.id
output mcpApiName string = mcpApi.name
output mcpApiPath string = mcpApi.properties.path
