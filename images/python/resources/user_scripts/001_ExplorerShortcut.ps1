# This file is a placeholder and can be removed
# The files in this folder (000_name.ps1) are executed for each user session starting on a session host
# The files are executed from the user account and have no admin priviledges
# All files must exit without an error for the VDI Browser to start up properly

# Define paths
$targetPath = "C:\Windows\explorer.exe"
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutName = "File Explorer.lnk"
$shortcutPath = Join-Path $desktopPath $shortcutName
$startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$shortcutName"

# Use the directory for tools
$toolsDir = "C:\Tools"
$pttbPath = Join-Path $toolsDir "pttb.exe"

# Create shortcut on Desktop
$WScriptShell = New-Object -ComObject WScript.Shell
$desktopShortcut = $WScriptShell.CreateShortcut($shortcutPath)
$desktopShortcut.TargetPath = $targetPath
$desktopShortcut.WorkingDirectory = Split-Path $targetPath
$desktopShortcut.IconLocation = "$targetPath, 0"
$desktopShortcut.Save()

# Adds shortcut to Start menu
Copy-Item -Path $shortcutPath -Destination $startMenuPath -Force

# Pin to taskbar using pttb.exe
Start-Process -FilePath $pttbPath -ArgumentList "`"$targetPath`"" -Wait
