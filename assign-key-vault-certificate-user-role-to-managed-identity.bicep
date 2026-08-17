@description('Set the Key Vault Certificate User Role Definition ID')
param keyVaultCertificateUserRoleDefinitionID string = 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba'

@description('Specifies the name of the managed identity.')
param managedIdentityName string

@description('The key vault name we need the permissions for.')
param keyVaultName string

@description('Generate a unique GUID to use as name for the role assignment')
var managedIdentityToKeyVaultRoleAssignmentName = guid(managedIdentity.id, keyVaultCertificateUserRoleDefinitionID, keyVault.id)

resource keyVault 'Microsoft.KeyVault/vaults@2026-02-01' existing = {
  name: keyVaultName
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: managedIdentityName
}

resource managedIdentityToKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: managedIdentityToKeyVaultRoleAssignmentName
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', keyVaultCertificateUserRoleDefinitionID)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
