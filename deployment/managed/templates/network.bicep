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
param internalServiceLinkIds object
param internalServicesPrivateDNSZoneName string
param tags object

// convert license server link service ids to array for iteration
var serviceIds = items(internalServiceLinkIds)
// we use a default value in case 'internalServicesPrivateDNSZoneName' is empty because 
// the A record resource will fail if parent has an empty name even though it will not deploy
var resolvedInternalServicesPrivateDNSZoneName = !empty(internalServicesPrivateDNSZoneName) ? internalServicesPrivateDNSZoneName : 'customerinternalservices.syavd.local'

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

// Our VNET
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

// conditional private endpoints
// that links to some private service
// only deploys if we specify Private Link Service Ids to connect to 
resource privateEndpoints 'Microsoft.Network/privateEndpoints@2024-05-01' = [for service in serviceIds: {
  name: '${service.key}-private-endpoint'
  location: location
  tags: tags

  properties: {
    privateLinkServiceConnections: [
      {
        name: '${service.key}-private-service-connection'
        properties: {
          privateLinkServiceId: service.value
        }
      }
    ] 
    subnet: {
      id: virtualNetwork::servicesSubnet.id
    }
    customNetworkInterfaceName: '${service.key}-private-endpoint-nic'
  }
}]

// IP Extractors,
// Yeap, exactly what it sounds like.
// This is needed to fetch the IP of the PrivateEndpoints underlying NICs
// Doing this directly without a module doesn't work for whatever Azure™ patented reason
module nicIpExtractors 'nicPrivateIpExtractor.bicep' = [for i in range(0, length(serviceIds)): {
  name: '${serviceIds[i].key}-nic-ip-extractor'

  params: {
    nicName: last(split(privateEndpoints[i].properties.networkInterfaces[0].id, '/'))
  }
}]


// Deploy Private DNS zone in case we have private endpoints
var deployPrivateDNSZoneForInternalServices = !empty(serviceIds)
resource licenseServersPrivateDNSZone 'Microsoft.Network/privateDnsZones@2024-06-01' = if (deployPrivateDNSZoneForInternalServices) {
  name: resolvedInternalServicesPrivateDNSZoneName
  location: 'global'
  tags: tags

  // Link Private DNS Zone to VNet
  resource deployLicenseServerDNSZoneVNetLink 'virtualNetworkLinks' = {
    name: '${resolvedInternalServicesPrivateDNSZoneName}-vnet-link'
    location: 'global'
    tags: tags

    properties: {
      virtualNetwork: {
        id: virtualNetwork.id
      }
      // we don't want this, if enabled
      // all vms in subnet will get an A record
      registrationEnabled: false
    }
  }

  resource licenseServersPrivateDNSZoneRecords 'A' = [for i in range(0, length(serviceIds)): {
    name: serviceIds[i].key
    
    properties: {
      ttl: 3600
      aRecords:[
        {
          ipv4Address: nicIpExtractors[i].outputs.privateIpAddr
        }
      ]
    }
  }]
}

output ipAddresses array = [natPublicIPAddress.properties.ipAddress]
output sessionHostsSubnetId string = virtualNetwork::sessionhostsSubnet.id
output servicesSubnetId string = virtualNetwork::servicesSubnet.id
