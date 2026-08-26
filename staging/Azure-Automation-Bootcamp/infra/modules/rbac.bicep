@description('Principal ID of the Automation Account System-Assigned Managed Identity.')
param principalId string

@description('Name of the Log Analytics workspace to scope the reader role to.')
param logAnalyticsWorkspaceName string

@description('Grant Virtual Machine Contributor at resource group scope, for the start/stop VM demo.')
param grantVmContributor bool = true

// Built-in role definition IDs - stable across all clouds.
var roles = {
  virtualMachineContributor: '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'
  logAnalyticsReader: '73c42c96-874c-492b-b04d-ab87d138a893'
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource vmContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (grantVmContributor) {
  name: guid(resourceGroup().id, principalId, roles.virtualMachineContributor)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.virtualMachineContributor)
  }
}

// Lets runbooks query their own job telemetry for reporting scenarios.
resource logAnalyticsReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: logAnalytics
  name: guid(logAnalytics.id, principalId, roles.logAnalyticsReader)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.logAnalyticsReader)
  }
}

// Required by 05-Demo-HybridWorker-Runbook.ps1 to enumerate resources.
resource readerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, roles.reader)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.reader)
  }
}
