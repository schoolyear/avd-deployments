@description('The URI of the vmCreationBatch.json linked template')
param batchVmCreationTemplateUri string

@description('The name of the Hostpool to be created.')
param hostpoolName string

@description('The location where the resources will be deployed.')
param location string

@description('The name of the workspace to be attach to new Applicaiton Group.')
param workSpaceName string = ''

@description('A username to be used as the virtual machine administrator account. The vmAdministratorAccountUsername and  vmAdministratorAccountPassword parameters must both be provided. Otherwise, domain administrator credentials provided by administratorAccountUsername and administratorAccountPassword will be used.')
param vmAdministratorAccountUsername string = ''

@description('The password associated with the virtual machine administrator account. The vmAdministratorAccountUsername and  vmAdministratorAccountPassword parameters must both be provided. Otherwise, domain administrator credentials provided by administratorAccountUsername and administratorAccountPassword will be used.')
@secure()
param vmAdministratorAccountPassword string = ''

@description('The size of the session host VMs.')
param vmSize string = ''

@description('The VM disk type for the VM: HDD or SSD.')
@allowed([
  'Premium_LRS'
  'StandardSSD_LRS'
  'Standard_LRS'
])
param vmDiskType string

@description('Number of session hosts that will be created and added to the hostpool.')
param vmNumberOfInstances int = 0

@description('This prefix will be used in combination with the VM number to create the VM name. If using \'rdsh\' as the prefix, VMs would be named \'rdsh-0\', \'rdsh-1\', etc. You should use a unique prefix to reduce name collisions in Active Directory.')
param vmNamePrefix string = ''

@description('(Required when vmImageType = CustomImage) Resource ID of the image')
param vmCustomImageSourceId string = ''

@description('Hostpool token expiration time')
param tokenExpirationTime string

@description('The tags to be assigned to the virtual machines')
param virtualMachineTags object = {}

param appGroupName string
param servicesSubnetResourceId string
param sessionhostsSubnetResourceId string
param privateLinkZoneName string
param userGroupId string

var maxSessionLimit = max(vmNumberOfInstances, 1)
var privateEndpointZoneLinkName = 'default'
var privateEndpointConnectionName = 'schoolyear-secure-endpoint-connection'
var privateEndpointConnectionNicName = '${privateEndpointConnectionName}-nic'
var privateEndpointConnectionZoneLinkName = '${privateEndpointConnectionName}/${privateEndpointZoneLinkName}'
var privateEndpointFeedName = 'schoolyear-secure-endpoint-feed'
var privateEndpointFeedNicName = '${privateEndpointFeedName}-nic'
var privateEndpointFeedZoneLinkName = '${privateEndpointFeedName}/${privateEndpointZoneLinkName}'

resource hostpool 'Microsoft.DesktopVirtualization/hostPools@2024-04-08-preview' = {
  name: hostpoolName
  location: location

  properties: {
    description: 'Created by Schoolyear'
    hostPoolType: 'Pooled'
    maxSessionLimit: maxSessionLimit
    loadBalancerType: 'BreadthFirst'
    validationEnvironment: false
    preferredAppGroupType: 'Desktop'
    ring: null
    registrationInfo: {
      expirationTime: tokenExpirationTime
      registrationTokenOperation: 'Update'
    }
    vmTemplate: '{"domain":"","galleryImageOffer":"office-365","galleryImagePublisher":"microsoftwindowsdesktop","galleryImageSKU":"win10-22h2-avd-m365-g2","imageType":"Gallery","customImageId":null,"namePrefix":"fp1","osDiskType":"Premium_LRS","vmSize":{"id":"Standard_D2s_v5","cores":2,"ram":8},"galleryItemId":"microsoftwindowsdesktop.office-365win10-22h2-avd-m365-g2","hibernate":false,"diskSizeGB":128,"securityType":"Standard","secureBoot":false,"vTPM":false,"vmInfrastructureType":"Cloud","virtualProcessorCount":null,"memoryGB":null,"maximumMemoryGB":null,"minimumMemoryGB":null,"dynamicMemoryConfig":false}'
    customRdpProperty: 'drivestoredirect:s:*;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:1;redirectprinters:i:1;devicestoredirect:s:*;redirectcomports:i:1;redirectsmartcards:i:1;usbdevicestoredirect:s:*;enablecredsspsupport:i:1;redirectwebauthn:i:1;use multimon:i:1;enablerdsaadauth:i:1;'

    publicNetworkAccess: 'Disabled'
    managementType: 'Standard'
  }
}

resource appGroup 'Microsoft.DesktopVirtualization/applicationgroups@2022-10-14-preview' = {
  name: appGroupName
  location: location
  properties: {
    hostPoolArmPath: hostpool.id
    friendlyName: 'Default Desktop'
    description: 'Desktop Application Group created by Schoolyear'
    applicationGroupType: 'Desktop'
  }
}

resource workSpace 'Microsoft.DesktopVirtualization/workspaces@2023-09-05' = {
  name: workSpaceName
  location: location

  properties: {
    applicationGroupReferences: [appGroup.id]
    publicNetworkAccess: 'Disabled'
    friendlyName: 'Safe Exam Workspace'
  }
}

resource privateEndpointConnection 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: privateEndpointConnectionName
  location: location
  properties: {
    subnet: {
      id: servicesSubnetResourceId
    }
    customNetworkInterfaceName: privateEndpointConnectionNicName
    privateLinkServiceConnections: [
      {
        name: privateEndpointConnectionName
        properties: {
          privateLinkServiceId: hostpool.id
          groupIds: [
            'connection'
          ]
        }
      }
    ]
  }
}

resource privateEndpointConnectionZoneLink 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  name: privateEndpointConnectionZoneLinkName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-wvd-microsoft-com'
        properties: {
          privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', privateLinkZoneName)
        }
      }
    ]
  }
  dependsOn: [
    privateEndpointConnection
  ]
}

resource privateEndpointFeed 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: privateEndpointFeedName
  location: location

  properties: {
    subnet: {
      id: servicesSubnetResourceId
    }
    customNetworkInterfaceName: privateEndpointFeedNicName
    privateLinkServiceConnections: [
      {
        name: privateEndpointFeedName
        properties: {
          privateLinkServiceId: workSpace.id
          groupIds: [
            'feed'
          ]
        }
      }
    ]
  }
}

resource privateEndpointFeedZoneLink 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  name: privateEndpointFeedZoneLinkName
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-wvd-microsoft-com'
        properties: {
          privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', privateLinkZoneName)
        }
      }
    ]
  }
  dependsOn: [
    privateEndpointFeed
  ]
}

// Bicep has a limit of 800 resources per deployment file
// If we just run a loop to deploy 1 vm each we will very quickly hit this limit
// (Each vmCreation deploys 5 resources)
// In order to bypass this we create a 'batch' deployment template and use that 
// in a loop to deploy many vms.
// When using a linked template in a loop, each iteration counts as 1 resource
// By batching the vmCreation and using a linked template we can bypass this limit
// see: https://stackoverflow.com/questions/68477355/arm-template-800-resource-limitation
var vmPerBatch = 100
var remainingVms = vmNumberOfInstances % vmPerBatch
var numBatchDeployments = (vmNumberOfInstances > vmPerBatch) ? ((vmNumberOfInstances / vmPerBatch) + (remainingVms == 0 ? 0 : 1)) : (vmNumberOfInstances > 0 ? 1 : 0)
resource vmCreation 'Microsoft.Resources/deployments@2024-03-01' = [for i in range(0, numBatchDeployments): {
  name: 'vmCreation-batch-${i}'

  dependsOn: [
    privateEndpointFeedZoneLink
  ]

  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: batchVmCreationTemplateUri
      contentVersion: '1.0.0.0'
    }

    parameters: {
      vmNamePrefix: {
        value: vmNamePrefix
      }
      offset: {
        value: i*vmPerBatch
      }
      numVms: {
        // For every batch except the last
        // numVms is the batch size
        // for the last batch, we check the remaining VMs
        // if it's 0, numVms should again be the batch size because it means the
        // total number of vms are divided equally in the batches.
        // if it's != 0, we send the remeinder VMs
        value: (i == numBatchDeployments - 1) ? (remainingVms == 0 ? vmPerBatch : remainingVms) : vmPerBatch
      }
      location: {
        value: location
      }
      sessionhostsSubnetResourceId: {
        value: sessionhostsSubnetResourceId
      }
      vmTags: {
        value: virtualMachineTags
      }
      vmSize: {
        value: vmSize
      }
      vmAdminUser: {
        value: vmAdministratorAccountUsername
      }
      vmAdminPassword: {
        value: vmAdministratorAccountPassword
      }
      vmDiskType: {
        value: vmDiskType
      }
      vmImageId: {
        value: vmCustomImageSourceId
      }
      artifactsLocation: {
        value: 'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02566.260.zip'
      }
      hostPoolName: {
        value: hostpoolName
      }
      hostPoolToken: {
        value: reference(hostpoolName).registrationInfo.token
      }
    }
  }  
}]

// NOTE: This was originally outside of the 'avdDeployment', however we need to reference the 
// created appGroup and it's much easier to do it here
resource appGroupRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appGroup.id, userGroupId, '1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63')
  scope: appGroup

  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1d18fff3-a72a-46b5-b4a9-0b38a3cd7e63')
    principalId: userGroupId
    principalType: 'Group'
  }
}

// NOTE: This was originally outside of the 'avdDeployment', however we need to reference the 
// created appGroup and it's much easier to do it here
// NOTE: the scope for this role assignment was initially inside the properties object
// which doesn't exist according to the docs. So i tried to put it outside of it. Make 
// sure this is the intended behaviour.
resource userGroupRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, userGroupId, 'fb879df8-f326-4884-b1cf-06f3ad86be52')
  scope: resourceGroup()

  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'fb879df8-f326-4884-b1cf-06f3ad86be52')
    principalId: userGroupId
  }
}

output workspaceId string = workSpace.properties.objectId
output hostpoolId string = hostpool.properties.objectId
