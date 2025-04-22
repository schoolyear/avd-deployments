Param ($username, $homedir)

# This file is a placeholder and can be removed
# The files in this folder (000_name.ps1) are executed for each user session starting on a session host
# The files are executed from the SYSTEM account and have admin priviledges
# All files must exit without an error for the VDI Browser to start up properly

# Set the source path
$sourcePath = "C:\Windows\System32\config\systemprofile\.vscode\extensions"

# Set the destination path
$destinationPath = "$homedir\.vscode\"

# Log variables to file for debugging
$username | Out-File -Append -FilePath C:\temp\SessionScriptVars.log
$homedir | Out-File -Append -FilePath C:\temp\SessionScriptVars.log
$sourcePath | Out-File -Append -FilePath C:\temp\SessionScriptVars.log
$destinationPath | Out-File -Append -FilePath C:\temp\SessionScriptVars.log
# Log content of source folder to file for debugging
Get-ChildItem C:\Windows\System32\config\systemprofile\.vscode\extensions | Out-File -Append -FilePath C:\temp\SessionScriptVars.log
# Copy the contents recursively, preserving structure
Copy-Item -Path "$sourcePath" -Destination $destinationPath -Recurse -Force