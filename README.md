# Contoso AKS Infrastructure

Azure Kubernetes Service (AKS) infrastructure for deploying 6 microservices applications using Bicep and Kubernetes.

## Overview

This repository contains infrastructure-as-code for deploying a complete AKS environment including:

- **Azure Kubernetes Service (AKS)** cluster with autoscaling
- **Azure Container Registry (ACR)** for storing Docker images
- **Application Insights** for application monitoring
- **Log Analytics Workspace** for centralized logging
- **Virtual Network** with dedicated AKS subnet
- **NGINX Ingress Controller** for CORS-enabled external access

## Architecture

### Applications
1. **Angular Frontend** - Web application (port 80)
2. **Workflow Service** - Workflow orchestration API (port 8080)
3. **Frontend API 1** - Public-facing API (port 8081) → Backend API 1
4. **Frontend API 2** - Public-facing API (port 8082) → Backend API 2
5. **Backend API 1** - Internal service (port 8083)
6. **Backend API 2** - Internal service (port 8084)

### Communication Flow
```
                                Internet
                                   ↓
                            NGINX Ingress (CORS)
                                   ↓
        ┌──────────────────────────┼──────────────────────────┐
        ↓                          ↓                          ↓
  Angular Frontend       Workflow Service              Frontend APIs
  (Port 80)              (Port 8080)           (Ports 8081, 8082)
                                                        ↓
                                                 Backend APIs
                                           (Ports 8083, 8084)
```

## Project Structure

```
.
├── main.bicep                    # Main infrastructure Bicep template
├── main.bicepparam               # Parameters file for deployment
├── deploy.sh                     # Bash deployment script
├── deploy.ps1                    # PowerShell deployment script
├── DEPLOYMENT-GUIDE.md           # Detailed deployment instructions
├── kubernetes/
│   └── deployments.yaml          # Kubernetes manifests for all 6 apps
└── applications/
    └── contoso-apps.bicep        # Application-specific configurations
```

## Quick Start

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Docker](https://docs.docker.com/get-docker/)
- [Helm](https://helm.sh/docs/intro/install/) (for NGINX ingress)
- SSH key pair (will be auto-generated if not present)

### Option 1: Automated Deployment (Recommended)

**For Linux/Mac:**
```bash
chmod +x deploy.sh
./deploy.sh
```

**For Windows (PowerShell):**
```powershell
.\deploy.ps1
```

### Option 2: Manual Deployment

```bash
# 1. Login to Azure
az login

# 2. Create resource group
az group create --name contoso-aks-rg --location eastus

# 3. Update main.bicepparam with your SSH public key
cat ~/.ssh/id_rsa.pub  # Copy this

# 4. Deploy infrastructure
az deployment group create \
  --resource-group contoso-aks-rg \
  --template-file main.bicep \
  --parameters main.bicepparam

# 5. Get AKS credentials
az aks get-credentials \
  --resource-group contoso-aks-rg \
  --name contoso-aks-dev

# 6. Install NGINX Ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

## Deploying Applications

### 1. Build and Push Docker Images

```bash
# Get ACR name
ACR_NAME=$(az deployment group show \
  --resource-group contoso-aks-rg \
  --name main \
  --query properties.outputs.acrLoginServer.value -o tsv)

# Login to ACR
az acr login --name $ACR_NAME

# Build and push each application
docker build -t $ACR_NAME/angular-frontend:latest ./apps/angular-frontend
docker push $ACR_NAME/angular-frontend:latest

docker build -t $ACR_NAME/workflow-service:latest ./apps/workflow-service
docker push $ACR_NAME/workflow-service:latest

# ... repeat for all 6 applications
```

### 2. Update Kubernetes Manifests

```bash
# Replace <ACR_NAME> with your actual ACR login server
sed -i "s/<ACR_NAME>/$ACR_NAME/g" kubernetes/deployments.yaml
```

### 3. Deploy to Kubernetes

```bash
kubectl apply -f kubernetes/deployments.yaml
```

### 4. Verify Deployment

```bash
# Check pods
kubectl get pods -n contoso-apps

# Check services
kubectl get services -n contoso-apps

# Check ingress
kubectl get ingress -n contoso-apps
```

## CI/CD Integration

### Best Practice: When to Run What

| Event | Action | Tool |
|-------|--------|------|
| **Project start** | Deploy infrastructure | Bicep (one-time) |
| **Infrastructure change** | Update infrastructure | Bicep (infrequent) |
| **Code commit** | Build Docker image | Docker + CI/CD |
| **Merge to main** | Deploy to AKS | kubectl + CI/CD |

### GitHub Actions

See the example workflow in `DEPLOYMENT-GUIDE.md` or create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to AKS
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      - name: Build and deploy
        run: |
          # Build images, push to ACR, update AKS
          # See DEPLOYMENT-GUIDE.md for full example
```

### Azure DevOps

See `DEPLOYMENT-GUIDE.md` for a complete Azure Pipelines YAML example.

## Infrastructure Components

### Resources Created

| Resource | Name Pattern | Purpose |
|----------|-------------|---------|
| AKS Cluster | `{projectName}-aks-{env}` | Kubernetes cluster |
| ACR | `{projectName}acr{env}` | Container registry |
| Log Analytics | `{projectName}-logs-{env}` | Centralized logging |
| App Insights | `{projectName}-insights-{env}` | Application monitoring |
| VNet | `{projectName}-vnet-{env}` | Network isolation |

### Default Configuration

- **Kubernetes Version**: 1.28.0
- **Node Count**: 3 (autoscale 1-5)
- **Node Size**: Standard_DS2_v2
- **Network Plugin**: Azure CNI
- **Network Policy**: Azure
- **RBAC**: Enabled
- **Workload Identity**: Enabled

## Monitoring and Observability

### Application Insights

All applications are configured to send telemetry to Application Insights:

```bash
# Get connection string
az deployment group show \
  --resource-group contoso-aks-rg \
  --name main \
  --query properties.outputs.appInsightsConnectionString.value
```

### Container Logs

```bash
# View logs for a specific pod
kubectl logs -f <pod-name> -n contoso-apps

# View logs for a deployment
kubectl logs -f deployment/angular-frontend -n contoso-apps
```

### AKS Diagnostics

AKS control plane logs are sent to Log Analytics:
- API server logs
- Controller manager logs
- Scheduler logs
- Audit logs
- Autoscaler logs

## Scaling

### Manual Scaling

```bash
# Scale a deployment
kubectl scale deployment angular-frontend --replicas=5 -n contoso-apps

# Scale AKS nodes
az aks scale \
  --resource-group contoso-aks-rg \
  --name contoso-aks-dev \
  --node-count 5
```

### Auto-scaling (Horizontal Pod Autoscaler)

Add to your deployment:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: angular-frontend-hpa
  namespace: contoso-apps
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: angular-frontend
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

## Security Best Practices

✅ **Implemented:**
- ACR integrated with AKS using managed identity
- Network policies enabled
- RBAC enabled on AKS
- Workload identity for pod-level access
- TLS termination at ingress (configure cert-manager for production)
- Backend APIs not exposed to internet

🔒 **Additional Recommendations:**
- Use Azure Key Vault for secrets
- Enable Azure Policy for compliance
- Implement pod security policies
- Configure network security groups
- Use private AKS cluster for production

## Cost Optimization

### Development Environment
- Use B-series VMs for non-production
- Scale down nodes during off-hours
- Use spot instances for batch workloads

### Production Environment
- Enable cluster autoscaler
- Right-size node pools
- Use Azure reservations for predictable workloads

## Troubleshooting

### Common Issues

**Issue: Pods stuck in ImagePullBackOff**
```bash
# Check if AKS can pull from ACR
kubectl describe pod <pod-name> -n contoso-apps

# Verify ACR role assignment
az role assignment list --scope $(az acr show --name <acr-name> --query id -o tsv)
```

**Issue: Ingress not accessible**
```bash
# Check ingress controller pods
kubectl get pods -n ingress-nginx

# Get external IP
kubectl get service nginx-ingress-ingress-nginx-controller -n ingress-nginx
```

**Issue: Application not logging to App Insights**
```bash
# Verify ConfigMap
kubectl get configmap app-config -n contoso-apps -o yaml

# Check environment variables in pod
kubectl exec <pod-name> -n contoso-apps -- env | grep INSIGHTS
```

## Cleanup

**Delete everything:**
```bash
az group delete --name contoso-aks-rg --yes --no-wait
```

**Delete only Kubernetes resources:**
```bash
kubectl delete namespace contoso-apps
```

## Documentation

- [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md) - Detailed step-by-step deployment guide
- [Azure AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Support

For issues or questions:
1. Check the [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)
2. Review AKS logs in Log Analytics
3. Check pod logs: `kubectl logs -n contoso-apps <pod-name>`

## License

[Your License Here]

## Contributing

[Your Contributing Guidelines Here]
