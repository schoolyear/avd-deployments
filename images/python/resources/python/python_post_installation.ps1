
$pipExecutable = "C:\Program Files\Python313\Scripts\pip.exe"
try {
  Write-Host "Installing ipykernel package"
  Start-Process -FilePath $pipExecutable -ArgumentList "install", "ipykernel" -Wait -NoNewWindow
  Write-Host "Done installing ipykernel package"
} catch {
  Write-Error "Failed to install ipykernel package: $_"
}