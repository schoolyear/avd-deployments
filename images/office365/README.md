# Office 365

## Image package

```cmd
avdcli image package \
    -l default_layers/common_config \
    -l default_layers/clean \
    -l default_layers/vdot \
    -l default_layers/vdi_browser \
    -l default_layers/scripts_setup \
    -l default_layers/network_lockdown \
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
    --start
```
