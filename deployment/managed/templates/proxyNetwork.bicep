param location string
param proxyIpName string
param proxyNsgName string
param proxyNicName string
param proxyVmName string
param servicesSubnetId string
param numProxyVms int
param tags object

// Ip Address of proxy
resource proxyPublicIPAddresses 'Microsoft.Network/publicIPAddresses@2023-04-01' = [for i in range(0, numProxyVms): {
  name: '${proxyIpName}-${i}'
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
}]

var httpsInboundRule = {
  name: 'AllowAnyHTTPSInbound'
  type: 'Microsoft.Network/networkSecurityGroups/securityRules'
  properties: {
    protocol: 'TCP'
    sourcePortRange: '*'
    destinationPortRange: '443'
    sourceAddressPrefix: '*'
    destinationAddressPrefix: '*'
    access: 'Allow'
    priority: 102
    direction: 'Inbound'
  }  
}

var sshInboundRule = {
  name: 'AllowAnySSHInbound'
  type: 'Microsoft.Network/networkSecurityGroups/securityRules'
  properties: {
    protocol: 'TCP'
    sourcePortRange: '*'
    destinationPortRange: '22'
    sourceAddressPrefix: '*'
    destinationAddressPrefix: '*'
    access: 'Allow'
    priority: 100
    direction: 'Inbound'
  }  
}

// if disableSsh is set, don't add the ssh rule to the nsg
var securityRules = concat([httpsInboundRule], [sshInboundRule])
resource proxyNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: proxyNsgName
  location: location
  tags: tags

  properties: {
    securityRules: securityRules
  }
}

resource proxyNetworkInterfaces 'Microsoft.Network/networkInterfaces@2020-06-01' = [for i in range(0, numProxyVms): {
  name: '${proxyNicName}-${i}'
  location: location
  tags: tags

  properties: {
    ipConfigurations: [
      {
        name: '${proxyVmName}-${i}-nic-ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: proxyPublicIPAddresses[i].id
          }
          subnet: {
            id: servicesSubnetId  
          }
        }
      }
    ]

    networkSecurityGroup: {
      id: proxyNetworkSecurityGroup.id
    }
  }
}]

output proxyNicIDs array = [for i in range(0, numProxyVms): proxyNetworkInterfaces[i].id]
output proxyNicPrivateIpAddresses array = [for i in range(0, numProxyVms): proxyNetworkInterfaces[i].properties.ipConfigurations[0].properties.privateIPAddress]
output proxyPublicIpAddresses array = [for i in range(0, numProxyVms): proxyPublicIPAddresses[i].properties.ipAddress]
