#This is used to create a log file and output logs to the console

function Log-Message {
    param (
        [string]$message
    )
    Add-Content -Path $logFile -Value "$(Get-Date) - $message"
    Write-Host $message
}