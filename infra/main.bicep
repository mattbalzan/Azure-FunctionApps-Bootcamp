/*
  Azure Functions Bootcamp - Infrastructure as Code

  Deploys the full lab. With `enablePrivateNetworking = true` (the default) it
  builds the locked-down reference architecture described in
  docs/Storage-Private-Endpoints.md: a storage account with public network
  access disabled, private endpoints for all four sub-resources, private DNS
  zones, and a Premium Function App with Regional VNet Integration.

  Deploy:
    az group create -n rg-functionapps-bootcamp -l uksouth
    az deployment group create -g rg-functionapps-bootcamp -f infra/main.bicep -p infra/main.bicepparam
*/

targetScope = 'resourceGroup'

@description('Base name used to derive all resource names.')
@minLength(3)
@maxLength(16)
param baseName string = 'funcbootcamp'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Hosting plan. Regional VNet Integration requires ElasticPremium or Dedicated - Consumption (Y1) does not support it.')
@allowed([
  'Consumption'
  'ElasticPremium'
  'Dedicated'
])
param planType string = 'ElasticPremium'

@description('SKU name used when planType is ElasticPremium or Dedicated.')
param planSkuName string = 'EP1'

@description('Master switch. True builds the locked-down topology: VNet, private endpoints, private DNS and VNet integration. False builds the simple public lab.')
param enablePrivateNetworking bool = true

@description('Disable storage account key access entirely. Leave false on Windows Elastic Premium - the content share still requires a key.')
param disableSharedKeyAccess bool = false

@description('Grant the Function App identity Virtual Machine Contributor for the start/stop VM demo.')
param grantVmContributor bool = false

@description('Address space for the virtual network.')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('Address prefix for the delegated integration subnet. /26 minimum - it cannot be resized once integration is active.')
param integrationSubnetPrefix string = '10.20.1.0/24'

@description('Address prefix for the private endpoint subnet.')
param privateEndpointSubnetPrefix string = '10.20.2.0/24'

@description('Tags applied to every resource.')
param tags object = {
  workload: 'functionapps-bootcamp'
  managedBy: 'bicep'
}

var uniqueSuffix = uniqueString(resourceGroup().id)
var functionAppName = 'func-${baseName}-${uniqueSuffix}'
var storageAccountName = take(toLower('st${replace(baseName, '-', '')}${uniqueSuffix}'), 24)

// Consumption cannot do VNet integration, so silently downgrading is safer than
// deploying a topology the app can never actually use.
var privateNetworkingEffective = enablePrivateNetworking && planType != 'Consumption'

module network 'modules/network.bicep' = if (privateNetworkingEffective) {
  name: 'deploy-network'
  params: {
    vnetName: 'vnet-${baseName}'
    location: location
    vnetAddressPrefix: vnetAddressPrefix
    integrationSubnetPrefix: integrationSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'deploy-storage'
  params: {
    storageAccountName: storageAccountName
    location: location
    enablePrivateNetworking: privateNetworkingEffective
    privateEndpointSubnetId: privateNetworkingEffective ? network.outputs.privateEndpointSubnetId : ''
    vnetId: privateNetworkingEffective ? network.outputs.vnetId : ''
    disableSharedKeyAccess: disableSharedKeyAccess
    tags: tags
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  params: {
    baseName: baseName
    location: location
    tags: tags
  }
}

module functionApp 'modules/functionApp.bicep' = {
  name: 'deploy-functionapp'
  params: {
    functionAppName: functionAppName
    location: location
    planType: planType
    planSkuName: planSkuName
    storageAccountName: storage.outputs.storageAccountName
    storageResourceGroup: resourceGroup().name
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    enablePrivateNetworking: privateNetworkingEffective
    integrationSubnetId: privateNetworkingEffective ? network.outputs.integrationSubnetId : ''
    tags: tags
  }
}

module rbac 'modules/rbac.bicep' = {
  name: 'deploy-rbac'
  params: {
    principalId: functionApp.outputs.principalId
    storageAccountName: storage.outputs.storageAccountName
    appInsightsName: monitoring.outputs.appInsightsName
    grantVmContributor: grantVmContributor
  }
}

output functionAppName string = functionApp.outputs.functionAppName
output functionAppUrl string = 'https://${functionApp.outputs.defaultHostName}'
output storageAccountName string = storage.outputs.storageAccountName
output appInsightsName string = monitoring.outputs.appInsightsName
output privateNetworkingEnabled bool = privateNetworkingEffective
output validationEndpoint string = 'https://${functionApp.outputs.defaultHostName}/api/Demo-StorageTest?format=json'
