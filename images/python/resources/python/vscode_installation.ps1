param (
  [switch]$RemoveInstaller
)

$scriptName = Split-Path -Path $PSCommandPath -Leaf
$logFile = "C:\${scriptName}.log"
#TODO, path aanpassen naar C:\imagebuild_resources\python\
. "C:\imagebuild_resources\python\helperFunctions.ps1"

# NOTE: Maybe we shouldn't use latest for this
$vsCodeZipURL = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-archive"
$vsCodeZipName = "vscode.zip"
$vsCodeZipDownloadPath = "C:\${vsCodeZipName}"
$vsCodeZipExtractPath = "C:\VSCode"

if (!(Test-Path $vsCodeZipDownloadPath)) {
  Log-Message "VSCode installer not found, downloading..."
  try {
    Invoke-WebRequest -Uri $vsCodeZipURL -OutFile $vsCodeZipDownloadPath
  } catch {
    Log-Message "Failed to download VSCode : $_"
  }
} else {
  Log-Message "VSCode installer found, skipping download"
}

# If extracted vscode exists, remove
if (Test-Path $vsCodeZipExtractPath) {
  Log-Message "Found $vsCodeZipExtractPath, removing..."
  Remove-Item $vsCodeZipExtractPath -Force -Recurse | Out-Null
  Log-Message "Removed $vsCodeZipExtractPath"
}

try {
  Log-Message "Extracting VSCode..."
  Expand-Archive $vsCodeZipDownloadPath $vsCodeZipExtractPath | Out-Null  
  Log-Message "Extracted VSCode"
} catch {
  Log-Message "Failed to extract VSCode: $_"
}

# Creating data file
try {
  Log-Message "Copying over data folder to $vsCodeZipExtractPath..."
  Copy-Item "C:\imagebuild_resources\python\files\vscode\user-data" $vsCodeZipExtractPath -Force -Recurse | Out-Null
  Log-Message "Successfully copied over data folder"
} catch {
  Log-Message "Failed to copy over data folder: $_"
}

if ($RemoveInstaller) {
  Log-Message "Removing downloaded installer (.zip file)"
  Remove-Item $vsCodeZipDownloadPath | Out-Null
  Log-Message "Successfully removed $vsCodeZipDownloadPath"
}