@description('Principal ID of the Function App System-Assigned Managed Identity.')
param principalId string

@description('Name of the storage account to scope the data-plane roles to.')
param storageAccountName string

@description('Name of the Application Insights resource to scope the metrics publisher role to.')
param appInsightsName string

@description('Also grant Virtual Machine Contributor at the resource group scope, for the start/stop VM demo.')
param grantVmContributor bool = false

// Built-in role definition IDs - stable across all clouds.
var roles = {
  storageBlobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  storageQueueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  storageTableDataContributor: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  storageFileDataPrivilegedContributor: '69566ab7-960f-475b-8e7c-b3118f30c6bd'
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  monitoringMetricsPublisher: '3913510d-42f4-4e42-8a64-420c390055eb'
  virtualMachineContributor: '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'
}

var storageRoleIds = [
  roles.storageBlobDataOwner
  roles.storageQueueDataContributor
  roles.storageTableDataContributor
  roles.storageFileDataPrivilegedContributor
  roles.reader
]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource storageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in storageRoleIds: {
  scope: storageAccount
  name: guid(storageAccount.id, principalId, roleId)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
  }
}]

resource appInsightsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: appInsights
  name: guid(appInsights.id, principalId, roles.monitoringMetricsPublisher)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.monitoringMetricsPublisher)
  }
}

resource vmContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantVmContributor) {
  name: guid(resourceGroup().id, principalId, roles.virtualMachineContributor)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.virtualMachineContributor)
  }
}
