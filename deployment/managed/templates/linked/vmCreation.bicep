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
var tags = commonInputParameters.tags

// vmName is actually dependent on the vm being created 
// and is controlled by the one (SY backend) deploying this template
param vmName string

// NOTE: These will be sent by the BE and are required to run the
// autoUpdateVdiBrowser script, removing them will break deployments
param latestAgentVersion string
param msiDownloadUrl string

// NOTE: will be baked in with each release
var templateVersion = '0.0.0'
// NOTE: will be baked in with each release
var autoUpdateScriptLocation = ''

@secure()
param vmAdminPassword string = newGuid()

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: '${vmName}-nic'
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
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: union(tags, vmTags)
  
  identity: {
    type: 'SystemAssigned'
  }

  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
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

  // NOTE: This must be run last because it locks down the VM internet access
  // if you skip the dependsOn of this extension
  // the DSC will most likely fail
  resource scheduledReboot 'extensions' = {
    name: 'scheduledReboot'
    location: location
    tags: tags

    dependsOn: [
      dsc
      aadLogin
    ]

    properties: {
      publisher: 'Microsoft.Compute'
      type: 'CustomScriptExtension'
      typeHandlerVersion: '1.10'
      autoUpgradeMinorVersion: true
      settings: {
        commandToExecute: 'powershell -ExecutionPolicy Unrestricted -Command "& { $scriptUrl = \'${autoUpdateScriptLocation}\'; $scriptPath = \'C:\\SessionhostScripts\\auto_update_vdi_browser.ps1\'; Invoke-WebRequest -Uri $scriptUrl -OutFile $scriptPath; & $scriptPath -LatestAgentVersion \'${latestAgentVersion}\' -MsiDownloadUrl \'${msiDownloadUrl}\' -Wait; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; Remove-Item -Path $scriptPath -Force; . \'C:\\SessionhostScripts\\sessionhost_setup.ps1\'; Register-ScheduledTask -Action (New-ScheduledTaskAction -Execute \'PowerShell\' -Argument \'-Command Restart-Computer -Force\') -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)) -RunLevel Highest -User System -Force -TaskName \'reboot\' }"'
      }
    }
  }
}

output templateVersion string = templateVersion
