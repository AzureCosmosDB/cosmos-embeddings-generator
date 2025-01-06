targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention.')
param environmentName string

@minLength(1)
@allowed([
  'canadaeast'
  'eastus'
  'eastus2'
  'francecentral'
  'japaneast'
  'norwayeast'
  'polandcentral'
  'southindia'
  'swedencentral'
  'switzerlandnorth'
  'westus3'
])
@description('Primary location for all resources.')
param location string

@description('User Id of the principal to assign database and application roles.')
param principalId string = ''

// serviceName is used as value for the tag (azd-service-name) azd uses to identify deployment host
param serviceName string = 'embedding-generator'


// Optional parameters
param functionAccountName string = ''
param functionAppPlanName string = ''
param openAiAccountName string = ''
param cosmosDbAccountName string = ''
param storageAccountName string = ''
param userAssignedIdentityName string = ''


var abbreviations = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-service-name': serviceName
  'azd-env-name': environmentName
  repo: 'https://github.com/AzureCosmosDB/cosmos-embeddings-generator'
}
var deploymentStorageContainerName = 'app-package-container'


var cosmosSettings = {
  database: 'embeddings-generator-db'
  container: 'customer'
  partitionKey: 'customerId'
  vectorProperty: 'vectors'
  hashProperty: 'hash'
  PropertyToEmbed: 'text'
}

var openAiSettings = {
  embeddingModelName: 'text-embedding-3-small'
  embeddingDeploymentName: 'text-3-small'
  dimensions: '1536'
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: environmentName
  location: location
  tags: tags
}

module identity 'app/identity.bicep' = {
  name: 'identity'
  scope: resourceGroup
  params: {
    identityName: !empty(userAssignedIdentityName) ? userAssignedIdentityName : '${abbreviations.userAssignedIdentity}-${resourceToken}'
    location: location
    tags: tags
  }
}

module ai 'app/ai.bicep' = {
  name: 'ai'
  scope: resourceGroup
  params: {
    accountName: !empty(openAiAccountName) ? openAiAccountName : '${abbreviations.openAiAccount}-${resourceToken}'
    location: location
    embeddingsModelName: openAiSettings.embeddingModelName
    embeddingsDeploymentName: openAiSettings.embeddingDeploymentName
    tags: tags
  }
}

// Backing storage for Azure functions backend processor
module storage 'core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: resourceGroup
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbreviations.storageAccount}${resourceToken}'
    location: location
    tags: tags
    containers: [
      {name: deploymentStorageContainerName}
     ]
  }
}

module functions 'app/functions.bicep' = {
  name: 'functions'
  scope: resourceGroup
  params: {
    name: !empty(functionAccountName) ? functionAccountName : '${abbreviations.functionApp}-${resourceToken}'
    location: location
    tags: tags
    planName: !empty(functionAppPlanName) ? functionAppPlanName : '${abbreviations.appServicePlan}-${resourceToken}'
    runtimeName: 'dotnet-isolated'
    runtimeVersion: '8.0'
    storageAccountName: storage.outputs.name
    deploymentStorageContainerName: deploymentStorageContainerName
    identityId: identity.outputs.resourceId
    identityClientId: identity.outputs.clientId
    appSettings: {
      COSMOS_DATABASE_NAME: cosmosSettings.database
      COSMOS_CONTAINER_NAME: cosmosSettings.container
      COSMOS_VECTOR_PROPERTY: cosmosSettings.vectorProperty
      COSMOS_HASH_PROPERTY: cosmosSettings.hashProperty
      COSMOS_PROPERTY_TO_EMBED: cosmosSettings.PropertyToEmbed
      COSMOS_CONNECTION__accountEndpoint: database.outputs.endpoint
      OPENAI_ENDPOINT: ai.outputs.endpoint
      OPENAI_KEY: ai.outputs.key
      OPENAI_DEPLOYMENT_NAME: openAiSettings.embeddingDeploymentName
      OPENAI_DIMENSIONS: openAiSettings.dimensions
    }
    aiServiceUrl: ai.outputs.endpoint
  }
}

module database 'app/database.bicep' = {
  name: 'database'
  scope: resourceGroup
  params: {
    accountName: !empty(cosmosDbAccountName) ? cosmosDbAccountName : '${abbreviations.cosmosDbAccount}-${resourceToken}'
    location: location
    tags: tags
    databaseName: cosmosSettings.database
    containerName: cosmosSettings.container
    partitionKeyName: cosmosSettings.partitionKey
    vectorPropertyName: cosmosSettings.vectorProperty
  }
}

module security 'app/security.bicep' = {
  name: 'security'
  scope: resourceGroup
  params: {
    databaseAccountName: database.outputs.accountName
    storageAccountName: storage.outputs.name
    appPrincipalId: identity.outputs.principalId
    userPrincipalId: !empty(principalId) ? principalId : null
  }
}

output COSMOS_CONNECTION__accountEndpoint string = database.outputs.endpoint
output COSMOS_DATABASE_NAME string = cosmosSettings.database
output COSMOS_CONTAINER_NAME string = cosmosSettings.container
output COSMOS_VECTOR_PROPERTY string = cosmosSettings.vectorProperty
output COSMOS_HASH_PROPERTY string = cosmosSettings.hashProperty
output COSMOS_PROPERTY_TO_EMBED string = cosmosSettings.PropertyToEmbed
output OPENAI_ENDPOINT string = ai.outputs.endpoint
output OPENAI_DEPLOYMENT_NAME string = openAiSettings.embeddingDeploymentName
output OPENAI_DIMENSIONS string = openAiSettings.dimensions
