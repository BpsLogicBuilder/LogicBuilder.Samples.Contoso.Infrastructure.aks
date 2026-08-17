# Contoso AKS Infrastructure Deployment steps

This document outlines the steps to deploy the Contoso AKS infrastructure from your workstation.

## Prerequisites
- Azure CLI installed
- kubectl installed
- An Azure subscription
- Resource group created
- A managed identity created to support the deployment.  The managed identity must have the following roles assigned in the resource group's scope:
  - Contributor
  - User Access Administrator
  - Key Vault Certificate Officer

The managed identity can exist in a different resource group than the one used for the AKS cluster although it must have the permissions listed above in the resource group's scope.

To run the deployment you must have the following roles assigned in the resource group's scope:
- Contributor
- User Access Administrator

The managed identity only needs the Key Vault Certificate Officer role for deployment from your workstation.  It needs all three roles for deployment from GitHub Actions.


### Set $rg to an existing resource group.
rg="rg-contoso-aks"

### Create SSH key if it does not exist.
az sshkey create --name "contosoAksSSHKey" --resource-group $rg

Main.bicep declares a Microsoft.Compute/sshPublicKeys resource whose name is "contosoAksSSHKey" and uses the public key from the SSH key created above.

### Deploy the AKS Cluster  
```bash
az deployment group create --resource-group $rg --template-file main.bicep 
```
### Get credentials to create nginx-ingress controller 
```bash
AKS_CLUSTER_NAME=$(az deployment group show --resource-group $rg --name main --query properties.outputs.aksClusterName.value -o tsv)
az aks get-credentials --resource-group $rg --name $AKS_CLUSTER_NAME --overwrite-existing
```
### Install nginx-ingress controller
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
MSYS_NO_PATHCONV=1 # needed to prevent Git Bash's POSIX path conversion feature (otherwise /healthz becomes C:/Program Files/Git/healthz)
helm install nginx-ingress ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace --set controller.replicaCount=2 --set controller.nodeSelector.'kubernetes\.io/os'=linux --set controller.service.annotations.'service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path'=/healthz

# To wait for the load balancer to be provisioned, run the following command until you see an external IP address assigned to the nginx-ingress service:
kubectl get service nginx-ingress-ingress-nginx-controller -n ingress-nginx -w
```
### Deploy namespace so we can add secrets before deploying workloads
```bash
KEY_VAULT_NAME=$(az deployment group show --resource-group $rg --name main --query properties.outputs.keyVaultName.value -o tsv)
CONTOSO_APP_NAMESPACE=$(az deployment group show --resource-group $rg --name main --query properties.outputs.kubernetesNamespace.value -o tsv)

sed -e "s|CONTOSO_APP_NAMESPACE|${CONTOSO_APP_NAMESPACE}|g" \
        kubernetes/namespace.yaml | tee /dev/tty | kubectl apply -f - -n $CONTOSO_APP_NAMESPACE
kubectl create secret generic app-secrets --namespace=$CONTOSO_APP_NAMESPACE --from-literal=keyVaultUrl="https://${KEY_VAULT_NAME}.vault.azure.net/" --from-literal=db-connection-string="<Your database connection string>"
```

### Upload images to the ACR
From the following repositories, go the infrastructure folder and run the commands to build and push the images to the ACR.  The ACR name is output from the main.bicep deployment.

- LogicBuilder.Samples.Contoso.Angular (1 image)
    ```bash
    docker buildx build --secret id=kendo_license,src=$env:APPDATA\Telerik\telerik-license.txt -t "${acrName}.azurecr.io/${imageName}:${imageTag}" -t "${acrName}.azurecr.io/${imageName}:latest" --push .
    ```
- LogicBuilder.Samples.Contoso.KendoGrid.Services (2 images)
    ```bash
    az acr build --registry $acrName --image "contosokendogridapi:${imageTag}" --image contosokendogridapi:latest --file ./Contoso.KendoGrid.Api/Dockerfile .
    az acr build --registry $acrName --image "contosokendogridbsl:${imageTag}" --image contosokendogridbsl:latest --file ./Contoso.KendoGrid.Bsl/Dockerfile . --secret-build-arg TELERIK_USERNAME="api-key" --secret-build-arg TELERIK_PASSWORD="<Your Telerik API Key>"
    ```
- LogicBuilder.Samples.Contoso.Services (2 images)
    ```bash
    az acr build --registry $acrName --image "contosoapi:${imageTag}" --image contosoapi:latest --file ./Contoso.Api/Dockerfile .
    az acr build --registry $acrName --image "contosobsl:${imageTag}" --image contosobsl:latest --file ./Contoso.Bsl/Dockerfile .
    ```
- LogicBuilder.Samples.Contoso.Spa.Flow (1 image)
    ```bash
    az acr build --registry $acrName --image "contosospaapi:${imageTag}" --image contosospaapi:latest --file ./Contoso.Spa.Api/Dockerfile .
    ```

### Deploy the manifests
First get the following variables from the main.bicep deployment outputs:

```bash
LOAD_BALANCER_IP=$(kubectl get service nginx-ingress-ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

ACR_NAME=$(az deployment group show --resource-group $rg --name main --query properties.outputs.acrName.value -o tsv)

APP_INSIGHTS_CONNECTION_STRING=$(az deployment group show --resource-group $rg --name main --query properties.outputs.appInsightsConnectionString.value -o tsv)

APP_CONFIG_ENDPOINT=$(az deployment group show --resource-group $rg --name main --query properties.outputs.appConfigurationEndPoint.value -o tsv)

CONTOSO_API_IDENTITY_CLIENTID=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoApiManagedIdentityClientId.value -o tsv)

CONTOSO_BSL_IDENTITY_CLIENTID=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoBslManagedIdentityClientId.value -o tsv)

CONTOSO_KENDO_GRID_API_IDENTITY_CLIENTID=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoKendoGridApiManagedIdentityClientId.value -o tsv)

CONTOSO_KENDO_GRID_BSL_IDENTITY_CLIENTID=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoKendoGridBslManagedIdentityClientId.value -o tsv)

CONTOSO_SPA_API_IDENTITY_CLIENTID=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoSpaApiManagedIdentityClientId.value -o tsv)

CONTOSO_ANGULAR_IDENTITY_CLIENTID=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoAngularManagedIdentityClientId.value -o tsv)

CONTOSO_API_SERVICEACCOUNT_NAME=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoApiServiceAccountName.value -o tsv)

CONTOSO_BSL_SERVICEACCOUNT_NAME=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoBslServiceAccountName.value -o tsv)

CONTOSO_KENDO_GRID_API_SERVICEACCOUNT_NAME=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoKendoGridApiServiceAccountName.value -o tsv)

CONTOSO_KENDO_GRID_BSL_SERVICEACCOUNT_NAME=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoKendoGridBslServiceAccountName.value -o tsv)

CONTOSO_SPA_API_SERVICEACCOUNT_NAME=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoSpaApiServiceAccountName.value -o tsv)

CONTOSO_ANGULAR_SERVICEACCOUNT_NAME=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoAngularServiceAccountName.value -o tsv)

CONTOSO_APP_NAMESPACE=$(az deployment group show --resource-group $rg --name main --query properties.outputs.kubernetesNamespace.value -o tsv)

EXPECTED_CERTIFICATE_THUMBPRINT=$(az deployment group show --resource-group $rg --name main --query properties.outputs.contosoBslCertificateThumbprint.value -o tsv)

---
Finally, run the following command to deploy the manifests.  The command will replace the placeholders in the manifests with the values from the main.bicep deployment outputs.

```bash
sed -e "s|LOAD_BALANCER_IP|${LOAD_BALANCER_IP}|g" \
        -e "s|ACR_NAME|${ACR_NAME}|g" \
        -e "s|APP_INSIGHTS_CONNECTION_STRING|${APP_INSIGHTS_CONNECTION_STRING}|g" \
        -e "s|APP_CONFIG_ENDPOINT|${APP_CONFIG_ENDPOINT}|g" \
        -e "s|CONTOSO_API_IDENTITY_CLIENTID|${CONTOSO_API_IDENTITY_CLIENTID}|g" \
        -e "s|CONTOSO_BSL_IDENTITY_CLIENTID|${CONTOSO_BSL_IDENTITY_CLIENTID}|g" \
        -e "s|CONTOSO_KENDO_GRID_API_IDENTITY_CLIENTID|${CONTOSO_KENDO_GRID_API_IDENTITY_CLIENTID}|g" \
        -e "s|CONTOSO_KENDO_GRID_BSL_IDENTITY_CLIENTID|${CONTOSO_KENDO_GRID_BSL_IDENTITY_CLIENTID}|g" \
        -e "s|CONTOSO_SPA_API_IDENTITY_CLIENTID|${CONTOSO_SPA_API_IDENTITY_CLIENTID}|g" \
        -e "s|CONTOSO_ANGULAR_IDENTITY_CLIENTID|${CONTOSO_ANGULAR_IDENTITY_CLIENTID}|g" \
        -e "s|CONTOSO_API_SERVICEACCOUNT_NAME|${CONTOSO_API_SERVICEACCOUNT_NAME}|g" \
        -e "s|CONTOSO_BSL_SERVICEACCOUNT_NAME|${CONTOSO_BSL_SERVICEACCOUNT_NAME}|g" \
        -e "s|CONTOSO_KENDO_GRID_API_SERVICEACCOUNT_NAME|${CONTOSO_KENDO_GRID_API_SERVICEACCOUNT_NAME}|g" \
        -e "s|CONTOSO_KENDO_GRID_BSL_SERVICEACCOUNT_NAME|${CONTOSO_KENDO_GRID_BSL_SERVICEACCOUNT_NAME}|g" \
        -e "s|CONTOSO_SPA_API_SERVICEACCOUNT_NAME|${CONTOSO_SPA_API_SERVICEACCOUNT_NAME}|g" \
        -e "s|CONTOSO_ANGULAR_SERVICEACCOUNT_NAME|${CONTOSO_ANGULAR_SERVICEACCOUNT_NAME}|g" \
        -e "s|CONTOSO_APP_NAMESPACE|${CONTOSO_APP_NAMESPACE}|g" \
        -e "s|EXPECTED_CERTIFICATE_THUMBPRINT|${EXPECTED_CERTIFICATE_THUMBPRINT}|g" \
        -e "s|IMAGE_TAG|latest|g" \
        kubernetes/deployments.yaml | tee /dev/tty | kubectl apply -f - -n ${CONTOSO_APP_NAMESPACE}
```