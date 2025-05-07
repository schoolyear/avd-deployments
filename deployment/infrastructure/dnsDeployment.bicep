param dnsZoneName string
param tags object 

resource dnsZone 'Microsoft.Network/dnsZones@2023-07-01-preview' = {
  name: dnsZoneName
  location: 'global' 
  tags: tags
}

output nameservers array = dnsZone.properties.nameServers
