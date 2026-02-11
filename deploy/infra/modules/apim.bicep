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

// Named value for function host keys (will be populated per function app)
resource npiBackend 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'npi-lookup-backend'
  properties: {
    title: 'NPI Lookup Function App'
    description: 'Backend for NPI Lookup MCP Server'
    url: 'https://${functionAppBaseName}-npi-lookup-func.azurewebsites.net'
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
    url: 'https://${functionAppBaseName}-icd10-validation-func.azurewebsites.net'
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
    url: 'https://${functionAppBaseName}-cms-coverage-func.azurewebsites.net'
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
    url: 'https://${functionAppBaseName}-fhir-operations-func.azurewebsites.net'
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
    url: 'https://${functionAppBaseName}-pubmed-func.azurewebsites.net'
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
    url: 'https://${functionAppBaseName}-clinical-trials-func.azurewebsites.net'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// ============================================================================
// NOTE: API definitions, operations, and policies are managed in apim-mcp-oauth.bicep
// This module only creates APIM service, backends, and base product configuration
// The OAuth module adds proper token validation and function key authentication
// ============================================================================

output apimId string = apim.id
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimManagementUrl string = apim.properties.managementApiUrl
output apimPrincipalId string = apim.identity.principalId
