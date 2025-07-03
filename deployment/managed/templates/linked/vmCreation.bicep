// All the 'common' parameters needed by this creation template
// These parameters are the same for all VMs
// The SY backend shouldn't care about these parameter
// and they are coming straight out of the main template
param commonInputParameters object

var location = commonInputParameters.location 
var sessionhostsSubnetId = commonInputParameters.sessionhostsSubnetid 
var vmTags = commonInputParameters.vmTags 
var vmSize = commonInputParameters.vmSize 
var vmAdminUser = commonInputParameters.vmAdminUser 
var vmDiskType = commonInputParameters.vmDiskType 
var vmImageId = commonInputParameters.vmImageId 
var artifactsLocation = commonInputParameters.artifactsLocation 
var hostPoolName = commonInputParameters.hostPoolName 
var hostPoolToken = commonInputParameters.hostPoolToken 
var sessionhostsSubnetIpRange = commonInputParameters.sessionhostsSubnetIpRange
// this is an object that will be serialized, base64-encoded and passed to the VM through the IMDS
var vmUserData = commonInputParameters.vmUserData
var tags = commonInputParameters.tags
var resourceTypeNamePrefixNsg = commonInputParameters.resourceTypeNamePrefixNsg
var resourceTypeNamePrefixNic = commonInputParameters.resourceTypeNamePrefixNic

// vmName is actually dependent on the vm being created 
// and is controlled by the one (SY backend) deploying this template
param vmName string
// vmComputerName is also controlled by the SY backend
// while vmName controls the vm resource name, vmComputerName controls 
// the underlying os computer name
param vmComputerName string

// NOTE: These will be sent by the BE and are required to run the
// autoUpdateVdiBrowser script, removing them will break deployments
param latestAgentVersion string
param msiDownloadUrl string

// NOTE: will be baked in with each release
var templateVersion = '0.0.0'
var sessionhostSetupScriptLocation = ''

@secure()
param vmAdminPassword string = newGuid()

var nsgName = '${resourceTypeNamePrefixNsg}${vmName}'
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName 
  location: location

  properties: {
    securityRules: [
      {
        name: 'DenySessionHostsOutbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: sessionhostsSubnetIpRange
        }
      }
    ]
  }
}

var nicName = '${resourceTypeNamePrefixNic}${vmName}'
resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: nicName
  location: location
  tags: tags

  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: sessionhostsSubnetId
          }
        }
      }
    ]

    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// We don't use a prefix for this, it's already included in ${vmName}
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: union(tags, vmTags)
  
  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    userData: base64(string(vmUserData))

    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmComputerName
      adminUsername: vmAdminUser
      adminPassword: vmAdminPassword
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: vmDiskType
        }
      }
      imageReference: {
        id: vmImageId
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    licenseType: 'Windows_Client'
  }

  resource dsc 'extensions' = {
    name: 'Microsoft.PowerShell.DSC'
    location: location
    tags: tags

    properties: {
      publisher: 'Microsoft.Powershell'
      type: 'DSC'
      typeHandlerVersion: '2.73'
      autoUpgradeMinorVersion: true
      settings: {
        modulesUrl: artifactsLocation
        configurationFunction: 'Configuration.ps1\\AddSessionHost'
        properties: {
          hostPoolName: hostPoolName
          registrationInfoTokenCredential: {
            UserName: 'PLACEHOLDER_DO_NOT_USE'
            Password: 'PrivateSettingsRef:RegistrationInfoToken'
          }
          aadJoin: true
          aadJoinPreview: false
          UseAgentDownloadEndpoint: true
        }
      }
      protectedSettings: {
        Items: {
          registrationInfoToken: hostPoolToken
        }
      }
    }
  }

  resource aadLogin 'extensions' = {
    name: 'AADLoginForWindows'
    location: location
    tags: tags

    dependsOn: [
      dsc
    ]

    properties: {
      publisher: 'Microsoft.Azure.ActiveDirectory'
      type: 'AADLoginForWindows'
      typeHandlerVersion: '2.0'
      autoUpgradeMinorVersion: true
    }
  }

  // NOTE: On windows VMs we can only have 1 extension per type aka only 1 'CustomScriptExtension'
  // this is why we put multiple actions into this single extension
  resource sessionhostSetup 'extensions' = {
    name: 'sessionhostSetup'
    location: location
    tags: tags

    dependsOn: [
      aadLogin
    ]


    properties: {
      publisher: 'Microsoft.Compute'
      type: 'CustomScriptExtension'
      typeHandlerVersion: '1.10'
      autoUpgradeMinorVersion: true
      settings: {
        fileUris: [
          '${sessionhostSetupScriptLocation}'
        ]

        commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File sessionhostSetup.ps1 -LatestAgentVersion ${latestAgentVersion} -MsiDownloadUrl ${msiDownloadUrl} -Wait'
      }
    }
  }
}

output templateVersion string = templateVersion
