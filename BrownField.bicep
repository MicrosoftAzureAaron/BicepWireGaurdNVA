// Bicep template for deploying a WireGuard NVA in an existing Azure environment

@description('Select the VM SKU')
param vmSku string = 'Standard_F2as_v6'

@description('Name of the VM')
param vmName string = 'WireGuardNVA'

@description('Name of the existing Key Vault')
param keyVaultName string = 'WireGuardNVAKeyVault3'

// Reference the existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = {
  name: keyVaultName
}

@description('Admin username for the Virtual Machine')
param adminUsername string = 'azureuser'
// Store the admin username in Key Vault
resource adminUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: '${vmName}AdminUsername'
  properties: {
    value: adminUsername
  }
}

@description('Admin password for the Virtual Machine')
@secure()
param adminPassword string

@description('Name of the secret to store the admin password')
var adminPasswordSecretName = '${vmName}AdminPassword'
// Create a Key Vault secret to store the admin password
resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault // Simplified syntax using the parent property
  name: adminPasswordSecretName
  properties: {
    value: adminPassword // Store the evaluated value of adminPassword
  }
}

@description('Ubuntu 20.04 LTS Gen2 image reference')
var ubuntuImage = {
  publisher: 'canonical'
  offer: '0001-com-ubuntu-server-focal'
  sku: '20_04-lts-gen2'
  version: 'latest'
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'WireGuardNVAMI'
}

// Reference existing NIC from Greenfield deployment
resource nic 'Microsoft.Network/networkInterfaces@2023-02-01' existing = {
  name: '${vmName}-nic'
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

// Custom Script Extension to configure WireGuard
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
