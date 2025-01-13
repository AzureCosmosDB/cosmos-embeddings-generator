param name string
param location string = resourceGroup().location
param tags object = {}
param applicationInsightsName string = ''
param planName string
param appSettings object = {}
param runtimeName string 
param runtimeVersion string 
param serviceName string
param storageAccountName string
param deploymentStorageContainerName string
param virtualNetworkSubnetId string = ''
param instanceMemoryMB int = 2048
param maximumInstanceCount int = 100
param identityId string = ''
param identityClientId string = ''

var applicationInsightsIdentity = 'ClientId=${identityClientId};Authorization=AAD'

module appServicePlan '../core/host/functions/appserviceplan.bicep' = {
  name: 'appserviceplan'
  params: {
    name: planName
    location: location
    tags: tags
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
  }
}

module function '../core/host/functions/flexconsumption.bicep' = {
  name: '${serviceName}-functions-module'
  params: {
    name: name
    location: location
    tags: union(tags, { 'azd-service-name': serviceName })
    identityType: 'UserAssigned'
    identityId: identityId
    identityClientId: identityClientId
    appSettings: union(appSettings,
      {
        AzureWebJobsStorage__clientId : identityClientId
        APPLICATIONINSIGHTS_AUTHENTICATION_STRING: applicationInsightsIdentity
        AZURE_CLIENT_ID: identityClientId
      })
    applicationInsightsName: applicationInsightsName
    appServicePlanId: appServicePlan.outputs.id
    runtimeName: runtimeName
    runtimeVersion: runtimeVersion
    storageAccountName: storageAccountName
    deploymentStorageContainerName: deploymentStorageContainerName
    instanceMemoryMB: instanceMemoryMB 
    maximumInstanceCount: maximumInstanceCount
  }
}

output SERVICE_API_NAME string = function.outputs.name
output SERVICE_API_URI string = function.outputs.uri
output SERVICE_API_IDENTITY_PRINCIPAL_ID string = function.outputs.identityPrincipalId
