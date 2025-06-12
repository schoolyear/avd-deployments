@description('The name of the Hostpool to be created.')
param hostpoolName string

@description('The location where the resources will be deployed.')
param location string

@description('The location where the AVD metadata resources will be deployed.')
param avdMetadataLocation string

@description('The name of the workspace to be attach to new Applicaiton Group.')
param workSpaceName string = ''

@description('Hostpool token expiration time')
param tokenExpirationTime string

param appGroupName string
param avdEndpointsSubnetId string
param privateDnsZoneId string

param privateEndpointConnectionName string
param privateEndpointConnectionLinkName string
param privateEndpointFeedName string
param privateEndpointFeedLinkName string
param tags object

resource hostpool 'Microsoft.DesktopVirtualization/hostPools@2024-04-08-preview' = {
  name: hostpoolName
  location: avdMetadataLocation
  tags: tags

  properties: {
    description: 'Created by Schoolyear'
    hostPoolType: 'Personal'
    loadBalancerType: 'Persistent'
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

resource appGroup 'Microsoft.DesktopVirtualization/applicationgroups@2024-04-08-preview' = {
  name: appGroupName
  location: avdMetadataLocation
  tags: tags
  properties: {
    hostPoolArmPath: hostpool.id
    friendlyName: 'Default Desktop'
    description: 'Desktop Application Group created by Schoolyear'
    applicationGroupType: 'Desktop'
  }
}

resource workSpace 'Microsoft.DesktopVirtualization/workspaces@2024-04-08-preview' = {
  name: workSpaceName
  location: avdMetadataLocation
  tags: tags

  properties: {
    applicationGroupReferences: [appGroup.id]
    publicNetworkAccess: 'Disabled'
    friendlyName: 'Safe Exam Workspace'
  }
}

resource privateEndpointConnection 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: privateEndpointConnectionName
  location: location
  tags: tags
  properties: {
    subnet: {
      id: avdEndpointsSubnetId
    }
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
  name: privateEndpointConnectionLinkName
  parent: privateEndpointConnection

  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-wvd-microsoft-com'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

resource privateEndpointFeed 'Microsoft.Network/privateEndpoints@2021-05-01' = {
  name: privateEndpointFeedName
  location: location
  tags: tags

  properties: {
    subnet: {
      id: avdEndpointsSubnetId
    }
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
  name: privateEndpointFeedLinkName
  parent: privateEndpointFeed

  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-wvd-microsoft-com'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output workspaceId string = workSpace.properties.objectId
output hostpoolId string = hostpool.properties.objectId
output hostpoolName string = hostpool.name
output hostpoolRegistrationToken string = reference(hostpoolName).registrationInfo.token
output appGroupId string = appGroup.id
