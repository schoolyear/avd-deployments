# This script is copied to the image during image build and is executed during session host deployment
# This script expects the sessionhost setup scripts to be stored in [systemdrive]\sessionhost_setup (systemdrive is usually C:)
$ErrorActionPreference = "Stop"
$path = "C:\SessionhostScripts"

$scripts = Get-ChildItem -Path $path -Filter "???_*.ps1" | Sort-Object

foreach ($script in $scripts)
{
    $scriptPath = Join-Path -Path $path -ChildPath $script
    Write-Host "[Executing: ${scriptPath}]"

    & $scriptpath

    if (!$?)
    {
        Write-Host "script failed"
        exit 1
    }
}

Write-Host "[Done]"