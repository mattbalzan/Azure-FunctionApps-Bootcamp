using 'main.bicep'

param baseName = 'bootcamp'
param location = 'uksouth'

// Runbooks are imported straight from the GitHub raw URLs, so a redeploy always
// pulls the latest published version.
param deployRunbooks = true
param runbookSourceBaseUri = 'https://raw.githubusercontent.com/mattbalzan/Azure-Automation-Bootcamp/main/scripts'

// Daily schedule linked to the start/stop VM runbook.
param deploySchedule = true

// Empty group - register machines afterwards with 07-Setup-HybridWorker.ps1.
param deployHybridWorkerGroup = false

// Needed by 02-Demo-ManagedIdentity-StartStopVMs.ps1.
param grantVmContributor = true

param retentionInDays = 30

param tags = {
  workload: 'automation-bootcamp'
  managedBy: 'bicep'
  environment: 'lab'
}
