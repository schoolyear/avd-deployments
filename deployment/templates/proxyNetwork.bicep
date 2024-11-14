param location string
param proxyIpName string
param proxyNsgName string
param proxyNicName string
param proxyVmName string
param servicesSubnetId string
param disableSsh bool

// Ip Address of proxy
resource proxyPublicIPAddress 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: proxyIpName
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
var securityRules = concat([httpsInboundRule], disableSsh ? [] : [sshInboundRule])
resource proxyNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: proxyNsgName
  location: location

  properties: {
    securityRules: securityRules
  }
}

resource proxyNetworkInterface 'Microsoft.Network/networkInterfaces@2020-06-01' = {
  name: proxyNicName
  location: location

  properties: {
    ipConfigurations: [
      {
        name: '${proxyVmName}-nic-ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: proxyPublicIPAddress.id
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
}

output proxyNicID string = proxyNetworkInterface.id
output proxyNicPrivateIpAddress string = proxyNetworkInterface.properties.ipConfigurations[0].properties.privateIPAddress
output proxyPublicIpAddress string = proxyPublicIPAddress.properties.ipAddress
