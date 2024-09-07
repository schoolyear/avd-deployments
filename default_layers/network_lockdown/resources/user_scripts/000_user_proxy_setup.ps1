$ErrorActionPreference = "Stop"

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

$matchingProxy = [uri]::EscapeDataString("PROXY $proxyIpAddr")
$pacUrl = "http://$proxyIpAddr/proxy.pac?matchingProxy=$matchingProxy&defaultProxy=DIRECT"

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
