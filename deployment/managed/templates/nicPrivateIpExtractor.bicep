// Simple module that accepts an already created 
// networkInterface, and returns its private ip Address
// This is necessary to bypass some hickups that Azure has
// when trying to reference the ip of a PrivateEndpoint's freshly created NIC.

param nicName string

resource  nic 'Microsoft.Network/networkInterfaces@2024-05-01' existing = {
  name: nicName
}

output privateIpAddr string = nic.properties.ipConfigurations[0].properties.privateIPAddress
