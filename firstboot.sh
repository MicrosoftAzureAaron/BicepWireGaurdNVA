#!/bin/bash

# Update and upgrade packages
echo "Updating package list..."
sudo apt-get update -y
echo "Upgrading installed packages..."
sudo apt-get upgrade -y

# Install WireGuard
echo "Installing WireGuard..."
sudo apt-get install -y wireguard

# Install Azure CLI for Key Vault access
echo "Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Login to Azure CLI using managed identity
echo "Logging in to Azure CLI with managed identity..."
az login --identity --allow-no-subscriptions

# Get Key Vault info
VM_NAME=$(curl -H "Metadata:true" --noproxy '*' "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
RESOURCE_GROUP=$(curl -H "Metadata:true" --noproxy '*' "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
KEYVAULT_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)

# Try to get the private and public keys from Key Vault
VM_PRIVATE_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-privatekey" --query value -o tsv 2>/dev/null || echo "")
VM_PUBLIC_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-publickey" --query value -o tsv 2>/dev/null || echo "")

if [[ -n "$VM_PRIVATE_KEY" && -n "$VM_PUBLIC_KEY" ]]; then
    echo "Found existing WireGuard keys in Key Vault. Writing to files..."
    echo "$VM_PRIVATE_KEY" | sudo tee /etc/wireguard/privatekey >/dev/null
    sudo chmod 600 /etc/wireguard/privatekey
    echo "$VM_PUBLIC_KEY" | sudo tee /etc/wireguard/publickey >/dev/null
    sudo chmod 600 /etc/wireguard/publickey
else
    # Generate WireGuard keys
    echo "Generating WireGuard keys..."
    wg genkey | sudo tee /etc/wireguard/privatekey >/dev/null
    sudo chmod 600 /etc/wireguard/privatekey
    sudo cat /etc/wireguard/privatekey | wg pubkey | sudo tee /etc/wireguard/publickey >/dev/null
    sudo chmod 600 /etc/wireguard/publickey

    # Store the public key in Azure Key Vault
    VM_PUBLIC_KEY=$(cat /etc/wireguard/publickey)
    if [[ -n "$VM_PUBLIC_KEY" ]]; then
        az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-publickey" --value "$VM_PUBLIC_KEY"
        echo "Stored VM public key in Key Vault."
    fi

    # Store the private key in Azure Key Vault
    VM_PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
    if [[ -n "$VM_PRIVATE_KEY" ]]; then
        az keyvault secret set --vault-name "$KEYVAULT_NAME" --name "${VM_NAME}-privatekey" --value "$VM_PRIVATE_KEY"
        echo "Stored VM private key in Key Vault."
    fi
fi

# Try to get the server public key from Key Vault
REMOTE_SERVER_PUBLIC_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'remoteserverpublickey' --query value -o tsv 2>/dev/null || echo "")
if [[ -n "$REMOTE_SERVER_PUBLIC_KEY" ]]; then
    sudo mkdir -p /etc/wireguard
    echo "$REMOTE_SERVER_PUBLIC_KEY" | sudo tee /etc/wireguard/remoteserverpublickey > /dev/null
    sudo chmod 600 /etc/wireguard/remoteserverpublickey
fi

# Try to get the server public key from Key Vault
REMOTE_ROUTER=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'remoterouter' --query value -o tsv 2>/dev/null || echo "")
if [[ -z "$REMOTE_ROUTER" ]]; then
    echo "No remote server found in Key Vault."
fi

# Create WireGuard configuration file
echo "Creating WireGuard configuration file..."
sudo bash -c "cat > /etc/wireguard/wg0.conf << EOF
[Interface]
MTU = 1420
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = 192.168.2.7/32 #tunnel interface
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostUp = sysctl -w net.ipv4.ip_forward=1
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
PostDown = sysctl -w net.ipv4.ip_forward=0

[Peer]
PublicKey = $(cat /etc/wireguard/remoteserverpublickey 2>/dev/null || echo "PLACEHOLDER")
Endpoint = ${REMOTE_ROUTER:-PLACEHOLDER}
AllowedIPs = 192.168.1.0/24
PersistentKeepalive = 25
EOF"

# Set permissions
sudo chmod 600 /etc/wireguard/wg0.conf

# Enable and start WireGuard
echo "Enabling and starting WireGuard service..."
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Check if WireGuard tunnel is up
echo "Checking WireGuard tunnel status..."
sleep 5
if sudo wg show wg0 > /dev/null 2>&1; then
    echo "WireGuard tunnel wg0 is up and running."
    sudo wg show wg0
else
    echo "WireGuard tunnel wg0 failed to start. Check configuration and logs."
    sudo systemctl status wg-quick@wg0 --no-pager
fi

# Create a cron job to check for the serverpublickey and update the config, only restart the service if key changes
CRON_SCRIPT="/usr/local/bin/update-wg-serverkey.sh"
sudo bash -c "cat > $CRON_SCRIPT << 'EOS'
#!/bin/bash
KEYVAULT_NAME=\"$KEYVAULT_NAME\"
SERVER_PUBLIC_KEY=\$(az keyvault secret show --vault-name \"\$KEYVAULT_NAME\" --name 'remoteserverpublickey' --query value -o tsv 2>/dev/null || echo \"\")
if [[ -n \"\$SERVER_PUBLIC_KEY\" ]]; then
    CURRENT_KEY_FILE=\"/etc/wireguard/remoteserverpublickey\"
    if [[ ! -f \"\$CURRENT_KEY_FILE\" ]] || [[ \"\$SERVER_PUBLIC_KEY\" != \"\$(cat \$CURRENT_KEY_FILE)\" ]]; then
        echo \"\$SERVER_PUBLIC_KEY\" | sudo tee \"\$CURRENT_KEY_FILE\" > /dev/null
        sudo systemctl restart wg-quick@wg0
    fi
fi
EOS"

# Make the script executable
sudo chmod +x $CRON_SCRIPT

# Add cron job to run every 15 minutes
( sudo crontab -l 2>/dev/null; echo "*/15 * * * * $CRON_SCRIPT" ) | sudo crontab -

echo "WireGuard installation and setup complete."

# End of script
# Note: This script assumes that the Azure Key Vault and the secrets are already set up.
# It also assumes that the VM has a managed identity assigned to it.
# Make sure to replace 'remoteserverpublickey' and 'remoterouter' with the actual names of your secrets in Key Vault.
# The script also assumes that the WireGuard interface is named 'wg0'.
# Adjust the IP addresses and network settings as per your requirements.
# The script uses a placeholder for the remote server public key and router address if they are not found in Key Vault.