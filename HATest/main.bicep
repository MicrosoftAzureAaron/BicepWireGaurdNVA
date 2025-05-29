@description('Name of the Virtual Network')
var vnetName = 'HaTest'

@description('Azure Address space for the Virtual Network')
param vnetAddressSpace string = '100.127.0.0/24'

@description('Subnet name')
var subnetName = 'HA-WGNVA'

@description('Subnet address prefix')
param subnetAddressPrefix string = '100.127.0.0/24'

@description('Name of the Key Vault')
param keyVaultName string = 'HATestKeyVault'


@description('Remote router IP address')
param remoteRouter string = 'IP:PORT or FQDN:PORT'
// Store the remote router IP in Key Vault
resource remoteRouterSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'remoteRouter'
  properties: {
    value: remoteRouter
  }
}

@description('Remote public key')
param remoteServerPublicKey string = ''
// Store the remote public key in Key Vault
resource remotePublicKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'remoteServerPublicKey'
  properties: {
    value: remoteServerPublicKey
  }
}

@description('Remote network address prefix')
param remoteNetwork string = '192.168.1.0/24'
// Store the remote network in Key Vault
resource remoteNetworkSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'remoteNetwork'
  properties: {
    value: remoteNetwork
  }
}

@description('NVA interface IP address (client IP in the Unifi router)')
param nvaInterfaceIp string = '192.168.2.7/32'
// Store the NVA interface IP in Key Vault
resource nvaInterfaceIpSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'nvaInterfaceIp'
  properties: {
    value: nvaInterfaceIp
  }
}

@description('NVA private key')
@secure()
param nvaPrivateKey string = ''
// Store the NVA private key in Key Vault if provided
resource nvaPrivateKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = if (!empty(nvaPrivateKey)) {
  parent: keyVault
  name: 'nvaPrivateKey'
  properties: {
    value: nvaPrivateKey
  }
}

@description('NVA public key')
param nvaPublicKey string = ''
// Store the NVA public key in Key Vault if provided
resource nvaPublicKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = if (!empty(nvaPublicKey)) {
  parent: keyVault
  name: 'nvaPublicKey'
  properties: {
    value: nvaPublicKey
  }
}

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

resource elb 'Microsoft.Network/loadBalancers@2023-04-01' = {
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

resource iLb 'Microsoft.Network/loadBalancers@2023-04-01' = {
  name: '${vnetName}-int-lb'
  location: resourceGroup().location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'InternalLoadBalancerFrontEnd'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/${subnetName}'
          }
          privateIPAddress: '100.127.0.253'
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'InternalLoadBalancerBackEnd'
      }
    ]
    loadBalancingRules: []
    probes: []
  }
}

// Deploy a new Key Vault and set access policy for the VM's managed identity
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: resourceGroup().location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    enabledForDeployment: true // Enable for ARM deployment
    enabledForTemplateDeployment: true // Enable for ARM template deployment
    enabledForDiskEncryption: false // Optional, set true if needed for disk encryption
  }
}

// Create Private DNS Zone for Key Vault
resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}

// Link Private DNS Zone to VNet
resource keyVaultDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${keyVaultPrivateDnsZone.name}Link'
  parent: keyVaultPrivateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// Create Private Endpoint to reference the DNS Zone
resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-02-01' = {
  name: 'kvPrivateEndpoint'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: '${vnet.id}/subnets/${subnetName}'
    }
    privateLinkServiceConnections: [
      {
        name: 'kvPrivateLink'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
    ipConfigurations: [
      {
        name: 'kvPrivateEndpointIpConfig'
        properties: {
          privateIPAddress: '100.127.0.254'
          groupId: 'vault'
          memberName: 'default'
        }
      }
    ]
  }
}

// DNS Zone Group for Private Endpoint
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-11-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'keyVaultDnsConfig'
        properties: {
          privateDnsZoneId: keyVaultPrivateDnsZone.id
        }
      }
    ]
  }
}

// Create a user-assigned managed identity for the VM
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'WireGuardNVAMI'
  location: resourceGroup().location
}

// Assign Reader role to the user-assigned identity at the resource group scope
resource userAssignedIdentityReaderRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, userAssignedIdentity.name, 'Reader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'acdd72a7-3385-48ef-bd42-f606fba81ae7'
    ) // Reader role, az cli commands in boot script
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign Key Vault Secrets User role to the user-assigned identity at the Key Vault scope
resource userAssignedIdentitySecretContributorRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(keyVault.id, userAssignedIdentity.name, 'SecretContributor')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
    ) // Key Vault Secrets User
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign Key Vault Administrator role to the user-assigned identity at the Key Vault scope
@description('Your objectId or service principal to assign as Key Vault Administrator')
param keyVaultAdminObjectId string

resource keyVaultAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(keyVault.id, 'KeyVaultAdmin')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '00482a5a-887f-4fb3-b363-3b7fe8e74483' // Key Vault Administrator
    )
    principalId: keyVaultAdminObjectId
    principalType: 'User'
  }
}
