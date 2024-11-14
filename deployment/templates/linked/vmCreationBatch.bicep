param vmNamePrefix string
param offset int
param numVms int
param location string
param sessionhostsSubnetResourceId string
param vmTags object
param vmSize string
param vmAdminUser string
@secure()
param vmAdminPassword string
param vmDiskType string
param vmImageId string
param artifactsLocation string
param hostPoolName string
param hostPoolToken string

// NOTE: will be baked in with each release
var templateVersion = '0.0.0'

module vmCreation './vmCreation.bicep' = [for i in range(offset, numVms): {
  name: 'vmCreation-${i}'

  params: {
    location: location
    vmName: '${vmNamePrefix}-${i}'
    sessionhostsSubnetid: sessionhostsSubnetResourceId
    vmTags: vmTags
    vmSize: vmSize
    vmAdminUser: vmAdminUser
    vmAdminPassword: vmAdminPassword
    vmDiskType: vmDiskType
    vmImageId: vmImageId
    artifactsLocation: artifactsLocation
    hostPoolName: hostPoolName
    hostPoolToken: hostPoolToken
  }
}]

// So we can actually see the version when running this 
// template
output templateVersion string = templateVersion
