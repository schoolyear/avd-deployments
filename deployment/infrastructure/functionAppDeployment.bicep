param targetGroupId string

param appServicePlanName string
param appServicePlanTags object
param functionAppName string
param functionAppTags object

param FunctionAppAddDeviceToGroupFunctionName string = 'AddDeviceToGroup'
param FunctionAppAddDevicesToGroupBatchFunctionName string = 'AddDevicesToGroupBatch'
param FunctionAppRemoveDeviceFromGroupFunctionName string = 'RemoveDeviceFromGroup'
param FunctionAppRemoveDevicesFromGroupBatchFunctionName string = 'RemoveDevicesFromGroupBatch'

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: resourceGroup().location
  tags: appServicePlanTags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
  properties: {}
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: resourceGroup().location
  kind: 'functionapp'
  tags: functionAppTags
  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
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
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
}

resource addDeviceToGroupFunction 'Microsoft.Web/sites/functions@2021-01-15' = {
  name: FunctionAppAddDeviceToGroupFunctionName
  parent: functionApp
  properties: {
    config: {
      bindings: [
        {
          authLevel: 'anonymous'
          type: 'httpTrigger'
          direction: 'in'
          name: 'Request'
          methods: [
            'post'
          ]
        }
        {
          type: 'http'
          direction: 'out'
          name: 'Response'
        }
      ]
    }
    files: {
      'run.ps1': loadTextContent('./addDeviceToGroup.ps1')
    }
  }
}

resource addDevicesToGroupBatchFunction 'Microsoft.Web/sites/functions@2021-01-15' = {
  name: FunctionAppAddDevicesToGroupBatchFunctionName
  parent: functionApp
  properties: {
    config: {
      bindings: [
        {
          authLevel: 'anonymous'
          type: 'httpTrigger'
          direction: 'in'
          name: 'Request'
          methods: [
            'post'
          ]
        }
        {
          type: 'http'
          direction: 'out'
          name: 'Response'
        }
      ]
    }
    files: {
      'run.ps1': loadTextContent('./addDevicesToGroupBatch.ps1')
    }
  }
}

resource removeDeviceFromGroupFunction 'Microsoft.Web/sites/functions@2021-01-15' = {
  name: FunctionAppRemoveDeviceFromGroupFunctionName
  parent: functionApp
  properties: {
    config: {
      bindings: [
        {
          authLevel: 'anonymous'
          type: 'httpTrigger'
          direction: 'in'
          name: 'Request'
          methods: [
            'post'
          ]
        }
        {
          type: 'http'
          direction: 'out'
          name: 'Response'
        }
      ]
    }
    files: {
      'run.ps1': loadTextContent('./removeDeviceFromGroup.ps1')
    }
  }
}

resource removeDevicesFromGroupBatchFunction 'Microsoft.Web/sites/functions@2021-01-15' = {
  name: FunctionAppRemoveDevicesFromGroupBatchFunctionName
  parent: functionApp
  properties: {
    config: {
      bindings: [
        {
          authLevel: 'anonymous'
          type: 'httpTrigger'
          direction: 'in'
          name: 'Request'
          methods: [
            'post'
          ]
        }
        {
          type: 'http'
          direction: 'out'
          name: 'Response'
        }
      ]
    }
    files: {
      'run.ps1': loadTextContent('./removeDevicesFromGroupBatch.ps1')
    }
  }
}


output appServicePlanName string = appServicePlan.name
output functionAppName string = functionApp.name
// functions
output functionAppAddDeviceToGroupFunctionName string = addDeviceToGroupFunction.name
output functionAppAddDeviceToGroupInvokeUrl string = addDeviceToGroupFunction.properties.invoke_url_template
output functionAppAddDevicesToGroupBatchFunctionName string = addDevicesToGroupBatchFunction.name
output functionAppAddDevicesToGroupBatchInvokeUrl string = addDevicesToGroupBatchFunction.properties.invoke_url_template
output functionAppRemoveDeviceFromGroupFunctionName string = removeDeviceFromGroupFunction.name
output functionAppRemoveDeviceFromGroupInvokeUrl string = removeDeviceFromGroupFunction.properties.invoke_url_template
output functionAppRemoveDevicesFromGroupBatchFunctionName string = removeDevicesFromGroupBatchFunction.name
output functionAppRemoveDevicesFromGroupBatchInvokeUrl string = removeDevicesFromGroupBatchFunction.properties.invoke_url_template
