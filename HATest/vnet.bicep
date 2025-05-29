@description('Name of the Virtual Network')
var vnetName = 'HaTest'

@description('Azure Address space for the Virtual Network')
param vnetAddressSpace string = '100.127.0.0/24'

@description('Subnet name')
var subnetName = 'WGNVA'

@description('Subnet address prefix')
param subnetAddressPrefix string = '100.127.0.0/24'
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: '${vnetName}-pip'
  location: resourceGroup().location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource lb 'Microsoft.Network/loadBalancers@2023-04-01' = {
  name: '${vnetName}-ext-lb'
  location: resourceGroup().location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerFrontEnd'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'LoadBalancerBackEnd'
      }
    ]
    loadBalancingRules: []
    probes: []
  }
}
