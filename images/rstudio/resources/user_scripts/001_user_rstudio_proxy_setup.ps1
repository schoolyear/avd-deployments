# Stop script on first error in order for the Schoolyear Agent to catch and report it.
$ErrorActionPreference = "Stop"

# The main purpose of this script is to set up RStudio in order to use our Trusted Proxy.
# Which in turn is configured to whitelist the hosts specified in our properties.json5 file.
# Configuring RStudio to use a proxy is as simple as setting some env variables that are loaded by RStudio on startup.
# This can be done by creating a `.Renviron` file in the user's `Documents` directory that tells RStudio the ip addr of the proxy to use
# If you do NOT want to allow for the installation of external R packages you can remove this file
# from the final build

# The 000_system_proxy_setup.ps1 script has already modified the windows hosts file to map a local domain (proxies.local) 
# to all the proxies we may have, this is necessary in order to have a fail-over 
# and not use a single proxy to get back the pac file
$domain = "proxies.local"

# Create the .Renviron file
$documentsFolder = [System.Environment]::GetFolderPath("MyDocuments")
$renvironFilePath = Join-Path -Path $documentsFolder -ChildPath ".Renviron"

# Define the content to write into .Renviron
$renvironFileContent = @"
options(internet.info = 0)
http_proxy=http://${domain}:8080
https_proxy=http://${domain}:8080
"@

Write-Host "Writing .Renviron file at: $renvironFilePath"
# Write the file (creates it if it doesn't exist)
Set-Content -Path $renvironFilePath -Value $renvironFileContent
Write-Host "Wrote $renvironFilePath"

# Now our RStudio installation should pick up on our `.Renviron` file and properly use the proxy if it needs to install any extra R packages
