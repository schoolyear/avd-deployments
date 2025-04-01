Log-Message "Start Script, Python installatie"

Function Get-MD5Hash($file)
{
  $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
  $fileStream = [System.IO.File]::OpenRead($file)
  try {
      $hash = [System.BitConverter]::ToString($md5.ComputeHash($fileStream)).Replace("-", "").ToLower()
  }
  finally {
      $fileStream.Close()
  }
  return $hash
}


function Log-Message {
    param (
        [string]$message
    )
    Write-Host $message
    
}

$pythonInstallerName = "python-3.11.6.exe"
$pythonInstallerURL = "https://www.python.org/ftp/python/3.11.6/python-3.11.6-amd64.exe"
$pythonInstallerMD5Sum = "4a501c073d0d688c033d43f85e22d77e"
$pythonInstallerDownloadPath = "$env:USERPROFILE\Downloads\$pythonInstallerName"

if (!(Test-Path $pythonInstallerDownloadPath)) {
  Log-Message "Python Installer not found, downloading..."
  $output = Invoke-WebRequest -Uri $pythonInstallerURL -OutFile $pythonInstallerDownloadPath 2>&1
  Log-Message $output
}

# Calculate the MD5 hash of the downloaded file
$downloadedMD5 = Get-MD5Hash -file $pythonInstallerDownloadPath
Log-Message "Calculated MD5: $downloadedMD5"

# Compare the calculated MD5 with the expected value
if (!($downloadedMD5 -eq $pythonInstallerMD5Sum))
{
  Log-Message "MD5 does not match: $downloadedMD5"
  Write-Error "MD5 does not match: $downloadedMD5"
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
  Write-Error "Failed to install python: $_"
}
