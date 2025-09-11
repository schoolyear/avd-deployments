# RStudio

## Image folder structure

The `rstudio` folder consists of the following subfolders/files

* **build_steps.json5**

  Contains all the necessary steps (powershell files/commands) to run in order to prepare our R & RStudio image.
    
* **properties.json5**

  Contains necessary properties for deployment. For this image, we provide the whitelisted hosts that are necessary for external package installation. If you do **not** want to allow external package installation within this image you can remove the whitelisted hosts from this file.

* **resources/** 

  The `resources` folder will be placed in `C:imagebuild_resources` inside our VM before the installation scripts run. You can use those resources according to your needs during the installation process. This folder contains:

  * **rstudio_install_scripts/**
    * **r_and_rstudio_installation.ps1**

      Downloads and installs R & RStudio.
    
    * **rstudio_post_installation.ps1**

      Configures RStudio to find and use the previously installed R Version.

    * **file_associations.ps1**

      Configures the Windows machine to open associated files with RStudio.

  * **rstudio_resources/**
    * **RStudio_config/**
      * **.Rprofile**

        Configures RStudio to find the previously installed TinyTex package which is necessary for PDF generation.
      
      * **config.json**

        Configures RStudio to find the previously installed R version on the machine, among other things. This file is taken from a local RStudio installation and can be altered according to your specific needs.

      * **rstudio-prefs.json**

        Configures the mirror RStudio should use when installing external packages.

  * **user-scripts/**

    This folder contains all the scripts that will be executed by the Schoolyear VDI Browser inside the SessionHost during start up. The scripts inside this folder will be executed in order (001, 002 etc) as a non-privileged user.

    * **001_user_rstudio_proxy_setup.ps1**

      Configures RStudio to use our Trusted Proxy (which whitelists the hosts specified in our `properties.json5` file) and enables external package installation.

## Image package

```cmd
avdcli image package \
    -l default_layers/common_config \
    -l default_layers/clean \
    -l default_layers/vdi_browser \
    -l default_layers/scripts_setup \
    -l default_layers/network_lockdown \
    -l default_layers/windows_update \
    -l images/rstudio \
    --overwrite
```

## Package deployment

```cmd
avdcli package deploy \
    -n rstudio \
    -s <<azure subscription id>> \
    -rg imagebuilding \
    -r "https://<storageaccount>.blob.core.windows.net/<containername>" \
    -dto out/resolved_template.json
    --start
```
