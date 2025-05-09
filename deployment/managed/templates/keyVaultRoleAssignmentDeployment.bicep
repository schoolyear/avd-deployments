param proxyVmName string
param proxyPrincipalId string
param keyVaultResourceGroup string
param keyVaultName string

var roleAssignmentName = guid(resourceGroup().id, proxyVmName, '4633458b-17de-408a-b874-0445c86b69e6')

// We use the 'existing' keyword to reference this keyVault in the roleAssignment
resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
  name: keyVaultName
}

// This must be scoped to the keyVault and not the resourceGroup
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  scope: keyVault
  
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: proxyPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output resourceUrl string = 'https://management.azure.com/subscriptions/${subscription().subscriptionId}/resourcegroups/${keyVaultResourceGroup}/providers/Microsoft.KeyVault/vaults/${keyVaultName}/providers/Microsoft.Authorization/roleAssignments/${roleAssignmentName}?api-version=2022-04-01'
