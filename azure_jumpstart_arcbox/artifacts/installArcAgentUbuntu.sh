#!/bin/sh

# Block Azure IMDS
sudo ufw --force enable
sudo ufw deny out from any to 169.254.169.254
sudo ufw default allow incoming

# Download the installation package
wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh # 2>/dev/null

# Install the hybrid agent
bash ~/install_linux_azcmagent.sh # 2>/dev/null

ArcServerResourceName=$(hostname |sed -e "s/\b\(.\)/\u\1/g")

# Run connect command
azcmagent connect --access-token $accessToken --resource-group $resourceGroup --tenant-id $tenantId --location $Azurelocation --subscription-id $subscriptionId --resource-name "${ArcServerResourceName}" --cloud "AzureCloud" --correlation-id "d009f5dd-dba8-4ac7-bac9-b54ef3a6671a"
