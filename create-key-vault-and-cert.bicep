@description('Specifies the name of the key vault.')
param keyVaultName string ='contoso-kv-${uniqueString(resourceGroup().id)}'

@description('Specifies the certificate name.')
param certName string ='front-end-cert'

@description('The location for all resources')
param location string = resourceGroup().location

@description('Specifies the Azure Active Directory tenant ID that should be used for authenticating requests to the key vault. Get it by using Get-AzSubscription cmdlet.')
param tenantId string = subscription().tenantId

@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Managed identity resource name.')
param deployerManagedIdentityName string

@description('Resource group to which the deployer identity belongs.')
param deployerManagedIdentityResourceGroup string

resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  scope: resourceGroup(deployerManagedIdentityResourceGroup)
  name: deployerManagedIdentityName
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    tenantId: tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    sku: {
      name: skuName
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}
//Key Vault Certificates Officer                                                       a4417e6f-fecd-4de8-b567-7b0420556985
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: kv
  name: guid(kv.id, scriptIdentity.id, 'a4417e6f-fecd-4de8-b567-7b0420556985')//Key Vault Certificates Officer 
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a441034c-53c2-433b-be46-794eaa64732a')
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource createAndFetchCert 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'createAndFetchCertScript'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.53.0'
    cleanupPreference: 'Always' 
    retentionInterval: 'PT1H'
    
    arguments: '"${keyVaultName}" "${certName}"'
    scriptContent: '''
      set -e # Stop immediately if certificate creation or query fails

      # 1. Map native arguments cleanly
      VAULT_NAME=$1
      CERT_NAME=$2

      echo "Target Key Vault: $VAULT_NAME"
      echo "Target Cert Name: $CERT_NAME"

      # 2. Execute the Key Vault Certificate creation utilizing the file reference
      echo "Executing certificate creation..."
      az keyvault certificate create --vault-name "$VAULT_NAME" --name "$CERT_NAME" --policy '{"issuerParameters":{"name":"Self"},"x509CertificateProperties":{"subject":"CN=front-end-certificate"}}'
      
      # 3. Extract the string value of the thumbprint
      echo "Extracting certificate thumbprint..."
      THUMBPRINT=$(az keyvault certificate show --vault-name "$VAULT_NAME" --name "$CERT_NAME" --query "x509Thumbprint" -o tsv)
      
      # 4. Ship the output payload back to Bicep
      jq -n --arg tp "$THUMBPRINT" '{"thumbprint": $tp}' > "$AZ_SCRIPTS_OUTPUT_PATH"
    '''
  }
}


output certificateThumbprint string = createAndFetchCert.properties.outputs.thumbprint
