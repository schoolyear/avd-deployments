param userCapacity int
param examId string
param instanceId string
@secure()
param trustedProxySecret string
param apiBaseUrl string
param entraAuthority string
param entraClientId string
param tokenExpirationTime string = dateTimeAdd(utcNow(), 'P1D')
param vmAdminUser string = 'syadmin'
param proxyAdminUsername string = 'syuser'
@description('Number of students that can be supported by a single proxy VM')
param studentsPerProxy int = 10
@description('Minimum number of proxy VMs to deploy')
param minProxyVms int = 2

param vmCustomImageSourceId string
param proxyRSAPublicKey string
param sessionHostProxyWhitelist string
param dnsZoneResourceGroup string
param dnsZoneName string
param keyVaultResourceGroup string
param keyVaultName string
param keyVaultCertificateName string
// Proxy servers
// User may pass a string of ip CIDRs for the proxy to whitelist
// SECURITY: only do this for ranges reserved for Chromebooks that are exclusively run the Schoolyear client
// ex. '31.149.165.25/32,31.149.163.0/24'
param ipRangesWhitelist string
param proxyVmSize string
// all resources are deployed in the region of the resource group
// the region in which the resource group is created, is configured in the AVD add-on in the Schoolyear admin dashboard
//
// AVD metadata resources can only be created in some select regions
// notably, in Europe the regions that do support these resources are heavily constrained on VM capacity
//
// location: the region in which you want to deploy your VMs
// avdMetadataLocation: a region that supports AVD resources: 'centralindia,uksouth,ukwest,japaneast,japanwest,australiaeast,canadaeast,canadacentral,northeurope,westeurope,southafricanorth,eastus,eastus2,westus,westus2,westus3,northcentralus,southcentralus,westcentralus,centralus'.
param location string
param avdMetadataLocation string
param vmSize string

param sessionhostsSubnetId string
param sessionhostsSubnetIpRange string
param servicesSubnetId string
param servicesSubnetIpRange string
param avdEndpointsSubnetId string
param avdEndpointsSubnetIpRange string
param privateDnsZoneId string
param publicIps array

// Optional tags provided by the customer
param tags object = {}

// Resource type name prefixes provided by the customer
param resourceTypeNamePrefixPip string
param resourceTypeNamePrefixHp string
param resourceTypeNamePrefixAg string
param resourceTypeNamePrefixWs string
param resourceTypeNamePrefixPep string
param resourceTypeNamePrefixPdnsLink string
param resourceTypeNamePrefixNsg string
param resourceTypeNamePrefixNic string
param resourceTypeNamePrefixVm string
param resourceTypeNamePrefixLb string

var numProxyVms = min(max(
  (userCapacity + studentsPerProxy - 1) / studentsPerProxy,
  minProxyVms
), 10)

// NOTE: will be baked in with each release
var templateVersion = '0.0.0'
var vmCreationTemplateUri = '[[param:vmCreationTemplateUri]]'

var shortExamId = substring(examId, 0, 6)

// Sessionhosts
var vmNumberOfInstances = userCapacity
var vmNamePrefix = '${resourceTypeNamePrefixVm}${shortExamId}'
var vmComputerNamePrefix = 'syvm${shortExamId}'

var proxyInstallScriptUrl = 'https://raw.githubusercontent.com/schoolyear/avd-deployments/main/deployment/proxy_installation.sh'
var proxyInstallScriptName = 'proxy_installation.sh'
var trustedProxyBinaryUrl = 'https://install.exams.schoolyear.app/trusted-proxy/latest-linux-amd64'

// Proxy DNS deployment
var proxyDnsEntryDeploymentName = 'proxy-dns-entry'

// Keyvault
var keyVaultRoleAssignmentDeploymentName = 'keyvaultRoleAssignment'

// Combine user-provided tags with the template version
var tagsWithVersion = union(tags, {
  Version: templateVersion
})

var privateEndpointConnectionName = 'sy-endpoint-connection'
var privateEndpointFeedName = 'sy-endpoint-feed'

var hostpoolName = '${resourceTypeNamePrefixHp}${shortExamId}'
var appGroupName = '${resourceTypeNamePrefixAg}${shortExamId}'
var workspaceNameWithPrefix = '${resourceTypeNamePrefixWs}${shortExamId}'
var privateEndpointConnectionNameWithPrefix = '${resourceTypeNamePrefixPep}${privateEndpointConnectionName}'
var privateEndpointConnectionLinkNameWithPrefix = '${resourceTypeNamePrefixPdnsLink}default'
var privateEndpointFeedNameWithPrefix = '${resourceTypeNamePrefixPep}${privateEndpointFeedName}'
var privateEndpointFeedLinkNameWithPrefix = '${resourceTypeNamePrefixPdnsLink}default'
module avdDeployment './avdDeployment.bicep' = {
  name: 'avd-deployment'

  params: {
    location: location
    avdMetadataLocation: avdMetadataLocation
    hostpoolName: hostpoolName
    appGroupName: appGroupName
    workSpaceName: workspaceNameWithPrefix
    privateEndpointConnectionName: privateEndpointConnectionNameWithPrefix
    privateEndpointConnectionLinkName: privateEndpointConnectionLinkNameWithPrefix
    privateEndpointFeedName: privateEndpointFeedNameWithPrefix
    privateEndpointFeedLinkName: privateEndpointFeedLinkNameWithPrefix
    tokenExpirationTime: tokenExpirationTime
    avdEndpointsSubnetId: avdEndpointsSubnetId
    privateDnsZoneId: privateDnsZoneId
    tags: tagsWithVersion
  }
}

var proxyPublicLbIpName = '${resourceTypeNamePrefixPip}lb-proxy-public'
var proxyPublicLbName = '${resourceTypeNamePrefixLb}proxy-public'
var proxyInternalLbName = '${resourceTypeNamePrefixLb}proxy-internal'
var proxyNsgName = '${resourceTypeNamePrefixNsg}proxy'
var proxyNicName = '${resourceTypeNamePrefixNic}proxy'
var proxyVmName = '${resourceTypeNamePrefixVm}proxy'
module proxyNetwork 'proxyNetwork.bicep' = {
  name: 'proxyNetwork'

  params: {
    location: location
    proxyPublicLbIpName: proxyPublicLbIpName
    proxyPublicLbName: proxyPublicLbName
    proxyInternalLbName: proxyInternalLbName
    proxyNsgName: proxyNsgName
    proxyNicName: proxyNicName
    proxyVmName: proxyVmName
    servicesSubnetId: servicesSubnetId
    numProxyVms: numProxyVms
    tags: tagsWithVersion
  }
}

module proxyDeployment 'proxyDeployment.bicep' = {
  name: 'proxyDeployment'
  
  params: {
    location: location
    proxyVmName: proxyVmName
    proxyVmSize: proxyVmSize
    proxyNicIDs: proxyNetwork.outputs.proxyNicIDs
    proxyAdminUsername: proxyAdminUsername
    sshPubKey: proxyRSAPublicKey
    keyVaultRoleAssignmentDeploymentName: keyVaultRoleAssignmentDeploymentName
    examId: examId
    keyVaultResourceGroup: keyVaultResourceGroup
    keyVaultName: keyVaultName
    proxyDnsEntryDeploymentName: proxyDnsEntryDeploymentName
    dnsZoneResourceGroup: dnsZoneResourceGroup
    proxyLoadBalancerPublicIpAddress: proxyNetwork.outputs.proxyLoadBalancerPublicIpAddress
    dnsZoneName: dnsZoneName
    proxyInstallScriptUrl: proxyInstallScriptUrl
    proxyInstallScriptName: proxyInstallScriptName
    hostpoolId: avdDeployment.outputs.hostpoolId
    workspaceId: avdDeployment.outputs.workspaceId
    sessionHostProxyWhitelist: sessionHostProxyWhitelist
    trustedProxySecret: trustedProxySecret
    apiBaseUrl: apiBaseUrl
    trustedProxyBinaryUrl: trustedProxyBinaryUrl
    keyVaultCertificateName: keyVaultCertificateName
    ipRangesWhitelist: ipRangesWhitelist
    tags: tagsWithVersion
  }
}

output publicIps array = publicIps
output proxyConfig object = {
  domains: [
    // Proxy traffic related to the hostpool of this exam
    {
      matcher: '*-*-*-*-*.*.wvd.microsoft.com'
      proxy: proxyDeployment.outputs.proxyDnsDeploymentDomain
    }
    // Proxy traffic related to global unrelated hostpools in order for the trusted proxy to block it
    {
      matcher: '*rdgateway*.wvd.microsoft.com'
      proxy: proxyDeployment.outputs.proxyDnsDeploymentDomain
    }
  ]
}
output resourceUrlsToDelete array = [
  ...proxyDeployment.outputs.keyVaultRoleAssignmentDeploymentResourceUrls
  proxyDeployment.outputs.proxyDnsEntryDeploymentResourceUrl
]
output hostpoolName string = avdDeployment.outputs.hostpoolName
output vmNumberOfInstances int = vmNumberOfInstances
output templateVersion string = templateVersion
output appGroupId string = avdDeployment.outputs.appGroupId

// Will be used by the BE to prefix vm names
// like:
//        ${vmNamePrefix}-0
//        ${vmNamePrefix}-1
//        ${vmNamePrefix}-2
output vmNamePrefix string = vmNamePrefix
// Will be used by the BE to prefix internal computer names
// these are necessary to allow sessionhosts connectivity.
// depends on how we configured the dynamic group
output vmComputerNamePrefix string = vmComputerNamePrefix

// the template that is responsible for deploying a single VM
// needed by the SY backend to initiate VM deployments
output vmCreationTemplateUri string = vmCreationTemplateUri
// common input parameters for vmCreation template
// all of these are going to be passed to the vmCreation template
// and do not change per vm
output vmCreationTemplateCommonInputParameters object = {
  location:  location
  vmTags:  {
    apiBaseUrl: apiBaseUrl
    examId: examId
    instanceId: instanceId
    entraAuthority: entraAuthority
    entraClientId: entraClientId
    proxyVmIpAddr: '${proxyNetwork.outputs.proxyNicPrivateIpAddresses[0]}:8080'
    proxyVmIpAddresses: join(map(proxyNetwork.outputs.proxyNicPrivateIpAddresses, ipAddr => '${ipAddr}:8080'), ',')
  }
  vmUserData: {
    version: templateVersion
    avdEndpointsIpRange: avdEndpointsSubnetIpRange
    proxyLoadBalancerPrivateIpAddress: proxyNetwork.outputs.proxyLoadBalancerPrivateIpAddress
  }
  vmSize: vmSize
  vmAdminUser: vmAdminUser
  vmDiskType: 'Premium_LRS'
  vmImageId:  vmCustomImageSourceId
  artifactsLocation:  'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02566.260.zip'
  hostPoolName:  avdDeployment.outputs.hostpoolName
  hostPoolToken:  avdDeployment.outputs.hostpoolRegistrationToken
  sessionhostsSubnetId:  sessionhostsSubnetId
  sessionhostsSubnetIpRange: sessionhostsSubnetIpRange
  tags: tagsWithVersion
  resourceTypeNamePrefixNsg: resourceTypeNamePrefixNsg
  resourceTypeNamePrefixNic: resourceTypeNamePrefixNic
}

// These urls will not leak any resources at the end of the deployment
// however they are necessary to completely remove a failing vm deployment 
// and restart it from a clean slate. 
// NOTE: {{vmName}} will be substituted by the BE with the actual vmName of each deployment
// NOTE: In case you change the name of the nic from the vmCreation template make sure to also modify the nic deletion url
// /subscriptions/${subscriptionId}/resourceGroups/${resourceGroup}/providers/Microsoft.Compute/virtualMachines/${vmName}
// /subscriptions/${subscriptionId}/resourceGroups/${resourceGroup}/providers/Microsoft.Network/networkInterfaces/${vmName}-nic
output vmCreationResourceUrls array = [
 'https://management.azure.com/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Compute/virtualMachines/{{vmName}}?api-version=2021-04-01' 
 'https://management.azure.com/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/networkInterfaces/{{vmName}}-nic?api-version=2021-04-01' 
]
