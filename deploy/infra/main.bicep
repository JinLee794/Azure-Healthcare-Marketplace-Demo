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

@description('Azure Container Registry SKU for dockerized MCP server images')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param containerRegistrySku string = 'Basic'

@description('Enable admin user on Azure Container Registry')
param containerRegistryAdminUserEnabled bool = false

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

@description('Display name for the MCP Entra application')
param mcpEntraAppDisplayName string = 'Healthcare MCP API'

@description('Unique name for the MCP Entra application')
param mcpEntraAppUniqueName string = ''

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
var mcpAppUniqueName = empty(mcpEntraAppUniqueName) ? 'healthcare-mcp-${uniqueSuffix}' : mcpEntraAppUniqueName
var acrBaseName = toLower(replace(baseName, '-', ''))
var containerRegistryName = take('${acrBaseName}acr${uniqueSuffix}', 50)

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

// 2. Dependent Resources (Storage, Cosmos DB, App Insights)
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

// 3. Azure Container Registry for dockerized MCP server images
module containerRegistry 'modules/container-registry.bicep' = {
  name: 'container-registry-deployment'
  params: {
    location: location
    registryName: containerRegistryName
    skuName: containerRegistrySku
    adminUserEnabled: containerRegistryAdminUserEnabled
    publicNetworkAccess: 'Enabled'
    tags: tags
  }
}

// 4. AI Foundry (AI Services + Project with network injection)
module aiFoundry 'modules/ai-foundry.bicep' = {
  name: 'ai-foundry-deployment'
  params: {
    location: location
    aiServicesName: '${baseName}-aiservices-${uniqueSuffix}'
    aiProjectName: '${baseName}-aiproject-${uniqueSuffix}'
    agentSubnetId: vnet.outputs.agentSubnetId
    storageAccountId: dependentResources.outputs.storageAccountId
    publicNetworkAccess: publicNetworkAccess
    modelDeployments: modelDeployments
    tags: tags
  }
}

// 5. Azure Health Data Services (FHIR R4)
// Workspace name: max 24 chars, alphanumeric only, no reserved words ("healthcare","fhir","azure","microsoft")
// Use uniqueSuffix to build a compliant name (baseName may contain "healthcare" which is reserved)
var ahdsWorkspaceName = 'mcphds${uniqueSuffix}'
module healthDataServices 'modules/health-data-services.bicep' = {
  name: 'health-data-services-deployment'
  params: {
    location: location
    workspaceName: ahdsWorkspaceName
    fhirServiceName: 'mcp'
    publicNetworkAccess: publicNetworkAccess
    tags: tags
  }
}

// 6. Function Apps for MCP Servers (container-based deployment)
module functionApps 'modules/function-apps.bicep' = {
  name: 'function-apps-deployment'
  params: {
    location: location
    baseName: baseName
    functionSubnetId: vnet.outputs.functionSubnetId
    apimSubnetId: vnet.outputs.apimSubnetId
    storageAccountId: dependentResources.outputs.storageAccountId
    storageAccountName: dependentResources.outputs.storageAccountName
    appInsightsInstrumentationKey: dependentResources.outputs.appInsightsInstrumentationKey
    appInsightsConnectionString: dependentResources.outputs.appInsightsConnectionString
    logAnalyticsId: dependentResources.outputs.logAnalyticsId
    fhirServerUrl: healthDataServices.outputs.fhirServerUrl
    acrLoginServer: containerRegistry.outputs.registryLoginServer
    cosmosDbEndpoint: dependentResources.outputs.cosmosDbEndpoint
    aiServicesEndpoint: aiFoundry.outputs.aiServicesEndpoint
    tags: tags
  }
}

// 7. API Management Standard v2
module apim 'modules/apim.bicep' = {
  name: 'apim-deployment'
  params: {
    location: location
    apimName: '${baseName}-apim-${uniqueSuffix}'
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    skuName: apimSku
    vnetId: vnet.outputs.vnetId
    apimSubnetId: vnet.outputs.apimSubnetId
    functionAppBaseName: baseName
    appInsightsId: dependentResources.outputs.appInsightsId
    appInsightsInstrumentationKey: dependentResources.outputs.appInsightsInstrumentationKey
    logAnalyticsId: dependentResources.outputs.logAnalyticsId
    publicNetworkAccess: enablePublicAccess ? 'Enabled' : 'Enabled' // APIM needs external access for gateway
    tags: tags
  }
  dependsOn: [functionApps]  // Ensure Function Apps exist before configuring backends
}

// 8. User-Assigned Managed Identity for MCP OAuth
module mcpUserIdentity 'modules/mcp-user-identity.bicep' = {
  name: 'mcp-user-identity-deployment'
  params: {
    identityName: '${baseName}-mcp-identity-${uniqueSuffix}'
    location: location
    tags: tags
  }
}

// 9. MCP Entra App Registration with Federated Identity Credential
module mcpEntraApp 'modules/mcp-entra-app.bicep' = {
  name: 'mcp-entra-app-deployment'
  params: {
    mcpAppUniqueName: mcpAppUniqueName
    mcpAppDisplayName: mcpEntraAppDisplayName
    userAssignedIdentityPrincipalId: mcpUserIdentity.outputs.identityPrincipalId
    apimGatewayUrl: apim.outputs.apimGatewayUrl
  }
}

// 10. APIM MCP OAuth Configuration (PRM endpoint + token validation)
module apimMcpOAuth 'modules/apim-mcp-oauth.bicep' = {
  name: 'apim-mcp-oauth-deployment'
  params: {
    apimServiceName: apim.outputs.apimName
    mcpAppId: mcpEntraApp.outputs.mcpAppId
    mcpAppTenantId: mcpEntraApp.outputs.mcpAppTenantId
    functionAppBaseName: baseName
  }
  dependsOn: [functionApps]  // Ensure Function Apps exist for host key retrieval
}

// 10b. APIM MCP Passthrough (Lightweight debug - no OAuth, subscription key only)
module apimMcpPassthrough 'modules/apim-mcp-passthrough.bicep' = {
  name: 'apim-mcp-passthrough-deployment'
  params: {
    apimServiceName: apim.outputs.apimName
    functionAppBaseName: baseName
  }
  dependsOn: [functionApps]
}

// 11. Private Endpoints for all services
module privateEndpoints 'modules/private-endpoints.bicep' = {
  name: 'private-endpoints-deployment'
  params: {
    location: location
    vnetId: vnet.outputs.vnetId
    peSubnetId: vnet.outputs.peSubnetId
    aiServicesId: aiFoundry.outputs.aiServicesId
    storageAccountId: dependentResources.outputs.storageAccountId
    cosmosDbId: dependentResources.outputs.cosmosDbId
    apimId: apim.outputs.apimId
    healthDataServicesWorkspaceId: healthDataServices.outputs.workspaceId
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

// FHIR Data Contributor for Function Apps (allows MCP servers to access FHIR data)
// Index 3 = fhir-operations server; assigning to all for flexibility
var mcpServerCount = 7 // Must match mcpServers array length in function-apps.bicep

resource containerRegistryResource 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: containerRegistryName
}

resource fhirDataContributorRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for i in range(0, mcpServerCount): {
  name: guid(resourceGroup().id, 'func-${i}', 'fhir-data-contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5a1fc7df-4bf1-4951-a576-89034ee01acd') // FHIR Data Contributor
    principalId: functionApps.outputs.functionAppPrincipalIds[i]
    principalType: 'ServicePrincipal'
  }
}]

// AcrPull for Function Apps (required when MCP servers are deployed as container images)
resource acrPullRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for i in range(0, mcpServerCount): {
  name: guid(resourceGroup().id, containerRegistryName, 'func-${i}', 'acr-pull')
  scope: containerRegistryResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: functionApps.outputs.functionAppPrincipalIds[i]
    principalType: 'ServicePrincipal'
  }
}]

// Cosmos DB Built-in Data Contributor for Function Apps (allows MCP servers to read/write Cosmos DB)
// Role ID: 00000000-0000-0000-0000-000000000002 is the Cosmos DB Built-in Data Contributor
// We use the ARM role 'DocumentDB Account Contributor' (5bd9cd88-fe45-4216-938b-f97437e15450) at RG scope
// and additionally the Cosmos DB data-plane RBAC via SQL Role Assignment
resource cosmosDbDataContributorRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for i in range(0, mcpServerCount): {
  name: guid(resourceGroup().id, 'func-${i}', 'cosmos-data-contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5bd9cd88-fe45-4216-938b-f97437e15450') // DocumentDB Account Contributor
    principalId: functionApps.outputs.functionAppPrincipalIds[i]
    principalType: 'ServicePrincipal'
  }
}]

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

// Azure Container Registry
output containerRegistryId string = containerRegistry.outputs.registryId
output containerRegistryName string = containerRegistry.outputs.registryName
output containerRegistryLoginServer string = containerRegistry.outputs.registryLoginServer

// MCP OAuth Configuration
output mcpClientId string = mcpEntraApp.outputs.mcpAppId
output mcpTenantId string = mcpEntraApp.outputs.mcpAppTenantId
output mcpPrmEndpoint string = apimMcpOAuth.outputs.prmEndpoint
output mcpIdentityId string = mcpUserIdentity.outputs.identityId
output mcpIdentityClientId string = mcpUserIdentity.outputs.identityClientId

// MCP Passthrough (Debug)
output mcpPassthroughApiPath string = apimMcpPassthrough.outputs.passthroughApiPath

// AI Foundry
output aiServicesId string = aiFoundry.outputs.aiServicesId
output aiServicesName string = aiFoundry.outputs.aiServicesName
output aiServicesEndpoint string = aiFoundry.outputs.aiServicesEndpoint
output aiProjectId string = aiFoundry.outputs.aiProjectId
output aiProjectName string = aiFoundry.outputs.aiProjectName

// Function Apps
output functionAppNames array = functionApps.outputs.functionAppNames
output mcpServerEndpoints array = functionApps.outputs.mcpServerEndpoints

// Azure Health Data Services
output fhirServiceId string = healthDataServices.outputs.fhirServiceId
output fhirServerUrl string = healthDataServices.outputs.fhirServerUrl
output ahdsWorkspaceName string = healthDataServices.outputs.workspaceName

// Dependent Resources
output storageAccountId string = dependentResources.outputs.storageAccountId
output storageAccountName string = dependentResources.outputs.storageAccountName
output cosmosDbId string = dependentResources.outputs.cosmosDbId
output cosmosDbEndpoint string = dependentResources.outputs.cosmosDbEndpoint
output appInsightsId string = dependentResources.outputs.appInsightsId
output appInsightsConnectionString string = dependentResources.outputs.appInsightsConnectionString

// ============================================================================
// AZD-SPECIFIC OUTPUTS
// These outputs are used by Azure Developer CLI for service discovery
// Format: SERVICE_<service-name-upper>_<property>
// ============================================================================

// APIM Gateway URL for MCP endpoints
output SERVICE_APIM_GATEWAY_URL string = apim.outputs.apimGatewayUrl

// AI Services endpoint
output SERVICE_AI_SERVICES_ENDPOINT string = aiFoundry.outputs.aiServicesEndpoint

// Resource Group name (for azd)
output AZURE_RESOURCE_GROUP string = resourceGroup().name

// Azure Container Registry outputs for azd dockerized service deployment
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.registryName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.registryLoginServer

// Function App resource names for azd service mapping
// Note: azd uses these to find the target resources for deployment
// Output names must match: SERVICE_<service-name-with-underscores>_RESOURCE_NAME
output SERVICE_NPI_LOOKUP_RESOURCE_NAME string = functionApps.outputs.functionAppNames[0]
output SERVICE_ICD10_VALIDATION_RESOURCE_NAME string = functionApps.outputs.functionAppNames[1]
output SERVICE_CMS_COVERAGE_RESOURCE_NAME string = functionApps.outputs.functionAppNames[2]
output SERVICE_FHIR_OPERATIONS_RESOURCE_NAME string = functionApps.outputs.functionAppNames[3]
output SERVICE_PUBMED_RESOURCE_NAME string = functionApps.outputs.functionAppNames[4]
output SERVICE_CLINICAL_TRIALS_RESOURCE_NAME string = functionApps.outputs.functionAppNames[5]
output SERVICE_COSMOS_RAG_RESOURCE_NAME string = functionApps.outputs.functionAppNames[6]
