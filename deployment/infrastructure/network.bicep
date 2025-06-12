param location string
param tags object

param natIpName string
param natName string
param vnetName string
param vnetSubnetCIDR string
param avdEndpointsSubnetName string
param avdEndpointsCIDR string
param sessionhostsSubnetName string
param sessionhostsCIDR string
param servicesSubnetName string
param servicesCIDR string
param privatelinkZoneName string

// A public IP Address for our NAT Gateway
resource natPublicIPAddress 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: natIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }

  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    ddosSettings: {
      protectionMode: 'VirtualNetworkInherited'
    }
  }
}

// Our NAT Gateway
// implicit dependsOn natPublicIPAddress
resource natGateway 'Microsoft.Network/natGateways@2023-05-01' = {
  name: natName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: natPublicIPAddress.id
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags

  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetSubnetCIDR
      ]
    }

    encryption: {
      enabled: false
      enforcement: 'AllowUnencrypted'
    }

    subnets: [
      {
        name: avdEndpointsSubnetName
        type: 'Microsoft.Network/virtualNetworks/subnets'
        properties: {
          addressPrefix: avdEndpointsCIDR
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      {
        name: sessionhostsSubnetName
        properties: {
          addressPrefix: sessionhostsCIDR
          natGateway: {
            id: natGateway.id
          }
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
      {
        name: servicesSubnetName
        properties: {
          addressPrefix: servicesCIDR
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
    ]

    virtualNetworkPeerings: []
    enableDdosProtection: false
  }

  resource avdEndspointsSubnet 'subnets' existing = {
    name: avdEndpointsSubnetName
  }

  resource sessionhostsSubnet 'subnets' existing = {
    name: sessionhostsSubnetName
  }

  resource servicesSubnet 'subnets' existing = {
    name: servicesSubnetName
  }
}

resource privateLinkDNSZone 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privatelinkZoneName
  location: 'global'
  tags: tags
}

var virtualNetworkLinkName = '${privatelinkZoneName}/vnetLink'

resource virtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: virtualNetworkLinkName
  location: 'global'
  tags: tags

  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }

  dependsOn: [
    privateLinkDNSZone
  ]
}

output ipAddresses array = [natPublicIPAddress.properties.ipAddress]
output privateDnsZoneId string = privateLinkDNSZone.id
output avdEndpointsSubnetId string = virtualNetwork::avdEndspointsSubnet.id
output sessionHostsSubnetId string = virtualNetwork::sessionhostsSubnet.id
output servicesSubnetId string = virtualNetwork::servicesSubnet.id


