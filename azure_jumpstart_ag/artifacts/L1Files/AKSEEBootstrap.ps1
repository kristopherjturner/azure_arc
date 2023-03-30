# Script runtime environment: Level-1 Nested Hyper-V virtual machine

###########################################
# Preparing environment folders structure #
###########################################

$ProgressPreference = "SilentlyContinue"

# Folders to be created
$deploymentFolder = "C:\Deployment" # Deployment folder is already pre-created in the VHD image
$logsFolder = "$deploymentFolder\Logs"
$kubeFolder = "$env:USERPROFILE\.kube"

# Set up an array of folders
$folders = @($logsFolder, $kubeFolder)

# Loop through each folder and create it
foreach ($Folder in $folders) {
    New-Item -ItemType Directory $Folder -Force
}

# Start logging
Start-Transcript -Path $logsFolder\AKSEEBootstrap.log

#########################################
# Deplying AKS Edge Essentials clusters #
#########################################

# Force time sync
$string = Get-Date
Write-Host "Time before forced time sync:" + $string.ToString("u")
net start w32time
W32tm /resync
$string = Get-Date
Write-Host "Time after forced time sync:" + $string.ToString("u")

# Validating internet connectivity
while (-not (Test-Connection -ComputerName google.com -Quiet)) {
    Write-Host "Waiting for internet connectivity..."
    Start-Sleep -Seconds 5
}

# Creating Hyper-V External Virtual Switch for AKS Edge Essentials cluster deployment
Write-Host
Write-Host "Creating Hyper-V External Virtual Switch for AKS Edge Essentials cluster"
$AdapterName = (Get-NetAdapter -Name Ethernet*).Name
New-VMSwitch -Name "AKSEE-ExtSwitch" -NetAdapterName $AdapterName -AllowManagementOS $true -Notes "External Virtual Switch for AKS Edge Essentials cluster"
Write-Host

# Installing AKS Edge Essentials binaries and PowerShell module
$msiFileName = (Get-ChildItem -Path $deploymentFolder | Where-Object { $_.Extension -eq ".msi" }).Name
$msiFilePath = Join-Path $deploymentFolder $msiFileName
$fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($msiFilePath)
$msiInstallLog = "$deploymentFolder\$fileNameWithoutExt.log"
Start-Process msiexec.exe -ArgumentList "/i `"$msiFilePath`" /passive /qb! /log `"$msiInstallLog`"" -Wait

Install-AksEdgeHostFeatures -Force

# Deploying AKS Edge Essentials cluster
Set-Location $deploymentFolder
New-AksEdgeDeployment -JsonConfigFilePath ".\Config.json"
Write-Host

# kubeconfig work for changing context and coping to the Hyper-V host machine
$newKubeContext = $(hostname).ToLower()
kubectx $newKubeContext=default
Write-Host
kubectl get nodes -o wide
Write-Host

$sourcePath = "$env:USERPROFILE\.kube\config"
$destinationPath = "$env:USERPROFILE\.kube\config-$newKubeContext"

$kubeReplacementParams = @{
    "name: default"    = "name: $newKubeContext"
    "cluster: default" = "cluster: $newKubeContext"
    "user: default"    = "user: $newKubeContext"
}

$content = Get-Content $sourcePath
foreach ($key in $kubeReplacementParams.Keys) {
    $content = $content -replace $key, $kubeReplacementParams[$key]
}
Set-Content $destinationPath -Value $content

Write-Host "Enabling ICMP for the cluster control plane IP address"
Invoke-AksEdgeNodeCommand -NodeType "Linux" -command "sudo iptables -A INPUT -p ICMP -j ACCEPT"

# Unregistering the scheduled task responsible for start script automation
Unregister-ScheduledTask -TaskName "Startup Scan" -Confirm:$false
