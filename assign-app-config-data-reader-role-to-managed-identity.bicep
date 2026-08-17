@description('Set the App Configuration Data Reader Role Definition ID')
param appConfigDataReaderRoleId string = '516239f1-63e1-4d78-a4de-a74fb236a071'

@description('Specifies the name of the managed identity.')
param managedIdentityName string

@description('The App Configuration name we need the permissions for.')
param appConfigName string

@description('Generate a unique GUID to use as name for the role assignment')
var managedIdentityToAppConfigurationRoleAssignmentName = guid(managedIdentity.id, appConfigDataReaderRoleId, appConfig.id)

resource appConfig 'Microsoft.AppConfiguration/configurationStores@2024-05-01' existing = {
  name: appConfigName
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: managedIdentityName
}

resource managedIdentityToAppConfigRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: appConfig
  name: managedIdentityToAppConfigurationRoleAssignmentName
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', appConfigDataReaderRoleId)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
