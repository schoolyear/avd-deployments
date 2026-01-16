# Office 365

## Image package

```cmd
avdcli image package \
    -l default_layers/common_config \
    -l default_layers/clean \
    -l default_layers/vdi_browser \
    -l default_layers/scripts_setup \
    -l default_layers/network_lockdown \
    -l default_layers/windows_update \
    -l images/office365 \
    --overwrite
```


## Package deployment

```cmd
avdcli package deploy \
    -n office365 \
    -s <<azure subscription id>> \
    -rg imagebuilding \
    -r "https://<storageaccount>.blob.core.windows.net/<containername>" \
    -dto out/resolved_template.json \
    --start
```

## 16 jan 2026 update

On the 16th of January 2026, Microsoft added an extra FQDN required for Office activation.
Without access to this domain, Office will show an activation error and block exam participants from using Office.

This FQDN is now added to the `properties.json5` in this layer, and we advise all customers using this layer to download this update for future image builds.
If you built your own custom Office layer based on this layer, we recommend updating that layer as well.

### Quick-fix

A change in a layer requires an image rebuild to take effect.
While we advise all users of this layer to perform such an image rebuild, there is a quick-fix available that takes effect immediately for all new exam deployments.

1. Look up the `Template Resource ID` in your AVD-addon for your Apps that use Office, and repeat the next steps for each of them.
2. Navigate to the Azure Portal, look up this Template Resource, click on `Versions`, and navigate to the one referenced in your `Template Resource ID`.
3. Click on `Edit > Edit Template` and find the line `"sessionHostProxyWhitelist": "...",`.
4. Scroll to the end of the line and add `,licensing.m365.svc.cloud.microsoft:443` to the string.
5. Click on `Review + Save`, then `Save Changes`.
6. Verify your fix by deploying a new exam with your Office app, starting the exam as a student, and checking whether
   Office properly activates.
