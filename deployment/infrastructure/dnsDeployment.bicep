param dnsZoneName string
param dnsZoneTags object 

resource dnsZone 'Microsoft.Network/dnsZones@2023-07-01-preview' = {
  name: dnsZoneName
  location: 'global' 
  tags: dnsZoneTags
}

output nameservers array = dnsZone.properties.nameServers
