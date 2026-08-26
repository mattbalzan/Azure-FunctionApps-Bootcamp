using 'main.bicep'

param baseName = 'funcbootcamp'
param location = 'uksouth'

// ElasticPremium (EP1) is the minimum for Regional VNet Integration.
// Switch to 'Consumption' for the cheap public-only lab - private networking
// is automatically skipped because Y1 cannot support it.
param planType = 'ElasticPremium'
param planSkuName = 'EP1'

// The whole point of docs/Storage-Private-Endpoints.md.
param enablePrivateNetworking = true

// Leave false on Windows Elastic Premium: WEBSITE_CONTENTAZUREFILECONNECTIONSTRING
// still requires an account key. Set true only on Flex Consumption or a Linux
// plan using WEBSITE_RUN_FROM_PACKAGE.
param disableSharedKeyAccess = false

// Needed only for 02-Demo-ManagedIdentity-StartStopVMs.ps1.
param grantVmContributor = false

param vnetAddressPrefix = '10.20.0.0/16'
param integrationSubnetPrefix = '10.20.1.0/24'
param privateEndpointSubnetPrefix = '10.20.2.0/24'

param tags = {
  workload: 'functionapps-bootcamp'
  managedBy: 'bicep'
  environment: 'lab'
}
