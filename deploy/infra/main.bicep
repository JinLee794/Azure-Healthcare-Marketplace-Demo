// Healthcare MCP Infrastructure - Main Orchestration
// Private network configuration with APIM Standard v2, Function Apps, and AI Foundry
// Based on foundry-samples/16-private-network-standard-agent-apim-setup-preview
targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Azure region for all resources')
@allowed([
  'australiaeast'
  'eastus'
  'eastus2'
  'francecentral'
  'japaneast'
  'norwayeast'
  'southindia'
  'swedencentral'
  'uksouth'
  'westus'
  'westus3'
])
param location string

@description('Base name for all resources (will be used as prefix)')
@minLength(3)
@maxLength(15)
param baseName string

@description('Publisher email for APIM')
param apimPublisherEmail string

@description('Publisher name for APIM')
param apimPublisherName string = 'Healthcare MCP Platform'

@description('APIM SKU - Standard v2 required for Foundry agents')
@allowed([
  'StandardV2'
  'Premium'
])
param apimSku string = 'StandardV2'

@description('VNet address space')
param vnetAddressPrefix string = '192.168.0.0/16'

@description('Enable public network access for dependent resources')
param enablePublicAccess bool = false

@description('Model deployments for AI Foundry')
param modelDeployments array = [
  {
    name: 'gpt-4o'
    model: 'gpt-4o'
    version: '2024-08-06'
    capacity: 10
  }
  {
    name: 'gpt-4o-mini'
    model: 'gpt-4o-mini'
    version: '2024-07-18'
    capacity: 10
  }
  {
    name: 'text-embedding-3-large'
    model: 'text-embedding-3-large'
    version: '1'
    capacity: 10
  }
]

@description('Tags to apply to all resources')
param tags object = {
  project: 'healthcare-mcp'
  environment: 'production'
  managedBy: 'bicep'
}

@description('Optional: Override region for Cosmos DB if primary region has capacity issues')
@allowed([
  ''
  'australiaeast'
  'brazilsouth'
  'canadacentral'
  'centralus'
  'eastasia'
  'eastus'
  'eastus2'
  'francecentral'
  'germanywestcentral'
  'japaneast'
  'koreacentral'
  'northcentralus'
  'northeurope'
  'norwayeast'
  'southcentralus'
  'southeastasia'
  'swedencentral'
  'switzerlandnorth'
  'uksouth'
  'westcentralus'
  'westeurope'
  'westus'
  'westus2'
  'westus3'
])
param cosmosDbLocation string = ''

// ============================================================================
// VARIABLES
// ============================================================================

var uniqueSuffix = uniqueString(resourceGroup().id)
var publicNetworkAccess = enablePublicAccess ? 'Enabled' : 'Disabled'

// ============================================================================
// MODULES
// ============================================================================

// 1. Virtual Network with subnets
module vnet 'modules/vnet.bicep' = {
  name: 'vnet-deployment'
  params: {
    location: location
    vnetName: '${baseName}-vnet'
    vnetAddressPrefix: vnetAddressPrefix
    // Subnet prefixes are derived from vnetAddressPrefix using defaults in vnet module
    tags: tags
  }
}

// 2. Dependent Resources (Storage, AI Search, Cosmos DB, App Insights)
module dependentResources 'modules/dependent-resources.bicep' = {
  name: 'dependent-resources-deployment'
  params: {
    location: location
    baseName: baseName
    cosmosDbLocation: empty(cosmosDbLocation) ? location : cosmosDbLocation
    publicNetworkAccess: publicNetworkAccess
    tags: tags
  }
}

// 3. AI Foundry (AI Services + Project with network injection)
module aiFoundry 'modules/ai-foundry.bicep' = {
  name: 'ai-foundry-deployment'
  params: {
    location: location
    aiServicesName: '${baseName}-aiservices'
    aiProjectName: '${baseName}-aiproject'
    agentSubnetId: vnet.outputs.agentSubnetId
    storageAccountId: dependentResources.outputs.storageAccountId
    aiSearchId: dependentResources.outputs.aiSearchId
    publicNetworkAccess: publicNetworkAccess
    modelDeployments: modelDeployments
    tags: tags
  }
}

// 4. Function Apps for MCP Servers
module functionApps 'modules/function-apps.bicep' = {
  name: 'function-apps-deployment'
  params: {
    location: location
    baseName: baseName
    functionSubnetId: vnet.outputs.functionSubnetId
    storageAccountId: dependentResources.outputs.storageAccountId
    storageAccountName: dependentResources.outputs.storageAccountName
    appInsightsInstrumentationKey: dependentResources.outputs.appInsightsInstrumentationKey
    appInsightsConnectionString: dependentResources.outputs.appInsightsConnectionString
    tags: tags
  }
}

// 5. API Management Standard v2
module apim 'modules/apim.bicep' = {
  name: 'apim-deployment'
  params: {
    location: location
    apimName: '${baseName}-apim'
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    skuName: apimSku
    vnetId: vnet.outputs.vnetId
    apimSubnetId: vnet.outputs.apimSubnetId
    publicNetworkAccess: enablePublicAccess ? 'Enabled' : 'Enabled' // APIM needs external access for gateway
    tags: tags
  }
}

// 6. Private Endpoints for all services
module privateEndpoints 'modules/private-endpoints.bicep' = {
  name: 'private-endpoints-deployment'
  params: {
    location: location
    vnetId: vnet.outputs.vnetId
    peSubnetId: vnet.outputs.peSubnetId
    aiServicesId: aiFoundry.outputs.aiServicesId
    aiSearchId: dependentResources.outputs.aiSearchId
    storageAccountId: dependentResources.outputs.storageAccountId
    cosmosDbId: dependentResources.outputs.cosmosDbId
    apimId: apim.outputs.apimId
    uniqueSuffix: uniqueSuffix
    tags: tags
  }
}

// ============================================================================
// ROLE ASSIGNMENTS
// ============================================================================

// Storage Blob Data Contributor for AI Services
resource aiServicesStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, '${baseName}-aiservices', 'storage-blob-contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: aiFoundry.outputs.aiServicesPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Search Index Data Contributor for AI Services
resource aiServicesSearchRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, '${baseName}-aiservices', 'search-index-contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7') // Search Index Data Contributor
    principalId: aiFoundry.outputs.aiServicesPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Cognitive Services OpenAI User for APIM
resource apimOpenAIRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, '${baseName}-apim', 'cognitive-services-openai-user')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: apim.outputs.apimPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

// Network
output vnetId string = vnet.outputs.vnetId
output vnetName string = vnet.outputs.vnetName
output agentSubnetId string = vnet.outputs.agentSubnetId
output peSubnetId string = vnet.outputs.peSubnetId
output apimSubnetId string = vnet.outputs.apimSubnetId
output functionSubnetId string = vnet.outputs.functionSubnetId

// APIM
output apimId string = apim.outputs.apimId
output apimName string = apim.outputs.apimName
output apimGatewayUrl string = apim.outputs.apimGatewayUrl
output apimManagementUrl string = apim.outputs.apimManagementUrl

// AI Foundry
output aiServicesId string = aiFoundry.outputs.aiServicesId
output aiServicesName string = aiFoundry.outputs.aiServicesName
output aiServicesEndpoint string = aiFoundry.outputs.aiServicesEndpoint
output aiProjectId string = aiFoundry.outputs.aiProjectId
output aiProjectName string = aiFoundry.outputs.aiProjectName

// Function Apps
output functionAppNames array = functionApps.outputs.functionAppNames
output mcpServerEndpoints array = functionApps.outputs.mcpServerEndpoints

// Dependent Resources
output storageAccountId string = dependentResources.outputs.storageAccountId
output storageAccountName string = dependentResources.outputs.storageAccountName
output aiSearchId string = dependentResources.outputs.aiSearchId
output aiSearchName string = dependentResources.outputs.aiSearchName
output cosmosDbId string = dependentResources.outputs.cosmosDbId
output cosmosDbEndpoint string = dependentResources.outputs.cosmosDbEndpoint
output appInsightsId string = dependentResources.outputs.appInsightsId
output appInsightsConnectionString string = dependentResources.outputs.appInsightsConnectionString
