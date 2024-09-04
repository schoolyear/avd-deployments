$ErrorActionPreference = "Stop"

function GetProxyIPsString()
{
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

    return $proxyIPAddr
}

$proxyIP = GetProxyIPsString
$proxyString = (($proxyIP -split ',') | ForEach-Object { "PROXY $_" }) -join '; '

$whitelist = Get-Content -Path "C:\domainwhitelist.json" | ConvertFrom-Json
$domainChecks = 'false'
if ($whitelist.PSObject.Properties.Name.count -gt 0)
{
    $domainChecks = ($whitelist.PSObject.Properties | ForEach-Object {
        "dnsDomainIs(host, `"$( $_.Name )`")"
    }) -join ' || '
}

$pacScriptPath = "C:\static\proxy.pac"
$pacSCriptParentPath = Split-Path -Path $pacScriptPath -Parent

if (-Not (Test-Path $pacSCriptParentPath))
{
    New-Item -ItemType Directory -Force -Path $pacSCriptParentPath
}

@"
function FindProxyForURL(url, host) {
    if (!dnsDomainIs(host, 'wvd.microsoft.com') && ($domainChecks)) {
        return "$( $proxyString )";
    }
    return "DIRECT";
}
"@ | Out-File -FilePath $pacScriptPath

try
{
    Write-Host "Setting system wide proxy..."
    bitsadmin /util /setieproxy LOCALSYSTEM AUTOSCRIPT "http://localhost:2015/proxy.pac"
    bitsadmin /util /setieproxy NETWORKSERVICE AUTOSCRIPT "http://localhost:2015/proxy.pac"
}
catch
{
    Write-Error "Could not set system wide proxy: $_"
    exit 1
}