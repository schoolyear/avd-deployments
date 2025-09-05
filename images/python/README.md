# VS Code + Python (incl. Jupyter Notebook) script
## created by Jim van Boven and Dirk van Nunen (TU/e), based partly on the Schoolyear "Schoolyear Cloud" for Python script.

A Python image that installs VS Code, Python and some Jupyter notebook extensions for VS Code. It also includes a colour blindness theme. Please note: The image has network access to python package repositories.

The image was tested at TU/e, but so far only by IT staff.

### Image package

```cmd
avdcli image package  -l default_layers/common_config -l default_layers/clean -l default_layers/vdot -l default_layers/vdi_browser -l default_layers/scripts_setup -l default_layers/network_lockdown -l images/python --overwrite
```


### Package deployment

```cmd
avdcli package deploy -n python -s <subscription ID> -rg imagebuilding -r "https://<name of storage account>.blob.core.windows.net/<name of container>" -dto out/resolved_template.json --start
```
