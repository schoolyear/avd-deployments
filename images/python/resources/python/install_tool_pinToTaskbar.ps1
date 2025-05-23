#This installs the tool that is used to pin shortcuts to the taskbar

# Use a user-writable directory for tools
$toolsDir = "C:\Tools"
$pttbPath = Join-Path $toolsDir "pttb.exe"

# Ensure Tools directory exists
if (-not (Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
}

# Download pttb.exe if not present
if (-not (Test-Path $pttbPath)) {
    Invoke-WebRequest -Uri "https://github.com/0x546F6D/pttb_-_Pin_To_TaskBar/releases/latest/download/pttb.exe" -OutFile $pttbPath
}