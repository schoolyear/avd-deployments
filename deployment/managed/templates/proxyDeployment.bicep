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
param ipRangesWhitelist string
@secure()
param proxyVmAdminPassword string = newGuid()
param tags object

var disableSsh = empty(sshPubKey) ? true : false

resource proxyVMs 'Microsoft.Compute/virtualMachines@2023-03-01' = [for i in range(0, length(proxyNicIDs)): {
  name: '${proxyVmName}-${i}'
  location: location
  tags: tags

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
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
        version: 'latest'
      }
    }
  }
}]

// NOTE: when running 'global' deployments you might run into a conflict
// if same name deployments run at the same time, it's best to add a uuid to this
// examId is as good as any
module keyVaultRoleAssignmentDeployments 'keyVaultRoleAssignmentDeployment.bicep' = [for i in range(0, length(proxyNicIDs)): {
  name: '${keyVaultRoleAssignmentDeploymentName}-${examId}-${i}'
  scope: resourceGroup(keyVaultResourceGroup)

  params: {
    proxyVmName: proxyVMs[i].name
    proxyPrincipalId: proxyVMs[i].identity.principalId
    keyVaultResourceGroup: keyVaultResourceGroup
    keyVaultName: keyVaultName
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

// This depends on the main deployment
resource proxyCustomScriptExt 'Microsoft.Compute/virtualMachines/extensions@2020-12-01' = [for i in range(0, length(proxyNicIDs)): {
  parent: proxyVMs[i]
  name: 'CustomScriptExtensionName'
  location: location
  tags: tags

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
      commandToExecute: 'bash ${proxyInstallScriptName} "${hostpoolId}.*.wvd.microsoft.com:*,${workspaceId}.*.wvd.microsoft.com:*" "${sessionHostProxyWhitelist}" "${trustedProxySecret}" "${apiBaseUrl}" "${trustedProxyBinaryUrl}" "${keyVaultName}" "${keyVaultCertificateName}" "${ipRangesWhitelist}" "${proxyDnsEntryDeployment.outputs.domain}"'
    }
  }
}]

output proxyDnsDeploymentDomain string = proxyDnsEntryDeployment.outputs.domain
output proxyDnsEntryDeploymentResourceUrl string = proxyDnsEntryDeployment.outputs.resourceUrl
output keyVaultRoleAssignmentDeploymentResourceUrls array = [for i in range(0, length(proxyNicIDs)): keyVaultRoleAssignmentDeployments[i].outputs.resourceUrl]
