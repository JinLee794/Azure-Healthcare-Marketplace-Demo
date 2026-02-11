// Function Apps Module for Healthcare MCP Servers
// Hosts MCP servers in VNet-integrated Function Apps

@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource ID of the Function App subnet for VNet integration')
param functionSubnetId string

@description('Resource ID of the Storage Account for Function Apps (for reference)')
#disable-next-line no-unused-params
param storageAccountId string

@description('Storage Account name')
param storageAccountName string

@description('Application Insights Instrumentation Key')
param appInsightsInstrumentationKey string = ''

@description('Application Insights Connection String')
param appInsightsConnectionString string = ''

@description('Python version')
param pythonVersion string = '3.11'

@description('Resource ID of the APIM subnet to allow traffic from')
param apimSubnetId string = ''

@description('Tags to apply to resources')
param tags object = {}

// Get storage account reference
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// App Service Plan for Function Apps (Elastic Premium for VNet integration)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${baseName}-asp'
  location: location
  tags: tags
  kind: 'elastic'
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    family: 'EP'
  }
  properties: {
    reserved: true // Linux
    maximumElasticWorkerCount: 20
  }
}

// MCP Server configurations
// MCP Server configurations - routes are exposed at root level (/.well-known/mcp and /mcp)
var mcpServers = [
  {
    name: 'npi-lookup'
    displayName: 'NPI Lookup MCP Server'
  }
  {
    name: 'icd10-validation'
    displayName: 'ICD-10 Validation MCP Server'
  }
  {
    name: 'cms-coverage'
    displayName: 'CMS Coverage MCP Server'
  }
  {
    name: 'fhir-operations'
    displayName: 'FHIR Operations MCP Server'
  }
  {
    name: 'pubmed'
    displayName: 'PubMed MCP Server'
  }
  {
    name: 'clinical-trials'
    displayName: 'Clinical Trials MCP Server'
  }
]

// Create Function Apps for each MCP server
resource functionApps 'Microsoft.Web/sites@2023-12-01' = [for server in mcpServers: {
  name: '${baseName}-${server.name}-func'
  location: location
  tags: union(tags, {
    'hidden-link: /app-insights-resource-id': appInsightsConnectionString
    mcpServer: server.name
    'azd-service-name': server.name
  })
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    virtualNetworkSubnetId: functionSubnetId
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      pythonVersion: pythonVersion
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      vnetRouteAllEnabled: true
      // Separate SCM restrictions from main site
      scmIpSecurityRestrictionsUseMain: false
      // Main site: Only allow traffic from APIM subnet
      ipSecurityRestrictions: !empty(apimSubnetId) ? [
        {
          name: 'AllowAPIM'
          description: 'Allow traffic from APIM subnet only'
          action: 'Allow'
          priority: 100
          vnetSubnetResourceId: apimSubnetId
        }
        {
          name: 'DenyAll'
          description: 'Deny all other traffic'
          action: 'Deny'
          priority: 2147483647
          ipAddress: 'Any'
        }
      ] : []
      // SCM site: Allow public access for azd deployment
      scmIpSecurityRestrictions: [
        {
          name: 'AllowAll'
          description: 'Allow deployment from anywhere (azd, GitHub Actions, etc.)'
          action: 'Allow'
          priority: 100
          ipAddress: 'Any'
        }
      ]
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower('${baseName}-${server.name}')
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsightsInstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'MCP_SERVER_NAME'
          value: server.name
        }
        {
          name: 'MCP_PROTOCOL_VERSION'
          value: '2025-06-18'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
    }
  }
}]

// Output function app details
output functionAppIds array = [for (server, i) in mcpServers: functionApps[i].id]
output functionAppNames array = [for (server, i) in mcpServers: functionApps[i].name]
output functionAppHostnames array = [for (server, i) in mcpServers: functionApps[i].properties.defaultHostName]
output functionAppPrincipalIds array = [for (server, i) in mcpServers: functionApps[i].identity.principalId]
output appServicePlanId string = appServicePlan.id

// Output for APIM backend configuration - Function Apps expose MCP endpoints at root level
output mcpServerEndpoints array = [for (server, i) in mcpServers: {
  name: server.name
  displayName: server.displayName
  backendUrl: 'https://${functionApps[i].properties.defaultHostName}'
}]
