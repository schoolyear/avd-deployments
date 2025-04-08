# Python

## Image package

```cmd
avdcli image package  -l default_layers/common_config -l default_layers/clean -l default_layers/vdot -l default_layers/vdi_browser -l default_layers/scripts_setup -l default_layers/network_lockdown -l images/python --overwrite
```


## Package deployment

```cmd
avdcli package deploy -n python -s b0604914-cd2c-4ac9-91bf-c25b32fd0892 -rg imagebuilding -r "https://stschoolyearimageres.blob.core.windows.net/resources" -dto out/resolved_template.json --start
```