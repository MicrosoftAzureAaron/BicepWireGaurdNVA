@description('Name of the Virtual Network')
var vnetName = 'WGNVA-VNet'

@description('Address space for the Virtual Network')
var vnetAddressSpace = '100.127.0.0/24'

@description('Subnet name')
var subnetName = 'WGNVA'

@description('Subnet address prefix')
var subnetAddressPrefix  = '100.127.0.0/24'

@description('Name of the existing Key Vault')
param keyVaultName string = 'Vault-o-Secrets'

@description('Admin username for the Virtual Machine')
param adminUsername string = 'azureuser'

@description('Select the VM SKU')
param vmSku string = 'Standard_F2as_v6'

@description('Name of the Virtual Machine')
param vmName string = 'WireGuardNVA'

@description('Name of the secret to store the admin password')
var adminPasswordSecretName = vmName

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

// Reference the existing Key Vault and set access policy for the VM's managed identity
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

// Create a Key Vault secret to store the admin password
resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault // Simplified syntax using the parent property
  name: adminPasswordSecretName
  properties: {
    value: adminPassword // Store the evaluated value of adminPassword
  }
}

resource publicIPSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'NVAPublicIP'
  properties: {
    value: publicIP.properties.ipAddress
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

//create the NVA VM
resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned' // Enable system-assigned managed identity
  }
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

// needed to read the KVs in subscription
resource vmReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, vmName, 'Reader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader role
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// needed to write the secret to the KV
resource vmSecretContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(keyVault.id, vmName, 'SecretContributor')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets User
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
