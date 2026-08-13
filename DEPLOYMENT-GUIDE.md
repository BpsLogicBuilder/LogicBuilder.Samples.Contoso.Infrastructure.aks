# Contoso AKS Infrastructure Deployment Guide

## Architecture Overview

### Applications
1. **Contoso Angular** - Web application accessible from the internet
2. **Contoso SPA API** - Handles workflow orchestration (called by Angular app via CORS)
3. **Contoso API** - Public-facing API (called by Angular app via CORS) → communicates with Backend API 1
4. **Contoso Kendo Grid API** - Public-facing API (called by Angular app via CORS) → communicates with Backend API 2
5. **Contoso BSL** - Internal API (called by Contoso API)
6. **Contoso Kendo Grid BSL** - Internal API (called by Contoso Kendo Grid API)

### Communication Flow
```
Internet → Ingress → Contoso Angular
                  ↓ (CORS)
                  → Contoso SPA API
                  → Contoso API → Backend API 1
                  → Contoso Kendo Grid API → Backend API 2
```

## Prerequisites

1. **Azure CLI** - [Install](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
2. **kubectl** - [Install](https://kubernetes.io/docs/tasks/tools/)
3. **SSH Key Pair** - Generate using `ssh-keygen -t rsa -b 4096`

## Best Practices for Infrastructure Setup

### When to Set Up Infrastructure

1. **Initial Setup (One-Time)**
   - Deploy infrastructure using Bicep **once** at the beginning of the project
   - This creates: AKS cluster, ACR, Application Insights, Log Analytics
   - Infrastructure changes are **infrequent** (scaling, adding node pools, etc.)

2. **Application Deployment (Frequent)**
   - Deploy Kubernetes manifests for your 6 applications
   - Update these whenever you merge to master/main branch
   - Use CI/CD pipelines to build images and update deployments

### Separation of Concerns

- **Bicep** → Infrastructure (AKS, ACR, monitoring) - Run infrequently
- **Kubernetes Manifests** → Application deployments - Run on every merge
- **Docker Images** → Application code - Build on every commit

## Step-by-Step Deployment

### Step 1: Deploy Infrastructure (One-Time Setup)

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "Your-Subscription-Name"

# Create resource group
az group create --name rg-contoso-aks --location eastus2

# Update the parameters file with your SSH public key
# Edit main.bicepparam and replace the sshPublicKey value with your public key:
#cat ~/.ssh/id_rsa.pub
az sshkey create --name "contosoAksSSHKey" --resource-group rg-contoso-aks

# Deploy the infrastructure
az deployment group create \
  --resource-group rg-contoso-aks \
  --template-file main.bicep \
  --parameters main.bicepparam

# Save the outputs (you'll need these later)
az deployment group show \
  --resource-group rg-contoso-aks \
  --name main \
  --query properties.outputs
```

### Step 2: Configure kubectl Access

AKS_CLUSTER_NAMe=(az deployment group show --resource-group rg-contoso-aks --name main --query properties.outputs.aksClusterName.value -o tsv)

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group rg-contoso-aks \
  --name $AKS_CLUSTER_NAME --overwrite-existing

# Verify connection
kubectl get nodes
```

### Step 3: Install NGINX Ingress Controller

```bash
# Add the ingress-nginx repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install the ingress controller
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2 \
  --set controller.nodeSelector."kubernetes\.io/os"=linux \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

# Wait for external IP
kubectl get service nginx-ingress-ingress-nginx-controller -n ingress-nginx -w
```

### Step 4: Update Kubernetes Manifests with ACR Name

```bash
# Get ACR login server
ACR_NAME=$(az deployment group show \
  --resource-group rg-contoso-aks \
  --name main \
  --query properties.outputs.acrLoginServer.value -o tsv)

echo "ACR Login Server: $ACR_NAME"

# Replace <ACR_NAME> in kubernetes/deployments.yaml with the actual ACR name
# You can do this manually or with sed:
sed -i "s/<ACR_NAME>/$ACR_NAME/g" kubernetes/deployments.yaml
```

### Step 5: Update ConfigMap with Application Insights

```bash
# Get Application Insights connection string
APP_INSIGHTS_CONN=$(az deployment group show \
  --resource-group rg-contoso-aks \
  --name main \
  --query properties.outputs.appInsightsConnectionString.value -o tsv)

# Update the ConfigMap in deployments.yaml with the connection string
# Or create it directly:
kubectl create configmap app-config \
  --namespace contoso-apps \
  --from-literal=APPLICATIONINSIGHTS_CONNECTION_STRING="$APP_INSIGHTS_CONN" \
  --from-literal=ASPNETCORE_ENVIRONMENT="Development" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 6: Build and Push Docker Images

For each application, you need to build and push Docker images to ACR:

```bash
# Login to ACR
az acr login --name $(az deployment group show \
  --resource-group rg-contoso-aks \
  --name main \
  --query properties.outputs.acrName.value -o tsv)

# Build and push each application (example for contoso-angular)
# Navigate to your application directory
cd /path/to/contoso-angular

docker build -t $ACR_NAME/contoso-angular:latest .
docker push $ACR_NAME/contoso-angular:latest

# Repeat for all 6 applications:
# - contoso-angular
# - contoso-spa-api
# - contoso-api
# - contoso-kendo-grid-api
# - contoso-bsl
# - contoso-kendo-grid-bsl
```

### Step 7: Deploy Applications to AKS

```bash
# Apply the Kubernetes manifests
kubectl apply -f kubernetes/deployments.yaml

# Check deployment status
kubectl get deployments -n contoso-apps
kubectl get pods -n contoso-apps
kubectl get services -n contoso-apps

# Check ingress
kubectl get ingress -n contoso-apps
```

### Step 8: Configure DNS (Optional)

```bash
# Get the external IP of the ingress controller
INGRESS_IP=$(kubectl get service nginx-ingress-ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Configure your DNS to point contoso.example.com to $INGRESS_IP"
```

## CI/CD Pipeline Setup

### GitHub Actions Example

Create `.github/workflows/deploy.yml`:

```yaml
name: Build and Deploy to AKS

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:

env:
  RESOURCE_GROUP: rg-contoso-aks
  AKS_CLUSTER: contoso-aks-dev
  NAMESPACE: contoso-apps

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    
    strategy:
      matrix:
        app:
          - contoso-angular
          - contoso-spa-api
          - contoso-api
          - contoso-kendo-grid-api
          - contoso-bsl
          - contoso-kendo-grid-bsl
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Get ACR name
      id: acr
      run: |
        ACR_NAME=$(az deployment group show \
          --resource-group ${{ env.RESOURCE_GROUP }} \
          --name main \
          --query properties.outputs.acrName.value -o tsv)
        echo "name=$ACR_NAME" >> $GITHUB_OUTPUT
        echo "loginServer=$ACR_NAME.azurecr.io" >> $GITHUB_OUTPUT
    
    - name: Build and push image
      run: |
        az acr build \
          --registry ${{ steps.acr.outputs.name }} \
          --image ${{ matrix.app }}:${{ github.sha }} \
          --image ${{ matrix.app }}:latest \
          --file ./apps/${{ matrix.app }}/Dockerfile \
          ./apps/${{ matrix.app }}
    
    - name: Set AKS context
      uses: azure/aks-set-context@v3
      with:
        resource-group: ${{ env.RESOURCE_GROUP }}
        cluster-name: ${{ env.AKS_CLUSTER }}
    
    - name: Deploy to AKS
      run: |
        kubectl set image deployment/${{ matrix.app }} \
          ${{ matrix.app }}=${{ steps.acr.outputs.loginServer }}/${{ matrix.app }}:${{ github.sha }} \
          -n ${{ env.NAMESPACE }}
        
        kubectl rollout status deployment/${{ matrix.app }} -n ${{ env.NAMESPACE }}
```

### Azure DevOps Pipeline Example

Create `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
    - main
    - master

pool:
  vmImage: 'ubuntu-latest'

variables:
  resourceGroup: 'rg-contoso-aks'
  aksCluster: 'contoso-aks-dev'
  namespace: 'contoso-apps'

stages:
- stage: Build
  jobs:
  - job: BuildImages
    strategy:
      matrix:
        AngularFrontend:
          appName: 'angular-frontend'
        WorkflowService:
          appName: 'workflow-service'
        FrontendAPI1:
          appName: 'frontend-api-1'
        FrontendAPI2:
          appName: 'frontend-api-2'
        BackendAPI1:
          appName: 'backend-api-1'
        BackendAPI2:
          appName: 'backend-api-2'
    steps:
    - task: AzureCLI@2
      displayName: 'Build and Push $(appName)'
      inputs:
        azureSubscription: 'Your-Service-Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          ACR_NAME=$(az deployment group show \
            --resource-group $(resourceGroup) \
            --name main \
            --query properties.outputs.acrName.value -o tsv)
          
          az acr build \
            --registry $ACR_NAME \
            --image $(appName):$(Build.BuildId) \
            --image $(appName):latest \
            --file ./apps/$(appName)/Dockerfile \
            ./apps/$(appName)

- stage: Deploy
  dependsOn: Build
  jobs:
  - deployment: DeployToAKS
    environment: 'production'
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureCLI@2
            displayName: 'Deploy to AKS'
            inputs:
              azureSubscription: 'Your-Service-Connection'
              scriptType: 'bash'
              scriptLocation: 'inlineScript'
              inlineScript: |
                az aks get-credentials \
                  --resource-group $(resourceGroup) \
                  --name $(aksCluster)
                
                ACR_LOGIN=$(az deployment group show \
                  --resource-group $(resourceGroup) \
                  --name main \
                  --query properties.outputs.acrLoginServer.value -o tsv)
                
                for app in angular-frontend workflow-service frontend-api-1 frontend-api-2 backend-api-1 backend-api-2; do
                  kubectl set image deployment/$app \
                    $app=$ACR_LOGIN/$app:$(Build.BuildId) \
                    -n $(namespace)
                done
                
                kubectl get pods -n $(namespace)
```

## Updating Infrastructure (Infrequent)

Only run these commands when you need to change infrastructure configuration:

```bash
# Update parameters in main.bicepparam (e.g., increase node count)
# Then redeploy:
az deployment group create \
  --resource-group rg-contoso-aks \
  --template-file main.bicep \
  --parameters main.bicepparam
```

## Monitoring and Logs

### View Application Insights
```bash
# Get Application Insights name
az deployment group show \
  --resource-group rg-contoso-aks \
  --name main \
  --query properties.outputs.appInsightsName.value

# Open in portal
az monitor app-insights component show \
  --app <app-insights-name> \
  --resource-group rg-contoso-aks \
  --query appId
```

### View Container Logs
```bash
# View logs for a specific pod
kubectl logs -f <pod-name> -n contoso-apps

# View logs for a deployment
kubectl logs -f deployment/angular-frontend -n contoso-apps
```

### Query Log Analytics
```bash
# Get Log Analytics workspace ID
az deployment group show \
  --resource-group rg-contoso-aks \
  --name main \
  --query properties.outputs.logAnalyticsWorkspaceId.value
```

## Cleanup

```bash
# Delete the entire resource group (WARNING: This deletes everything)
az group delete --name rg-contoso-aks --yes --no-wait
```

## Best Practices Summary

✅ **DO:**
- Use Bicep for infrastructure provisioning (one-time or infrequent)
- Use Kubernetes manifests for application deployment (frequent)
- Use CI/CD pipelines to automate image building and deployment
- Tag images with commit SHA for traceability
- Use separate namespaces for different environments
- Enable monitoring and Application Insights
- Use resource limits and requests for all containers
- Implement health checks (liveness and readiness probes)

❌ **DON'T:**
- Use Bicep to deploy application images (use kubectl/Helm instead)
- Rebuild infrastructure on every code change
- Use :latest tag in production (use specific version tags)
- Expose backend APIs directly to the internet
- Skip health checks or monitoring
