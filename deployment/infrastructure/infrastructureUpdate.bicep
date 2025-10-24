targetScope = 'subscription'

param tagsByResource object
param baseResourceGroupName string

// Needed from the Function app to configure the Function
param functionAppTargetGroupId string
param appServicePlanName string
param functionAppName string

// NOTE: Will be baked in with each release
var version = '<<BAKED-IN>>'
var versionTag = {
  Version: version
}

// Always append the version to already provided tags
var tagsByResourceWithVersion = reduce(items(tagsByResource), {}, (acc, item) => union(acc, {
  '${item.key}': union(item.value, versionTag)
}))

resource baseResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: baseResourceGroupName
}

// Function App Deployment
var appServicePlanTags = tagsByResourceWithVersion[?'Microsoft.Web/serverfarms@2023-01-01'] ?? versionTag
var functionAppTags = tagsByResourceWithVersion[?'Microsoft.Web/sites@2023-01-01'] ?? versionTag
module functionAppDeployment 'functionAppDeployment.bicep' = {
  scope: baseResourceGroup

  params: {
    targetGroupId: functionAppTargetGroupId
    appServicePlanName: appServicePlanName
    appServicePlanTags: appServicePlanTags
    functionAppName: functionAppName
    functionAppTags: functionAppTags
  }
}

output installationOutput object = {
  // function app related
  function_app: {
    name: functionAppDeployment.outputs.functionAppName
    app_service_plan_name: functionAppDeployment.outputs.appServicePlanName
    // functions
    add_device_to_group_function_name: functionAppDeployment.outputs.functionAppAddDeviceToGroupFunctionName
    add_device_to_group_invoke_url: functionAppDeployment.outputs.functionAppAddDeviceToGroupInvokeUrl
    remove_devices_from_group_based_on_prefix_function_name: functionAppDeployment.outputs.functionAppRemoveDevicesFromGroupBasedOnPrefixFunctionName
    remove_devices_from_group_based_on_prefix_invoke_url: functionAppDeployment.outputs.functionAppRemoveDevicesFromGroupBasedOnPrefixInvokeUrl
  }
}
