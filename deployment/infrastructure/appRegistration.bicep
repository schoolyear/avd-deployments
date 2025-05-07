param appName string
param environment string
param tags object

var callbackUrls = {
  development: 'https://dev.api.schoolyear.app/v2/sas/vdi-provider/avd/oidc-callback'
  testing:     'https://testing.api.schoolyear.app/v2/sas/vdi-provider/avd/oidc-callback'
  beta:        'https://beta.api.schoolyear.app/v2/sas/vdi-provider/avd/oidc-callback'
  production:  'https://api.schoolyear.app/v2/sas/vdi-provider/avd/oidc-callback'
}

var callbackUrl = callbackUrls[environment]

extension microsoftGraphV1

resource appRegistration 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: guid(tenant().tenantId, appName)
  displayName: appName
  signInAudience: 'AzureADMyOrg'
  web: {
    redirectUris: [callbackUrl]
  }
  publicClient: {
    redirectUris: ['https://login.microsoftonline.com/common/oauth2/nativeclient']
  }

  tags: [for item in items(tags): '${item.key}=${item.value}']
}

output appId string = appRegistration.appId
