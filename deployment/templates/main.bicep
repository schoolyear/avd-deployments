param userCapacity int
// startTime & endTime are not actually used
// but the BE sends them over, so this template fails if we don't supply them.
param startTime string
param endTime string
param examId string
param instanceId string
@secure()
param trustedProxySecret string
param userGroupId string
param apiBaseUrl string
param entraAuthority string
param entraClientId string
param tokenExpirationTime string = dateTimeAdd(utcNow(), 'P1D')
param vmAdminUser string = 'syadmin'
@secure()
param vmAdminPassword string = newGuid()
param proxyAdminUsername string = 'syuser'

// NOTE: will be baked in with each release
var templateVersion = '0.0.0'
var vmCreationBatchTemplateUri = '[[param:vmCreationBatchTemplateUri]]'

var location = resourceGroup().location
var defaultNamingPrefix = resourceGroup().name

// VNET
var natIpName = '${defaultNamingPrefix}ip'
var natName = '${defaultNamingPrefix}nat'
var vnetName = '${defaultNamingPrefix}vnet'
var vnetSubnetCIDR = '10.0.0.0/19'
var sessionhostsSubnetCIDR = '10.0.0.0/20'
var sessionhostsSubnetName = 'sessionhosts'
var servicesSubnetCIDR = '10.0.16.0/20'
var servicesSubnetName = 'services'
var privatelinkZoneName = 'privatelink.wvd.microsoft.com'

// AVD
var hostpoolName = '${defaultNamingPrefix}pool'
var appGroupName = '${defaultNamingPrefix}dag'
var workspaceName = '${defaultNamingPrefix}ws'

// Sessionhosts
var vmNumberOfInstances = userCapacity
var vmNamePrefix = 'syvm${substring(examId,0,7)}'
var vmCustomImageSourceId = '[[param:vmCustomImageSourceId]]]'

// Proxy servers
// User may pass an array of ip CIDRs for the proxy to whitelist
// SECURITY: only do this for ranges reserved for Chromebooks that are exclusively run the Schoolyear client
// ex. [31.149.165.25/32, 31.149.163.0/24]
var ipRangesWhitelist = []
var sshPubKey = '[[param:proxyRSAPublicKey]]]' // NOTE: if left empty, ssh for the proxy VM will be disabled
var proxyVmSize = 'Standard_D1_v2'
var proxyIpName = '${defaultNamingPrefix}proxy-ip'
var proxyNsgName = '${defaultNamingPrefix}proxy-nsg'
var proxyNicName = '${defaultNamingPrefix}proxy-nic'
var proxyVmName = '${defaultNamingPrefix}proxy-vm'
var proxyInstallScriptUrl = 'https://raw.githubusercontent.com/schoolyear/avd-deployments/main/deployment/proxy_installation.sh'
var proxyInstallScriptName = 'proxy_installation.sh'
var trustedProxyBinaryUrl = 'https://install.exams.schoolyear.app/trusted-proxy/latest-linux-amd64'
var sessionHostProxyWhitelist = '[[builtin:sessionHostProxyWhitelist]]]'

// Proxy DNS deployment
var proxyDnsEntryDeploymentName = 'proxy-dns-entry'
var dnsZoneResourceGroup = '[[param:dnsZoneResourceGroup]]]'
var dnsZoneName = '[[param:dnsZoneName]]]'

// Keyvault
var keyVaultResourceGroup = '[[param:keyVaultResourceGroup]]]'
var keyVaultName = '[[param:keyVaultName]]]'
var keyVaultCertificateName = '[[param:keyVaultCertificateName]]]'
var keyVaultRoleAssignmentDeploymentName = 'keyvaultRoleAssignment'

// Our network for AVD Deployment, contains VNET, subnets and dns zones / links etc
module network './network.bicep' = {
  name: 'network-deployment'

  params: {
    location: location
    natIpName: natIpName
    natName: natName
    vnetName: vnetName
    vnetSubnetCIDR: vnetSubnetCIDR
    sessionhostsSubnetName: sessionhostsSubnetName
    sessionhostsSubnetCIDR: sessionhostsSubnetCIDR
    servicesSubnetName: servicesSubnetName
    servicesSubnetCIDR: servicesSubnetCIDR
    privatelinkZoneName: privatelinkZoneName
  }
}

module avdDeployment './avdDeployment.bicep' = {
  name: 'avd-deployment'

  params: {
    batchVmCreationTemplateUri: vmCreationBatchTemplateUri
    hostpoolName: hostpoolName
    location: location
    vmNamePrefix: vmNamePrefix
    vmSize: 'Standard_D2s_v5'
    vmDiskType: 'Premium_LRS'
    vmNumberOfInstances: vmNumberOfInstances
    vmCustomImageSourceId: vmCustomImageSourceId
    workSpaceName: workspaceName
    tokenExpirationTime: tokenExpirationTime
    vmAdministratorAccountUsername: vmAdminUser
    vmAdministratorAccountPassword: vmAdminPassword
    appGroupName: appGroupName
    servicesSubnetResourceId: network.outputs.servicesSubnetId
    sessionhostsSubnetResourceId: network.outputs.sessionHostsSubnetId
    privateLinkZoneName: privatelinkZoneName
    virtualMachineTags: {
      apiBaseUrl: apiBaseUrl
      examId: examId
      instanceId: instanceId
      entraAuthority: entraAuthority
      entraClientId: entraClientId
      proxyVmIpAddr: '${proxyNetwork.outputs.proxyNicPrivateIpAddress}:8080'
    }
    userGroupId: userGroupId
  }
}

var disableSsh = empty(sshPubKey) ? true : false
module proxyNetwork 'proxyNetwork.bicep' = {
  name: 'proxyNetwork'

  params: {
    location: location
    proxyIpName: proxyIpName
    proxyNsgName: proxyNsgName
    proxyNicName: proxyNicName
    proxyVmName: proxyVmName
    servicesSubnetId: network.outputs.servicesSubnetId
    disableSsh: disableSsh
  }
}

module proxyDeployment 'proxyDeployment.bicep' = {
  name: 'proxyDeployment'
  
  params: {
    location: location
    proxyVmName: proxyVmName
    proxyVmSize: proxyVmSize
    proxyNicID: proxyNetwork.outputs.proxyNicID
    proxyAdminUsername: proxyAdminUsername
    sshPubKey: sshPubKey
    keyVaultRoleAssignmentDeploymentName: keyVaultRoleAssignmentDeploymentName
    examId: examId
    keyVaultResourceGroup: keyVaultResourceGroup
    keyVaultName: keyVaultName
    proxyDnsEntryDeploymentName: proxyDnsEntryDeploymentName
    dnsZoneResourceGroup: dnsZoneResourceGroup
    proxyPublicIpAddress: proxyNetwork.outputs.proxyPublicIpAddress
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
  }
}


output publicIps array = network.outputs.ipAddresses
output proxyConfig object = {
  domains: [
    {
      matcher: '*-*-*-*-*.*.wvd.microsoft.com'
      proxy: proxyDeployment.outputs.proxyDnsDeploymentDomain
    }
  ]
}
output resourceUrlsToDelete array = [
  proxyDeployment.outputs.keyVaultRoleAssignmentDeploymentResourceUrl
  proxyDeployment.outputs.proxyDnsEntryDeploymentResourceUrl
]
output proxyIp string = proxyNetwork.outputs.proxyPublicIpAddress
output hostpoolName string = hostpoolName
output vmNumberOfInstances int = vmNumberOfInstances
output templateVersion string = templateVersion
