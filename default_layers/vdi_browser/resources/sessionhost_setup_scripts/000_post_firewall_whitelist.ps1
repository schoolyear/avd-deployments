$syFolder = "C:\Program Files (x86)\Schoolyear\"
$installationFolders = @("Schoolyear Browser Development (confidential)", "Schoolyear Browser Testing", "Schoolyear Browser Preview", "Schoolyear Browser")

foreach ($folder in $installationFolders) {
    $syExamsFolder= Join-Path -Path $syFolder -ChildPath $folder

    $syExamsExe = "$syExamsFolder\shell\Schoolyear Exams.exe"
    $syVDIServiceExe = "$syExamsFolder\schoolyear-vdi-service.exe"
    $avdTokenProviderExe = "$syExamsFolder\shell\resources\avd_token_provider.exe"

    # Allow the VDI browser
    New-NetFirewallRule -DisplayName "Allow Schoolyear Browser outbound" -Program $syExamsExe -Direction Outbound -Action Allow -Profile Any | Out-Null
    # Allow the background service
    New-NetFirewallRule -DisplayName "Allow Schoolyear VDI service" -Program $syVDIServiceExe -Direction Outbound -Action Allow -Profile Any | Out-Null
    # Allow the token provider
    New-NetFirewallRule -DisplayName "Allow AVD token provider" -Program $avdTokenProviderExe -Direction Outbound -Action Allow -Profile Any | Out-Null
}

