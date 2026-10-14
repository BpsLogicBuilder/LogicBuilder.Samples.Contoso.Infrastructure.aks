@description('Specifies the foundry resource.')
param foundryAccountResourceName string

@description('Specifies the name of the container app.')
param managedIdentityPrincipalId string

@description('Computed role assignment name')
param managedIdentityToFoundryRoleAssignmentName string

param foundryUserRoleDefinitionID string = '53ca6127-db72-4b80-b1b0-d745d6d5456d'

resource foundryAccountResource 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountResourceName
}

resource containerAppToFoundryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccountResource
  name: managedIdentityToFoundryRoleAssignmentName
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', foundryUserRoleDefinitionID)
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
