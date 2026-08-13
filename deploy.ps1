# Quick deployment script for Contoso AKS Infrastructure (PowerShell)

param(
    [string]$ResourceGroup = "rg-contoso-aks",
    [string]$Location = "eastus2"
)

$ErrorActionPreference = "Stop"

Write-Host "======================================" -ForegroundColor Green
Write-Host "Contoso AKS Infrastructure Deployment" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green

# Variables
$DeploymentName = "main-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# Check if Azure CLI is installed
try {
    az version | Out-Null
} catch {
    Write-Host "Error: Azure CLI is not installed" -ForegroundColor Red
    Write-Host "Please install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
}

# Check if kubectl is installed
try {
    kubectl version --client | Out-Null
} catch {
    Write-Host "Warning: kubectl is not installed" -ForegroundColor Yellow
    Write-Host "Install from: https://kubernetes.io/docs/tasks/tools/"
}

# Check if logged in to Azure
Write-Host "Checking Azure login..." -ForegroundColor Yellow
try {
    az account show | Out-Null
} catch {
    Write-Host "Please login to Azure" -ForegroundColor Yellow
    az login
}

# Display current subscription
$Subscription = az account show --query name -o tsv
Write-Host "Current subscription: $Subscription" -ForegroundColor Green
$Continue = Read-Host "Continue with this subscription? (y/n)"
if ($Continue -ne 'y') {
    Write-Host "Please set the correct subscription using: az account set --subscription <subscription-name>"
    exit 1
}

# Check if SSH key exists
$SshKeyPath = "$env:USERPROFILE\.ssh\id_rsa.pub"
if (-not (Test-Path $SshKeyPath)) {
    Write-Host "SSH public key not found. Generating..." -ForegroundColor Yellow
    ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\id_rsa" -N '""'
}

$SshKey = Get-Content $SshKeyPath -Raw
Write-Host "Using SSH public key from $SshKeyPath" -ForegroundColor Green

# Create resource group
Write-Host "Creating resource group: $ResourceGroup" -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location

# Update parameters file with SSH key
Write-Host "Updating parameters file with SSH key..." -ForegroundColor Yellow
$ParamsFile = "main.bicepparam"
$TempParams = "main.bicepparam.tmp"

# Create temporary parameters file with actual SSH key
(Get-Content $ParamsFile) -replace 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC\.\.\. \(replace with your SSH public key\)', $SshKey.Trim() | Set-Content $TempParams

# Deploy infrastructure
Write-Host "Deploying infrastructure... This may take 10-15 minutes" -ForegroundColor Yellow
az deployment group create `
  --resource-group $ResourceGroup `
  --name $DeploymentName `
  --template-file main.bicep `
  --parameters $TempParams

# Clean up temp file
Remove-Item $TempParams

# Get outputs
Write-Host "Deployment complete! Getting outputs..." -ForegroundColor Green
$OutputsJson = az deployment group show `
  --resource-group $ResourceGroup `
  --name $DeploymentName `
  --query properties.outputs | ConvertFrom-Json

$AcrName = $OutputsJson.acrName.value
$AcrLoginServer = $OutputsJson.acrLoginServer.value
$AksCluster = $OutputsJson.aksClusterName.value
$AppInsightsKey = $OutputsJson.appInsightsInstrumentationKey.value
$AppInsightsConn = $OutputsJson.appInsightsConnectionString.value

Write-Host "======================================" -ForegroundColor Green
Write-Host "Deployment Outputs:" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host "ACR Name: " -NoNewline; Write-Host $AcrName -ForegroundColor Yellow
Write-Host "ACR Login Server: " -NoNewline; Write-Host $AcrLoginServer -ForegroundColor Yellow
Write-Host "AKS Cluster: " -NoNewline; Write-Host $AksCluster -ForegroundColor Yellow
Write-Host "App Insights Key: " -NoNewline; Write-Host $AppInsightsKey -ForegroundColor Yellow

# Save outputs to file
@"
ACR_NAME=$AcrName
ACR_LOGIN_SERVER=$AcrLoginServer
AKS_CLUSTER=$AksCluster
APP_INSIGHTS_KEY=$AppInsightsKey
APP_INSIGHTS_CONN=$AppInsightsConn
RESOURCE_GROUP=$ResourceGroup
"@ | Set-Content deployment-outputs.env

Write-Host "Outputs saved to deployment-outputs.env" -ForegroundColor Green

# Get AKS credentials
try {
    kubectl version --client | Out-Null
    Write-Host "Getting AKS credentials..." -ForegroundColor Yellow
    az aks get-credentials `
      --resource-group $ResourceGroup `
      --name $AksCluster `
      --overwrite-existing
    
    Write-Host "kubectl configured successfully" -ForegroundColor Green
    kubectl get nodes
} catch {
    Write-Host "kubectl not found. Install it to interact with the cluster." -ForegroundColor Yellow
}

# Update Kubernetes manifests
Write-Host "Updating Kubernetes manifests with ACR name..." -ForegroundColor Yellow
if (Test-Path "kubernetes\deployments.yaml") {
    (Get-Content "kubernetes\deployments.yaml") -replace '<ACR_NAME>', $AcrLoginServer | Set-Content "kubernetes\deployments.yaml"
    Write-Host "Updated kubernetes\deployments.yaml" -ForegroundColor Green
    
    # Update ConfigMap with App Insights connection string
    try {
        kubectl version --client | Out-Null
        Write-Host "Creating/updating ConfigMap with Application Insights..." -ForegroundColor Yellow
        kubectl create namespace contoso-apps --dry-run=client -o yaml | kubectl apply -f -
        kubectl create configmap app-config `
          --namespace contoso-apps `
          --from-literal=APPLICATIONINSIGHTS_CONNECTION_STRING="$AppInsightsConn" `
          --from-literal=ASPNETCORE_ENVIRONMENT="Development" `
          --dry-run=client -o yaml | kubectl apply -f -
        Write-Host "ConfigMap created/updated" -ForegroundColor Green
    } catch {
        Write-Host "Could not create ConfigMap. kubectl may not be configured." -ForegroundColor Yellow
    }
}

Write-Host "======================================" -ForegroundColor Green
Write-Host "Next Steps:" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host "1. Build and push your Docker images to ACR:"
Write-Host "   az acr login --name $AcrName" -ForegroundColor Yellow
Write-Host "   docker build -t $AcrLoginServer/angular-frontend:latest ./apps/angular-frontend" -ForegroundColor Yellow
Write-Host "   docker push $AcrLoginServer/angular-frontend:latest" -ForegroundColor Yellow
Write-Host ""
Write-Host "2. Install NGINX Ingress Controller:"
Write-Host "   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx" -ForegroundColor Yellow
Write-Host "   helm install nginx-ingress ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. Deploy applications to AKS:"
Write-Host "   kubectl apply -f kubernetes\deployments.yaml" -ForegroundColor Yellow
Write-Host ""
Write-Host "4. Check deployment status:"
Write-Host "   kubectl get pods -n contoso-apps" -ForegroundColor Yellow
Write-Host ""
Write-Host "See DEPLOYMENT-GUIDE.md for detailed instructions" -ForegroundColor Green
