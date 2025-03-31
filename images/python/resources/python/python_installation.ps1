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

$pythonInstallerName = "python-3.11.6.exe"
$pythonInstallerURL = "https://www.python.org/ftp/python/3.11.6/python-3.11.6-amd64.exe"
$pythonInstallerMD5Sum = "4a501c073d0d688c033d43f85e22d77e"
$pythonInstallerDownloadPath = "$env:USERPROFILE\Downloads\$pythonInstallerName"

if (!(Test-Path $pythonInstallerDownloadPath)) {
  Write-Host "Python Installer not found, downloading..."
  Invoke-WebRequest -Uri $pythonInstallerURL -OutFile $pythonInstallerDownloadPath
}

# Calculate the MD5 hash of the downloaded file
$downloadedMD5 = Get-MD5Hash -file $pythonInstallerDownloadPath

# Compare the calculated MD5 with the expected value
if (!($downloadedMD5 -eq $pythonInstallerMD5Sum))
{
  Write-Error "md5 does not match: $downloadedMD5"
}

# Actually install python
try {
  Write-Host "Installing python..."
  Start-Process -FilePath $pythonInstallerDownloadPath -Args "/quiet InstallAllUsers=1 AssociateFiles=1 PrependPath=1" -Wait -NoNewWindow
  Write-Host "Successfully installed python"
} catch {
  Write-Error "Failed to install python: $_"
}