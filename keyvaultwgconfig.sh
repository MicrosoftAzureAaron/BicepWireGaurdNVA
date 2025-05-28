#!/bin/bash
#current script path
SCRIPT_PATH="$(readlink -f "$0")"

# Script version (auto-updated by deployment process)
GIT_COMMIT=$(curl -fsSL "https://api.github.com/repos/MicrosoftAzureAaron/BicepWireGaurdNVA/commits?path=keyvaultwgconfig.sh&sha=main&per_page=1" | grep '"sha":' | head -n 1 | awk -F '"' '{print $4}')
echo "keyvaultwgconfig.sh version: $GIT_COMMIT"

# Login to Azure CLI using user assigned managed identity, tenant, and subscription
echo "Logging in to Azure CLI with user assigned managed identity..."
AZ_LOGIN_OUTPUT=$(az login --identity --allow-no-subscriptions)
if [[ -z "$AZ_LOGIN_OUTPUT" ]]; then
    echo "ERROR: az login did not return any output. Exiting."
    exit 1
fi

# Get Key Vault info
VM_NAME=$(curl -H "Metadata:true" --noproxy '*' "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
RESOURCE_GROUP=$(curl -H "Metadata:true" --noproxy '*' "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
KEYVAULT_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)

# Check that required variables are not blank or empty
if [[ -z "$VM_NAME" || -z "$RESOURCE_GROUP" || -z "$KEYVAULT_NAME" ]]; then
    echo "ERROR: One or more required variables (VM_NAME, RESOURCE_GROUP, KEYVAULT_NAME) are empty. Exiting."
    exit 1
else
    echo "VM Name: $VM_NAME"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Key Vault Name: $KEYVAULT_NAME"
    echo "Script Path: $SCRIPT_PATH"  
fi

# Try to get the private and public keys from Key Vault
echo "Trying to get the private and public keys from Key Vault..."
NVAPRIVATEKEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "nvaprivatekey" --query value -o tsv 2>/dev/null || echo "")
NVAPUBLICKEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "nvapublickey" --query value -o tsv 2>/dev/null || echo "")

# Check to see if the keys were retrieved successfully
if [[ -n "$NVAPRIVATEKEY" && -n "$NVAPUBLICKEY" ]]; then
    echo "Found existing WireGuard keys in Key Vault. Writing to files..."
    echo "$NVAPRIVATEKEY" | sudo tee /etc/wireguard/privatekey >/dev/null
    sudo chmod 600 /etc/wireguard/privatekey
    echo "$NVAPUBLICKEY" | sudo tee /etc/wireguard/publickey >/dev/null
    sudo chmod 600 /etc/wireguard/publickey
fi

# Output the first 7 characters of both keys for verification
echo "NVAPUBLICKEY (first 7 chars): ${NVAPUBLICKEY:0:7}"
echo "NVAPRIVATEKEY (first 7 chars): ${NVAPRIVATEKEY:0:7}"

# Try to get the server public key from Key Vault
REMOTE_SERVER_PUBLIC_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'remoteserverpublickey' --query value -o tsv 2>/dev/null || echo "")
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to retrieve remoteserverpublickey from Key Vault."
    exit 1
fi

if [[ -n "$REMOTE_SERVER_PUBLIC_KEY" ]]; then
    sudo mkdir -p /etc/wireguard
    echo "$REMOTE_SERVER_PUBLIC_KEY" | sudo tee /etc/wireguard/remoteserverpublickey > /dev/null
    sudo chmod 600 /etc/wireguard/remoteserverpublickey
else
    echo "No remoteserverpublickey found in Key Vault. Please ensure it is set up."
    exit 1
fi

# Try to get the server public key from Key Vault
REMOTE_ROUTER=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'remoterouter' --query value -o tsv 2>/dev/null || echo "")
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to retrieve remoterouter from Key Vault. IP:PORT or FQDN:PORT"
    exit 1
fi

# Validate REMOTE_ROUTER is in IP:PORT or FQDN:PORT format
if ! [[ "$REMOTE_ROUTER" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$ || "$REMOTE_ROUTER" =~ ^([a-zA-Z0-9.-]+):[0-9]{1,5}$ ]]; then
    echo "ERROR: remoterouter value '$REMOTE_ROUTER' is not a valid IP:PORT or FQDN:PORT."
    exit 1
fi

# Try to get the NVA interface IP from Key Vault
NVA_INTERFACE_IP=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'nvainterfaceip' --query value -o tsv 2>/dev/null || echo "")
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to retrieve nvainterfaceip from Key Vault."
    exit 1
fi

# Validate NVA_INTERFACE_IP is in proper IPv4/CIDR format (e.g., 192.168.2.7/32)
if ! [[ "$NVA_INTERFACE_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    echo "ERROR: nvainterfaceip value '$NVA_INTERFACE_IP' is not a valid IPv4/CIDR address."
    exit 1
fi

echo "NVA Interface IP: $NVA_INTERFACE_IP"

# Try to get the remote network from Key Vault
REMOTENETWORK=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'remotenetwork' --query value -o tsv 2>/dev/null || echo "")
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to retrieve remotenetwork from Key Vault."
    exit 1
fi

# Validate REMOTENETWORK is in proper IPv4/CIDR format (e.g., 192.168.1.0/24)
if ! [[ "$REMOTENETWORK" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    echo "ERROR: remotenetwork value '$REMOTENETWORK' is not a valid IPv4/CIDR address."
    exit 1
fi

echo "Remote Network: $REMOTENETWORK"

# Create WireGuard configuration file
echo "Creating WireGuard configuration file..."
sudo bash -c "cat > /etc/wireguard/wg0.conf << EOF
[Interface]
MTU = 1420
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = ${NVA_INTERFACE_IP:-PLACEHOLDER} #tunnel interface
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostUp = sysctl -w net.ipv4.ip_forward=1
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
PostDown = sysctl -w net.ipv4.ip_forward=0

[Peer]
PublicKey = $(cat /etc/wireguard/remoteserverpublickey 2>/dev/null || echo "PLACEHOLDER")
Endpoint = ${REMOTE_ROUTER:-PLACEHOLDER}
AllowedIPs = ${REMOTENETWORK:-PLACEHOLDER}
PersistentKeepalive = 25
EOF"

# Set permissions
sudo chmod 600 /etc/wireguard/wg0.conf

#restart wiregaurd service to apply new keys if it was already running
sudo systemctl restart wg-quick@wg0 