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
var location = resourceGroup().location
var defaultNamingPrefix = resourceGroup().name
var natIpName = '${defaultNamingPrefix}ip'
var natName = '${defaultNamingPrefix}nat'
var vnetName = '${defaultNamingPrefix}vnet'
var vnetSubnetCIDR = '10.0.0.0/19'
var sessionhostsSubnetCIDR = '10.0.0.0/20'
var servicesSubnetCIDR = '10.0.16.0/20'
var hostpoolName = '${defaultNamingPrefix}pool'
var appGroupName = '${defaultNamingPrefix}dag'
var workspaceName = '${defaultNamingPrefix}ws'
var vmNumberOfInstances = userCapacity
var proxyIpName = '${defaultNamingPrefix}proxy-ip'
var proxyNsgName = '${defaultNamingPrefix}proxy-nsg'
var proxyNicName = '${defaultNamingPrefix}proxy-nic'
var proxyVmName = '${defaultNamingPrefix}proxy-vm'
var vmNamePrefix = 'syvm${substring(examId,0,7)}'
var vmCustomImageSourceId = '[[param:vmCustomImageSourceId]]]'
var privatelinkZoneName = 'privatelink.wvd.microsoft.com'
var deploymentName = 'avdDeployment'
var sessionhostsSubnetName = 'sessionhosts'
var servicesSubnetName = 'services'
// NOTE: if left empty, ssh for the proxy VM will be disabled
var sshPubKey = '[[param:proxyRSAPublicKey]]]'
var proxyVmSize = 'Standard_D1_v2'
var keyVaultResourceGroup = '[[param:keyVaultResourceGroup]]]'
var keyVaultName = '[[param:keyVaultName]]]'
var keyVaultCertificateName = '[[param:keyVaultCertificateName]]]'
var keyVaultRoleAssignmentDeploymentName = 'keyvaultRoleAssignment'
var dnsZoneResourceGroup = '[[param:dnsZoneResourceGroup]]]'
var dnsZoneName = '[[param:dnsZoneName]]]'
var proxyDnsEntryDeploymentName = 'proxyDnsEntry'
var proxyInstallScriptUrl = 'https://raw.githubusercontent.com/schoolyear/avd-deployments/main/deployment/proxy_installation.sh'
var proxyInstallScriptName = 'proxy_installation.sh'
var sessionHostProxyWhitelist = '[[builtin:sessionHostProxyWhitelist]]]'
var trustedProxyBinaryUrl = 'https://install.exams.schoolyear.app/trusted-proxy/latest-linux-amd64'
// NOTE: will be baked in by the release
var vmCreationBatchTemplateUri = '[[param:vmCreationBatchTemplateUri]]'

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
  name: deploymentName

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
