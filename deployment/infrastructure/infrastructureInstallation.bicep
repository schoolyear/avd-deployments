targetScope = 'subscription'

extension microsoftGraphV1

param location string = 'germanywestcentral'
param baseResourceGroupName string = 'schoolyear-base'
param dnsZoneName string
param keyVaultName string
param appRegistrationName string
param dynamicDeviceGroupName string = 'schoolyear-avd'
@allowed(['development', 'testing', 'beta', 'production'])
param environment string = 'production'
param imageBuildingResourceGroupName string = 'imagebuilding'
param tags object = {}

// NOTE: Will be baked in with each release
var version = '0.0.0'

// Always append the version to already provided tags
var tagsWithVersion = union(tags, {
  Version: version
})

// Create your main resource group after providers are registered
resource baseResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: baseResourceGroupName
  location: location
  tags: tagsWithVersion
}

// DNS Zone deployment
module dnsZone 'dnsDeployment.bicep' = {
  scope: baseResourceGroup

  params : {
    dnsZoneName: dnsZoneName
    tags: tagsWithVersion
  }
}

// KeyVault Deployment
module keyVaultDeployment 'keyVaultDeployment.bicep' = {
  scope: baseResourceGroup

  params: {
    keyVaultName: keyVaultName 
    tags: tagsWithVersion
  }
}

// App registration
module appRegistration 'appRegistration.bicep' = {
  scope: baseResourceGroup

  params: {
    appName: appRegistrationName
    environment: environment
    tags: tagsWithVersion
  }
}

// Create the service principal for the application
resource appRegistrationSP 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: appRegistration.outputs.appId
  displayName: appRegistrationName

  tags: [for item in items(tags): '${item.key}=${item.value}']
}

// https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged#owner
var ownerRoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
// App Registration service principal ownership role Assignment
resource appRegistrationServicePrincipalRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: subscription()

  name: guid(tenant().tenantId, subscription().id, appRegistrationName, ownerRoleDefinitionId)
  properties: {
    principalId: appRegistrationSP.id
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', ownerRoleDefinitionId)
    principalType: 'ServicePrincipal'
  }
}

// Create the dynamic group
// This is required to skip unwanted SSO popups during the exam: https://learn.microsoft.com/en-us/azure/virtual-desktop/configure-single-sign-on
resource dynamicDeviceGroup 'Microsoft.Graph/groups@v1.0' = {
  uniqueName: guid(tenant().tenantId, dynamicDeviceGroupName)
  displayName: dynamicDeviceGroupName 
  description: 'Dynamic group for Schoolyear AVD'
  membershipRule: '(device.displayName -startsWith "syvm")'
  membershipRuleProcessingState: 'On'
  mailEnabled: false
  mailNickname: replace(dynamicDeviceGroupName, '-', '')
  groupTypes: ['DynamicMembership']
  securityEnabled: true
}

resource imageBuildingResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: imageBuildingResourceGroupName
  location: location
  tags: tagsWithVersion
}

// Image building resources
var subscriptionShortId = substring(last(split(subscription().id, '-')), 0, 4)
var imagebuilderCustomRoleName = 'schoolyearavd-imagebuilder-${subscriptionShortId}'
module imageBuildingResources 'imageBuildingResources.bicep' = {
  scope: imageBuildingResourceGroup

  params: {
    location: location
    imageGalleryName: 'schoolyear_avd_gallery'
    imageDefinitionName: 'office365'
    storageAccountName: 'imageresources${subscriptionShortId}'
    containerName: 'resources'
    imagebuilderCustomRoleName: imagebuilderCustomRoleName
    tags: tags
  }
}

output installationOutput object = {
  // infra config needed by the BE
  tenant_id: tenant().tenantId
  subscription_id: subscription().id
  app_registration_client_id: appRegistration.outputs.appId
  base_rg_name: baseResourceGroupName
  base_rg_location: baseResourceGroup.location
  dns_zone_name: dnsZoneName
  key_vault_name: keyVaultName
  image_builder_rg_name: imageBuildingResourceGroup.name
  image_builder_rg_location: imageBuildingResourceGroup.location
  image_builder_managed_identity_name: imageBuildingResources.outputs.managedIdentityId
  image_gallery_name: imageBuildingResources.outputs.imageGalleryName

  dynamic_device_group_id: dynamicDeviceGroup.id 
  dynamic_device_group_name: dynamicDeviceGroupName

  // not needed by BE
  dns_zone_nameservers: dnsZone.outputs.nameservers
}
