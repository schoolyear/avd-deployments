param location string
param proxyVmName string
param proxyVmSize string
param proxyNicIDs array
param proxyAdminUsername string
param sshPubKey string
param keyVaultRoleAssignmentDeploymentName string
param examId string
param keyVaultResourceGroup string
param keyVaultName string
param proxyDnsEntryDeploymentName string
param dnsZoneResourceGroup string
param proxyPublicIpAddresses array
param dnsZoneName string
param proxyInstallScriptUrl string
param proxyInstallScriptName string
param hostpoolId string
param workspaceId string
param sessionHostProxyWhitelist string
@secure()
param trustedProxySecret string
param apiBaseUrl string
param trustedProxyBinaryUrl string
param keyVaultCertificateName string
param ipRangesWhitelist array

@secure()
param proxyVmAdminPassword string = newGuid()

var disableSsh = empty(sshPubKey) ? true : false

resource proxyVMs 'Microsoft.Compute/virtualMachines@2023-03-01' = [for i in range(0, length(proxyNicIDs)): {
  name: '${proxyVmName}-${i}'
  location: location

  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    hardwareProfile: {
      vmSize: proxyVmSize
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: proxyNicIDs[i]
        }
      ]
    }
    osProfile: {
      computerName: '${proxyVmName}-${i}'
      adminUsername: proxyAdminUsername
      adminPassword: disableSsh ? proxyVmAdminPassword : null
      linuxConfiguration: {
        // NOTE: either password authentication or ssh must be enabled on linux
        // machines
        disablePasswordAuthentication: disableSsh ? false : true
        ssh: disableSsh ? null : {
          publicKeys: [
            {
              keyData: sshPubKey
              path: '/home/${proxyAdminUsername}/.ssh/authorized_keys'
            }
          ]
        }
      }
    }
    storageProfile: {
      osDisk: {
        deleteOption: 'Delete'
        createOption: 'FromImage'
      }
      imageReference: {
        publisher: 'canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server-gen1'
        version: 'latest'
      }
    }
  }
}]

// NOTE: when running 'global' deployments you might run into a conflict
// if same name deployments run at the same time, it's best to add a uuid to this
// examId is as good as any
var keyVaultSecretsUserRoleDefinitionId = '4633458b-17de-408a-b874-0445c86b69e6'
module keyVaultRoleAssignmentDeployments 'keyVaultRoleAssignmentDeployment.bicep' = [for i in range(0, length(proxyNicIDs)): {
  name: '${keyVaultRoleAssignmentDeploymentName}-${examId}-${i}'
  scope: resourceGroup(keyVaultResourceGroup)

  params: {
    roleAssignmentName: guid(resourceGroup().id, proxyVMs[i].name, examId, keyVaultSecretsUserRoleDefinitionId)
    proxyPrincipalId: proxyVMs[i].identity.principalId
    keyVaultResourceGroup: keyVaultResourceGroup
    keyVaultName: keyVaultName
    keyVaultSecretsUserRoleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}]

// NOTE: when running 'global' deployments you might run into a conflict
// if same name deployments run at the same time, it's best to add a uuid to this
// examId is as good as any
module proxyDnsEntryDeployment './proxyDnsEntryDeployment.bicep' = {
  name: '${proxyDnsEntryDeploymentName}-${examId}'
  scope: resourceGroup(dnsZoneResourceGroup)
  
  params: {
    ipv4Addresses: proxyPublicIpAddresses
    dnsZoneName: dnsZoneName
    dnsRecord: examId
  }
}

// If user has provided an array of ips to whitelist
// pass these to the auth_bypass.txt file
var ipRangesWhitelistStr = join(ipRangesWhitelist, ',')

// This depends on the main deployment
resource proxyCustomScriptExt 'Microsoft.Compute/virtualMachines/extensions@2020-12-01' = [for i in range(0, length(proxyNicIDs)): {
  parent: proxyVMs[i]
  name: 'CustomScriptExtensionName'
  location: location

  dependsOn: [
    keyVaultRoleAssignmentDeployments
  ]

  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      skipDos2Unix: true
      fileUris: [
        proxyInstallScriptUrl
      ]
    }
    protectedSettings: {
      commandToExecute: 'bash ${proxyInstallScriptName} "${hostpoolId}.*.wvd.microsoft.com:*,${workspaceId}.*.wvd.microsoft.com:*" "${sessionHostProxyWhitelist}" "${trustedProxySecret}" "${apiBaseUrl}" "${trustedProxyBinaryUrl}" "${keyVaultName}" "${keyVaultCertificateName}" "${ipRangesWhitelistStr}" "${proxyDnsEntryDeployment.outputs.domain}"'
    }
  }
}]

output proxyDnsDeploymentDomain string = proxyDnsEntryDeployment.outputs.domain
output proxyDnsEntryDeploymentResourceUrl string = proxyDnsEntryDeployment.outputs.resourceUrl
output keyVaultRoleAssignmentDeploymentResourceUrls array = [for i in range(0, length(proxyNicIDs)): keyVaultRoleAssignmentDeployments[i].outputs.resourceUrl]
