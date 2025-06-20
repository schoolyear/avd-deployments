param keyVaultName string
param keyVaultTags object

// Create the Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2024-12-01-preview' = {
  name: keyVaultName
  location: resourceGroup().location
  tags: keyVaultTags

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
