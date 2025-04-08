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

# Skip auto-update if the currently installed version is less than or equal to this version
$SkipAutoUpdateMinVersion = "3.10.0"

# VDI Agent Auto-Update
# This script checks for the latest VDI agent version and updates the agent if it detects that the 
# currently installed version is older than the latest

# Logging functions #
function Write-Log {
  param (
    [string]$Level,
    [string]$Message
  )
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $logMessage = "[$timestamp] [$Level] $Message"
  Write-Host $logMessage
}

function Write-Info {
  param (
    [string]$Message
  )
  Write-Log -Level "INFO" -Message $Message
}

function Write-Error {
  param (
    [string]$Message
  )
  Write-Log -Level "ERROR" -Message $Message
}

function Write-Warning {
  param (
    [string]$Message
  )
  Write-Log -Level "WARNING" -Message $Message
}

$schoolyearInstallationBaseFolder = "C:\Program Files\Schoolyear"
if (!(Test-Path $schoolyearInstallationBaseFolder)) {
  Write-Info -Message "Could not find 64bit installation folder"

  $schoolyearInstallationBaseFolder = "C:\Program Files (x86)\Schoolyear"
  if (!(Test-Path $schoolyearInstallationBaseFolder)) {
    Write-Error -Message "Could not find 32bit installation folder either, exiting"
    exit 1
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
  Write-Error -Message "Could not find schoolyear browser installation folder"
  exit 1
}

Write-Info -Message "Found schoolyear browser installation folder: $schoolyearBrowserInstallationFolderName"

# Configuration
$programDataPath = Join-Path $env:ProgramData "Schoolyear"
$appExecutable = "schoolyear-exams.exe"

# Create necessary directories if they don't exist
if (-not (Test-Path $programDataPath)) {
  New-Item -Path $programDataPath -ItemType Directory -Force | Out-Null
}

## Function definitions ##

# Utility functions

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
  Write-Info -Message "Trying to kill vdi agent executable if it is running"
    
  try {
    $process = Get-Process -Name $appExecutable.Replace(".exe", "") -ErrorAction SilentlyContinue
    if ($process) {
      $process | Stop-Process -Force
      Write-Info -Message "Successfully killed $appExecutable"
      return $true
    }
    else {
      Write-Info -Message "$appExecutable is not running"
      return $true
    }
  }
  catch {
    Write-Error -Message "Failed to kill $appExecutable : $_"
    return $false
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
    Write-Info -Message "Installing MSI and waiting for it to finish"
    try {
      $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /quiet VDIPROVIDER=`"$vdiProvider`"" -Wait -PassThru
      if ($process.ExitCode -ne 0) {
        Write-Error -Message "msiexec failed with exit code: $($process.ExitCode)"
        return $false
      }
            
      Write-Warning -Message "msiexec finished but the service was not restarted"
      return $true
    }
    catch {
      Write-Error -Message "Failed to run msiexec: $_"
      return $false
    }
  }
  else {
    # Start msiexec without waiting
    try {
      Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" /quiet VDIPROVIDER=`"$vdiProvider`"" -NoNewWindow
      Write-Info -Message "Installing MSI (not waiting for completion)"
      return $true
    }
    catch {
      Write-Error -Message "Failed to start msiexec: $_"
      return $false
    }
  }
}

function Auto-UpdateVdiAgent {
  param (
    [string]$LatestAgentVersion,
    [string]$MsiDownloadUrl,
    [switch]$Wait
  )
    
  Write-Info -Message "Starting auto-update check for VDI agent"
    
  # Get current version
  $currentVersion = Get-CurrentVersion

  # Compare with SkipAutoUpdateMinVersion
  $cmpRes = Compare-SemVer -Version1 $SkipAutoUpdateMinVersion -Version2 $currentVersion
  if ($cmpRes -in @(0, 1)) {
    Write-Info -Message "Current version is $currentVersion while min auto update version is $SkipAutoUpdateMinVersion, skipping auto-update"
    return $true
  }

  # Compare versions with Latest Version
  $cmpRes = Compare-SemVer -Version1 $LatestAgentVersion -Version2 $currentVersion
  if ($cmpRes -in @(0, -1)) {
    Write-Info -Message "Agent version is up to date: $currentVersion"
    return $true
  }
    
  Write-Info -Message "Update needed: Current version $currentVersion, latest version $LatestAgentVersion"

  Write-Info -Message "Updating full MSI to version: $LatestAgentVersion"
  if (Update-VdiAgentMsi -Version $LatestAgentVersion -MsiDownloadUrl $MsiDownloadUrl -Wait $Wait) {
    Write-Info -Message "Successfully started MSI update to version: $LatestAgentVersion"
    return $true
  } else {
    Write-Error -Message "Failed to update VDI agent"
    return $false
  }
}

## /Function definitions ##

## Main ##

try {
  # Check if running as admin
  $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  
  if (-not $isAdmin) {
    Write-Error -Message "This script must be run as Administrator"
    exit 1
  }
  
  # Run the auto-update
  $result = Auto-UpdateVdiAgent -Wait $Wait -LatestAgentVersion $LatestAgentVersion -MsiDownloadUrl $MsiDownloadUrl
    
  if ($result) {
    Write-Info -Message "Auto-update script completed successfully"
    exit 0
  }
  else {
    Write-Error -Message "Auto-update script failed"
    exit 1
  }
}
catch {
  Write-Error -Message "Unhandled exception: $_"
  exit 1
}

## /Main ##