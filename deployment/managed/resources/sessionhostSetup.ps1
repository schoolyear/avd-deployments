param (
  [Parameter(Mandatory)]
  [string]$LatestAgentVersion,
  [Parameter(Mandatory)]
  [string]$MsiDownloadUrl,
  [Parameter(Mandatory)]
  [switch]$Wait
)

$ProgressPreference = 'SilentlyContinue'
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

### Auto-update VDI ###

# Compare-SemVer accepts 2 SemVer versions. 
# Returns -1, 0, 1 if Version1 is less than, equal to or greater than version 2 respectively
# Throws an exception if unable to convert string input to a proper SemVer 
function Compare-SemVer {
  param (
    [Parameter(Mandatory)]
    [string]$Version1,
    
    [Parameter(Mandatory)]
    [string]$Version2
  )
  
  # Convert string versions to System.Version objects
  $v1 = [System.Version]$Version1
  $v2 = [System.Version]$Version2
  
  if ($v1 -eq $v2) {
    return 0
  }

  if ($v1 -lt $v2) {
    return -1
  }

  return 1
}

# Gets the current version by reading the build-metadata.json file
function Get-CurrentVersion {
  $buildMetadataFile = Join-Path -Path $schoolyearBrowserInstallationFolderName -ChildPath "shell\resources\build-metadata.json"
  if (!(Test-Path $buildMetadataFile)) {
    throw "Could not find metadata file: $buildMetadataFile"
  }

  $jsonContent = Get-Content -Path $buildMetadataFile -Raw | ConvertFrom-Json
  $version = $jsonContent.version

  return $version
}

function Kill-SchoolyearExamsProcess {
  Write-Host "Trying to kill vdi agent executable if it is running"
    
  $process = Get-Process -Name $appExecutable.Replace(".exe", "") -ErrorAction SilentlyContinue
  if ($process) {
    $process | Stop-Process -Force
    Write-Host "Successfully killed $appExecutable"
  }
  else {
    Write-Host "$appExecutable is not running"
  }
}

function Update-VdiAgentMsi {
  param (
    [string]$Version,
    [string]$MsiDownloadUrl,
    [switch]$Wait
  )
    
  $vdiProvider = "avd"
  $filename = "schoolyear-exams-browser-win-${Version}.msi"

  # Download the MSI
  $msiPath = Join-Path $programDataPath $filename
  Invoke-WebRequest -Uri $MsiDownloadUrl -OutFile $msiPath
    
  # Kill the app executable if it's running
  Kill-SchoolyearExamsProcess
    
  if ($Wait) {
    # Execute msiexec and wait for it to finish
    Write-Host "Installing MSI and waiting for it to finish"
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /quiet VDIPROVIDER=`"$vdiProvider`"" -Wait -PassThru
    if ($process.ExitCode -ne 0) {
      throw "msiexec failed with exit code: $($process.ExitCode)"
    }
            
    Write-Host "msiexec finished but the service was not restarted"
  }
  else {
    # Start msiexec without waiting
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /quiet VDIPROVIDER=`"$vdiProvider`"" -NoNewWindow
    Write-Host "Installing MSI (not waiting for completion)"
  }
}

function Auto-UpdateVdiAgent {
  param (
    [string]$LatestAgentVersion,
    [string]$MsiDownloadUrl,
    [switch]$Wait
  )
    
  Write-Host "Starting auto-update check for VDI agent"
    
  # Get current version
  $currentVersion = Get-CurrentVersion

  # Compare with SkipAutoUpdateMinVersion
  $cmpRes = Compare-SemVer -Version1 $SkipAutoUpdateMinVersion -Version2 $currentVersion
  if ($cmpRes -in @(0, 1)) {
    Write-Host "Current version is $currentVersion while min auto update version is $SkipAutoUpdateMinVersion, skipping auto-update"
    return
  }

  # Compare versions with Latest Version
  $cmpRes = Compare-SemVer -Version1 $LatestAgentVersion -Version2 $currentVersion
  if ($cmpRes -in @(0, -1)) {
    Write-Host "Agent version is up to date: $currentVersion"
    return
  }
    
  Write-Host "Update needed: Current version $currentVersion, latest version $LatestAgentVersion"

  Write-Host "Updating full MSI to version: $LatestAgentVersion"
  Update-VdiAgentMsi -Version $LatestAgentVersion -MsiDownloadUrl $MsiDownloadUrl -Wait $Wait
  Write-Host "Successfully started MSI update to version: $LatestAgentVersion"
}

# Skip auto-update if the currently installed version is less than or equal to this version
$SkipAutoUpdateMinVersion = "3.10.0"

# VDI Agent Auto-Update
# This script checks for the latest VDI agent version and updates the agent if it detects that the 
# currently installed version is older than the latest

try {
  $schoolyearInstallationBaseFolder = "C:\Program Files\Schoolyear"
  if (!(Test-Path $schoolyearInstallationBaseFolder)) {
    Write-Host "Could not find 64bit installation folder"

    $schoolyearInstallationBaseFolder = "C:\Program Files (x86)\Schoolyear"
    if (!(Test-Path $schoolyearInstallationBaseFolder)) {
      throw "Could not find 32bit installation folder either, exiting"
    }
  }

  # We try to find the installation path.
  # We have 4 distinct environments and we really don't want to pass the 
  # environment as a parameter, so we can enumerate all of them and check
  # for existance. First one we find is our path
  $schoolyearBrowserInstallationFolderNames = @(
    "Schoolyear Browser Development (confidential)",
    "Schoolyear Browser Testing",
    "Schoolyear Browser Preview",
    "Schoolyear Browser"
  )

  $schoolyearBrowserInstallationFolderName = $null
  foreach ($folderName in $schoolyearBrowserInstallationFolderNames) {
    $fullPath = Join-Path -Path $schoolyearInstallationBaseFolder -ChildPath $folderName

    if (Test-Path $fullPath) {
      $schoolyearBrowserInstallationFolderName = $fullPath
      break
    }
  }

  if (!$schoolyearBrowserInstallationFolderName) {
    throw "Could not find schoolyear browser installation folder"
  }

  Write-Host "Found schoolyear browser installation folder: $schoolyearBrowserInstallationFolderName"

  # Configuration
  $programDataPath = Join-Path $env:ProgramData "Schoolyear"
  $appExecutable = "schoolyear-exams.exe"

  # Create necessary directories if they don't exist
  if (-not (Test-Path $programDataPath)) {
    New-Item -Path $programDataPath -ItemType Directory -Force | Out-Null
  }

  # Check if running as admin
  $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  
  if (-not $isAdmin) {
    throw "Auto-updating the vdi browser needs admin right"
  }
  
  # Run the auto-update
  Auto-UpdateVdiAgent -Wait $Wait -LatestAgentVersion $LatestAgentVersion -MsiDownloadUrl $MsiDownloadUrl
  Write-Host "Auto-updating completed successfully" -ForegroundColor Green
}
catch {
  Write-Host "Error while executing auto update vdi browser" -ForegroundColor Red
  $_ | Write-ExceptionDetails
  exit 1
}

### /Auto-update VDI ###

### Sessionhost Setup ###

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

# Find AVD Endpoints ip range to whitelist
$avdEndpointsIpRange = $userData.avdEndpointsIpRange
if ([string]::IsNullOrEmpty($avdEndpointsIpRange)) {
  Write-Error "avdEndpointsIpRange is empty"
  exit 1
}

Write-Host "Open firewall to AVD endpoints subnet: $avdEndpointsIpRange"
try {
  New-NetFirewallRule -DisplayName "Allow all outbound to azure AVD endpoints $avdEndpointsIpRange" -Direction Outbound -RemoteAddress $avdEndpointsIpRange -Action Allow -Profile Any | Out-Null
}
catch {
  Write-Host "Error while opening firewall to AVD endpoints subnet" -ForegroundColor Red
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
      & $scriptPath
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

# set the default network profile to public
Set-NetConnectionProfile -NetworkCategory Public
# block all outbound traffic
Set-NetFirewallProfile -Profile Domain, Private, Public -DefaultOutboundAction Block

### /Sessionhost Setup ###

### Schedule Reboot ###

try {
  Register-ScheduledTask -Action (New-ScheduledTaskAction -Execute 'Powershell' -Argument '-Command Restart-Computer -Force') -Trigger (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)) -RunLevel Highest -User System -Force -TaskName 'reboot'
}
catch {
  Write-Host "Error while trying to schedule reboot" -ForegroundColor Red
  $_ | Write-ExceptionDetails
  exit 1
}

### /Schedule Reboot ###

Write-Host "[Done]" -ForegroundColor Green

