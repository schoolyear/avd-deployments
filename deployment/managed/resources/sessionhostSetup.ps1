$ErrorActionPreference = "Stop"

## Add detailed error handling helper function
function Write-ExceptionDetails {
  param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [System.Management.Automation.ErrorRecord]$ErrorRecord
  )

  process {
    Write-Host "=== EXCEPTION DETAILS ===" -ForegroundColor Red
    Write-Host "Error Message: $($ErrorRecord.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Exception Type: $($ErrorRecord.Exception.GetType().FullName)" -ForegroundColor Yellow

    Write-Host "`n=== ERROR RECORD DETAILS ===" -ForegroundColor Red
    Write-Host "CategoryInfo: $($ErrorRecord.CategoryInfo)" -ForegroundColor Yellow
    Write-Host "FullyQualifiedErrorId: $($ErrorRecord.FullyQualifiedErrorId)" -ForegroundColor Yellow

    if ($ErrorRecord.ScriptStackTrace) {
      Write-Host "`n=== SCRIPT STACK TRACE ===" -ForegroundColor Red
      Write-Host $ErrorRecord.ScriptStackTrace -ForegroundColor Yellow
    }

    if ($ErrorRecord.Exception.StackTrace) {
      Write-Host "`n=== EXCEPTION STACK TRACE ===" -ForegroundColor Red
      Write-Host $ErrorRecord.Exception.StackTrace -ForegroundColor Yellow
    }

    if ($ErrorRecord.Exception.InnerException) {
      Write-Host "`n=== INNER EXCEPTION ===" -ForegroundColor Red
      Write-Host "Message: $($ErrorRecord.Exception.InnerException.Message)" -ForegroundColor Yellow
      Write-Host "Type: $($ErrorRecord.Exception.InnerException.GetType().FullName)" -ForegroundColor Yellow

      if ($ErrorRecord.Exception.InnerException.StackTrace) {
        Write-Host "`n=== INNER EXCEPTION STACK TRACE ===" -ForegroundColor Red
        Write-Host $ErrorRecord.Exception.InnerException.StackTrace -ForegroundColor Yellow
      }
    }

    # Additional PowerShell specific details
    Write-Host "`n=== INVOCATION INFO ===" -ForegroundColor Red
    Write-Host "ScriptName: $($ErrorRecord.InvocationInfo.ScriptName)" -ForegroundColor Yellow
    Write-Host "Line Number: $($ErrorRecord.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
    Write-Host "Position Message: $($ErrorRecord.InvocationInfo.PositionMessage)" -ForegroundColor Yellow
    Write-Host "Line: $($ErrorRecord.InvocationInfo.Line)" -ForegroundColor Yellow
  }
}

$url = "http://169.254.169.254/metadata/instance/compute/userData?api-version=2021-01-01&format=text"
$headers = @{
  "Metadata" = "true"
}

try {
  $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
}
catch {
  Write-Host "Error occured while making request to Azure metadata service" -ForegroundColor Red
  $_ | Write-ExceptionDetails
  exit 1
}

# decode userData string blob (base64) and parse as json
$userData = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($response)) | ConvertFrom-Json

$proxyLoadBalancerPrivateIpAddress = $userData.proxyLoadBalancerPrivateIpAddress
if ([string]::IsNullOrEmpty($proxyLoadBalancerPrivateIpAddress)) {
  Write-Error "proxyLoadBalancerPrivateIpAddress is empty"
  exit 1
}

Write-Host "Open firewall to sessionhost proxy LB: $proxyLoadBalancerPrivateIpAddress"
try {
  New-NetFirewallRule -DisplayName "Allow sessionhost proxy LB outbound ($proxyLoadBalancerPrivateIpAddress)" -RemoteAddress $proxyLoadBalancerPrivateIpAddress -Direction Outbound -Action Allow -Profile Any | Out-Null
}
catch {
  Write-Host "Error while opening firewall to sessionhost proxy LB" -ForegroundColor Red
  $_ | Write-ExceptionDetails
  exit 1
}

# We map a local domain name to point to the LB private IP
$hostsFilepath = "C:\Windows\System32\drivers\etc\hosts"
$domain = "proxies.local"
$hostsFileUpdated = $false

$retryWaitTimeInSeconds = 5
for ($($retry = 1; $maxRetries = 5); $retry -le $maxRetries; $retry++) {
  try {
    # Prior to PowerShell 6.2, Add-Content takes a read lock, so if another process is already reading
    # the hosts file by the time we attempt to write to it, the cmdlet fails. This is a bug in older versions of PS.
    # https://github.com/PowerShell/PowerShell/issues/5924
    #
    # Using Out-File cmdlet with -Append flag reduces the chances of failure.

    "$proxyLoadBalancerPrivateIpAddress $domain" | Out-File -FilePath $hostsFilepath -Encoding Default -Append
    $hostsFileUpdated = $true;
    break
  }
  catch {
    Write-Host "Failed to update hosts file. Trying again... ($retry/$maxRetries)" -ForegroundColor Red
    Start-Sleep -Seconds $retryWaitTimeInSeconds
  }
}

if (!$hostsFileUpdated) {
  Write-Error "Could not update hosts file."
  exit 1
}

Write-Host "Updated hosts file"

ipconfig /flushdns

try {
  Write-Host "Setting default outbound action of all network profiles to [Allow]"
  Set-NetFirewallProfile -Profile Domain, Private, Public -DefaultOutboundAction Allow
}
catch {
  Write-Host "Error while setting default outbound action of all network profiles to [Allow]" -ForegroundColor Red
  $_ | Write-ExceptionDetails
  exit 1
}

$sessionhostScriptsPath = "C:\SessionhostScripts"
$scripts = Get-ChildItem -Path $sessionhostScriptsPath -Filter "???_*.ps1" | Sort-Object
foreach ($script in $scripts) {
  try {
    $scriptPath = Join-Path -Path $sessionhostScriptsPath -ChildPath $script
    Write-Host "[Executing: ${scriptPath}]"
  
    & {
      $ErrorActionPreference = "Continue"
      Set-StrictMode -Off
      $scriptpath
    }
  
    if (!$?) {
      throw "Error while executing sessionhost script: $script"
    }
  }
  catch {
    Write-Host "Error in sessionhost script execution" -ForegroundColor Red
    $_ | Write-ExceptionDetails
    exit 1
  }
}

# Allow hardcoded IP addresses used by Azure
New-NetFirewallRule -DisplayName "Allow metadata service outbound" -RemoteAddress 169.254.169.254 -Direction Outbound -Action Allow -Profile Any | Out-Null
New-NetFirewallRule -DisplayName "Allow health service monitor outbound" -RemoteAddress 168.63.129.16 -Direction Outbound -Action Allow -Profile Any | Out-Null
  
Set-NetFirewallProfile -Profile Domain, Private, Public -DefaultOutboundAction Block

Write-Host "[Done]" -ForegroundColor Green