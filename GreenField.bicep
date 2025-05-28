@description('Name of the Virtual Network')
param vnetName string = 'WGNVA-Vet'

@description('Azure Address space for the Virtual Network')
param vnetAddressSpace string = '100.127.0.0/24'

@description('Subnet name')
param subnetName string = 'WGNVA'

@description('Subnet address prefix')
param subnetAddressPrefix string = '100.127.0.0/24'

@description('Name of the existing Key Vault')
param keyVaultName string = 'WireGuardNVAKeyVault'

@description('Admin username for the Virtual Machine')
param adminUsername string = 'azureuser'

@description('Select the VM SKU')
param vmSku string = 'Standard_F2as_v6'

@description('Name of the Virtual Machine')
param vmName string = 'WireGuardNVA'

@description('Remote router IP address')
param remoteRouter string = 'IP:PORT or FQDN:PORT'
// Store the remote router IP in Key Vault
resource remoteRouterSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'remoterouter'
  properties: {
    value: remoteRouter
  }
}

@description('Remote public key')
@secure()
param remoteserverpublickey string = 'Home Routers Public Key'
// Store the remote public key in Key Vault
resource remotePublicKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'remoteserverpublickey'
  properties: {
    value: remoteserverpublickey
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
  name: 'nvaprivatekey'
  properties: {
    value: nvaPrivateKey
  }
}

@description('NVA public key')
param nvaPublicKey string = ''

// Store the NVA public key in Key Vault if provided
resource nvaPublicKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = if (!empty(nvaPublicKey)) {
  parent: keyVault
  name: 'nvapublickey'
  properties: {
    value: nvaPublicKey
  }
}

@description('Name of the secret to store the admin password')
var adminPasswordSecretName = '${vmName}-adminPassword'

@description('Ubuntu 20.04 LTS Gen2 image reference')
var ubuntuImage = {
  publisher: 'canonical'
  offer: '0001-com-ubuntu-server-focal'
  sku: '20_04-lts-gen2'
  version: 'latest'
}

@description('Admin password for the Virtual Machine')
@secure()
param adminPassword string

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
    enableSoftDelete: true
    enablePurgeProtection: true
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

// add resource lock to Key Vault
resource keyVaultDeleteLock 'Microsoft.Authorization/locks@2020-05-01' = {
  name: '${keyVault.name}-delete-lock'
  scope: keyVault
  properties: {
    level: 'CanNotDelete'
    notes: 'Prevents accidental deletion of the Key Vault.'
  }
}

// Create Private DNS Zone for Key Vault
resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}

// Link Private DNS Zone to VNet
resource keyVaultDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: '${keyVaultPrivateDnsZone.name}-link'
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
  name: 'kv-private-endpoint'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: '${vnet.id}/subnets/${subnetName}'
    }
    privateLinkServiceConnections: [
      {
        name: 'kv-private-link'
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
        name: 'kvPrivateEndpointIPConfig'
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

// Create a Key Vault secret to store the admin password
resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault // Simplified syntax using the parent property
  name: adminPasswordSecretName
  properties: {
    value: adminPassword // Store the evaluated value of adminPassword
  }
}

// store the public IP of the VM in Key Vault
resource publicIPSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'nvapublicip'
  properties: {
    value: publicIP.properties.ipAddress
  }
}

// Create a user-assigned managed identity for the VM
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'WireGaurdNVAMI'
  location: resourceGroup().location
}

// Assign Reader role to the user-assigned identity at the resource group scope
resource userAssignedIdentityReaderRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, userAssignedIdentity.name, 'Reader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader role, az cli commands in boot script
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign Key Vault Secrets User role to the user-assigned identity at the Key Vault scope
resource userAssignedIdentitySecretContributorRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(keyVault.id, userAssignedIdentity.name, 'SecretContributor')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets User
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Create a virtual network with a subnet
resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
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
          serviceEndpoints: [
            {
              service: 'Microsoft.KeyVault'
            }
          ]
        }
      }
    ]
  }
}

// Create a network interface for the VM
resource nic 'Microsoft.Network/networkInterfaces@2023-02-01' = {
  name: '${vmName}-nic'
  location: resourceGroup().location
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  dependsOn: [
    keyVaultPrivateEndpoint
    keyVaultDnsZoneVnetLink
  ]
  properties: {
    hardwareProfile: {
      vmSize: vmSku
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: ubuntuImage
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: null // Use a managed storage account
      }
    }
  }
}

// run the custom script extension to install and configure WireGuard
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: vm
  name: 'customScript'
  location: resourceGroup().location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/MicrosoftAzureAaron/BicepWireGaurdNVA/main/firstboot.sh'
      ]
      commandToExecute: 'sudo bash firstboot.sh'
    }
  }
}

// Create a route table route traffic for the home LAN to the WireGuard NVA
resource routeTable 'Microsoft.Network/routeTables@2023-02-01' = {
  name: 'WGRouteTable'
  location: resourceGroup().location
  properties: {
    routes: [
      {
        name: 'HomeLANRoute'
        properties: {
          addressPrefix: '192.168.1.0/24'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: nic.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

// Associate the route table with the subnet
resource subnetRouteTableAssoc 'Microsoft.Network/virtualNetworks/subnets@2023-02-01' = {
  parent: vnet
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    routeTable: {
      id: routeTable.id
    }
  }
}

// Create a public IP address for the VM
resource publicIP 'Microsoft.Network/publicIPAddresses@2023-02-01' = {
  name: '${vmName}-publicIP'
  location: resourceGroup().location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}
