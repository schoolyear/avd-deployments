targetScope = 'subscription'

param location string
param tagsByResource object
param avdMetadataLocation string

// App registration is created before this installation script is run
// however we need this param here to automate the 
// necessary role assignment (needs ownership on the subscription)
param appRegistrationServicePrincipalId string

// Resources that may be renamed
param baseResourceGroupName string
param dnsZoneName string
param keyVaultName string
param imageBuildingResourceGroupName string
param imageGalleryName string
param storageAccountName string
param storageAccountBlobServiceName string
param storageAccountContainerName string
param imageBuilderCustomRoleName string
param managedIdentityName string
param appRegistrationCustomRoleName string

// Network specific
param networkRgName string
param networkRgLocation string
param natIpName string
param natName string
param vnetName string
param vnetSubnetCIDR string
param avdEndpointsSubnetName string
param avdEndpointsSubnetCIDR string
param sessionhostsSubnetName string
param sessionhostsSubnetCIDR string
param servicesSubnetName string
param servicesSubnetCIDR string
param privatelinkZoneName string

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

// Create your main resource group after providers are registered
var rgTags = tagsByResourceWithVersion[?'Microsoft.Resources/resourceGroups'] ?? versionTag
resource baseResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: baseResourceGroupName
  location: location
  tags: rgTags
}

// DNS Zone deployment
var dnsZoneTags = tagsByResourceWithVersion[?'Microsoft.Network/dnsZones'] ?? versionTag
module dnsZone 'dnsDeployment.bicep' = {
  scope: baseResourceGroup

  params : {
    dnsZoneName: dnsZoneName
    dnsZoneTags: dnsZoneTags
  }
}

// KeyVault Deployment
var keyVaultTags = tagsByResourceWithVersion[?'Microsoft.KeyVault/vaults'] ?? versionTag
module keyVaultDeployment 'keyVaultDeployment.bicep' = {
  scope: baseResourceGroup

  params: {
    keyVaultName: keyVaultName 
    keyVaultTags: keyVaultTags
  }
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
// Custom role definition for your App Registration
resource appRegistrationCustomRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(tenant().tenantId, subscription().subscriptionId, appRegistrationCustomRoleName)
  properties: {
    roleName: appRegistrationCustomRoleName
    description: 'Custom role for the SY App Registration backend operations'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          // Resource management
          'Microsoft.Resources/subscriptions/resourceGroups/read'
          'Microsoft.Resources/subscriptions/resourceGroups/write'
          'Microsoft.Resources/subscriptions/resourceGroups/delete'
          'Microsoft.Resources/deployments/*'
          'Microsoft.Resources/deployments/operations/read'
          
          // Get resources by ID (general read access)
          'Microsoft.Resources/subscriptions/resources/read'
          'Microsoft.Resources/subscriptions/resourceGroups/resources/read'
          
          // Compute Gallery (for image versions)
          'Microsoft.Compute/galleries/read'
          'Microsoft.Compute/galleries/images/read'
          'Microsoft.Compute/galleries/images/versions/read'
          
          // Storage account operations
          'Microsoft.Storage/storageAccounts/read'
          'Microsoft.Storage/storageAccounts/write'
          'Microsoft.Storage/storageAccounts/delete'
          'Microsoft.Storage/storageAccounts/blobServices/read'
          'Microsoft.Storage/storageAccounts/blobServices/containers/read'
          'Microsoft.Storage/storageAccounts/blobServices/containers/write'
          'Microsoft.Storage/storageAccounts/blobServices/containers/delete'
          'Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action'
          
          // AVD specific operations - ALL PERMISSIONS
          'Microsoft.DesktopVirtualization/hostPools/*'
          'Microsoft.DesktopVirtualization/workspaces/*'
          'Microsoft.DesktopVirtualization/applicationGroups/*'

          // VM actions for AVD session hosts
          'Microsoft.Compute/virtualMachines/read'
          'Microsoft.Compute/virtualMachines/write'
          'Microsoft.Compute/virtualMachines/delete'
          'Microsoft.Compute/virtualMachines/restart/action'
          'Microsoft.Compute/virtualMachines/start/action'
          'Microsoft.Compute/virtualMachines/deallocate/action'
          'Microsoft.Compute/virtualMachines/powerOff/action'
          
          // VM Extensions
          'Microsoft.Compute/virtualMachines/extensions/read'
          'Microsoft.Compute/virtualMachines/extensions/write'
          'Microsoft.Compute/virtualMachines/extensions/delete'
          
          // Role assignments for VM user roles
          'Microsoft.Authorization/roleAssignments/read'
          'Microsoft.Authorization/roleAssignments/write'
          'Microsoft.Authorization/roleAssignments/delete'
          'Microsoft.Authorization/roleDefinitions/read'
          'Microsoft.Authorization/permissions/read'
          'Microsoft.Authorization/providerOperations/read'
          
          // Network resources (if needed)
          'Microsoft.Network/virtualNetworks/read'
          'Microsoft.Network/virtualNetworks/subnets/read'
          'Microsoft.Network/networkInterfaces/read'
          'Microsoft.Network/networkInterfaces/write'
          'Microsoft.Network/networkInterfaces/delete'
          'Microsoft.Network/networkInterfaces/join/action'

          // Private Endpoints
          'Microsoft.Network/privateEndpoints/read'
          'Microsoft.Network/privateEndpoints/write'
          'Microsoft.Network/privateEndpoints/delete'
          'Microsoft.Network/privateEndpoints/privateDnsZoneGroups/read'
          'Microsoft.Network/privateEndpoints/privateDnsZoneGroups/write'
          'Microsoft.Network/privateEndpoints/privateDnsZoneGroups/delete'

          // Public IP Addresses
          'Microsoft.Network/publicIPAddresses/read'
          'Microsoft.Network/publicIPAddresses/write'
          'Microsoft.Network/publicIPAddresses/delete'

          // Load Balancers
          'Microsoft.Network/loadBalancers/read'
          'Microsoft.Network/loadBalancers/write'
          'Microsoft.Network/loadBalancers/delete'

          // Load balancer backend pool join action (for network interfaces)
          'Microsoft.Network/loadBalancers/backendAddressPools/join/action'

          // Subnet join actions (for private endpoints and load balancers)
          'Microsoft.Network/virtualNetworks/subnets/join/action'
          
          // Public IP join actions (for load balancers)
          'Microsoft.Network/publicIPAddresses/join/action'

          // Network Security Groups
          'Microsoft.Network/networkSecurityGroups/read'
          'Microsoft.Network/networkSecurityGroups/write'
          'Microsoft.Network/networkSecurityGroups/delete'

          // Network Security Group join action (for network interfaces)
          'Microsoft.Network/networkSecurityGroups/join/action'

          // DNS Zone operations (needed for deleting extra exam resources)
          'Microsoft.Network/dnsZones/A/read'
          'Microsoft.Network/dnsZones/A/write'
          'Microsoft.Network/dnsZones/A/delete'
          
          // Private DNS Zones (needed for private endpoints) - ALL PERMISSIONS
          'Microsoft.Network/privateDnsZones/*'
          
          // Monitoring and logging
          'Microsoft.Insights/*/read'
          'Microsoft.Support/*'

          // Read quotas
          'Microsoft.Compute/locations/usages/read'
          'Microsoft.Network/locations/usages/read'
          'Microsoft.Storage/locations/usages/read'
          'Microsoft.Quota/quotas/read'
          'Microsoft.Quota/usages/read'
        ]
        notActions: []
        dataActions: [
          // Storage blob data access
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write'
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete'
        ]
        notDataActions: []
      }
    ]
    assignableScopes: [
      subscription().id
    ]
  }
}

resource appRegistrationServicePrincipalCustomRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(tenant().tenantId, subscription().id, appRegistrationServicePrincipalId, appRegistrationCustomRole.id)
  scope: subscription()

  properties: {
    principalId: appRegistrationServicePrincipalId
    roleDefinitionId: appRegistrationCustomRole.id
    principalType: 'ServicePrincipal'
  }
}

resource imageBuildingResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: imageBuildingResourceGroupName
  location: location
  tags: rgTags
}

// Image building resources
var imageGalleryTags = tagsByResourceWithVersion[?'Microsoft.Compute/galleries'] ?? versionTag
var storageAccountTags = tagsByResourceWithVersion[?'Microsoft.Storage/storageAccounts'] ?? versionTag
var managedIdentityTags = tagsByResourceWithVersion[?'Microsoft.ManagedIdentity/userAssignedIdentities'] ?? versionTag
module imageBuildingResources 'imageBuildingResources.bicep' = {
  scope: imageBuildingResourceGroup

  params: {
    location: location
    imageGalleryTags: imageGalleryTags
    storageAccountTags: storageAccountTags
    managedIdentityTags: managedIdentityTags
    imageGalleryName: imageGalleryName
    storageAccountName: storageAccountName
    storageAccountBlobServiceName: storageAccountBlobServiceName
    storageAccountContainerName: storageAccountContainerName
    imageBuilderCustomRoleName: imageBuilderCustomRoleName
    managedIdentityName: managedIdentityName
    appRegistrationServicePrincipalId: appRegistrationServicePrincipalId
  }
}

// Network resource group, all exams will connect to the subnets in this 
// resource group
resource networkResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: networkRgName
  location: networkRgLocation
  tags: rgTags
}

var publicIpAddressTags = tagsByResourceWithVersion[?'Microsoft.Network/publicIPAddresses'] ?? versionTag
var natTags = tagsByResourceWithVersion[?'Microsoft.Network/natGateways'] ?? versionTag
var vnetTags = tagsByResourceWithVersion[?'Microsoft.Network/virtualNetworks'] ?? versionTag
var privateDnsZoneTags = tagsByResourceWithVersion[?'Microsoft.Network/privateDnsZones'] ?? versionTag
var privateDnsZoneVnetLinkTags = tagsByResourceWithVersion[?'Microsoft.Network/privateDnsZones/virtualNetworkLinks'] ?? versionTag
module networkResources 'network.bicep' = {
  scope: networkResourceGroup

  params: {
    location: location
    publicIpAddressTags: publicIpAddressTags
    natTags: natTags
    vnetTags: vnetTags
    privateDnsZoneTags: privateDnsZoneTags
    privateDnsZoneVnetLinkTags: privateDnsZoneVnetLinkTags
    natIpName: natIpName
    natName: natName
    vnetName: vnetName
    vnetSubnetCIDR: vnetSubnetCIDR
    avdEndpointsSubnetName: avdEndpointsSubnetName
    avdEndpointsCIDR: avdEndpointsSubnetCIDR
    sessionhostsSubnetName: sessionhostsSubnetName
    sessionhostsCIDR: sessionhostsSubnetCIDR
    servicesSubnetName: servicesSubnetName
    servicesCIDR: servicesSubnetCIDR
    privatelinkZoneName: privatelinkZoneName
  }
}

output installationOutput object = {
  // infra config needed by the BE
  tenant_id: tenant().tenantId
  subscription_id: subscription().subscriptionId
  base_rg_name: baseResourceGroupName
  base_rg_location: baseResourceGroup.location
  dns_zone_name: dnsZoneName
  key_vault_name: keyVaultName
  image_builder_rg_name: imageBuildingResourceGroup.name
  image_builder_rg_location: imageBuildingResourceGroup.location
  image_builder_managed_identity_name: imageBuildingResources.outputs.managedIdentityId
  image_gallery_name: imageBuildingResources.outputs.imageGalleryName
  storage_account_name: imageBuildingResources.outputs.storageAccountName
  storage_account_container_name: imageBuildingResources.outputs.storageAccountContainerName
  avd_metadata_location: avdMetadataLocation
  
  // function app related
  function_app: {
    name: functionAppDeployment.outputs.functionAppName
    app_service_plan_name: functionAppDeployment.outputs.appServicePlanName
    // functions
    add_device_to_group_function_name: functionAppDeployment.outputs.functionAppAddDeviceToGroupFunctionName
    add_device_to_group_invoke_url: functionAppDeployment.outputs.functionAppAddDeviceToGroupInvokeUrl
    add_devices_to_group_batch_function_name: functionAppDeployment.outputs.functionAppAddDevicesToGroupBatchFunctionName
    add_devices_to_group_batch_invoke_url: functionAppDeployment.outputs.functionAppAddDevicesToGroupBatchInvokeUrl
    remove_device_from_group_function_name: functionAppDeployment.outputs.functionAppRemoveDeviceFromGroupFunctionName
    remove_device_from_group_invoke_url: functionAppDeployment.outputs.functionAppRemoveDeviceFromGroupInvokeUrl
    remove_devices_from_group_batch_function_name: functionAppDeployment.outputs.functionAppRemoveDevicesFromGroupBatchFunctionName
    remove_devices_from_group_batch_invoke_url: functionAppDeployment.outputs.functionAppRemoveDevicesFromGroupBatchInvokeUrl
  }

  tags_by_resource: tagsByResourceWithVersion
  
  virtual_networks: {
    '${networkResourceGroup.location}': {
      name: vnetName
      ip_range: vnetSubnetCIDR
      rg_name: networkResourceGroup.name
      public_ips: networkResources.outputs.ipAddresses
      private_dns_zone_id: networkResources.outputs.privateDnsZoneId

      avd_endpoints_subnet: {
        id: networkResources.outputs.avdEndpointsSubnetId
        name: avdEndpointsSubnetName
        ip_range: avdEndpointsSubnetCIDR
      }

      sessionhosts_subnet: {
        id: networkResources.outputs.sessionHostsSubnetId
        name: sessionhostsSubnetName
        ip_range: sessionhostsSubnetCIDR
      }

      services_subnet: {
        id: networkResources.outputs.servicesSubnetId
        name: servicesSubnetName
        ip_range: servicesSubnetCIDR
      }
    }
  }

  // not needed by BE
  dns_zone_nameservers: dnsZone.outputs.nameservers
}
