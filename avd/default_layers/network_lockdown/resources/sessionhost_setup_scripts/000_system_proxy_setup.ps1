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
    Write-Host "Setting system proxy..."
    bitsadmin /util /setieproxy LOCALSYSTEM MANUAL_PROXY "$proxyIpAddr" *.wvd.microsoft.com
    bitsadmin /util /setieproxy NETWORKSERVICE MANUAL_PROXY "$proxyIpAddr" *.wvd.microsoft.com
}
catch
{
    Write-Error "Could not set system proxy: $_"
    exit 1
}