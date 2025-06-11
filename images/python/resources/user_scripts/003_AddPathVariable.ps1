# The files in this folder (000_name.ps1) are executed for each user session starting on a session host
# The files are executed from the user account and have no admin priviledges
# All files must exit without an error for the VDI Browser to start up properly

#This scripts add a folder to the path variable, this ensures additional installed packages can be used using a path variable
$folderToAdd = "$env:USERPROFILE\AppData\Roaming\Python\Python313\Scripts"

# Get the current user PATH environment variable
$currentPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)

# Check if the folder is already in the PATH
if ($currentPath -notmatch [regex]::Escape($folderToAdd)) {
    # Add the folder to the PATH
    $newPath = "$currentPath;$folderToAdd"
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, [System.EnvironmentVariableTarget]::User)
    Write-Output "Folder added to user PATH successfully."
} else {
    Write-Output "Folder is already in the user PATH."
}
