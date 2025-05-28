# BicepWireGuardNVA

This repo stores a deployment that creates a VNET with an NVA and a WireGuard tunnel NVA.

The deployment provisions all resources for the first time, including:
- User Assigned Managed Identity for the VM
- VNET
- Key Vault and Private Endpoint with Linked Private DNS zone
- Wiregaurd NVA VM
- OS Disk
- NIC
- Public IP
- Startup script to store all information in the Key Vault

The following values are entered and stored in key vault during first deployment. If you already have the Private and Public keys for the WireGuard NVA enter them as well or they will be generated on the first run. 

remoterouter : Home Router's public IP and Wire Guard Port or FQDN:PORT
remoteserverpublickey : Home routers public key
remotenetwork : Home local lan IP range, the network that the NVA is creating a tunnel to
nvainterfaceip : The client IP or IP that your router expects to see as the source of the traffic. This is the wg0 interface IP, it cannot overlap with Azure or Remote Networks and will need to be configured on your router. 

WireGuardNVA-privatekey : Optional, auto-generated automatically by first boot script
WireGuardNVA-publickey : Optional, auto-generated automatically by first boot script

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoftAzureAaron%2FBicepWireGaurdNVA%2Fmain%2FGreenField.json)

---

Deploy the WireGuard NVA VM (assuming all other resources still exist):

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoftAzureAaron%2FBicepWireGaurdNVA%2Fmain%2FBrownField.json)


---

Deploy the WireGuard NVA VM with a new disk(assuming all other resources still exist):

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FMicrosoftAzureAaron%2FBicepWireGaurdNVA%2Fmain%2FPurpleField.json)
