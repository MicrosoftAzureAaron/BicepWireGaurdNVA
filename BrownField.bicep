@description('Select the VM SKU')
param vmSku string = 'Standard_F2as_v6'

@description('Name of the VM')
param vmName string = 'WireGuardNVA'

@description('Name of the Key Vault containing the secrets')
param keyVaultName string

@description('Name of the secret for the admin username')
param adminUsernameSecretName string = 'AdminUsername'

@description('Name of the secret for the admin password')
param adminPasswordSecretName string = 'AdminPassword'

// Get the admin username from Key Vault (secure)
var adminUsername = reference(format('/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.KeyVault/vaults/{2}', subscription().subscriptionId, resourceGroup().name, keyVaultName), '2019-09-01').properties.secrets[adminUsernameSecretName].value

// Get the admin password from Key Vault (secure)
var adminPassword = reference(format('/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.KeyVault/vaults/{2}', subscription().subscriptionId, resourceGroup().name, keyVaultName), '2019-09-01', 'Full').properties.secrets[adminPasswordSecretName].value

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

// Deploy VM using existing NIC and OS disk
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
    storageProfile: {
      imageReference: ubuntuImage
      osDisk: {
      createOption: 'FromImage'
      managedDisk: {
        storageAccountType: 'Standard_LRS'
      }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
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
