# Stop script on first error in order for the Schoolyear Agent to catch and report it.
$ErrorActionPreference = "Stop"

# The main purpose of this script is to set up Python in order to use our Trusted Proxy.
# Which in turn is configured to whitelist the hosts specified in our properties.json5 file.
# Configuring Python to use a proxy is as simple as creating a `pip.ini` file which is read by
# Python on startup.
# If you do NOT want to allow for the installation of external Python packages you can remove this file
# from the final build

# Within the VM SessionHosts Azure provides a `Metadata` service which contains (among others)
# the ip address of our proxy server which we can use to configure RStudio.
$url = "http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-02-01"
$headers = @{
  "Metadata" = "true"
}

try {
  # Make the request and get the response
  $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
}
catch {
  Write-Error "Could not make request to metadata endpoint: $_"
  exit 1
}

# Find the "name": "proxyVmIpAddr" and print its value
$found = $false 
$proxyIpAddr = ""
foreach ($tag in $response) {
  if ($tag.name -eq "proxyVmIpAddr") {
    $proxyIpAddr = $tag.value
    $found = $true
    break
  }
}

if (!$found) {
  Write-Error "Could not find proxyVmIpAddr in metadata"
  exit 1
}

Write-Host "Found proxyIpAddr: $proxyIpAddr"

# Find user home directory and create a subfoler named 'pip'
# inside the `pip` subfolder we create the `pip.ini` file
$userHomeDir = [System.Environment]::GetFolderPath('UserProfile')
$pipDir = Join-Path -Path $userHomeDir -ChildPath "pip"
if (!(Test-Path $pipDir)) {
  Write-Host "Creating $pipDir"
  New-Item -Path $pipDir -ItemType Directory -Force | Out-Null
}

# and fill it with our trusted hosts
# and the proxy pip should use when downloading packages
$pipIniPath = Join-Path -Path $pipDir -ChildPath "pip.ini"
$pipIniContent = @"
[global]
trusted-host =  pypi.python.org
                pypi.org
                files.pythonhosted.org
proxy = http://$proxyIpAddr
"@

Write-Host "Writing pip.ini file at: $pipIniPath"
Set-Content -Path $pipIniPath -Value $pipIniContent
Write-Host "Wrote $pipIniPath"