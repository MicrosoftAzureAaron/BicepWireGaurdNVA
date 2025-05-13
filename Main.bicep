@description('Name of the Virtual Network')
param vnetName string = 'WGNVA-VNet'

@description('Address space for the Virtual Network')
param vnetAddressSpace string = '100.127.0.0/16'

@description('Subnet name')
param subnetName string = 'WGNVA'

@description('Subnet address prefix')
param subnetAddressPrefix string = '100.127.0.0/24'

@description('Name of the Key Vault')
param keyVaultName string = 'myWGNVAKeyVault'

@description('Name of the secret to store the admin password')
param adminPasswordSecretName string = 'adminPasswordSecret'

@description('Admin username for the Virtual Machine')
param adminUsername string = 'azureuser'

@description('Select the VM SKU')
param vmSku string = 'Standard_B1s'

@description('Name of the Virtual Machine')
param vmName string = 'WireGuardNVA'

@description('Ubuntu 24.04 LTS image reference')
var ubuntuImage = {
  publisher: 'Canonical'
  offer: '0001-com-ubuntu-server-jammy'
  sku: '24_04-lts-gen2'
  version: 'latest'
}

@description('Randomly generated admin password')
var adminPassword = '${newGuid()}P@ssw0rd!' // Appends a secure suffix to ensure password complexity

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: resourceGroup().location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
  }
}

resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  name: '${keyVault.name}/${adminPasswordSecretName}'
  properties: {
    value: adminPassword
  }
}

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
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-02-01' = {
  name: '${vmName}-nic'
  location: resourceGroup().location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: resourceGroup().location
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
  }
}
