# Define variables
$caddyUrl = "https://github.com/caddyserver/caddy/releases/download/v2.6.2/caddy_2.6.2_windows_amd64.zip"
$zipPath = "$env:TEMP\caddy.zip"
$extractPath = "$env:ProgramFiles\Caddy"
$caddyExecutable = "$extractPath\caddy.exe"
$staticDir = "$env:SystemDrive\static"
$serviceName = "Caddy"
$serviceDescription = "Caddy Web Server"

# Remove existing service if it exists, otherwise we cannot delete folder if service is running
if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)
{
    Write-Host "Found existing service $serviceName .. removing"
    Stop-Service -Name $serviceName -Force
    sc.exe delete $serviceName
    Write-Host "Deleted existing service: $serviceName"
}

# Download Caddy
Invoke-WebRequest -Uri $caddyUrl -OutFile $zipPath

# Extract the zip file
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

# Clean up zip file
Remove-Item -Path $zipPath

# Create static directory if it doesn't exist
if (-Not (Test-Path -Path $staticDir))
{
    Write-Host "Creating static directory because it doesn't exist"
    New-Item -Path $staticDir -ItemType Directory
}

# Create the service
sc.exe create $serviceName binPath= "$caddyExecutable file-server --root $staticDir --listen localhost:2015" start=auto
sc.exe description $serviceName $serviceDescription
sc.exe start $serviceName