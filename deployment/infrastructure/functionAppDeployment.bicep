param targetGroupId string

param appServicePlanName string
param appServicePlanTags object
param functionAppName string
param functionAppTags object

param FunctionAppAddDeviceToGroupFunctionName string = 'AddDeviceToGroup'
param FunctionAppDeleteDevicesBasedOnPrefixName string = 'DeleteDevicesBasedOnPrefix'

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

resource deleteDevicesBasedOnPrefixFunction 'Microsoft.Web/sites/functions@2021-01-15' = {
  name: FunctionAppDeleteDevicesBasedOnPrefixName
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
      'run.ps1': loadTextContent('./deleteDevicesBasedOnPrefix.ps1')
    }
  }
}

output appServicePlanName string = appServicePlan.name
output functionAppName string = functionApp.name
// functions
output functionAppAddDeviceToGroupFunctionName string = addDeviceToGroupFunction.name
output functionAppAddDeviceToGroupInvokeUrl string = addDeviceToGroupFunction.properties.invoke_url_template
output functionAppDeleteDevicesBasedOnPrefixFunctionName string = deleteDevicesBasedOnPrefixFunction.name
output functionAppDeleteDevicesBasedOnPrefixInvokeUrl string = deleteDevicesBasedOnPrefixFunction.properties.invoke_url_template
