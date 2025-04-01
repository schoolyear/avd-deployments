$ErrorActionPreference = "Stop"

try {
  C:\imagebuild_resources\python\hello_world_2.ps1
} catch { 
  Write-Error "Failed to run Hello World $_" 
}
