// Azure AI Foundry Module with Private Network Configuration
// Based on foundry-samples/16-private-network-standard-agent-apim-setup-preview

@description('Azure region for resources')
param location string

@description('Name of the AI Services account (hub)')
param aiServicesName string

@description('Name of the AI Project')
param aiProjectName string

@description('Resource ID of the agent subnet for network injection (reserved for future use)')
#disable-next-line no-unused-params
param agentSubnetId string

@description('Resource ID of the Storage Account (reserved for future use)')
#disable-next-line no-unused-params
param storageAccountId string

@description('Resource ID of the AI Search service (reserved for future use)')
#disable-next-line no-unused-params
param aiSearchId string = ''

@description('Enable public network access')
param publicNetworkAccess string = 'Disabled'

@description('SKU for AI Services')
param aiServicesSku string = 'S0'

@description('Model deployments configuration')
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

@description('Tags to apply to resources')
param tags object = {}

// AI Services Account (Hub)
resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: aiServicesName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: aiServicesSku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: aiServicesName
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: []
    }
    disableLocalAuth: false
  }
}

// Model Deployments - deployed sequentially to avoid conflicts
@batchSize(1)
resource deployments 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = [for deployment in modelDeployments: {
  parent: aiServices
  name: deployment.name
  sku: {
    name: 'Standard'
    capacity: deployment.capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: deployment.model
      version: deployment.version
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}]

// AI Project - Using standard properties for now
// Note: Network injection requires preview API - use ARM template or portal for full configuration
resource aiProject 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: aiProjectName
  location: location
  tags: tags
  kind: 'OpenAI'  // Use OpenAI kind for compatibility
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: aiProjectName
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
  dependsOn: [
    aiServices
  ]
}

// Connections are created using Azure ML/AI Foundry portal or CLI
// The connections API requires preview features

output aiServicesId string = aiServices.id
output aiServicesName string = aiServices.name
output aiServicesEndpoint string = aiServices.properties.endpoint
output aiServicesPrincipalId string = aiServices.identity.principalId
output aiProjectId string = aiProject.id
output aiProjectName string = aiProject.name
output aiProjectPrincipalId string = aiProject.identity.principalId
