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
    # Managed version
    $proxyLoadBalancerPrivateIpAddress = $userData.proxyLoadBalancerPrivateIpAddress
    if ([string]::IsNullOrEmpty($proxyLoadBalancerPrivateIpAddress)) {
        Write-Error "proxyLoadBalancerPrivateIpAddress is empty"
        exit 1
    }

    Write-Host "Open firewall to sessionhost proxy LB: $proxyLoadBalancerPrivateIpAddress"
    New-NetFirewallRule -DisplayName "Allow sessionhost proxy LB outbound ($proxyLoadBalancerPrivateIpAddress)" -RemoteAddress $proxyLoadBalancerPrivateIpAddress -Direction Outbound -Action Allow -Profile Any | Out-Null

    # We map a local domain name to point to the LB private IP
    $hostsFilepath = "C:\Windows\System32\drivers\etc\hosts"
    $domain = "proxies.local"
    $hostsFileUpdated = $false

    $retryWaitTimeInSeconds = 5
    for($($retry = 1; $maxRetries = 5); $retry -le $maxRetries; $retry++) {
        try {
            # Prior to PowerShell 6.2, Add-Content takes a read lock, so if another process is already reading
            # the hosts file by the time we attempt to write to it, the cmdlet fails. This is a bug in older versions of PS.
            # https://github.com/PowerShell/PowerShell/issues/5924
            #
            # Using Out-File cmdlet with -Append flag reduces the chances of failure.

            "$proxyLoadBalancerPrivateIpAddress $domain" | Out-File -FilePath $hostsFilepath -Encoding Default -Append
            $hostsFileUpdated = $true;
            break
        } catch {
            Write-Host "Failed to update hosts file. Trying again... ($retry/$maxRetries)";
            Start-Sleep -Seconds $retryWaitTimeInSeconds
        }
    }

    if (!$hostsFileUpdated) {
        Write-Error "Could not update hosts file."
        exit 1
    }

    Write-Host "Updated hosts file"

    ipconfig /flushdns

    $proxyBytes = [System.Text.Encoding]::UTF8.GetBytes("PROXY $($proxyLoadBalancerPrivateIpAddress):8080")
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
$hostsFileUpdated = $false
foreach ($proxyIpAddr in $splitProxyIpAddresses) {
    # add line by line each proxy ip pointing to that domain
    # ex.
    #    10.0.16.4 proxies.local
    #    10.0.16.5 proxies.local
    $ipWithoutPort = ($proxyIpAddr -split ":")[0]
    $retryWaitTimeInSeconds = 5

    for($($retry = 1; $maxRetries = 5); $retry -le $maxRetries; $retry++) {
        try {
            # Prior to PowerShell 6.2, Add-Content takes a read lock, so if another process is already reading
            # the hosts file by the time we attempt to write to it, the cmdlet fails. This is a bug in older versions of PS.
            # https://github.com/PowerShell/PowerShell/issues/5924
            #
            # Using Out-File cmdlet with -Append flag reduces the chances of failure.

            "$ipWithoutPort $domain" | Out-File -FilePath $hostsFilepath -Encoding Default -Append
            $hostsFileUpdated = $true;
            break
        } catch {
            Write-Host "Failed to update hosts file. Trying again... ($retry/$maxRetries)";
            Start-Sleep -Seconds $retryWaitTimeInSeconds
        }
    }
}

if (!$hostsFileUpdated) {
    Write-Error "Could not update hosts file."
    exit 1
}

Write-Host "Hosts file updated."

# Flush dns
ipconfig /flushdns

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