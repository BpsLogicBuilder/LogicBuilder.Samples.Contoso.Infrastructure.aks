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

@description('Managed Identity for contoso-api')
param contosoApiManagedIdentityName string = 'uai-${projectName}-api'

@description('Managed Identity for contoso-bsl')
param contosoBslManagedIdentityName string = 'uai-${projectName}-bsl'

@description('Managed Identity for contoso-kendo-grid-api')
param contosoKendoGridApiManagedIdentityName string = 'uai-${projectName}-kendo-grid-api'

@description('Managed Identity for contoso-kendo-grid-bsl')
param contosoKendoGridBslManagedIdentityName string = 'uai-${projectName}-kendo-grid-bsl'

@description('Managed Identity for contoso-spa-api')
param contosoSpaApiManagedIdentityName string = 'uai-${projectName}-spa-api'

@description('Managed Identity for contoso-api and contoso-kendo-grid-api')
param contosoAngularManagedIdentityName string = 'uai-${projectName}-angular'

@description('Namespace for all Contoso services in the cluster')
param k8sNamespace string = '${projectName}-apps'

@description('When the service account is assigned to sa-contoso-api, they will receive the permissions assigned to the managed identity.')
param k8sContosoApiServiceAccountName string = 'sa-${projectName}-api'

@description('When the service account is assigned to sa-contoso-bsl, they will receive the permissions assigned to the managed identity.')
param k8sContosoBslServiceAccountName string = 'sa-${projectName}-bsl'

@description('When the service account is assigned to sa-contoso-kendo-grid-api, they will receive the permissions assigned to the managed identity.')
param k8sContosoKendoGridApiServiceAccountName string = 'sa-${projectName}-kendo-grid-api'

@description('When the service account is assigned to sa-contoso-kendo-grid-bsl, they will receive the permissions assigned to the managed identity.')
param k8sContosoKendoGridBslServiceAccountName string = 'sa-${projectName}-kendo-grid-bsl'

@description('When the service account is assigned to sa-contoso-spa-api, they will receive the permissions assigned to the managed identity.')
param k8sContosoSpaApiServiceAccountName string = 'sa-${projectName}-spa-api'

@description('When the service account is assigned to sa-contoso-angular, they will receive the permissions assigned to the managed identity.')
param k8sContosoAngularServiceAccountName string = 'sa-${projectName}-angular'

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)

var aksClusterName = '${projectName}-aks-${uniqueSuffix}'
var acrName = replace('${projectName}acr${uniqueSuffix}', '-', '')
var logAnalyticsName = '${projectName}-logs-${uniqueSuffix}'
var appInsightsName = '${projectName}-insights-${uniqueSuffix}'
var appConfigurationName = '${projectName}-config-${uniqueSuffix}'
var federatedCredentialAudience = 'api://AzureADTokenExchange'

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

resource appConfiguration 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  name: appConfigurationName
  location: location
  sku: {
    name: 'standard'
  }
  identity: {
    type: 'SystemAssigned'
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

resource contosoBslManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: contosoBslManagedIdentityName
  location: location
}

resource contosoKendoGridApiManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: contosoKendoGridApiManagedIdentityName
  location: location
}

resource contosoKendoGridBslManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: contosoKendoGridBslManagedIdentityName
  location: location
}

resource contosoSpaApiManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: contosoSpaApiManagedIdentityName
  location: location
}

resource contosoAngularManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: contosoAngularManagedIdentityName
  location: location
}

resource contosoApiFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: contosoApiManagedIdentity
  name: 'fed-${contosoApiManagedIdentityName}'
  properties: {
    audiences: [
      federatedCredentialAudience
    ]
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sContosoApiServiceAccountName}'
  }
}

resource contosoBslFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: contosoBslManagedIdentity
  name: 'fed-${contosoBslManagedIdentityName}'
  properties: {
    audiences: [
      federatedCredentialAudience
    ]
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sContosoBslServiceAccountName}'
  }
}

resource contosoKendoGridApiFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: contosoKendoGridApiManagedIdentity
  name: 'fed-${contosoKendoGridApiManagedIdentityName}'
  properties: {
    audiences: [
      federatedCredentialAudience
    ]
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sContosoKendoGridApiServiceAccountName}'
  }
}

resource contosoKendoGridBslFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: contosoKendoGridBslManagedIdentity
  name: 'fed-${contosoKendoGridBslManagedIdentityName}'
  properties: {
    audiences: [
      federatedCredentialAudience
    ]
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sContosoKendoGridBslServiceAccountName}'
  }
}

resource contosoSpaApiFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: contosoSpaApiManagedIdentity
  name: 'fed-${contosoSpaApiManagedIdentityName}'
  properties: {
    audiences: [
      federatedCredentialAudience
    ]
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sContosoSpaApiServiceAccountName}'
  }
}

resource contosoAngularFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: contosoAngularManagedIdentity
  name: 'fed-${contosoAngularManagedIdentityName}'
  properties: {
    audiences: [
      federatedCredentialAudience
    ]
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sContosoAngularServiceAccountName}'
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

module apiManagedIdentityToKeyVaultCertificateUserRoleAssignment './assign-key-vault-certificate-user-role-to-managed-identity.bicep' = {
  name: 'apiManagedIdentityToKeyVaultRoleAssignment'
  params: {
    managedIdentityName: contosoApiManagedIdentity.name
    keyVaultName: keyVault.name
  }
  dependsOn: [createKeyVaultAndCertificate]
}

module kendoGridApiManagedIdentityToKeyVaultCertificateUserRoleAssignment './assign-key-vault-certificate-user-role-to-managed-identity.bicep' = {
  name: 'kendoGridApiManagedIdentityToKeyVaultRoleAssignment'
  params: {
    managedIdentityName: contosoKendoGridApiManagedIdentity.name
    keyVaultName: keyVault.name
  }
  dependsOn: [createKeyVaultAndCertificate]
}

module apiManagedIdentityToAppConfigDataReaderRoleAssignment './assign-app-config-data-reader-role-to-managed-identity.bicep' = {
  name: 'apiManagedIdentityToAppConfigRoleAssignment'
  params: {
    managedIdentityName: contosoApiManagedIdentity.name
    appConfigName: appConfiguration.name
  }
}

module kendoGridApiManagedIdentityToAppConfigDataReaderRoleAssignment './assign-app-config-data-reader-role-to-managed-identity.bicep' = {
  name: 'kendoGridApiManagedIdentityToAppConfigRoleAssignment'
  params: {
    managedIdentityName: contosoKendoGridApiManagedIdentity.name
    appConfigName: appConfiguration.name
  }
}

module bslManagedIdentityToAppConfigDataReaderRoleAssignment './assign-app-config-data-reader-role-to-managed-identity.bicep' = {
  name: 'bslManagedIdentityToAppConfigRoleAssignment'
  params: {
    managedIdentityName: contosoBslManagedIdentity.name
    appConfigName: appConfiguration.name
  }
}

module kendoGridBslManagedIdentityToAppConfigDataReaderRoleAssignment './assign-app-config-data-reader-role-to-managed-identity.bicep' = {
  name: 'kendoGridBslManagedIdentityToAppConfigRoleAssignment'
  params: {
    managedIdentityName: contosoKendoGridBslManagedIdentity.name
    appConfigName: appConfiguration.name
  }
}

module spaApiManagedIdentityToAppConfigDataReaderRoleAssignment './assign-app-config-data-reader-role-to-managed-identity.bicep' = {
  name: 'spaApiManagedIdentityToAppConfigRoleAssignment'
  params: {
    managedIdentityName: contosoSpaApiManagedIdentity.name
    appConfigName: appConfiguration.name
  }
}

module angularManagedIdentityToAppConfigDataReaderRoleAssignment './assign-app-config-data-reader-role-to-managed-identity.bicep' = {
  name: 'angularManagedIdentityToAppConfigRoleAssignment'
  params: {
    managedIdentityName: contosoAngularManagedIdentity.name
    appConfigName: appConfiguration.name
  }
}

// Outputs
output aksClusterName string = aksCluster.name
output aksClusterId string = aksCluster.id
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output keyVaultName string = keyVault.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appConfigurationEndPoint string = appConfiguration.properties.endpoint
output logAnalyticsWorkspaceId string = logAnalytics.id
output logAnalyticsWorkspaceName string = logAnalytics.name
output aksNodeResourceGroup string = aksCluster.properties.nodeResourceGroup
output aksApiServerAddress string = aksCluster.properties.fqdn
output contosoApiManagedIdentityClientId string = contosoApiManagedIdentity.properties.clientId
output contosoBslManagedIdentityClientId string = contosoBslManagedIdentity.properties.clientId
output contosoKendoGridApiManagedIdentityClientId string = contosoKendoGridApiManagedIdentity.properties.clientId
output contosoKendoGridBslManagedIdentityClientId string = contosoKendoGridBslManagedIdentity.properties.clientId
output contosoSpaApiManagedIdentityClientId string = contosoSpaApiManagedIdentity.properties.clientId
output contosoAngularManagedIdentityClientId string = contosoAngularManagedIdentity.properties.clientId
output contosoApiServiceAccountName string = k8sContosoApiServiceAccountName
output contosoBslServiceAccountName string = k8sContosoBslServiceAccountName
output contosoKendoGridApiServiceAccountName string = k8sContosoKendoGridApiServiceAccountName
output contosoKendoGridBslServiceAccountName string = k8sContosoKendoGridBslServiceAccountName
output contosoSpaApiServiceAccountName string = k8sContosoSpaApiServiceAccountName
output contosoAngularServiceAccountName string = k8sContosoAngularServiceAccountName
output kubernetesNamespace string = k8sNamespace
output contosoBslCertificateThumbprint string = createKeyVaultAndCertificate.outputs.certificateThumbprint
