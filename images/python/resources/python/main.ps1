$scriptName = Split-Path -Path $PSCommandPath -Leaf
$logFile = "C:\${scriptName}.log"

. "C:\imagebuild_resources\python\helperFunctions.ps1"

try {
  C:\imagebuild_resources\python\python_installation.ps1
} catch { 
  Log-Message "Failed to run python_installation $_"
}

try {
  C:\imagebuild_resources\python\python_post_installation.ps1
} catch { 
  Log-Message "Failed to run python_post_installation $_"
}

try {
  C:\imagebuild_resources\python\vscode_installation.ps1 -RemoveInstaller
} catch {
  Log-Message "Failed to install VSCode: $_"
}
try {
  C:\imagebuild_resources\python\install_extensions_vscode.ps1
} catch {
  Log-Message "Failed to install VSCode extensions: $_"
}

try {
  C:\imagebuild_resources\python\file_associations.ps1
} catch {
  Log-Message "Failed to install file associations: $_"
}

try {
  C:\imagebuild_resources\python\install_tool_pinToTaskbar.ps1
} catch {
  Log-Message "Failed to install PinToTaskbar Tool: $_"
}