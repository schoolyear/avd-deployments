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

try
{
    Write-Host "Setting user-level proxy..."
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

    Set-ItemProperty -Path $regPath -Name ProxyServer -Value "$proxyIpAddr"
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1
    Set-ItemProperty -Path $regPath -Name AutoDetect -Value 0
    Set-ItemProperty -Path $regPath -Name ProxyOverride -Value "*.wvd.microsoft.com"
    netsh winhttp import proxy source=ie
}
catch
{
    Write-Error "Could not set user-level proxy: $_"
    exit 1
}
