param appServicePlanName string
param appServicePlanTags object
param functionAppName string
param functionAppTags object

param targetGroupId string

param FunctionAppAddDeviceToGroupFunctionName string = 'AddDeviceToGroup'
param FunctionAppDeleteDevicesBasedOnPrefixName string = 'DeleteDevicesBasedOnPrefix'

param functionAppStorageAccountName string
param functionAppStorageBlobEndpoint string
param functionAppStorageContainerName string

resource functionAppStorageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: functionAppStorageAccountName
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: resourceGroup().location
  tags: appServicePlanTags
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'functionapp,linux'
  properties: {
    // this is actually required and an indicator that this is linux and not windows, has to be paired with kind: `functionapp,linux`
    reserved: true 
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: resourceGroup().location
  kind: 'functionapp,linux'
  tags: functionAppTags
  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      appSettings: [
        // The Functions host uses blob/queue/table as three separate data-plane APIs
        // on the same storage account (key storage + deployment package on blob, internal
        // lease/lock coordination on queue, internal bookkeeping on table) - regardless of
        // which trigger types the functions themselves use.
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: 'https://${functionAppStorageAccountName}.blob.${environment().suffixes.storage}'
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: 'https://${functionAppStorageAccountName}.queue.${environment().suffixes.storage}'
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: 'https://${functionAppStorageAccountName}.table.${environment().suffixes.storage}'
        }
        {
          name: 'TARGET_GROUP_ID'
          value: targetGroupId
        }
        {
          name: 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS'
          value: tenant().tenantId
        }
      ]
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${functionAppStorageBlobEndpoint}${functionAppStorageContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      runtime: {
        name: 'powershell'
        version: '7.4'
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        // Starting point, not a platform limit (Flex Consumption allows up to 1000).
        // 100 instances * 16 perInstanceConcurrency = 1600 theoretical concurrent capacity.
        // We can raise this if it starts to cause problems (unlikely).
        // Cost is execution-based, so a higher ceiling doesn't cost anything while idle.
        maximumInstanceCount: 100
        alwaysReady: []
        triggers: {
          http: {
            perInstanceConcurrency: 16
          }
        }
      }
    }
  }
}

// Grants the Function App's own system-assigned identity access to its storage account:
// AzureWebJobsStorage__* host operations (blob/queue/table) AND pulling the Flex Consumption
// deployment package from the configured blob container. 
// Role IDs taken from Microsoft's official Flex Consumption Bicep samples [https://github.com/Azure-Samples/azure-functions-flex-consumption-samples/blob/main/IaC/bicep/rbac.bicep]
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
resource functionAppStorageBlobDataOwnerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(tenant().tenantId, functionApp.id, storageBlobDataOwnerRoleId, functionAppStorageAccount.id)
  scope: functionAppStorageAccount

  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
resource functionAppStorageQueueDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(tenant().tenantId, functionApp.id, storageQueueDataContributorRoleId, functionAppStorageAccount.id)
  scope: functionAppStorageAccount

  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
resource functionAppStorageTableDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(tenant().tenantId, functionApp.id, storageTableDataContributorRoleId, functionAppStorageAccount.id)
  scope: functionAppStorageAccount

  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output appServicePlanName string = appServicePlan.name
output functionAppName string = functionApp.name
output functionAppAddDeviceToGroupFunctionName string = FunctionAppAddDeviceToGroupFunctionName
output functionAppAddDeviceToGroupInvokeUrl string = 'https://${functionApp.properties.defaultHostName}/api/${FunctionAppAddDeviceToGroupFunctionName}'
output functionAppDeleteDevicesBasedOnPrefixFunctionName string = FunctionAppDeleteDevicesBasedOnPrefixName
output functionAppDeleteDevicesBasedOnPrefixInvokeUrl string = 'https://${functionApp.properties.defaultHostName}/api/${FunctionAppDeleteDevicesBasedOnPrefixName}'
