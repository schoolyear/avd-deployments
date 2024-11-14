param location string
param natIpName string
param natName string
param vnetName string
param vnetSubnetCIDR string
param sessionhostsSubnetName string
param sessionhostsSubnetCIDR string
param servicesSubnetName string
param servicesSubnetCIDR string
param privatelinkZoneName string

// A public IP Address for our NAT Gateway
resource natPublicIPAddress 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: natIpName
  location: location
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

// Our VNET
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location

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
        name: sessionhostsSubnetName
        properties: {
          addressPrefix: sessionhostsSubnetCIDR
          natGateway: {
            id: natGateway.id
          }
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: true
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
      {
        name: servicesSubnetName
        properties: {
          addressPrefix: servicesSubnetCIDR
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: true
        }
        type: 'Microsoft.Network/virtualNetworks/subnets'
      }
    ]

    virtualNetworkPeerings: []
    enableDdosProtection: false
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
}

var virtualNetworkLinkName = '${privatelinkZoneName}/vnetLink'

resource virtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2018-09-01' = {
  name: virtualNetworkLinkName
  location: 'global'

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
output sessionHostsSubnetId string = virtualNetwork::sessionhostsSubnet.id
output servicesSubnetId string = virtualNetwork::servicesSubnet.id

