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
    value: '2024-11-05'
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

// Global policy for MCP protocol handling
resource globalPolicy 'Microsoft.ApiManagement/service/policies@2023-09-01-preview' = {
  parent: apim
  name: 'policy'
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
  </outbound>
  <on-error>
    <base />
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
