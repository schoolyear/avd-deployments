Write-Host "Downloading VDI agent MSI"
# todo: generalize for environments
$url = 'https://dev.install.exams.schoolyear.app/schoolyear-exams-browser-win-3.8.0.msi'
Invoke-WebRequest $url -OutFile ./browser.msi

Write-Host "Installing VDI agent"
& msiexec.exe /i browser.msi /qn VDIPROVIDER="avd" | Write-Verbose

Write-Host "Removing VDI agent MSI"
Remove-Item browser.msi