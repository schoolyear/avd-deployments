# This file is a placeholder and can be removed
# The files in this folder (000_name.ps1) are executed for each user session starting on a session host
# The files are executed from the user account and have no admin priviledges
# All files must exit without an error for the VDI Browser to start up properly

# Define paths
$targetPath = "C:\VSCode\code.exe"  # Make sure this path is correct on your system
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutName = "Visual Studio Code.lnk"
$shortcutPath = Join-Path $desktopPath $shortcutName
$startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$shortcutName"

# Use a user-writable directory for tools
$toolsDir = Join-Path $env:LOCALAPPDATA "Tools"
$pttbPath = Join-Path $toolsDir "pttb.exe"

# Ensure Tools directory exists
if (-not (Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
}

# Download pttb.exe if not present
if (-not (Test-Path $pttbPath)) {
    Invoke-WebRequest -Uri "https://github.com/0x546F6D/pttb_-_Pin_To_TaskBar/releases/latest/download/pttb.exe" -OutFile $pttbPath
}

# Create shortcut on Desktop
$WScriptShell = New-Object -ComObject WScript.Shell
$desktopShortcut = $WScriptShell.CreateShortcut($shortcutPath)
$desktopShortcut.TargetPath = $targetPath
$desktopShortcut.WorkingDirectory = Split-Path $targetPath
$desktopShortcut.IconLocation = "$targetPath, 0"
$desktopShortcut.Save()

# Copy shortcut to Start Menu Programs folder (adds to Start menu)
Copy-Item -Path $shortcutPath -Destination $startMenuPath -Force

# Pin to taskbar using pttb.exe
Start-Process -FilePath $pttbPath -ArgumentList "`"$targetPath`"" -Wait
