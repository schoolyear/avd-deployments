targetScope = 'subscription'

param location string = 'germanywestcentral'
param tags object = {}

// App registration is created before this installation script is run
// however we need these params here to automate the 
// necessary role assignment (needs ownership on the subscription)
param appRegistrationName string
param appRegistrationServicePrincipalId string

// Resources that may be renamed
param baseResourceGroupName string = 'rg-sy-base'
param dnsZoneName string
param keyVaultName string
param imageBuildingResourceGroupName string = 'rg-sy-imagebuilding'
param imageGalleryName string = 'sig-sy-avd'
param imageDefinitionName string = 'img-office365'
param storageAccountName string = 'stsy'
param storageAccountBlobServiceName string = 'default'
param storageAccountContainerName string = 'resources'
param imageBuilderCustomRoleDefinitionName string = 'rd-syavd-imagebuilder'
param managedIdentityName string = 'mi-sy-imagebuilder'

// Network specific
param networkRgName string = 'rg-sy-exams-network'
param networkRgLocation string = location
param natIpName string = 'pip-nat-sy'
param natName string = 'nat-sy'
param vnetName string = 'vnet-sy'
param vnetSubnetCIDR string = '10.0.0.0/19'
param avdEndpointsSubnetName string = 'avd-endpoints'
param avdEndpointsSubnetCIDR string = '10.0.0.0/21'
param sessionhostsSubnetName string = 'sessionhosts'
param sessionhostsSubnetCIDR string = '10.0.8.0/21'
param servicesSubnetName string = 'services'
param servicesSubnetCIDR string = '10.0.16.0/21'
param privatelinkZoneName string = 'privatelink.wvd.microsoft.com'

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

// https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/privileged#owner
var ownerRoleDefinitionId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
// App Registration service principal ownership role Assignment
resource appRegistrationServicePrincipalRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: subscription()

  name: guid(tenant().tenantId, subscription().id, appRegistrationName, ownerRoleDefinitionId)
  properties: {
    principalId: appRegistrationServicePrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', ownerRoleDefinitionId)
    principalType: 'ServicePrincipal'
  }
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
    tags: tags
    imageGalleryName: imageGalleryName
    imageDefinitionName: imageDefinitionName
    storageAccountName: storageAccountName
    storageAccountBlobServiceName: storageAccountBlobServiceName
    storageAccountContainerName: storageAccountContainerName
    imagebuilderCustomRoleName: imagebuilderCustomRoleName
    imageBuilderCustomRoleDefinitionName: imageBuilderCustomRoleDefinitionName
    managedIdentityName: managedIdentityName
  }
}

// Network resource group, all exams will connect to the subnets in this 
// resource group
resource networkResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: networkRgName
  location: networkRgLocation
  tags: tagsWithVersion
}

module networkResources 'network.bicep' = {
  scope: networkResourceGroup

  params: {
    location: location
    tags: tagsWithVersion
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

  virtual_networks: {
    '${networkResourceGroup.location}': {
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
