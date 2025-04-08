# Starting the script with ProgressPreference = 'SilentlyContinue' is necessary to make downloads much faster.
# This setting disables the windows spinning bar during the command `Invoke-Webrequest`
# which significantly speeds up the process of downloading the necessary installers.
$ProgressPreference = 'SilentlyContinue'

### Functions ###

# Helper function to download R
function Download-R {
    param (
        [string]$rVersion,
        [string]$rDestination
    )

    # Define the URL for the specific version of the R installer
    $url = "https://cran.r-project.org/bin/windows/base/old/$rVersion/R-$rVersion-win.exe"
    
    try {
        Write-Host "Downloading R... : $url"
        Invoke-WebRequest -Uri $url -OutFile $rDestination
        Write-Host "Download complete: $rDestination"
    } catch {
        Write-Error "Failed to download R-$rVersion $_"
    }
}

# Helper function to download RStudio
function Download-RStudio {
  param (
    [string]$rStudioVersion,
    [string]$rStudioDestination
  )

  $url = "https://download1.rstudio.org/electron/windows/RStudio-$rStudioVersion.exe"
  try {
    Write-Host "Downloading RStudio... : $url"
    Invoke-WebRequest -Uri $url -OutFile $rStudioDestination
    Write-Host "Download complete: $rStudioDestination"
  } catch {
    Write-Error "Failed to download RStudio: $_"
  }
}

### /Functions ###

### MAIN ###

## Create Download folder ##

# We need a place inside the VM to save the downloaded executables
# We choose to create `C:\AVDImage\Downloads` which will act as our Downloads folder
# We cannot use a specific user's Downloads folder since this script will be run as `System`
$downloadFolder = "C:\AVDImage\Downloads"
if (!(Test-Path $downloadFolder)) {
  Write-Host "$downloadFolder does not exist, creating..."
  New-Item -Path $downloadFolder -ItemType Directory -Force
} else {
  Write-Host "Found $downloadFolder"
}

## /Create Download folder ##

# Download R
$rVersion = "4.4.1"
$rDownloadDestination = Join-Path -Path $downloadFolder -ChildPath "R-$rVersion-win.exe"
if (!(Test-Path $rDownloadDestination)) {
  Write-Host "R installer doesn't seem to exist, downloading..."
  Download-R -rVersion $rVersion -rDestination $rDownloadDestination
} else {
  Write-Host "Found R installer, skipping download"
}

# Download RStudio
$rStudioVersion = "2024.04.2-764"
$rStudioDownloadDestination = Join-Path -Path $downloadFolder -ChildPath "RStudio-$rStudioVersion.exe"
if (!(Test-Path $rStudioDownloadDestination)) {
  Write-Host "RStudio installer not found, downloading..."
  Download-RStudio -rStudioVersion $rStudioVersion -rStudioDestination $rStudioDownloadDestination
} else {
  Write-Host "Found RStudio installer, skipping download"
}

# Install R
try {
  Write-Host "Installing R..."
  Start-Process -FilePath $rDownloadDestination -ArgumentList "/SILENT" -Wait -NoNewWindow
  Write-Host "Installed R"
} catch {
  Write-Error "Failed to install R: $_"
}

# Install RStudio
try {
  Write-Host "Installing RStudio..."
  Start-Process -FilePath $rStudioDownloadDestination -ArgumentList "/S" -Wait -NoNewWindow
  Write-Host "Installed RStudio"
} catch {
  Write-Error "Failed to install RStudio: $_"
}

# Cleanup, remove our Downloads folder
Write-Host "Removing folder: $downloadFolder"
Remove-Item -Path $downloadFolder -Recurse -Force
Write-Host "Removed folder"
