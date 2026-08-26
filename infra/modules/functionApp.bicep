@description('Name of the Function App. Must be globally unique.')
param functionAppName string

@description('Azure region for the Function App and its plan.')
param location string

@description('Hosting plan. Regional VNet Integration requires ElasticPremium or Dedicated - Consumption (Y1) does not support it.')
@allowed([
  'Consumption'
  'ElasticPremium'
  'Dedicated'
])
param planType string = 'ElasticPremium'

@description('SKU name used when planType is ElasticPremium or Dedicated.')
param planSkuName string = 'EP1'

@description('Name of the storage account backing the Function App.')
param storageAccountName string

@description('Resource group of the storage account, surfaced to the validation function for control-plane assertions.')
param storageResourceGroup string = resourceGroup().name

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Enable Regional VNet Integration and route all outbound traffic through the VNet.')
param enablePrivateNetworking bool = true

@description('Resource ID of the delegated integration subnet. Required when enablePrivateNetworking is true.')
param integrationSubnetId string = ''

@description('Tags applied to all resources.')
param tags object = {}

var isConsumption = planType == 'Consumption'
var contentShareName = toLower('${functionAppName}-content')

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-${functionAppName}'
  location: location
  tags: tags
  sku: {
    name: isConsumption ? 'Y1' : planSkuName
    tier: isConsumption ? 'Dynamic' : (planType == 'ElasticPremium' ? 'ElasticPremium' : 'Standard')
  }
  properties: {
    maximumElasticWorkerCount: planType == 'ElasticPremium' ? 20 : null
  }
}

var baseAppSettings = [
  {
    name: 'FUNCTIONS_EXTENSION_VERSION'
    value: '~4'
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: 'powershell'
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
  {
    name: 'AzureWebJobsStorage'
    value: storageConnectionString
  }
  {
    name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
    value: storageConnectionString
  }
  {
    name: 'WEBSITE_CONTENTSHARE'
    value: contentShareName
  }
  // Consumed by 08-Demo-StorageTest.ps1 for the validation run.
  {
    name: 'STORAGE_ACCOUNT_NAME'
    value: storageAccountName
  }
  {
    name: 'STORAGE_RESOURCE_GROUP'
    value: storageResourceGroup
  }
]

// WEBSITE_CONTENTOVERVNET is the setting people miss - without it the platform
// still tries to mount the content share over the public endpoint and the app
// starts with no functions in it.
var privateNetworkingSettings = [
  {
    name: 'WEBSITE_VNET_ROUTE_ALL'
    value: '1'
  }
  {
    name: 'WEBSITE_CONTENTOVERVNET'
    value: '1'
  }
]

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    virtualNetworkSubnetId: (enablePrivateNetworking && !isConsumption) ? integrationSubnetId : null
    vnetContentShareEnabled: enablePrivateNetworking && !isConsumption
    vnetRouteAllEnabled: enablePrivateNetworking && !isConsumption
    siteConfig: {
      powerShellVersion: '7.2'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: (enablePrivateNetworking && !isConsumption)
        ? concat(baseAppSettings, privateNetworkingSettings)
        : baseAppSettings
    }
  }
}

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output principalId string = functionApp.identity.principalId
output defaultHostName string = functionApp.properties.defaultHostName
