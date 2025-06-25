param location string

param imageGalleryTags object
param imageDefinitionTags object
param storageAccountTags object
param managedIdentityTags object

param imageGalleryName string
param imageDefinitionName string
param storageAccountName string
param storageAccountBlobServiceName string
param storageAccountContainerName string
param imageBuilderCustomRoleName string
param managedIdentityName string

resource imageGallery 'Microsoft.Compute/galleries@2022-03-03' = {
  name: imageGalleryName
  location: location
  tags: imageGalleryTags
}

resource imageDefinition 'Microsoft.Compute/galleries/images@2022-03-03' = {
  name: imageDefinitionName
  parent: imageGallery
  location: location
  tags: imageDefinitionTags

  properties: {
    osType: 'Windows'
    osState: 'Generalized'
    identifier: {
      publisher: 'avd-deployments'
      offer: 'office365'
      sku: 'standard'
    }
    hyperVGeneration: 'V2'
    features: [
      {
        name: 'SecurityType'
        value: 'TrustedLaunchSupported'
      }
    ]
  }
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  tags: storageAccountTags
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
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

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobService
  name: storageAccountContainerName
}

// Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: managedIdentityName
  location: location
  tags: managedIdentityTags
}

// 'Storage Blob Data Reader' role to the managed identity
var storageBlobDataReaderRoleDefinitionId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
resource managedIdentityStorageBlobDataReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(tenant().tenantId, managedIdentity.id, storageBlobDataReaderRoleDefinitionId)
  scope: storageAccount

  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleDefinitionId)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Create the custom role definition for 'schoolyearavd-imagebuilder'
resource customRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(tenant().tenantId, subscription().subscriptionId, imageBuilderCustomRoleName)

  properties: {
    roleName: imageBuilderCustomRoleName
    description: 'Custom role for Azure Image Builder service'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Compute/galleries/read'
          'Microsoft.Compute/galleries/images/read'
          'Microsoft.Compute/galleries/images/versions/read'
          'Microsoft.Compute/galleries/images/versions/write'
          'Microsoft.Compute/images/read'
          'Microsoft.Compute/images/write'
          'Microsoft.Compute/images/delete'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

resource managedIdentityCustomRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(tenant().tenantId, managedIdentity.id, managedIdentity.id, customRoleDefinition.id)
  scope: resourceGroup()

  properties: {
    roleDefinitionId: customRoleDefinition.id
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output managedIdentityId string = managedIdentity.id
output imageGalleryName string = imageGallery.name
output storageAccountName string = storageAccount.name
output storageAccountContainerName string = container.name
