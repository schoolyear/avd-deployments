try
{
    $appNames = @("Mail")
    $action = "Unpin from taskbar"

    ((New-Object -Com Shell.Application).Namespace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items() |
            Where-Object { $appNames -contains $_.Name }).Verbs() |
            Where-Object { $_.Name.replace('&', '') -match $action } |
            ForEach-Object { $_.DoIt() }
}
catch
{
    Write-Error "Failed to unping apps from taskbar: $_"
    # No need to exit on failure
}