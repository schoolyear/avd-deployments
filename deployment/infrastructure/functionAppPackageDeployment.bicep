param location string
param managedIdentityTags object
param functionAppName string
param packageUrl string

param managedIdentityName string
param deploymentScriptName string

resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: managedIdentityName
  location: location
  tags: managedIdentityTags
}

// 'Website Contributor' role to the deploy identity, scoped to the resource group (not just the
// function app site) because `az functionapp deployment source config-zip` also needs to read
// the sibling App Service Plan (Microsoft.Web/serverfarms), which isn't a child of the site.
var websiteContributorRoleId = 'de139f84-1756-47ae-9be6-808fbbe84772'
resource deployIdentityWebsiteContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(tenant().tenantId, deployIdentity.id, websiteContributorRoleId, resourceGroup().id)
  scope: resourceGroup()

  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', websiteContributorRoleId)
    principalId: deployIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Flex Consumption only supports the 'One Deploy' deployment technology
// (az functionapp deployment source config-zip) - a raw blob upload to the
// deployment storage container is not picked up by the platform.
resource packageDeployScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: deploymentScriptName
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deployIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.60.0'
    retentionInterval: 'P1D'
    cleanupPreference: 'OnSuccess'
    timeout: 'PT10M'
    environmentVariables: [
      {
        name: 'PACKAGE_URL'
        value: packageUrl
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
      {
        name: 'FUNCTION_APP_NAME'
        value: functionAppName
      }
    ]
      // curl was removed from the azure-cli image due to microsoft wanting to reduce image size...
      // we use python3 -c and the internal requests module to download the package zip
      // which should be included since azure-cli is a python program
    scriptContent: '''
      set -e
      python3 -c "import os, urllib.request; urllib.request.urlretrieve(os.environ['PACKAGE_URL'], '/tmp/functionapp-package.zip')"
      az functionapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP_NAME" \
        --src /tmp/functionapp-package.zip
    '''
  }
  dependsOn: [
    deployIdentityWebsiteContributorRoleAssignment
  ]
}

output managedIdentityName string = deployIdentity.name
output managedIdentityId string = deployIdentity.id
