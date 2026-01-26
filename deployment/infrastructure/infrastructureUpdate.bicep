targetScope = 'subscription'

param tagsByResource object
param baseResourceGroupName string
param vmLoginCustomRoleName string

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

// We can't really use a module for this, because Modules cannot be deployed at the subscription 
// scope directly from a subscription-scoped template.
// Custom role definition for Assigning VM Login roles to users
resource vmLoginCustomRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(tenant().tenantId, subscription().subscriptionId, vmLoginCustomRoleName)
  properties: {
    roleName: vmLoginCustomRoleName
    description: 'Custom role for allowing users to log into the VMs. We use this role instead of doing 2 role assignments in the backend (Virtual Machine User Login & Desktop Virtualization User).'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Network/publicIPAddresses/read'
          'Microsoft.Network/virtualNetworks/read'
          'Microsoft.Network/loadBalancers/read'
          'Microsoft.Network/networkInterfaces/read'
          'Microsoft.Compute/virtualMachines/*/read'
          'Microsoft.HybridCompute/machines/*/read'
          'Microsoft.HybridConnectivity/endpoints/listCredentials/action'
        ]
        notActions: []
        dataActions: [
          'Microsoft.DesktopVirtualization/applicationGroups/useApplications/action'
          'Microsoft.DesktopVirtualization/appAttachPackages/useApplications/action'
          'Microsoft.Compute/virtualMachines/login/action'
          'Microsoft.HybridCompute/machines/login/action'
        ]
        notDataActions: []
      }
    ]
    assignableScopes: [
      subscription().id
    ]
  }
}

output installationOutput object = {
  vm_login_custom_role_id: vmLoginCustomRole.id
  // function app related
  function_app: {
    name: functionAppDeployment.outputs.functionAppName
    app_service_plan_name: functionAppDeployment.outputs.appServicePlanName
    // functions
    add_device_to_group_function_name: functionAppDeployment.outputs.functionAppAddDeviceToGroupFunctionName
    add_device_to_group_invoke_url: functionAppDeployment.outputs.functionAppAddDeviceToGroupInvokeUrl
    delete_devices_based_on_prefix_function_name: functionAppDeployment.outputs.functionAppDeleteDevicesBasedOnPrefixFunctionName
    delete_devices_based_on_prefix_invoke_url: functionAppDeployment.outputs.functionAppDeleteDevicesBasedOnPrefixInvokeUrl
  }
}
