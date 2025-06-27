$syInstallationBaseFolder = "C:\Program Files\Schoolyear"
if (!(Test-Path $syInstallationBaseFolder)) {
    Write-Host "Could not find 64bit Schooolyear base installation folder"

    $syInstallationBaseFolder = "C:\Program Files (x86)\Schoolyear"
    if (!(Test-Path $syInstallationBaseFolder)) {
        Write-Error "Could not find either 64bit or 32bit version of Schoolyear base installation folder"
        exit 1
    }
}

Write-Host "Schoolyear base installation folder: $syInstallationBaseFolder"

# We try to find the installation path.
# We have 4 distinct environments and we really don't want to pass the 
# environment as a parameter, so we can enumerate all of them and check
# for existance. First one we find is our path
$syBrowserInstallationFolderNames = @(
  "Schoolyear Browser Development (confidential)",
  "Schoolyear Browser Testing",
  "Schoolyear Browser Preview",
  "Schoolyear Browser"
)

$syBrowserInstallationFolderName = $null
foreach ($folderName in $syBrowserInstallationFolderNames) {
    $fullPath = Join-Path $syInstallationBaseFolder -ChildPath $folderName
    if (Test-Path $fullPath) {
        $syBrowserInstallationFolderName = $fullPath
        break
    }
}

if (!$syBrowserInstallationFolderName) {
    Write-Error "Could not find Schoolyear browser installation folder"
    exit 1
}

Write-Host "Found Schoolyear browser installation folder: $syBrowserInstallationFolderName"

$syExamsExe = Join-Path $syBrowserInstallationFolderName -ChildPath "shell\Schoolyear Exams.exe"
$syVDIServiceExe = Join-Path $syBrowserInstallationFolderName -ChildPath "schoolyear-vdi-service.exe"
$avdTokenProviderExe = Join-Path $syBrowserInstallationFolderName -ChildPath "shell\resources\avd_token_provider.exe"
# Allow the VDI browser
New-NetFirewallRule -DisplayName "Allow Schoolyear Browser outbound" -Program $syExamsExe -Direction Outbound -Action Allow -Profile Any | Out-Null
# Allow the background service
New-NetFirewallRule -DisplayName "Allow Schoolyear VDI service" -Program $syVDIServiceExe -Direction Outbound -Action Allow -Profile Any | Out-Null
# Allow the token provider
New-NetFirewallRule -DisplayName "Allow AVD token provider" -Program $avdTokenProviderExe -Direction Outbound -Action Allow -Profile Any | Out-Null

Write-Host "Whitelisted Schoolyear Browser, Schoolyear VDI Service & AVD token provider outbound"