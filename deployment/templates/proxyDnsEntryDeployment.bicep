param ipv4Addresses array
param dnsZoneName string
param dnsRecord string

resource dnsZoneRecord 'Microsoft.Network/dnsZones/A@2018-05-01' = {
  name: '${dnsZoneName}/${dnsRecord}'
  properties: {
    TTL: 3600
    ARecords: [for ipv4 in ipv4Addresses: {
      ipv4Address: ipv4
    }]
  }
}

output domain string = substring(dnsZoneRecord.properties.fqdn, 0, (length(dnsZoneRecord.properties.fqdn) - 1))
output resourceUrl string = 'https://management.azure.com${dnsZoneRecord.id}?api-version=2018-05-01'
