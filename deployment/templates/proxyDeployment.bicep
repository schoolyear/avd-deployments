param location string
param proxyVmName string
param proxyVmSize string
param proxyNicID string
param proxyAdminUsername string
param sshPubKey string
param keyVaultRoleAssignmentDeploymentName string
param examId string
param keyVaultResourceGroup string
param keyVaultName string
param proxyDnsEntryDeploymentName string
param dnsZoneResourceGroup string
param proxyPublicIpAddress string
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

resource proxyVM 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: proxyVmName
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
          id: proxyNicID
        }
      ]
    }
    osProfile: {
      computerName: proxyVmName
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
}

// NOTE: when running 'global' deployments you might run into a conflict
// if same name deployments run at the same time, it's best to add a uuid to this
// examId is as good as any
module keyVaultRoleAssignmentDeployment 'keyVaultRoleAssignmentDeployment.bicep' = {
  name: '${keyVaultRoleAssignmentDeploymentName}-${examId}'
  scope: resourceGroup(keyVaultResourceGroup)

  params: {
    proxyVmName: proxyVmName
    proxyPrincipalId: proxyVM.identity.principalId
    keyVaultResourceGroup: keyVaultResourceGroup
    keyVaultName: keyVaultName
  }
}

// NOTE: when running 'global' deployments you might run into a conflict
// if same name deployments run at the same time, it's best to add a uuid to this
// examId is as good as any
module proxyDnsEntryDeployment './proxyDnsEntryDeployment.bicep' = {
  name: '${proxyDnsEntryDeploymentName}-${examId}'
  scope: resourceGroup(dnsZoneResourceGroup)
  
  params: {
    ipv4: proxyPublicIpAddress
    dnsZoneName: dnsZoneName
    dnsRecord: examId
  }
}

// If user has provided an array of ips to whitelist
// pass these to the auth_bypass.txt file
var ipRangesWhitelistStr = join(ipRangesWhitelist, ',')

// This depends on the main deployment
resource proxyCustomScriptExt 'Microsoft.Compute/virtualMachines/extensions@2020-12-01' = {
  parent: proxyVM
  name: 'CustomScriptExtensionName'
  location: location

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
      commandToExecute: 'bash ${proxyInstallScriptName} "${hostpoolId}.*.wvd.microsoft.com:*,${workspaceId}.*.wvd.microsoft.com:*" "${sessionHostProxyWhitelist}" "${trustedProxySecret}" "${apiBaseUrl}" "${trustedProxyBinaryUrl}" "${keyVaultName}" "${keyVaultCertificateName}" "${ipRangesWhitelistStr}"'
    }
  }
}

output proxyDnsDeploymentDomain string = proxyDnsEntryDeployment.outputs.domain
output proxyDnsEntryDeploymentResourceUrl string = proxyDnsEntryDeployment.outputs.resourceUrl
output keyVaultRoleAssignmentDeploymentResourceUrl string = keyVaultRoleAssignmentDeployment.outputs.resourceUrl
