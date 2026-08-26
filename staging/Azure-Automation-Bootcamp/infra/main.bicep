/*
  Azure Automation Bootcamp - Infrastructure as Code

  Deploys the lab that scripts/06-Setup-AutomationAccount.ps1 builds imperatively:
  an Automation Account with a System-Assigned Managed Identity, a Log Analytics
  workspace, diagnostic settings streaming JobLogs/JobStreams (which the
  Runbook-Monitoring workbook depends on), the demo runbooks, a schedule, and
  least-privilege RBAC.

  Deploy:
    az group create -n rg-automation-bootcamp -l uksouth
    az deployment group create -g rg-automation-bootcamp -f infra/main.bicep -p infra/main.bicepparam
*/

targetScope = 'resourceGroup'

@description('Base name used to derive all resource names.')
@minLength(3)
@maxLength(16)
param baseName string = 'bootcamp'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Import the demo runbooks straight from GitHub.')
param deployRunbooks bool = true

@description('Raw GitHub base URL the runbook content is pulled from.')
param runbookSourceBaseUri string = 'https://raw.githubusercontent.com/mattbalzan/Azure-Automation-Bootcamp/main/scripts'

@description('Create a daily schedule and link it to the start/stop VM runbook.')
param deploySchedule bool = true

@description('Schedule start time. Must be at least 5 minutes in the future.')
param scheduleStartTime string = dateTimeAdd(utcNow(), 'PT2H')

@description('Create an empty Hybrid Runbook Worker group ready for machines to be registered into.')
param deployHybridWorkerGroup bool = false

@description('Grant the Automation Account identity Virtual Machine Contributor at resource group scope, for the start/stop VM demo.')
param grantVmContributor bool = true

@description('Retention in days for the Log Analytics workspace.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Tags applied to every resource.')
param tags object = {
  workload: 'automation-bootcamp'
  managedBy: 'bicep'
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  params: {
    baseName: baseName
    location: location
    retentionInDays: retentionInDays
    tags: tags
  }
}

module automation 'modules/automationAccount.bicep' = {
  name: 'deploy-automation'
  params: {
    automationAccountName: 'aa-${baseName}'
    location: location
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsId
    deployRunbooks: deployRunbooks
    runbookSourceBaseUri: runbookSourceBaseUri
    deploySchedule: deploySchedule
    scheduleStartTime: scheduleStartTime
    deployHybridWorkerGroup: deployHybridWorkerGroup
    tags: tags
  }
}

module rbac 'modules/rbac.bicep' = {
  name: 'deploy-rbac'
  params: {
    principalId: automation.outputs.principalId
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsName
    grantVmContributor: grantVmContributor
  }
}

output automationAccountName string = automation.outputs.automationAccountName
output automationPrincipalId string = automation.outputs.principalId
output logAnalyticsName string = monitoring.outputs.logAnalyticsName
output logAnalyticsId string = monitoring.outputs.logAnalyticsId
