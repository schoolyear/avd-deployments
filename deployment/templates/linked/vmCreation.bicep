
param location string
param vmName string
param sessionhostsSubnetid string
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

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: '${vmName}-nic'
  location: location

  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: sessionhostsSubnetid
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: vmTags
  
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
        commandToExecute: 'powershell -ExecutionPolicy Unrestricted -Command "& { . \'C:\\SessionhostScripts\\sessionhost_setup.ps1\'; Register-ScheduledTask -Action (New-ScheduledTaskAction -Execute \'PowerShell\' -Argument \'-Command Restart-Computer -Force\') -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)) -RunLevel Highest -User System -Force -TaskName \'reboot\' }"'
      }
    }
  }
}
