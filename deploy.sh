#!/bin/bash
# Quick deployment script for Contoso AKS Infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Contoso AKS Infrastructure Deployment${NC}"
echo -e "${GREEN}======================================${NC}"

# Variables
RESOURCE_GROUP="contoso-aks-rg"
LOCATION="eastus"
DEPLOYMENT_NAME="main-$(date +%Y%m%d-%H%M%S)"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Please install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}Warning: kubectl is not installed${NC}"
    echo "Install from: https://kubernetes.io/docs/tasks/tools/"
fi

# Check if logged in to Azure
echo -e "${YELLOW}Checking Azure login...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Please login to Azure${NC}"
    az login
fi

# Display current subscription
SUBSCRIPTION=$(az account show --query name -o tsv)
echo -e "${GREEN}Current subscription: ${SUBSCRIPTION}${NC}"
read -p "Continue with this subscription? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please set the correct subscription using: az account set --subscription <subscription-name>"
    exit 1
fi

# Check if SSH key exists
if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo -e "${YELLOW}SSH public key not found. Generating...${NC}"
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
echo -e "${GREEN}Using SSH public key from ~/.ssh/id_rsa.pub${NC}"

# Create resource group
echo -e "${YELLOW}Creating resource group: ${RESOURCE_GROUP}${NC}"
az group create --name $RESOURCE_GROUP --location $LOCATION

# Update parameters file with SSH key
echo -e "${YELLOW}Updating parameters file with SSH key...${NC}"
PARAMS_FILE="main.bicepparam"
TEMP_PARAMS="main.bicepparam.tmp"

# Create temporary parameters file with actual SSH key
sed "s|ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... (replace with your SSH public key)|$SSH_KEY|g" $PARAMS_FILE > $TEMP_PARAMS

# Deploy infrastructure
echo -e "${YELLOW}Deploying infrastructure... This may take 10-15 minutes${NC}"
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --name $DEPLOYMENT_NAME \
  --template-file main.bicep \
  --parameters $TEMP_PARAMS

# Clean up temp file
rm $TEMP_PARAMS

# Get outputs
echo -e "${GREEN}Deployment complete! Getting outputs...${NC}"
OUTPUTS=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name $DEPLOYMENT_NAME \
  --query properties.outputs)

ACR_NAME=$(echo $OUTPUTS | jq -r '.acrName.value')
ACR_LOGIN_SERVER=$(echo $OUTPUTS | jq -r '.acrLoginServer.value')
AKS_CLUSTER=$(echo $OUTPUTS | jq -r '.aksClusterName.value')
APP_INSIGHTS_KEY=$(echo $OUTPUTS | jq -r '.appInsightsInstrumentationKey.value')
APP_INSIGHTS_CONN=$(echo $OUTPUTS | jq -r '.appInsightsConnectionString.value')

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Deployment Outputs:${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "ACR Name: ${YELLOW}${ACR_NAME}${NC}"
echo -e "ACR Login Server: ${YELLOW}${ACR_LOGIN_SERVER}${NC}"
echo -e "AKS Cluster: ${YELLOW}${AKS_CLUSTER}${NC}"
echo -e "App Insights Key: ${YELLOW}${APP_INSIGHTS_KEY}${NC}"

# Save outputs to file
cat > deployment-outputs.env <<EOF
ACR_NAME=${ACR_NAME}
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER}
AKS_CLUSTER=${AKS_CLUSTER}
APP_INSIGHTS_KEY=${APP_INSIGHTS_KEY}
APP_INSIGHTS_CONN=${APP_INSIGHTS_CONN}
RESOURCE_GROUP=${RESOURCE_GROUP}
EOF

echo -e "${GREEN}Outputs saved to deployment-outputs.env${NC}"

# Get AKS credentials
if command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}Getting AKS credentials...${NC}"
    az aks get-credentials \
      --resource-group $RESOURCE_GROUP \
      --name $AKS_CLUSTER \
      --overwrite-existing
    
    echo -e "${GREEN}kubectl configured successfully${NC}"
    kubectl get nodes
else
    echo -e "${YELLOW}kubectl not found. Install it to interact with the cluster.${NC}"
fi

# Update Kubernetes manifests
echo -e "${YELLOW}Updating Kubernetes manifests with ACR name...${NC}"
if [ -f kubernetes/deployments.yaml ]; then
    sed -i.bak "s|<ACR_NAME>|${ACR_LOGIN_SERVER}|g" kubernetes/deployments.yaml
    echo -e "${GREEN}Updated kubernetes/deployments.yaml${NC}"
    
    # Update ConfigMap with App Insights connection string
    if command -v kubectl &> /dev/null; then
        echo -e "${YELLOW}Creating/updating ConfigMap with Application Insights...${NC}"
        kubectl create namespace contoso-apps --dry-run=client -o yaml | kubectl apply -f -
        kubectl create configmap app-config \
          --namespace contoso-apps \
          --from-literal=APPLICATIONINSIGHTS_CONNECTION_STRING="${APP_INSIGHTS_CONN}" \
          --from-literal=ASPNETCORE_ENVIRONMENT="Development" \
          --dry-run=client -o yaml | kubectl apply -f -
        echo -e "${GREEN}ConfigMap created/updated${NC}"
    fi
fi

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Next Steps:${NC}"
echo -e "${GREEN}======================================${NC}"
echo "1. Build and push your Docker images to ACR:"
echo -e "   ${YELLOW}az acr login --name ${ACR_NAME}${NC}"
echo -e "   ${YELLOW}docker build -t ${ACR_LOGIN_SERVER}/angular-frontend:latest ./apps/angular-frontend${NC}"
echo -e "   ${YELLOW}docker push ${ACR_LOGIN_SERVER}/angular-frontend:latest${NC}"
echo ""
echo "2. Install NGINX Ingress Controller:"
echo -e "   ${YELLOW}helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx${NC}"
echo -e "   ${YELLOW}helm install nginx-ingress ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace${NC}"
echo ""
echo "3. Deploy applications to AKS:"
echo -e "   ${YELLOW}kubectl apply -f kubernetes/deployments.yaml${NC}"
echo ""
echo "4. Check deployment status:"
echo -e "   ${YELLOW}kubectl get pods -n contoso-apps${NC}"
echo ""
echo -e "${GREEN}See DEPLOYMENT-GUIDE.md for detailed instructions${NC}"
