// ============================================================================
// APIM MCP Passthrough Configuration Module (Lightweight - No OAuth)
// 
// PURPOSE: Establish and verify APIM → Function App backend connectivity
// before layering on OAuth/PRM complexity.
//
// Security: APIM subscription key (front-door) + Function key (backend)
// No OAuth validation, no PRM endpoints, minimal policy.
// ============================================================================

@description('Name of the API Management service')
param apimServiceName string

@description('Base name for function apps')
param functionAppBaseName string

// ============================================================================
// Reference existing APIM service and Function Apps
// ============================================================================

resource apimService 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimServiceName
}

// ============================================================================
// Server configuration array for DRY iteration
// ============================================================================

var funcAppApiVersion = '2023-12-01'

var mcpServers = [
  {
    name: 'npi'
    backendName: 'npi-pt'
    funcName: '${functionAppBaseName}-npi-lookup-func'
    funcHostName: '${functionAppBaseName}-npi-lookup-func.azurewebsites.net'
    keyName: 'npi-pt-key'
  }
  {
    name: 'icd10'
    backendName: 'icd10-pt'
    funcName: '${functionAppBaseName}-icd10-validation-func'
    funcHostName: '${functionAppBaseName}-icd10-validation-func.azurewebsites.net'
    keyName: 'icd10-pt-key'
  }
  {
    name: 'cms'
    backendName: 'cms-pt'
    funcName: '${functionAppBaseName}-cms-coverage-func'
    funcHostName: '${functionAppBaseName}-cms-coverage-func.azurewebsites.net'
    keyName: 'cms-pt-key'
  }
  {
    name: 'fhir'
    backendName: 'fhir-pt'
    funcName: '${functionAppBaseName}-fhir-operations-func'
    funcHostName: '${functionAppBaseName}-fhir-operations-func.azurewebsites.net'
    keyName: 'fhir-pt-key'
  }
  {
    name: 'pubmed'
    backendName: 'pubmed-pt'
    funcName: '${functionAppBaseName}-pubmed-func'
    funcHostName: '${functionAppBaseName}-pubmed-func.azurewebsites.net'
    keyName: 'pubmed-pt-key'
  }
  {
    name: 'clinical-trials'
    backendName: 'clinical-trials-pt'
    funcName: '${functionAppBaseName}-clinical-trials-func'
    funcHostName: '${functionAppBaseName}-clinical-trials-func.azurewebsites.net'
    keyName: 'clinical-trials-pt-key'
  }
  {
    name: 'cosmos-rag'
    backendName: 'cosmos-rag-pt'
    funcName: '${functionAppBaseName}-cosmos-rag-func'
    funcHostName: '${functionAppBaseName}-cosmos-rag-func.azurewebsites.net'
    keyName: 'cosmos-rag-pt-key'
  }
]

// ============================================================================
// Function Host Keys as Named Values
// ============================================================================

resource functionKeys 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = [for server in mcpServers: {
  parent: apimService
  name: server.keyName
  properties: {
    displayName: server.keyName
    secret: true
    value: listKeys(resourceId('Microsoft.Web/sites/host', server.funcName, 'default'), funcAppApiVersion).functionKeys.default
  }
}]

// ============================================================================
// Backend Definitions - one per MCP server
// ============================================================================

resource backends 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = [for server in mcpServers: {
  parent: apimService
  name: server.backendName
  properties: {
    title: '${server.name} MCP Backend (passthrough)'
    url: 'https://${server.funcHostName}'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}]

// ============================================================================
// Passthrough API - subscription key required, no OAuth
// Path: /mcp-pt/{server}/mcp
// ============================================================================

resource passthroughApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apimService
  name: 'mcp-passthrough'
  properties: {
    displayName: 'Healthcare MCP Servers (Passthrough - Debug)'
    description: 'Lightweight passthrough API for debugging backend connectivity. No OAuth.'
    path: 'mcp-pt'
    protocols: ['https']
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
  }
}

// ============================================================================
// Product & Subscription for the passthrough API
// ============================================================================

resource passthroughProduct 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = {
  parent: apimService
  name: 'mcp-passthrough-product'
  properties: {
    displayName: 'MCP Passthrough (Debug)'
    description: 'Debug product for testing MCP backend connectivity'
    state: 'published'
    subscriptionRequired: true
    approvalRequired: false
  }
}

resource passthroughProductApi 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: passthroughProduct
  name: 'mcp-passthrough'
  dependsOn: [passthroughApi]
}

resource passthroughSubscription 'Microsoft.ApiManagement/service/subscriptions@2023-09-01-preview' = {
  parent: apimService
  name: 'mcp-passthrough-sub'
  properties: {
    scope: passthroughProduct.id
    displayName: 'MCP Passthrough Debug Subscription'
    state: 'active'
    allowTracing: true
  }
}

// ============================================================================
// Per-Server Operations: POST /{server}/mcp and GET /{server}/mcp
// Each operation has its own inline policy for backend routing
// ============================================================================

// ----- NPI -----
resource npiPostOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'npi-post'
  properties: {
    displayName: 'NPI - POST /mcp'
    method: 'POST'
    urlTemplate: '/npi/mcp'
    description: 'MCP message endpoint for NPI server'
  }
}

resource npiPostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: npiPostOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="npi-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{npi-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
    <trace source="mcp-passthrough-npi" severity="information">
      <message>@($"NPI POST → backend: {context.Request.Url}")</message>
    </trace>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","npi-backend-failure"),new JProperty("detail",context.LastError?.Message),new JProperty("source",context.LastError?.Source),new JProperty("reason",context.LastError?.Reason)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

resource npiGetOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'npi-get'
  properties: {
    displayName: 'NPI - GET /mcp'
    method: 'GET'
    urlTemplate: '/npi/mcp'
    description: 'MCP info endpoint for NPI server'
  }
}

resource npiGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: npiGetOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="npi-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{npi-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","npi-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

// ----- ICD-10 -----
resource icd10PostOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'icd10-post'
  properties: {
    displayName: 'ICD-10 - POST /mcp'
    method: 'POST'
    urlTemplate: '/icd10/mcp'
    description: 'MCP message endpoint for ICD-10 server'
  }
}

resource icd10PostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: icd10PostOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="icd10-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{icd10-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","icd10-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

resource icd10GetOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'icd10-get'
  properties: {
    displayName: 'ICD-10 - GET /mcp'
    method: 'GET'
    urlTemplate: '/icd10/mcp'
    description: 'MCP info endpoint for ICD-10 server'
  }
}

resource icd10GetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: icd10GetOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="icd10-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{icd10-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","icd10-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

// ----- CMS -----
resource cmsPostOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'cms-post'
  properties: {
    displayName: 'CMS - POST /mcp'
    method: 'POST'
    urlTemplate: '/cms/mcp'
    description: 'MCP message endpoint for CMS server'
  }
}

resource cmsPostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: cmsPostOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="cms-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{cms-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","cms-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

resource cmsGetOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'cms-get'
  properties: {
    displayName: 'CMS - GET /mcp'
    method: 'GET'
    urlTemplate: '/cms/mcp'
    description: 'MCP info endpoint for CMS server'
  }
}

resource cmsGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: cmsGetOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="cms-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{cms-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","cms-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

// ----- FHIR -----
resource fhirPostOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'fhir-post'
  properties: {
    displayName: 'FHIR - POST /mcp'
    method: 'POST'
    urlTemplate: '/fhir/mcp'
    description: 'MCP message endpoint for FHIR server'
  }
}

resource fhirPostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: fhirPostOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="fhir-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{fhir-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","fhir-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

resource fhirGetOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'fhir-get'
  properties: {
    displayName: 'FHIR - GET /mcp'
    method: 'GET'
    urlTemplate: '/fhir/mcp'
    description: 'MCP info endpoint for FHIR server'
  }
}

resource fhirGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: fhirGetOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="fhir-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{fhir-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","fhir-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

// ----- PubMed -----
resource pubmedPostOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'pubmed-post'
  properties: {
    displayName: 'PubMed - POST /mcp'
    method: 'POST'
    urlTemplate: '/pubmed/mcp'
    description: 'MCP message endpoint for PubMed server'
  }
}

resource pubmedPostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: pubmedPostOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="pubmed-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{pubmed-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","pubmed-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

resource pubmedGetOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'pubmed-get'
  properties: {
    displayName: 'PubMed - GET /mcp'
    method: 'GET'
    urlTemplate: '/pubmed/mcp'
    description: 'MCP info endpoint for PubMed server'
  }
}

resource pubmedGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: pubmedGetOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="pubmed-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{pubmed-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","pubmed-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

// ----- Clinical Trials -----
resource clinicalTrialsPostOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'clinical-trials-post'
  properties: {
    displayName: 'Clinical Trials - POST /mcp'
    method: 'POST'
    urlTemplate: '/clinical-trials/mcp'
    description: 'MCP message endpoint for Clinical Trials server'
  }
}

resource clinicalTrialsPostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: clinicalTrialsPostOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="clinical-trials-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{clinical-trials-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","clinical-trials-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

resource clinicalTrialsGetOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'clinical-trials-get'
  properties: {
    displayName: 'Clinical Trials - GET /mcp'
    method: 'GET'
    urlTemplate: '/clinical-trials/mcp'
    description: 'MCP info endpoint for Clinical Trials server'
  }
}

resource clinicalTrialsGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: clinicalTrialsGetOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="clinical-trials-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{clinical-trials-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","clinical-trials-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

// ----- Cosmos RAG -----
resource cosmosRagPostOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'cosmos-rag-post'
  properties: {
    displayName: 'Cosmos RAG - POST /mcp'
    method: 'POST'
    urlTemplate: '/cosmos-rag/mcp'
    description: 'MCP message endpoint for Cosmos RAG & Audit server'
  }
}

resource cosmosRagPostPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: cosmosRagPostOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="cosmos-rag-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{cosmos-rag-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
    <trace source="mcp-passthrough-cosmos-rag" severity="information">
      <message>@($"Cosmos RAG POST → backend: {context.Request.Url}")</message>
    </trace>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","cosmos-rag-backend-failure"),new JProperty("detail",context.LastError?.Message),new JProperty("source",context.LastError?.Source),new JProperty("reason",context.LastError?.Reason)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

resource cosmosRagGetOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'cosmos-rag-get'
  properties: {
    displayName: 'Cosmos RAG - GET /mcp'
    method: 'GET'
    urlTemplate: '/cosmos-rag/mcp'
    description: 'MCP info endpoint for Cosmos RAG & Audit server'
  }
}

resource cosmosRagGetPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: cosmosRagGetOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="cosmos-rag-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{cosmos-rag-pt-key}}</value></set-header>
    <rewrite-uri template="/mcp" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","cosmos-rag-backend-failure"),new JProperty("detail",context.LastError?.Message)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

// ============================================================================
// Health Check Endpoints - for verifying each backend is reachable
// ============================================================================

resource npiHealthOp 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: passthroughApi
  name: 'npi-health'
  properties: {
    displayName: 'NPI - Health Check'
    method: 'GET'
    urlTemplate: '/npi/health'
    description: 'Health check for NPI backend'
  }
}

resource npiHealthPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: npiHealthOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="npi-pt" />
    <set-header name="x-functions-key" exists-action="override"><value>{{npi-pt-key}}</value></set-header>
    <rewrite-uri template="/health" copy-unmatched-params="false" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error>
    <base />
    <return-response>
      <set-status code="502" reason="Backend Error" />
      <set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header>
      <set-body>@(new JObject(new JProperty("error","npi-health-unreachable"),new JProperty("detail",context.LastError?.Message),new JProperty("reason",context.LastError?.Reason)).ToString())</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
  dependsOn: [backends, functionKeys]
}

// ============================================================================
// Outputs
// ============================================================================

output passthroughApiId string = passthroughApi.id
output passthroughApiPath string = passthroughApi.properties.path
output passthroughSubscriptionId string = passthroughSubscription.id
output gatewayUrl string = apimService.properties.gatewayUrl
