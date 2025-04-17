# This file is a placeholder and can be removed
# The files in this folder (000_name.ps1) are executed for each user session starting on a session host
# The files are executed from the SYSTEM account and have admin priviledges
# All files must exit without an error for the VDI Browser to start up properly

# Set the source path
$sourcePath = "C:\Windows\System32\config\systemprofile\.vscode\extensions"

# Set the destination path
$destinationPath = "C:\Users\$username\.vscode\"

# Copy the contents recursively, preserving structure
Copy-Item -Path "$sourcePath" -Destination $destinationPath -Recurse -Force