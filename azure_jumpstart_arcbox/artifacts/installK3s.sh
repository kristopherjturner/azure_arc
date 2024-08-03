#!/bin/bash
exec >installK3s.log
exec 2>&1

sudo apt-get update

sudo sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config
sudo adduser staginguser --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password
sudo echo "staginguser:ArcPassw0rd" | sudo chpasswd

# Injecting environment variables
echo '#!/bin/bash' >> vars.sh
echo $adminUsername:$1 | awk '{print substr($1,2); }' >> vars.sh
echo $subscriptionId:$2 | awk '{print substr($1,2); }' >> vars.sh
echo $vmName:$3 | awk '{print substr($1,2); }' >> vars.sh
echo $location:$4 | awk '{print substr($1,2); }' >> vars.sh
echo $stagingStorageAccountName:$5 | awk '{print substr($1,2); }' >> vars.sh
echo $logAnalyticsWorkspace:$6 | awk '{print substr($1,2); }' >> vars.sh
echo $templateBaseUrl:$7 | awk '{print substr($1,2); }' >> vars.sh
echo $storageContainerName:$8 | awk '{print substr($1,2); }' >> vars.sh
echo $k3sControlPlane:$9 | awk '{print substr($1,2); }' >> vars.sh


sed -i '2s/^/export adminUsername=/' vars.sh
sed -i '3s/^/export subscriptionId=/' vars.sh
sed -i '4s/^/export vmName=/' vars.sh
sed -i '5s/^/export location=/' vars.sh
sed -i '6s/^/export stagingStorageAccountName=/' vars.sh
sed -i '7s/^/export logAnalyticsWorkspace=/' vars.sh
sed -i '8s/^/export templateBaseUrl=/' vars.sh
sed -i '9s/^/export storageContainerName=/' vars.sh
sed -i '10s/^/export k3sControlPlane=/' vars.sh

# Set k3 deployment variables
export K3S_VERSION="1.29.6+k3s2" # Do not change!

chmod +x vars.sh
. ./vars.sh

# Creating login message of the day (motd)
sudo curl -v -o /etc/profile.d/welcomeK3s.sh ${templateBaseUrl}artifacts/welcomeK3s.sh

# Syncing this script log to 'jumpstart_logs' directory for ease of troubleshooting
sudo -u $adminUsername mkdir -p /home/${adminUsername}/jumpstart_logs
while sleep 1; do sudo -s rsync -a /var/lib/waagent/custom-script/download/0/installK3s.log /home/${adminUsername}/jumpstart_logs/installK3s.log; done &

# Downloading azcopy
echo ""
echo "Downloading azcopy"
echo ""
wget -O azcopy.tar.gz https://aka.ms/downloadazcopy-v10-linux
if [[ $? -ne 0 ]]; then
    echo "ERROR: Failed to download azcopy"
    exit 1
fi

tar -xf azcopy.tar.gz
sudo mv azcopy_linux_amd64_*/azcopy /usr/local/bin/azcopy
sudo chmod +x /usr/local/bin/azcopy
# Authorize azcopy by using a system-wide managed identity
export AZCOPY_AUTO_LOGIN_TYPE=MSI

# Installing Azure CLI & Azure Arc extensions
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

echo ""
echo "Log in to Azure"
echo ""
for i in {1..5}; do
    sudo -u $adminUsername az login --identity
    if [[ $? -eq 0 ]]; then
        break
    fi
    sleep 15
    if [[ $i -eq 5 ]]; then
        echo "Error: Failed to login to Azure after 5 retries"
        exit 1
    fi
done

sudo -u $adminUsername az account set --subscription $subscriptionId
az -v

if [[ "$k3sControlPlane" == "true" ]]; then

    # Installing Azure Arc extensions
    echo ""
    echo "Installing Azure Arc extensions"
    echo ""
    sudo -u $adminUsername az extension add --name connectedk8s
    sudo -u $adminUsername az extension add --name k8s-configuration
    sudo -u $adminUsername az extension add --name k8s-extension

    # Installing Rancher K3s cluster (single control plane)
    echo ""
    echo "Installing Rancher K3s cluster"
    echo ""
    publicIp=$(hostname -i)
    sudo mkdir ~/.kube
    sudo -u $adminUsername mkdir /home/${adminUsername}/.kube
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --disable servicelb --node-ip ${publicIp} --node-external-ip ${publicIp} --bind-address ${publicIp} --tls-san ${publicIp}" INSTALL_K3S_VERSION=v${K3S_VERSION} K3S_KUBECONFIG_MODE="644" sh -
    if [[ $? -ne 0 ]]; then
        echo "ERROR: K3s installation failed"
        exit 1
    fi
    # Renaming default context to k3s cluster name
    context=$(echo $storageContainerName | sed 's/-[^-]*$//')
    sudo kubectl config rename-context default $context --kubeconfig /etc/rancher/k3s/k3s.yaml
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo cp /etc/rancher/k3s/k3s.yaml /home/${adminUsername}/.kube/config
    sudo cp /etc/rancher/k3s/k3s.yaml /home/${adminUsername}/.kube/config.staging
    sudo chown -R $adminUsername /home/${adminUsername}/.kube/
    sudo chown -R staginguser /home/${adminUsername}/.kube/config.staging

    # Installing Helm 3
    echo ""
    echo "Installing Helm"
    echo ""
    sudo snap install helm --classic
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Helm installation failed"
        exit 1
    fi

    echo ""
    echo "Making sure Rancher K3s cluster is ready..."
    echo ""
    sudo kubectl wait --for=condition=Available --timeout=60s --all deployments -A >/dev/null
    sudo kubectl get nodes -o wide | expand | awk 'length($0) > length(longest) { longest = $0 } { lines[NR] = $0 } END { gsub(/./, "=", longest); print "/=" longest "=\\"; n = length(longest); for(i = 1; i <= NR; ++i) { printf("| %s %*s\n", lines[i], n - length(lines[i]) + 1, "|"); } print "\\=" longest "=/" }'

    # Copying Rancher K3s kubeconfig file to staging storage account
    echo ""
    echo "Copying Rancher K3s kubeconfig file to staging storage account"
    echo ""
    localPath="/home/$adminUsername/.kube/config"
    k3sClusterNodeConfig="/home/$adminUsername/k3sClusterNodeConfig.yaml"
    echo "k3sNodeToken: $(sudo cat /var/lib/rancher/k3s/server/node-token)" >> $k3sClusterNodeConfig
    echo "k3sClusterIp: $publicIp" >> $k3sClusterNodeConfig
    # Copying kubeconfig file to staging storage account
    azcopy make "https://$stagingStorageAccountName.blob.core.windows.net/$storageContainerName"
    azcopy cp $localPath "https://$stagingStorageAccountName.blob.core.windows.net/$storageContainerName/config"
    azcopy cp $k3sClusterNodeConfig "https://$stagingStorageAccountName.blob.core.windows.net/$storageContainerName/k3sClusterNodeConfig.yaml"

    # Onboard the cluster to Azure Arc
    echo ""
    echo "Onboarding the cluster to Azure Arc"
    echo ""
    resourceGroup=$(sudo -u $adminUsername az resource list --query "[?name=='$stagingStorageAccountName']".[resourceGroup] --resource-type "Microsoft.Storage/storageAccounts" -o tsv)
    workspaceResourceId=$(sudo -u $adminUsername az resource show --resource-group $resourceGroup --name $logAnalyticsWorkspace --resource-type "Microsoft.OperationalInsights/workspaces" --query id -o tsv)
    echo "Log Analytics workspace id $workspaceResourceId"

    sudo -u $adminUsername az connectedk8s connect --name $vmName --resource-group $resourceGroup --location $location
    echo "Onboarding the k3s cluster to Azure Arc completed"
    
    # Verify if cluster is connected to Azure Arc successfully
    connectedClusterInfo=$(sudo -u $adminUsername az connectedk8s show --name $vmName --resource-group $resourceGroup)
    echo "Connected cluster info: $connectedClusterInfo"

    # Wait
    # Enabling Container Insights and Microsoft Defender for Containers cluster extensions
    echo ""
    echo "Enabling Container Insights and Microsoft Defender for Containers cluster extensions"
    echo ""
    sudo -u $adminUsername az k8s-extension create -n "azuremonitor-containers" --cluster-name $vmName --resource-group $resourceGroup --cluster-type connectedClusters --extension-type Microsoft.AzureMonitor.Containers --configuration-settings logAnalyticsWorkspaceResourceID=$workspaceResourceId --only-show-errors
    sudo -u $adminUsername az k8s-extension create -n "azure-defender" --cluster-name $vmName --resource-group $resourceGroup --cluster-type connectedClusters --extension-type Microsoft.AzureDefender.Kubernetes --configuration-settings logAnalyticsWorkspaceResourceID=$workspaceResourceId --only-show-errors

    # Enabling Azure Policy for Kubernetes on the cluster
    echo ""
    echo "Enabling Azure Policy for Kubernetes on the cluster"
    echo ""
    sudo -u $adminUsername az k8s-extension create --name "arc-azurepolicy" --cluster-name $vmName --resource-group $resourceGroup --cluster-type connectedClusters --extension-type Microsoft.PolicyInsights --only-show-errors

else
    # Downloading k3s control plane details
    echo ""
    echo "Downloading k3s control plane details"
    echo ""
    k3sClusterNodeConfigYaml="k3sClusterNodeConfig.yaml"
    azcopy cp --check-md5 FailIfDifferentOrMissing "https://$stagingStorageAccountName.blob.core.windows.net/$storageContainerName/$k3sClusterNodeConfigYaml" "/home/$adminUsername/$k3sClusterNodeConfigYaml"

    # Installing Rancher K3s cluster (single worker node)
    echo ""
    echo "Installing Rancher K3s cluster node"
    echo ""
    k3sNodeToken=$(grep 'k3sNodeToken' "/home/$adminUsername/$k3sClusterNodeConfigYaml" | awk '{print $2}')
    k3sClusterIp=$(grep 'k3sClusterIp' "/home/$adminUsername/$k3sClusterNodeConfigYaml" | awk '{print $2}')
    curl -sfL https://get.k3s.io | K3S_URL=https://${k3sClusterIp}:6443 INSTALL_K3S_VERSION=v${K3S_VERSION} K3S_TOKEN=${k3sNodeToken} sh -
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Failed to add k3s worker nodes"
        exit 1
    fi
    
    sudo service sshd restart
fi

# Uploading this script log to staging storage for ease of troubleshooting
echo ""
echo "Uploading the script logs to staging storage"
echo ""
# Authorize azcopy by using a system-wide managed identity
log="/home/$adminUsername/jumpstart_logs/installK3s.log"
#vmNameLower=$(echo $vmName | tr '[:upper:]' '[:lower:]')
storageContainerNameLower=$(echo $storageContainerName | tr '[:upper:]' '[:lower:]')
azcopy cp $log "https://$stagingStorageAccountName.blob.core.windows.net/$storageContainerNameLower/installK3s-$vmName.log"