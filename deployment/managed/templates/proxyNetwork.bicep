param location string
param proxyPublicLbIpName string
param proxyPublicLbName string
param proxyInternalLbName string
param proxyNsgName string
param proxyNicName string
param proxyVmName string
param servicesSubnetId string
param numProxyVms int
param tags object

resource proxyLoadBalancerPublicIp 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: proxyPublicLbIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }

  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource proxyLoadBalancerPublic 'Microsoft.Network/loadBalancers@2024-07-01' = {
  name: proxyPublicLbName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }


  properties: {
    frontendIPConfigurations: [
      {
        name: 'frontend'
        properties: {
          publicIPAddress: {
            id: proxyLoadBalancerPublicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'proxy-backend-pool'
      }
    ]
    loadBalancingRules: [
      {
        name: 'http-8080'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', proxyPublicLbName, 'frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', proxyPublicLbName, 'proxy-backend-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', proxyPublicLbName, 'http-8080-probe')
          }
          protocol: 'Tcp'
          frontendPort: 8080
          backendPort: 8080
        }
      }
      {
        name: 'https-443'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', proxyPublicLbName, 'frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', proxyPublicLbName, 'proxy-backend-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', proxyPublicLbName, 'https-443-probe')
          }
          protocol: 'Tcp'
          frontendPort: 443
          backendPort: 443
        }
      }
    ]
    probes: [
      {
        name: 'http-8080-probe'
        properties: {
          protocol: 'Tcp'
          port: 8080
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
      {
        name: 'https-443-probe'
        properties: {
          protocol: 'Tcp'
          port: 443
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
  }
}

resource proxyInternalLoadBalancer 'Microsoft.Network/loadBalancers@2024-07-01' = {
  name: proxyInternalLbName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }

  properties: {
    frontendIPConfigurations: [
      {
        name: 'frontend'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: servicesSubnetId
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'proxy-backend-pool'
      }
    ]
    loadBalancingRules: [
      {
        name: 'http-8080'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', proxyInternalLbName, 'frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', proxyInternalLbName, 'proxy-backend-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', proxyInternalLbName, 'http-8080-probe')
          }
          protocol: 'Tcp'
          frontendPort: 8080
          backendPort: 8080
        }
      }
      {
        name: 'https-443'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', proxyInternalLbName, 'frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', proxyInternalLbName, 'proxy-backend-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', proxyInternalLbName, 'https-443-probe')
          }
          protocol: 'Tcp'
          frontendPort: 443
          backendPort: 443
        }
      }
    ]
    probes: [
      {
        name: 'http-8080-probe'
        properties: {
          protocol: 'Tcp'
          port: 8080
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
      {
        name: 'https-443-probe'
        properties: {
          protocol: 'Tcp'
          port: 443
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
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
          subnet: {
            id: servicesSubnetId  
          }
          loadBalancerBackendAddressPools: [
            {
              id: proxyLoadBalancerPublic.properties.backendAddressPools[0].id // public LB pool
            }
            {
              id: proxyInternalLoadBalancer.properties.backendAddressPools[0].id // internal LB pool
            }
          ]
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
output proxyLoadBalancerPublicIpAddress string = proxyLoadBalancerPublicIp.properties.ipAddress
output proxyLoadBalancerPrivateIpAddress string = proxyInternalLoadBalancer.properties.frontendIPConfigurations[0].properties.privateIPAddress
