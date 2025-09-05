$scriptName = Split-Path -Path $PSCommandPath -Leaf
$logFile = "C:\${scriptName}.log"
. "C:\imagebuild_resources\python\helperFunctions.ps1"

Log-Message "Start Script, Python installation"

$pythonInstallerName = "python-3.13.3-amd64.exe"
$pythonInstallerURL = "https://www.python.org/ftp/python/3.13.3/python-3.13.3-amd64.exe"
$pythonInstallerDownloadPath = "C:\${pythonInstallerName}"

#Downloads Python
if (!(Test-Path $pythonInstallerDownloadPath)) {
  Log-Message "Python Installer not found, downloading..."
  $output = Invoke-WebRequest -Uri $pythonInstallerURL -OutFile $pythonInstallerDownloadPath 2>&1
  Log-Message $output
}


# Installs Python
try {
  Log-Message "Installing python..."
  $process = Start-Process -FilePath $pythonInstallerDownloadPath -Args "/quiet InstallAllUsers=1 AssociateFiles=1 PrependPath=1" -Wait -NoNewWindow -PassThru
  Log-Message "Process exit code: $($process.ExitCode)"
  if ($process.ExitCode -eq 0) {
    Log-Message "Successfully installed python"
  } else {
    Log-Message "Python installation failed with exit code: $($process.ExitCode)"
  }
} catch {
  Log-Message "Failed to install python: $_"
}
