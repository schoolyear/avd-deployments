# Setup proxy for user if there are any whitelisted hosts
$url = "http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-02-01"
$headers = @{
    "Metadata" = "true"
}

try
{
    # Make the request and get the response
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
}
catch
{
    Write-Error "Could not make request to metadata endpoint: $_"
    exit 1
}

# Find the "name": "proxyVmIpAddr" and print its value
$found = $false
$proxyIpAddr = ""
foreach ($tag in $response)
{
    if ($tag.name -eq "proxyVmIpAddr")
    {
        $proxyIpAddr = $tag.value
        $found = $true
        break
    }
}

if (!$found)
{
    Write-Error "Could not find proxyVmIpAddr in metadata"
    exit 1
}

##  Create pac file ##

# todo: make this dynamic
$pacContent = @"
function FindProxyForURL(url, host) {
  if (
    dnsDomainIs(host, "events.data.microsoft.com") ||
    dnsDomainIs(host, "login.microsoftonline.com") ||
    dnsDomainIs(host, "msauth.net") ||
    dnsDomainIs(host, "msftauth.net") ||
    dnsDomainIs(host, "officeapps.live.com") ||
    dnsDomainIs(host, "officeclient.microsoft.com")
  ) {
    return "PROXY $( $proxyIpAddr ):8080";
  }

  return "DIRECT";
}
"@

# Define the file path
$pacFilePath = "C:\static\proxy.pac"

# Create the directory if it doesn't exist
if (-Not (Test-Path "C:\static"))
{
    New-Item -ItemType Directory -Path "C:\static"
}

# Create the .pac file and write the content to it
Set-Content -Path $pacFilePath -Value $pacContent

Write-Output "proxy.pac file created at $pacFilePath"

## /Create pac file ##

$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

# Set the proxy server
Set-ItemProperty -Path $regPath -Name "AutoConfigURL" -Value "http://localhost:2015/proxy.pac"
# Enable the proxy
Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1
Set-ItemProperty -Path $regPath -Name AutoDetect -Value 0

# Refresh the settings
$refreshSystem = @"
using System;
using System.Runtime.InteropServices;

public class RefreshSystem
{
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);

    public const int INTERNET_OPTION_SETTINGS_CHANGED = 39;
    public const int INTERNET_OPTION_REFRESH = 37;

    public static void Refresh()
    {
        InternetSetOption(IntPtr.Zero, INTERNET_OPTION_SETTINGS_CHANGED, IntPtr.Zero, 0);
        InternetSetOption(IntPtr.Zero, INTERNET_OPTION_REFRESH, IntPtr.Zero, 0);
    }
}
"@
Add-Type -TypeDefinition $refreshSystem
[RefreshSystem]::Refresh()

Write-Output "Proxy server set to $proxyIpAddr and enabled."