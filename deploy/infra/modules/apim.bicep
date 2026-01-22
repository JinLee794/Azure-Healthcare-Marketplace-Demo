// Azure API Management Standard v2 Module
// Configured for private VNet integration with backend Function Apps

@description('Azure region for APIM')
param location string

@description('Name of the API Management instance')
param apimName string

@description('Publisher email address')
param publisherEmail string

@description('Publisher organization name')
param publisherName string

@description('SKU of the API Management instance - Standard v2 required for Foundry agents')
@allowed([
  'StandardV2'
  'Premium'
])
param skuName string = 'StandardV2'

@description('Capacity of the API Management instance')
@minValue(1)
@maxValue(10)
param skuCapacity int = 1

@description('Resource ID of the VNet (reserved for future VNet peering)')
#disable-next-line no-unused-params
param vnetId string

@description('Resource ID of the APIM subnet for VNet integration')
param apimSubnetId string

@description('Enable public network access')
param publicNetworkAccess string = 'Enabled'

@description('Base name for Function App backends')
param functionAppBaseName string = ''

@description('Tags to apply to resources')
param tags object = {}

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    publicNetworkAccess: publicNetworkAccess
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnetId
    }
    apiVersionConstraint: {
      minApiVersion: '2021-08-01'
    }
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_GCM_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA256': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_256_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TLS_RSA_WITH_AES_128_CBC_SHA': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
    }
  }
}

// Named values for MCP server configuration
resource namedValueMcpVersion 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'mcp-protocol-version'
  properties: {
    displayName: 'mcp-protocol-version'
    value: '2025-06-18'
  }
}

// ============================================================================
// Backend Configuration - Route to Function Apps
// ============================================================================

resource npiBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'npi-lookup-backend'
  properties: {
    title: 'NPI Lookup Function App'
    description: 'Backend for NPI Lookup MCP Server'
    url: 'https://${functionAppBaseName}-npi-lookup-func.azurewebsites.net/api'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource icd10Backend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'icd10-validation-backend'
  properties: {
    title: 'ICD-10 Validation Function App'
    description: 'Backend for ICD-10 Validation MCP Server'
    url: 'https://${functionAppBaseName}-icd10-validation-func.azurewebsites.net/api'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource cmsBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'cms-coverage-backend'
  properties: {
    title: 'CMS Coverage Function App'
    description: 'Backend for CMS Coverage MCP Server'
    url: 'https://${functionAppBaseName}-cms-coverage-func.azurewebsites.net/api'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource fhirBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'fhir-operations-backend'
  properties: {
    title: 'FHIR Operations Function App'
    description: 'Backend for FHIR Operations MCP Server'
    url: 'https://${functionAppBaseName}-fhir-operations-func.azurewebsites.net/api'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource pubmedBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'pubmed-backend'
  properties: {
    title: 'PubMed Function App'
    description: 'Backend for PubMed MCP Server'
    url: 'https://${functionAppBaseName}-pubmed-func.azurewebsites.net/api'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource clinicalTrialsBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'clinical-trials-backend'
  properties: {
    title: 'Clinical Trials Function App'
    description: 'Backend for Clinical Trials MCP Server'
    url: 'https://${functionAppBaseName}-clinical-trials-func.azurewebsites.net/api'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// Product for Healthcare MCP APIs
resource healthcareMcpProduct 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = {
  parent: apim
  name: 'healthcare-mcp'
  properties: {
    displayName: 'Healthcare MCP APIs'
    description: 'API product for Healthcare Model Context Protocol servers'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

// API for NPI Lookup
resource npiApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'npi-lookup-mcp'
  properties: {
    displayName: 'NPI Lookup MCP Server'
    description: 'Model Context Protocol server for NPI (National Provider Identifier) lookups'
    path: 'mcp/npi'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    apiType: 'http'
  }
}

// API for ICD-10 Validation
resource icd10Api 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'icd10-validation-mcp'
  properties: {
    displayName: 'ICD-10 Validation MCP Server'
    description: 'Model Context Protocol server for ICD-10 diagnosis code validation'
    path: 'mcp/icd10'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    apiType: 'http'
  }
}

// API for CMS Coverage
resource cmsApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'cms-coverage-mcp'
  properties: {
    displayName: 'CMS Coverage MCP Server'
    description: 'Model Context Protocol server for CMS coverage determination lookups'
    path: 'mcp/cms'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    apiType: 'http'
  }
}

// API for FHIR Operations
resource fhirApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'fhir-operations-mcp'
  properties: {
    displayName: 'FHIR Operations MCP Server'
    description: 'Model Context Protocol server for FHIR R4 operations'
    path: 'mcp/fhir'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    apiType: 'http'
  }
}

// API for PubMed
resource pubmedApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'pubmed-mcp'
  properties: {
    displayName: 'PubMed MCP Server'
    description: 'Model Context Protocol server for PubMed medical literature search'
    path: 'mcp/pubmed'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    apiType: 'http'
  }
}

// API for Clinical Trials
resource clinicalTrialsApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'clinical-trials-mcp'
  properties: {
    displayName: 'Clinical Trials MCP Server'
    description: 'Model Context Protocol server for ClinicalTrials.gov data access'
    path: 'mcp/clinical-trials'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    apiType: 'http'
  }
}

// Link APIs to product
resource npiApiProductLink 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: healthcareMcpProduct
  name: npiApi.name
}

resource icd10ApiProductLink 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: healthcareMcpProduct
  name: icd10Api.name
}

resource cmsApiProductLink 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: healthcareMcpProduct
  name: cmsApi.name
}

resource fhirApiProductLink 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: healthcareMcpProduct
  name: fhirApi.name
}

resource pubmedApiProductLink 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: healthcareMcpProduct
  name: pubmedApi.name
}

resource clinicalTrialsApiProductLink 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: healthcareMcpProduct
  name: clinicalTrialsApi.name
}

// ============================================================================
// MCP Discovery Operations (/.well-known/mcp)
// Each MCP server exposes discovery endpoint for Foundry agent integration
// ============================================================================

resource npiDiscoveryOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: npiApi
  name: 'mcp-discovery'
  properties: {
    displayName: 'MCP Discovery'
    method: 'GET'
    urlTemplate: '/.well-known/mcp'
    description: 'Returns MCP server capabilities and tool definitions for NPI Lookup'
    responses: [
      {
        statusCode: 200
        description: 'MCP server manifest'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource icd10DiscoveryOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: icd10Api
  name: 'mcp-discovery'
  properties: {
    displayName: 'MCP Discovery'
    method: 'GET'
    urlTemplate: '/.well-known/mcp'
    description: 'Returns MCP server capabilities and tool definitions for ICD-10 Validation'
    responses: [
      {
        statusCode: 200
        description: 'MCP server manifest'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource cmsDiscoveryOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: cmsApi
  name: 'mcp-discovery'
  properties: {
    displayName: 'MCP Discovery'
    method: 'GET'
    urlTemplate: '/.well-known/mcp'
    description: 'Returns MCP server capabilities and tool definitions for CMS Coverage'
    responses: [
      {
        statusCode: 200
        description: 'MCP server manifest'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource fhirDiscoveryOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: fhirApi
  name: 'mcp-discovery'
  properties: {
    displayName: 'MCP Discovery'
    method: 'GET'
    urlTemplate: '/.well-known/mcp'
    description: 'Returns MCP server capabilities and tool definitions for FHIR Operations'
    responses: [
      {
        statusCode: 200
        description: 'MCP server manifest'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource pubmedDiscoveryOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: pubmedApi
  name: 'mcp-discovery'
  properties: {
    displayName: 'MCP Discovery'
    method: 'GET'
    urlTemplate: '/.well-known/mcp'
    description: 'Returns MCP server capabilities and tool definitions for PubMed Search'
    responses: [
      {
        statusCode: 200
        description: 'MCP server manifest'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource clinicalTrialsDiscoveryOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: clinicalTrialsApi
  name: 'mcp-discovery'
  properties: {
    displayName: 'MCP Discovery'
    method: 'GET'
    urlTemplate: '/.well-known/mcp'
    description: 'Returns MCP server capabilities and tool definitions for Clinical Trials'
    responses: [
      {
        statusCode: 200
        description: 'MCP server manifest'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

// ============================================================================
// MCP Message Operations (POST /mcp)
// Main endpoint for MCP protocol messages (tools/call, etc.)
// ============================================================================

resource npiMessageOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: npiApi
  name: 'mcp-message'
  properties: {
    displayName: 'MCP Message'
    method: 'POST'
    urlTemplate: '/mcp'
    description: 'Handle MCP protocol messages for NPI Lookup tools'
    request: {
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'MCP response'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource icd10MessageOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: icd10Api
  name: 'mcp-message'
  properties: {
    displayName: 'MCP Message'
    method: 'POST'
    urlTemplate: '/mcp'
    description: 'Handle MCP protocol messages for ICD-10 Validation tools'
    request: {
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'MCP response'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource cmsMessageOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: cmsApi
  name: 'mcp-message'
  properties: {
    displayName: 'MCP Message'
    method: 'POST'
    urlTemplate: '/mcp'
    description: 'Handle MCP protocol messages for CMS Coverage tools'
    request: {
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'MCP response'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource fhirMessageOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: fhirApi
  name: 'mcp-message'
  properties: {
    displayName: 'MCP Message'
    method: 'POST'
    urlTemplate: '/mcp'
    description: 'Handle MCP protocol messages for FHIR Operations tools'
    request: {
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'MCP response'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource pubmedMessageOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: pubmedApi
  name: 'mcp-message'
  properties: {
    displayName: 'MCP Message'
    method: 'POST'
    urlTemplate: '/mcp'
    description: 'Handle MCP protocol messages for PubMed Search tools'
    request: {
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'MCP response'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

resource clinicalTrialsMessageOperation 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: clinicalTrialsApi
  name: 'mcp-message'
  properties: {
    displayName: 'MCP Message'
    method: 'POST'
    urlTemplate: '/mcp'
    description: 'Handle MCP protocol messages for Clinical Trials tools'
    request: {
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'MCP response'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

// ============================================================================
// API-Level Policies - Route to Backend Function Apps
// ============================================================================

resource npiApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: npiApi
  name: 'policy'
  dependsOn: [npiBackend]
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="npi-lookup-backend" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
}

resource icd10ApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: icd10Api
  name: 'policy'
  dependsOn: [icd10Backend]
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="icd10-validation-backend" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
}

resource cmsApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: cmsApi
  name: 'policy'
  dependsOn: [cmsBackend]
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="cms-coverage-backend" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
}

resource fhirApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: fhirApi
  name: 'policy'
  dependsOn: [fhirBackend]
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="fhir-operations-backend" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
}

resource pubmedApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: pubmedApi
  name: 'policy'
  dependsOn: [pubmedBackend]
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="pubmed-backend" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
}

resource clinicalTrialsApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: clinicalTrialsApi
  name: 'policy'
  dependsOn: [clinicalTrialsBackend]
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="clinical-trials-backend" />
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
}

// ============================================================================
// Product-Level Policy for Healthcare MCP APIs
// Applied only to APIs in the healthcare-mcp product, not globally
// ============================================================================

resource healthcareMcpProductPolicy 'Microsoft.ApiManagement/service/products/policies@2023-09-01-preview' = {
  parent: healthcareMcpProduct
  name: 'policy'
  dependsOn: [
    namedValueMcpVersion
    npiApiProductLink
    icd10ApiProductLink
    cmsApiProductLink
    fhirApiProductLink
    pubmedApiProductLink
    clinicalTrialsApiProductLink
  ]
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-header name="X-MCP-Protocol-Version" exists-action="override">
      <value>{{mcp-protocol-version}}</value>
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
    <set-header name="X-Frame-Options" exists-action="override">
      <value>DENY</value>
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
      <set-body>@{
        return new JObject(
          new JProperty("jsonrpc", "2.0"),
          new JProperty("error", new JObject(
            new JProperty("code", -32603),
            new JProperty("message", "Internal error processing MCP request")
          )),
          new JProperty("id", null)
        ).ToString();
      }</set-body>
    </return-response>
  </on-error>
</policies>
'''
  }
}

output apimId string = apim.id
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimManagementUrl string = apim.properties.managementApiUrl
output apimPrincipalId string = apim.identity.principalId
output healthcareProductId string = healthcareMcpProduct.id
