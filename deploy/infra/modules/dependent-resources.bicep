// Standard Dependent Resources Module
// Based on foundry-samples/16-private-network-standard-agent-apim-setup-preview

@description('Azure region for resources')
param location string

@description('Azure region for Cosmos DB (use different region if primary has capacity issues)')
param cosmosDbLocation string = location

@description('Base name for resources')
param baseName string

@description('Enable public network access')
param publicNetworkAccess string = 'Disabled'

@description('Tags to apply to resources')
param tags object = {}

// Determine storage redundancy based on region
// Regions without zone redundancy fallback to GRS
var zrsUnsupportedRegions = [
  'westus'
  'centralus'
  'eastus'
]
var storageRedundancy = contains(zrsUnsupportedRegions, location) ? 'Standard_GRS' : 'Standard_ZRS'

// Storage Account - ensure name is at least 3 chars
var storageBaseName = replace(baseName, '-', '')
var storageSuffix = 'st${uniqueString(resourceGroup().id)}'
var storageAccountName = take('${storageBaseName}${storageSuffix}', 24)

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageRedundancy
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    // Must be Enabled for Function Apps to create file shares during initial deployment
    // Can be locked down after deployment via private endpoints
    publicNetworkAccess: 'Enabled'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Blob service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Unique suffix for globally unique resource names
var uniqueSuffix = uniqueString(resourceGroup().id)

// Cosmos DB Account - name must be globally unique
// Note: cosmosDbLocation allows deploying to a different region if primary has capacity issues
// Zone redundancy disabled by default for better availability (demo/dev scenarios)
resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: '${baseName}-cosmos-${uniqueSuffix}'
  location: cosmosDbLocation
  tags: tags
  kind: 'GlobalDocumentDB'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: cosmosDbLocation
        failoverPriority: 0
        isZoneRedundant: false // Disabled for better regional availability
      }
    ]
    publicNetworkAccess: publicNetworkAccess
    networkAclBypass: 'AzureServices'
    networkAclBypassResourceIds: []
    isVirtualNetworkFilterEnabled: true
    virtualNetworkRules: []
    ipRules: []
    capabilities: [
      {
        name: 'EnableServerless'
      }
      {
        name: 'EnableNoSQLVectorSearch'
      }
      {
        name: 'EnableNoSQLFullTextSearch'
      }
    ]
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
  }
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosDb
  name: 'healthcare-mcp'
  properties: {
    resource: {
      id: 'healthcare-mcp'
    }
  }
}

// Container for MCP session state
resource mcpSessionContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDatabase
  name: 'mcp-sessions'
  properties: {
    resource: {
      id: 'mcp-sessions'
      partitionKey: {
        paths: [
          '/sessionId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        automatic: true
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
      }
      defaultTtl: 86400 // 24 hours
    }
  }
}

// Container for RAG document corpus — clinical guidelines, payer policies, formularies
// Supports hybrid search via vector (DiskANN) + full-text (BM25) with RRF fusion
resource documentsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDatabase
  name: 'documents'
  properties: {
    resource: {
      id: 'documents'
      partitionKey: {
        paths: [
          '/category'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        automatic: true
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/embedding/*'
          }
        ]
        fullTextIndexes: [
          {
            path: '/content'
          }
        ]
        vectorIndexes: [
          {
            path: '/embedding'
            type: 'diskANN'
          }
        ]
      }
      vectorEmbeddingPolicy: {
        vectorEmbeddings: [
          {
            path: '/embedding'
            dataType: 'float32'
            dimensions: 3072
            distanceFunction: 'cosine'
          }
        ]
      }
      fullTextPolicy: {
        defaultLanguage: 'en-US'
        fullTextPaths: [
          {
            path: '/content'
            language: 'en-US'
          }
        ]
      }
    }
  }
}

// Container for audit trail — immutable log of all agent actions and decisions
// No TTL — compliance requirement for healthcare auditability
resource auditTrailContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDatabase
  name: 'audit-trail'
  properties: {
    resource: {
      id: 'audit-trail'
      partitionKey: {
        paths: [
          '/workflowId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        automatic: true
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        compositeIndexes: [
          [
            {
              path: '/workflowId'
              order: 'ascending'
            }
            {
              path: '/timestamp'
              order: 'ascending'
            }
          ]
          [
            {
              path: '/workflowType'
              order: 'ascending'
            }
            {
              path: '/timestamp'
              order: 'descending'
            }
          ]
        ]
      }
    }
  }
}

// Container for agent memory — short-term session context + long-term accumulated knowledge
// Supports semantic search over past cases via vector index
resource agentMemoryContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDatabase
  name: 'agent-memory'
  properties: {
    resource: {
      id: 'agent-memory'
      partitionKey: {
        paths: [
          '/agentId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        automatic: true
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/embedding/*'
          }
        ]
        vectorIndexes: [
          {
            path: '/embedding'
            type: 'diskANN'
          }
        ]
      }
      vectorEmbeddingPolicy: {
        vectorEmbeddings: [
          {
            path: '/embedding'
            dataType: 'float32'
            dimensions: 3072
            distanceFunction: 'cosine'
          }
        ]
      }
      defaultTtl: -1 // No expiry by default; individual items can set TTL
    }
  }
}

// Application Insights (workspace-based)
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${baseName}-insights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    RetentionInDays: 90
  }
}

// Log Analytics Workspace (required for App Insights)
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${baseName}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Link App Insights to Log Analytics
resource appInsightsDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diagnostics'
  scope: appInsights
  properties: {
    workspaceId: logAnalytics.id
    logs: []
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output cosmosDbId string = cosmosDb.id
output cosmosDbName string = cosmosDb.name
output cosmosDbEndpoint string = cosmosDb.properties.documentEndpoint
output cosmosDbPrincipalId string = cosmosDb.identity.principalId
output appInsightsId string = appInsights.id
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsId string = logAnalytics.id
