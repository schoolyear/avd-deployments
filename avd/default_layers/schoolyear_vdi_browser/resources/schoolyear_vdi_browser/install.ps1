param (
    [string]$msiUrl
)

Write-Host "Downloading VDI agent MSI"
Invoke-WebRequest $msiUrl -OutFile "C:\vdi_browser.msi"

Write-Host "Installing VDI agent"
$main_process = Start-Process msiexec.exe -ArgumentList '/i "C:\vdi_browser.msi" /q VDIPROVIDER="avd" /l*! output.log' -PassThru
$log_process = Start-Process "powershell" "Get-Content -Path output.log -Wait" -NoNewWindow -PassThru
$main_process.WaitForExit()
$log_process.Kill()

Write-Host "Removing VDI agent MSI"
Remove-Item "C:\vdi_browser.msi"

exit $main_process.ExitCode
