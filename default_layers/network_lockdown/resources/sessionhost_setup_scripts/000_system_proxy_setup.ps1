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
foreach ($proxyIpAddr in $splitProxyIpAddresses) {
    $ipWithoutPort = ($proxyIpAddr -split ":")[0]
    Write-Host "Open firewall to sessionhost proxy: $ipWithoutPort"
    New-NetFirewallRule -DisplayName "Allow sessionhost proxy outbound ($ipWithoutPort)" -RemoteAddress $ipWithoutPort -Direction Outbound -Action Allow -Profile Any | Out-Null
}

# We modify the windows hosts file to map a local domain (proxies.local) 
# to all the proxies we may have, this is necessary in order to have a fail-over 
# and not use a single proxy to get back the pac file
$hostsFilepath = "C:\Windows\System32\drivers\etc\hosts"
$domain = "proxies.local"
foreach ($proxyIpAddr in $splitProxyIpAddresses) {
    # add line by line each proxy ip pointing to that domain
    # ex.
    #    10.0.16.4 proxies.local
    #    10.0.16.5 proxies.local
    $ipWithoutPort = ($proxyIpAddr -split ":")[0]
    Add-Content -Path $hostsFilepath -Value "$ipWithoutPort $domain"
}

Write-Host "Updated hosts file"

# Flush dns
ipconfig \flushdns

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
    Write-Host "Setting system proxy..."
    bitsadmin /util /setieproxy LOCALSYSTEM AUTOSCRIPT "$pacUrl"
    bitsadmin /util /setieproxy NETWORKSERVICE AUTOSCRIPT "$pacUrl"
}
catch
{
    Write-Error "Could not set system proxy: $_"
    exit 1
}