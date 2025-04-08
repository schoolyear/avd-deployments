$scriptName = Split-Path -Path $PSCommandPath -Leaf
$logFile = "C:\${scriptName}.log"
#TODO, path aanpassen naar C:\imagebuild_resources\python\
. "C:\imagebuild_resources\python\helperFunctions.ps1"

Log-Message "Start Script, Python installatie"

$pythonInstallerName = "python-3.11.6.exe"
$pythonInstallerURL = "https://www.python.org/ftp/python/3.11.6/python-3.11.6-amd64.exe"
$pythonInstallerDownloadPath = "C:\${pythonInstallerName}"

if (!(Test-Path $pythonInstallerDownloadPath)) {
  Log-Message "Python Installer not found, downloading..."
  $output = Invoke-WebRequest -Uri $pythonInstallerURL -OutFile $pythonInstallerDownloadPath 2>&1
  Log-Message $output
}


# Actually install python
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
