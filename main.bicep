// Main infrastructure file for AKS environment with 6 applications
// This sets up: AKS, ACR, Application Insights, Log Analytics

targetScope = 'resourceGroup'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The name prefix for all resources')
param projectName string = 'contoso'

@description('AKS cluster node count')
@minValue(1)
@maxValue(10)
param nodeCount int = 3

@description('AKS cluster node VM size')
param nodeVmSize string = 'standard_d2ads_v7'

@description('Admin username for AKS nodes')
param adminUsername string = 'azureuser'

@description('Enable Azure Policy for AKS')
param enableAzurePolicy bool = true

@description('Enable monitoring and diagnostics')
param enableMonitoring bool = true

@description('Kubernetes version')
param kubernetesVersion string = '1.36.0'

@description('Set the Key Vault Certificate User Role Definition ID')
param keyVaultCertificateUserRoleDefinitionID string = 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba'

@description('Managed Identity for contoso-api and contoso-kendo-grid-api')
param contosoApiManagedIdentityName string = 'uai-${projectName}-api-${uniqueString(resourceGroup().id)}'

@description('Namespace for all Contoso services in the cluster')
param k8sNamespace string = '${projectName}-apps'

@description('When the service account is assigned to contoso-api and contoso-kendo-grid-api, they will receive the permissions assigned to the managed identity.')
param k8sContosoApiServiceAccountName string = 'sa-${projectName}-api'

@description('Generate a unique GUID to use as name for the role assignment')
var contosoApiManagedIdentityToKeyVaultRoleAssignmentName = guid(contosoApiManagedIdentity.id, keyVaultCertificateUserRoleDefinitionID, keyVault.id)

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)

var aksClusterName = '${projectName}-aks-${uniqueSuffix}'
var acrName = replace('${projectName}acr${uniqueSuffix}', '-', '')
var logAnalyticsName = '${projectName}-logs-${uniqueSuffix}'
var appInsightsName = '${projectName}-insights-${uniqueSuffix}'

resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: 'contoso-kv-${uniqueString(resourceGroup().id)}'
  dependsOn: [createKeyVaultAndCertificate]
}

resource contosoAksSSHKey 'Microsoft.Compute/sshPublicKeys@2023-09-01' existing = {
  name: 'contosoAksSSHKey'
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: false
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
  }
}

// AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: aksClusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: '${aksClusterName}-dns'
    enableRBAC: true
    
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        maxPods: 110
      }
    ]
    
    linuxProfile: {
      adminUsername: adminUsername
      ssh: {
        publicKeys: [
          {
            keyData: contosoAksSSHKey.properties.publicKey
          }
        ]
      }
    }
    
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '10.2.0.0/16'
      dnsServiceIP: '10.2.0.10'
      loadBalancerSku: 'standard'
    }
    
    addonProfiles: {
      omsagent: {
        enabled: enableMonitoring
        config: {
          logAnalyticsWorkspaceResourceID: logAnalytics.id
        }
      }
      azurepolicy: {
        enabled: enableAzurePolicy
      }
      ingressApplicationGateway: {
        enabled: false
      }
    }
    
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
    }
    
    oidcIssuerProfile: {
      enabled: true
    }
    
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
  }
}

// Role assignment: AKS to pull images from ACR
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(resourceGroup().id, aksCluster.id, acr.id, 'AcrPull')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull role
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

resource contosoApiManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: contosoApiManagedIdentityName
  location: location
}

resource contosoApiFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: contosoApiManagedIdentity
  name: 'fed-${contosoApiManagedIdentityName}'
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    // Subject format MUST strictly match: system:serviceaccount:<namespace>:<service-account-name>
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sContosoApiServiceAccountName}'
  }
}

resource contosoApiManagedIdentityToKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: contosoApiManagedIdentityToKeyVaultRoleAssignmentName
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', keyVaultCertificateUserRoleDefinitionID)
    principalId: contosoApiManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Diagnostic settings for AKS
resource aksDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  scope: aksCluster
  name: '${aksClusterName}-diagnostics'
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'kube-apiserver'
        enabled: true
      }
      {
        category: 'kube-controller-manager'
        enabled: true
      }
      {
        category: 'kube-scheduler'
        enabled: true
      }
      {
        category: 'kube-audit'
        enabled: true
      }
      {
        category: 'cluster-autoscaler'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

module  createKeyVaultAndCertificate './create-key-vault-and-cert.bicep' = {
  name: 'createKeyVaultAndCertificate'
}

// Outputs
output aksClusterName string = aksCluster.name
output aksClusterId string = aksCluster.id
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output keyVaultName string = keyVault.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output logAnalyticsWorkspaceId string = logAnalytics.id
output logAnalyticsWorkspaceName string = logAnalytics.name
output aksNodeResourceGroup string = aksCluster.properties.nodeResourceGroup
output aksApiServerAddress string = aksCluster.properties.fqdn
output managedIdentityClientId string = contosoApiManagedIdentity.properties.clientId
output contosoApiServiceAccountName string = k8sContosoApiServiceAccountName
output kubernetesNamespace string = k8sNamespace
output contosoBslCertificateThumbprint string = createKeyVaultAndCertificate.outputs.certificateThumbprint
