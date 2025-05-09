param keyVaultName string
param tags object

// Create the Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2024-12-01-preview' = {
  name: keyVaultName
  location: resourceGroup().location
  tags: tags

  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: subscription().tenantId
    publicNetworkAccess: 'enabled'
    enableRbacAuthorization: true
  }
}

// // Key Vault Administrator role definition ID
// // https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/security#key-vault-administrator
// var keyVaultAdministratorRoleDefinitionId = '00482a5a-887f-4fb3-b363-3b7fe8e74483'

// // Assign the 'Key Vault Administrator' role to the user
// resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(tenant().tenantId, keyVault.id, userPrincipalId, keyVaultAdministratorRoleDefinitionId)
//   scope: resourceGroup()

//   properties: {
//     roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', keyVaultAdministratorRoleDefinitionId)
//     principalId: userPrincipalId
//     principalType: 'User'
//   }
// }
