@description('Name of the storage account. Must be globally unique, 3-24 lowercase alphanumeric characters.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Azure region for the storage account.')
param location string

@description('When true, creates private endpoints + private DNS zones and seals the public endpoint.')
param enablePrivateNetworking bool = true

@description('Resource ID of the undelegated subnet that will host the private endpoint NICs. Required when enablePrivateNetworking is true.')
param privateEndpointSubnetId string = ''

@description('Resource ID of the VNet the private DNS zones are linked to. Required when enablePrivateNetworking is true.')
param vnetId string = ''

@description('Disable shared key (account key) access, forcing all data-plane calls through Entra ID.')
param disableSharedKeyAccess bool = false

@description('Tags applied to all resources.')
param tags object = {}

// All four sub-resources are required. Creating only 'blob' is the single most
// common mistake - the Functions runtime will not start without 'file'.
var storageServices = [
  'blob'
  'file'
  'queue'
  'table'
]

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: !disableSharedKeyAccess
    publicNetworkAccess: enablePrivateNetworking ? 'Disabled' : 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: enablePrivateNetworking ? 'Deny' : 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
  }
}

resource privateEndpoints 'Microsoft.Network/privateEndpoints@2023-11-01' = [for service in storageServices: if (enablePrivateNetworking) {
  name: 'pe-${storageAccountName}-${service}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${storageAccountName}-${service}'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            service
          ]
        }
      }
    ]
  }
}]

// A private endpoint gives you a private IP. Without these zones, the storage
// hostname still resolves publicly and the private path is never used.
resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for service in storageServices: if (enablePrivateNetworking) {
  name: 'privatelink.${service}.${environment().suffixes.storage}'
  location: 'global'
  tags: tags
}]

resource privateDnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (service, i) in storageServices: if (enablePrivateNetworking) {
  parent: privateDnsZones[i]
  name: 'link-to-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}]

resource privateDnsZoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = [for (service, i) in storageServices: if (enablePrivateNetworking) {
  parent: privateEndpoints[i]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config-${service}'
        properties: {
          privateDnsZoneId: privateDnsZones[i].id
        }
      }
    ]
  }
}]

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
