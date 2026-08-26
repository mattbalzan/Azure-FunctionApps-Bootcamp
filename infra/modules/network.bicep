@description('Name of the virtual network.')
param vnetName string

@description('Azure region for the virtual network.')
param location string

@description('Address space for the virtual network.')
param vnetAddressPrefix string = '10.20.0.0/16'

@description('Name of the subnet delegated to Microsoft.Web/serverFarms for Regional VNet Integration.')
param integrationSubnetName string = 'snet-func-integration'

@description('Address prefix for the integration subnet. /26 minimum - it cannot be resized once integration is active.')
param integrationSubnetPrefix string = '10.20.1.0/24'

@description('Name of the undelegated subnet that hosts the private endpoint NICs.')
param privateEndpointSubnetName string = 'snet-private-endpoints'

@description('Address prefix for the private endpoint subnet.')
param privateEndpointSubnetPrefix string = '10.20.2.0/24'

@description('Tags applied to all resources.')
param tags object = {}

resource nsgIntegration 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${integrationSubnetName}'
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        // Delegated to App Service. Cannot host anything else - no VMs, no private endpoints.
        name: integrationSubnetName
        properties: {
          addressPrefix: integrationSubnetPrefix
          networkSecurityGroup: {
            id: nsgIntegration.id
          }
          delegations: [
            {
              name: 'delegation-serverfarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output integrationSubnetId string = '${vnet.id}/subnets/${integrationSubnetName}'
output privateEndpointSubnetId string = '${vnet.id}/subnets/${privateEndpointSubnetName}'
