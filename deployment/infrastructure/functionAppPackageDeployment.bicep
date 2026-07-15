param location string
param managedIdentityTags object
param functionAppName string
param packageUrl string

param managedIdentityName string

resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: functionAppName
}

resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: managedIdentityName
  location: location
  tags: managedIdentityTags
}

// 'Website Contributor' role to the deploy identity, scoped to the function app site only
var websiteContributorRoleId = 'de139f84-1756-47ae-9be6-808fbbe84772'
resource deployIdentityWebsiteContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(tenant().tenantId, deployIdentity.id, websiteContributorRoleId, functionApp.id)
  scope: functionApp

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
  name: 'deploy-functionapp-package'
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
    scriptContent: '''
      set -e
      curl -fsSL -o /tmp/functionapp-package.zip "$PACKAGE_URL"
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
