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
param servicesSubnetResourceId string
param privateLinkZoneName string

var privateEndpointZoneLinkName = 'default'
var privateEndpointConnectionName = 'schoolyear-secure-endpoint-connection'
var privateEndpointConnectionNicName = '${privateEndpointConnectionName}-nic'
var privateEndpointConnectionZoneLinkName = '${privateEndpointConnectionName}/${privateEndpointZoneLinkName}'
var privateEndpointFeedName = 'schoolyear-secure-endpoint-feed'
var privateEndpointFeedNicName = '${privateEndpointFeedName}-nic'
var privateEndpointFeedZoneLinkName = '${privateEndpointFeedName}/${privateEndpointZoneLinkName}'

resource hostpool 'Microsoft.DesktopVirtualization/hostPools@2024-04-03' = {
  name: hostpoolName
  location: avdMetadataLocation

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
    customRdpProperty: 'drivestoredirect:s:;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:0;redirectprinters:i:0;devicestoredirect:s:*;redirectcomports:i:0;redirectsmartcards:i:0;usbdevicestoredirect:s:;enablecredsspsupport:i:1;redirectwebauthn:i:1;use multimon:i:0;enablerdsaadauth:i:1;screen mode id:i:1;displayconnectionbar:i:0;keyboardhook:i:0;use multimon:i:0'

    publicNetworkAccess: 'Disabled'
    managementType: 'Standard'
  }
}

resource appGroup 'Microsoft.DesktopVirtualization/applicationgroups@2024-04-03' = {
  name: appGroupName
  location: avdMetadataLocation
  properties: {
    hostPoolArmPath: hostpool.id
    friendlyName: 'Default Desktop'
    description: 'Desktop Application Group created by Schoolyear'
    applicationGroupType: 'Desktop'
  }
}

// Used only to fetch the objectId of the desktop
// Azure will always create a default one with the name 'SessionDesktop'
resource sessionDesktop 'Microsoft.DesktopVirtualization/applicationgroups/desktops@2024-04-03' existing = {
    parent: appGroup
    name: 'SessionDesktop'
}

resource workSpace 'Microsoft.DesktopVirtualization/workspaces@2024-04-03' = {
  name: workSpaceName
  location: avdMetadataLocation

  properties: {
    applicationGroupReferences: [appGroup.id]
    publicNetworkAccess: 'Enabled'
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

output workspaceObjectId string = workSpace.properties.objectId
output hostpoolId string = hostpool.properties.objectId
output hostpoolRegistrationToken string = reference(hostpoolName).registrationInfo.token
output appGroupId string = appGroup.id
output appGroupSessionDesktopObjectId string = sessionDesktop.properties.objectId
