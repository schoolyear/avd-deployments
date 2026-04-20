param location string
param storageAccountTags object
param storageAccountName string
param storageAccountBlobServiceName string
param storageAccountContainerName string
param appRegistrationServicePrincipalId string

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  tags: storageAccountTags
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    // Disables raw account-key auth, forcing Azure AD only. The BE generates User Delegation SAS
    // (signed with service principal credentials) via the generateUserDelegationKey permission
    // (already present in our custom role).
    allowSharedKeyAccess: false
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: storageAccount
  name: storageAccountBlobServiceName

  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource backupsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobService
  name: storageAccountContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2022-09-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'backup-expiry'
          type: 'Lifecycle'
          enabled: true
          definition: {
            filters: {
              blobTypes: [
                'blockBlob'
              ]
            }
            actions: {
              baseBlob: {
                delete: {
                  daysAfterModificationGreaterThan: 30 // TTL of 30 days
                }
              }
            }
          }
        }
      ]
    }
  }
}

// Grants the 'Storage Blob Data Contributor' built-in role to our Service Principal
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
resource appRegistrationStorageBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(tenant().tenantId, appRegistrationServicePrincipalId, storageBlobDataContributorRoleId, storageAccount.id)
  scope: storageAccount

  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: appRegistrationServicePrincipalId
    principalType: 'ServicePrincipal'
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output storageAccountContainerName string = backupsContainer.name
