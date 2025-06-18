$ErrorActionPreference = "Stop"

$url = "http://169.254.169.254/metadata/instance/compute/userData?api-version=2021-01-01&format=text"
$headers = @{
    "Metadata" = "true"
}

try {
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
} catch {
    Write-Error "Could not make request to metadata endpoint (userData): $_"
    exit 1
}

# decode userData string blob (base64) and parse as json
$userData = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($response)) | ConvertFrom-Json

# Find version, we need to decide if this is managed or unmanaged version
$version = $userData.version
if (![string]::IsNullOrEmpty($version)) {
    # Managed
    $proxyLoadBalancerPrivateIpAddress = $userData.proxyLoadBalancerPrivateIpAddress
    if ([string]::IsNullOrEmpty($proxyLoadBalancerPrivateIpAddress)) {
        Write-Error "proxyLoadBalancerPrivateIpAddress is empty"
        exit 1
    }

    # The 000_system_proxy_setup.ps1 script has already modified the windows hosts file to map a local domain (proxies.local) to the proxy LB private ip address
    $domain = "proxies.local"

    $proxyBytes = [System.Text.Encoding]::UTF8.GetBytes("PROXY $($proxyLoadBalancerPrivateIpAddress):8080")
    $proxyStringBase64 = [Convert]::ToBase64String($proxyBytes)
    $matchingProxyBase64 = $proxyStringBase64.Replace('+','-').Replace('/','_').TrimEnd('=')
    $pacUrl = "http://${domain}:8080/proxy.pac?matchingProxyBase64=$matchingProxyBase64&defaultProxy=DIRECT"

    try
    {
        Write-Host "Setting user-level proxy..."
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

        Set-ItemProperty -Path $regPath -Name AutoConfigURL -Value "$pacUrl"
        Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1
        netsh winhttp import proxy source=ie
    }
    catch
    {
        Write-Error "Could not set user-level proxy: $_"
        exit 1
    }


    exit 0
}

# Unmanaged

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

# Find the "proxyVmIpAddresses" from metadata
$found = $false
$proxyIpAddresses = ""
foreach ($tag in $response) {
    if ($tag.name -eq "proxyVmIpAddresses")
    {
        $proxyIpAddresses = $tag.value
        $found = $true
        break
    }
}

if (!$found) {
    Write-Error "Could not find proxyVmIpAddresses in metadata"
    exit 1
}

$splitProxyIpAddresses = $proxyIpAddresses.split(",")

# The 000_system_proxy_setup.ps1 script has already modified the windows hosts file to map a local domain (proxies.local) 
# to all the proxies we may have, this is necessary in order to have a fail-over 
# and not use a single proxy to get back the pac file
$domain = "proxies.local"

# Turns out Windows doesn't properly escape semicolons, so we opted to use url-safe base64 encoding for this
# matchingProxyBase64 query param takes priority over matchingProxy in order not to break existing deployments
# Please use the new base64 encoded param for now so we don't run into any shenanigans in the future
$proxyString = $splitProxyIpAddresses.ForEach({ "PROXY $_" }) -join "; "
$proxyBytes = [System.Text.Encoding]::UTF8.GetBytes($proxyString)
$proxyStringBase64 = [Convert]::ToBase64String($proxyBytes)
$matchingProxyBase64 = $proxyStringBase64.Replace('+','-').Replace('/','_').TrimEnd('=')
$pacUrl = "http://${domain}:8080/proxy.pac?matchingProxyBase64=$matchingProxyBase64&defaultProxy=DIRECT"

try
{
    Write-Host "Setting user-level proxy..."
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

    Set-ItemProperty -Path $regPath -Name AutoConfigURL -Value "$pacUrl"
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1
    netsh winhttp import proxy source=ie
}
catch
{
    Write-Error "Could not set user-level proxy: $_"
    exit 1
}
