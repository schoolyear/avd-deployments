# This script associates .r, .rdata, .rmd, .rproj file extensions with RStudio
# By default the RStudio installer doesn't do this, so we have to manually set
# the necessary registry keys responsible for this
$rstudioInstallationFolder = "C:\Program Files\RStudio"
$registryKey = "registry::HKEY_CLASSES_ROOT"
$rstudioExecutableFile = Join-Path -Path $rstudioInstallationFolder -ChildPath "rstudio.exe"
if (!(Test-Path $rstudioExecutableFile)) {
  Write-Error "Could not find rstudio executable: $rstudioExecutableFile"
  exit 1
}

Write-Host "Setting up file associations for r & rstudio..."

New-Item -Path "$registryKey\RScript.File" -Force | Out-Null
New-ItemProperty -Path "$registryKey\RScript.File" -Name "(Default)" -Value "RScript File" -PropertyType String -Force | Out-Null
New-Item -Path "$registryKey\RScript.File\shell\open\command" -Force | Out-Null
New-ItemProperty -Path "$registryKey\RScript.File\shell\open\command" -Name "(Default)" -Value "$rstudioExecutableFile `"%1`"" -PropertyType String -Force | Out-Null
New-Item -Path "$registryKey\RScript.File\DefaultIcon" -Force | Out-Null
New-ItemProperty -Path "$registryKey\RScript.File\DefaultIcon" -Name "(Default)" -Value "$rstudioExecutableFile,-2" -PropertyType String -Force | Out-Null

New-Item -Path "$registryKey\.r" -Force | Out-Null
New-ItemProperty -Path "$registryKey\.r" -Name "(Default)" -Value "RScript.File" -PropertyType String -Force | Out-Null
New-Item -Path "$registryKey\.rdata" -Force | Out-Null
New-ItemProperty -Path "$registryKey\.rdata" -Name "(Default)" -Value "RScript.File" -PropertyType String -Force | Out-Null
New-Item -Path "$registryKey\.rmd" -Force | Out-Null
New-ItemProperty -Path "$registryKey\.rmd" -Name "(Default)" -Value "RScript.File" -PropertyType String -Force | Out-Null
New-Item -Path "$registryKey\.rproj" -Force | Out-Null
New-ItemProperty -Path "$registryKey\.rproj" -Name "(Default)" -Value "RScript.File" -PropertyType String -Force | Out-Null

# In case you want to associate any more file extensions with RStudio add it here.
# $ext = "?"
# New-Item -Path "$registryKey\$ext" -Force | Out-Null
# New-ItemProperty -Path "$registryKey\$ext" -Name "(Default)" -Value "RScript.File" -PropertyType String -Force | Out-Null

Write-Host "Done setting up file associations for r & rstudio"

