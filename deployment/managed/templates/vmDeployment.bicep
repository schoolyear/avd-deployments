param location string
@description('The URI of the vmCreationBatch.json linked template')
param batchVmCreationTemplateUri string
@description('A username to be used as the virtual machine administrator account. The vmAdministratorAccountUsername and  vmAdministratorAccountPassword parameters must both be provided. Otherwise, domain administrator credentials provided by administratorAccountUsername and administratorAccountPassword will be used.')
param vmAdministratorAccountUsername string = ''
@description('The password associated with the virtual machine administrator account. The vmAdministratorAccountUsername and  vmAdministratorAccountPassword parameters must both be provided. Otherwise, domain administrator credentials provided by administratorAccountUsername and administratorAccountPassword will be used.')
@secure()
param vmAdministratorAccountPassword string = ''
@description('The size of the session host VMs.')
param vmSize string = ''
@description('The VM disk type for the VM: HDD or SSD.')
@allowed([
  'Premium_LRS'
  'StandardSSD_LRS'
  'Standard_LRS'
])
param vmDiskType string
@description('This prefix will be used in combination with the VM number to create the VM name. If using \'rdsh\' as the prefix, VMs would be named \'rdsh-0\', \'rdsh-1\', etc. You should use a unique prefix to reduce name collisions in Active Directory.')
param vmNamePrefix string = ''
@description('(Required when vmImageType = CustomImage) Resource ID of the image')
param vmCustomImageSourceId string = ''
@description('The tags to be assigned to the virtual machines')
param virtualMachineTags object = {}
@description('Number of session hosts that will be created and added to the hostpool.')
param vmNumberOfInstances int
param sessionhostsSubnetResourceId string
param hostpoolName string
param hostpoolRegistrationToken string

// Bicep has a limit of 800 resources per deployment file
// If we just run a loop to deploy 1 vm each we will very quickly hit this limit
// (Each vmCreation deploys 5 resources)
// In order to bypass this we create a 'batch' deployment template and use that 
// in a loop to deploy many vms.
// When using a linked template in a loop, each iteration counts as 1 resource
// By batching the vmCreation and using a linked template we can bypass this limit
// see: https://stackoverflow.com/questions/68477355/arm-template-800-resource-limitation
var vmPerBatch = 100
var remainingVms = vmNumberOfInstances % vmPerBatch
var numBatchDeployments = (vmNumberOfInstances > vmPerBatch) ? ((vmNumberOfInstances / vmPerBatch) + (remainingVms == 0 ? 0 : 1)) : (vmNumberOfInstances > 0 ? 1 : 0)
resource vmCreation 'Microsoft.Resources/deployments@2024-03-01' = [for i in range(0, numBatchDeployments): {
  name: 'vmCreation-batch-${i}'

  properties: {
    mode: 'Incremental'
    templateLink: {
      uri: batchVmCreationTemplateUri
      contentVersion: '1.0.0.0'
    }

    parameters: {
      vmNamePrefix: {
        value: vmNamePrefix
      }
      offset: {
        value: i*vmPerBatch
      }
      numVms: {
        // For every batch except the last
        // numVms is the batch size
        // for the last batch, we check the remaining VMs
        // if it's 0, numVms should again be the batch size because it means the
        // total number of vms are divided equally in the batches.
        // if it's != 0, we send the remeinder VMs
        value: (i == numBatchDeployments - 1) ? (remainingVms == 0 ? vmPerBatch : remainingVms) : vmPerBatch
      }
      location: {
        value: location
      }
      sessionhostsSubnetResourceId: {
        value: sessionhostsSubnetResourceId
      }
      vmTags: {
        value: virtualMachineTags
      }
      vmSize: {
        value: vmSize
      }
      vmAdminUser: {
        value: vmAdministratorAccountUsername
      }
      vmAdminPassword: {
        value: vmAdministratorAccountPassword
      }
      vmDiskType: {
        value: vmDiskType
      }
      vmImageId: {
        value: vmCustomImageSourceId
      }
      artifactsLocation: {
        value: 'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02566.260.zip'
      }
      hostPoolName: {
        value: hostpoolName
      }
      hostPoolToken: {
        value: hostpoolRegistrationToken
      }
    }
  }  
}]
