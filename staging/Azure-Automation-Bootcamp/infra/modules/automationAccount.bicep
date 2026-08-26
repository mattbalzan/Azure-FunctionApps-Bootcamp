@description('Name of the Automation Account.')
param automationAccountName string

@description('Azure region for the Automation Account.')
param location string

@description('Resource ID of the Log Analytics workspace that receives JobLogs and JobStreams.')
param logAnalyticsWorkspaceId string

@description('Import the demo runbooks from GitHub.')
param deployRunbooks bool = true

@description('Raw GitHub base URL the runbook content is pulled from.')
param runbookSourceBaseUri string

@description('Create a daily schedule and link it to the start/stop VM runbook.')
param deploySchedule bool = true

@description('Schedule start time. Must be at least 5 minutes in the future.')
param scheduleStartTime string

@description('Create an empty Hybrid Runbook Worker group.')
param deployHybridWorkerGroup bool = false

@description('Tags applied to all resources.')
param tags object = {}

var runbooks = [
  {
    name: '01-Demo-HelloWorld-Runbook'
    description: 'Smoke test - proves a new Automation Account runs jobs'
    file: '01-Demo-HelloWorld-Runbook.ps1'
  }
  {
    name: '02-Demo-ManagedIdentity-StartStopVMs'
    description: 'Start/stop VMs by tag using the System-Assigned Managed Identity'
    file: '02-Demo-ManagedIdentity-StartStopVMs.ps1'
  }
  {
    name: '03-Demo-Webhook-Runbook'
    description: 'Runbook that receives and parses a webhook payload'
    file: '03-Demo-Webhook-Runbook.ps1'
  }
  {
    name: '05-Demo-HybridWorker-Runbook'
    description: 'Inventory + internal connectivity test, run on a Hybrid Worker'
    file: '05-Demo-HybridWorker-Runbook.ps1'
  }
]

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    publicNetworkAccess: true
    disableLocalAuth: false
    encryption: {
      keySource: 'Microsoft.Automation'
    }
  }
}

resource automationRunbooks 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = [for runbook in runbooks: if (deployRunbooks) {
  parent: automationAccount
  name: runbook.name
  location: location
  tags: tags
  properties: {
    runbookType: 'PowerShell72'
    logProgress: true
    logVerbose: false
    description: runbook.description
    publishContentLink: {
      uri: '${runbookSourceBaseUri}/${runbook.file}'
    }
  }
}]

resource dailySchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = if (deploySchedule) {
  parent: automationAccount
  name: 'sch-daily-startstop'
  properties: {
    description: 'Daily trigger for the start/stop VM demo'
    startTime: scheduleStartTime
    frequency: 'Day'
    interval: 1
    timeZone: 'Europe/London'
  }
}

// The job schedule name must be a GUID, and it must be deterministic or every
// redeploy creates a duplicate link.
resource jobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = if (deploySchedule && deployRunbooks) {
  parent: automationAccount
  name: guid(automationAccount.id, 'sch-daily-startstop', '02-Demo-ManagedIdentity-StartStopVMs')
  properties: {
    runbook: {
      name: '02-Demo-ManagedIdentity-StartStopVMs'
    }
    schedule: {
      name: 'sch-daily-startstop'
    }
  }
  dependsOn: [
    automationRunbooks
    dailySchedule
  ]
}

resource hybridWorkerGroup 'Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups@2023-11-01' = if (deployHybridWorkerGroup) {
  parent: automationAccount
  name: 'hwg-onprem'
  properties: {}
}

// Nothing appears in AzureDiagnostics - and the workbook stays empty - until
// these categories are streaming to the workspace.
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: automationAccount
  name: 'diag-automation-to-law'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'JobLogs'
        enabled: true
      }
      {
        // The bulk of the ingestion bill. Disable if cost bites - you only lose
        // the error-message tile in the workbook.
        category: 'JobStreams'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output automationAccountId string = automationAccount.id
output automationAccountName string = automationAccount.name
output principalId string = automationAccount.identity.principalId
