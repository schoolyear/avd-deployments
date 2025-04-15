$scriptName = Split-Path -Path $PSCommandPath -Leaf
$logFile = "C:\${scriptName}.log"
#TODO, path aanpassen naar C:\imagebuild_resources\python\
. "C:\imagebuild_resources\python\helperFunctions.ps1"

$pythonIconOriginalPath = "C:\imagebuild_resources\python\files\python.ico"
$pythonIconDestinationPath = "C:\Program Files\Python313\python.ico"
$registryKey = "registry::HKEY_CLASSES_ROOT"
$vsCodeExecutable = "C:\VSCode\Code.exe"

# Copy over the python.ico
try {
  Copy-Item $pythonIconOriginalPath $pythonIconDestinationPath -Force | Out-Null
} catch {
  Log-Message "Failed to copy over python icon: $_"
}

Write-Host "Setting up file associations for python..."
New-Item -Path "$registryKey\.py" -Force | Out-Null
New-Item -Path "$registryKey\.python" -Force | Out-Null
New-Item -Path "$registryKey\.pyc" -Force | Out-Null
New-Item -Path "$registryKey\.pyd" -Force | Out-Null
New-Item -Path "$registryKey\.pyo" -Force | Out-Null
New-Item -Path "$registryKey\.pyw" -Force | Out-Null
New-Item -Path "$registryKey\.pyz" -Force | Out-Null
New-Item -Path "$registryKey\.pyzw" -Force | Out-Null
New-Item -Path "$registryKey\.ipynb" -Force | Out-Null
New-ItemProperty -Path "$registryKey\.py" -Name "(Default)" -Value "Python.File" -PropertyType String -Force | Out-Null
New-ItemProperty -Path "$registryKey\.python" -Name "(Default)" -Value "Python.File" -PropertyType String -Force | Out-Null
New-ItemProperty -Path "$registryKey\.pyc" -Name "(Default)" -Value "Python.File" -PropertyType String -Force | Out-Null
New-ItemProperty -Path "$registryKey\.pyd" -Name "(Default)" -Value "Python.File" -PropertyType String -Force | Out-Null
New-ItemProperty -Path "$registryKey\.pyo" -Name "(Default)" -Value "Python.File" -PropertyType String -Force | Out-Null
New-ItemProperty -Path "$registryKey\.pyw" -Name "(Default)" -Value "Python.File" -PropertyType String -Force | Out-Null
New-ItemProperty -Path "$registryKey\.pyz" -Name "(Default)" -Value "Python.File" -PropertyType String -Force | Out-Null
New-ItemProperty -Path "$registryKey\.pyzw" -Name "(Default)" -Value "Python.File" -PropertyType String -Force | Out-Null
New-ItemProperty -Path "$registryKey\.ipynb" -Name "(Default)" -Value "Python.File" -PropertyType String -Force | Out-Null
New-Item -Path "$registryKey\Python.File" -Force | Out-Null
New-ItemProperty -Path "$registryKey\Python.File" -Name "(Default)" -Value "Python File" -PropertyType String -Force | Out-Null
New-Item -Path "$registryKey\Python.File\shell\open\command" -Force | Out-Null
New-ItemProperty -Path "$registryKey\Python.File\shell\open\command" -Name "(Default)" -Value "$vsCodeExecutable `"%1`"" -PropertyType String -Force | Out-Null
New-Item -Path "$registryKey\Python.File\DefaultIcon" -Force | Out-Null
New-ItemProperty -Path "$registryKey\Python.File\DefaultIcon" -Name "(Default)" -Value "$pythonIconDestinationPath,0" -PropertyType String -Force | Out-Null
Log-Message "Done setting up file associations for python"