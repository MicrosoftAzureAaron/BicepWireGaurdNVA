#!/bin/bash

# Script version (auto-updated by deployment process)
GIT_COMMIT=$(curl -fsSL "https://api.github.com/repos/MicrosoftAzureAaron/BicepWireGaurdNVA/commits?path=update-wg-key.sh&sha=main&per_page=1" | grep '"sha":' | head -n 1 | awk -F '"' '{print $4}')
echo "[update-wg-key.sh] version: $GIT_COMMIT"

RESTART_WG=0
KEYVAULT_NAME="$KEYVAULT_NAME"

# Compare and update private key
VM_PRIVATE_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "nvaprivatekey" --query value -o tsv 2>/dev/null || echo "")
CURRENT_PRIVATE_KEY=$(cat /etc/wireguard/privatekey 2>/dev/null || echo "")
if [[ "$VM_PRIVATE_KEY" != "$CURRENT_PRIVATE_KEY" && -n "$VM_PRIVATE_KEY" ]]; then
    echo "[update-wg-key.sh] Private key changed, updating file and will restart WireGuard."
    echo "$VM_PRIVATE_KEY" | sudo tee /etc/wireguard/privatekey > /dev/null
    sudo chmod 600 /etc/wireguard/privatekey
    RESTART_WG=1
fi

# Compare and update public key
VM_PUBLIC_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "nvapublickey" --query value -o tsv 2>/dev/null || echo "")
CURRENT_PUBLIC_KEY=$(cat /etc/wireguard/publickey 2>/dev/null || echo "")
if [[ "$VM_PUBLIC_KEY" != "$CURRENT_PUBLIC_KEY" && -n "$VM_PUBLIC_KEY" ]]; then
    echo "[update-wg-key.sh] Public key changed, updating file and will restart WireGuard."
    echo "$VM_PUBLIC_KEY" | sudo tee /etc/wireguard/publickey > /dev/null
    sudo chmod 600 /etc/wireguard/publickey
    RESTART_WG=1
fi

# Compare and update remote server public key
SERVER_PUBLIC_KEY=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name 'remoteserverpublickey' --query value -o tsv 2>/dev/null || echo "")
CURRENT_SERVER_KEY=$(cat /etc/wireguard/remoteserverpublickey 2>/dev/null || echo "")
if [[ "$SERVER_PUBLIC_KEY" != "$CURRENT_SERVER_KEY" && -n "$SERVER_PUBLIC_KEY" ]]; then
    echo "[update-wg-key.sh] Remote server public key changed, updating file and will restart WireGuard."
    echo "$SERVER_PUBLIC_KEY" | sudo tee /etc/wireguard/remoteserverpublickey > /dev/null
    sudo chmod 600 /etc/wireguard/remoteserverpublickey
    RESTART_WG=1
fi

if [[ $RESTART_WG -eq 1 ]]; then
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
    echo "[update-wg-key.sh] Restarting WireGuard service due to key changes..."
    sudo systemctl restart wg-quick@wg0
else
    echo "[update-wg-key.sh] No key changes detected. WireGuard service remains running."
fi
echo "[update-wg-key.sh] WireGuard keys checked successfully."

# Check for commit version changes before downloading firstboot.sh
REMOTE_COMMIT=$(curl -fsSL https://api.github.com/repos/MicrosoftAzureAaron/BicepWireGaurdNVA/commits/main | grep '"sha":' | head -n 1 | awk -F '"' '{print $4}')
LOCAL_COMMIT_FILE="/home/azureuser/firstboot.sh.commit"

LOCAL_COMMIT=""
if [[ -f "$LOCAL_COMMIT_FILE" ]]; then
    LOCAL_COMMIT=$(cat "$LOCAL_COMMIT_FILE")
fi

if [[ "$REMOTE_COMMIT" != "$LOCAL_COMMIT" && -n "$REMOTE_COMMIT" ]]; then
    echo "[update-wg-key.sh] New commit detected for firstboot.sh, downloading updated script."
    curl -fsSL -o /home/azureuser/firstboot.sh https://raw.githubusercontent.com/MicrosoftAzureAaron/BicepWireGaurdNVA/refs/heads/main/firstboot.sh
    sudo chown azureuser:azureuser /home/azureuser/firstboot.sh
    sudo chmod 700 /home/azureuser/firstboot.sh
    echo "$REMOTE_COMMIT" > "$LOCAL_COMMIT_FILE"
else
    echo "[update-wg-key.sh] No changes detected for firstboot.sh, skipping download."
fi