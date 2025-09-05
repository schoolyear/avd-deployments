$pipExecutable = "C:\Program Files\Python313\Scripts\pip.exe"

Write-Host "Installing packages one by one"

$packages = @(
  "pandas",
  "vpython",
  "ipykernel",
  "numpy",
  "matplotlib",
  "requests",
  "flask",
  "django"
)

foreach ($package in $packages) {
  Write-Host "Installing package: $package"
  try {
    Start-Process -FilePath $pipExecutable -ArgumentList "install", $package -Wait -NoNewWindow
    Write-Host "Successfully installed $package"
  } catch {
    Write-Error "Failed to install package: $package — $_"
  }
}

Write-Host "Done installing packages"
