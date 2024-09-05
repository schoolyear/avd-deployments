# todo: cleanup, this doesn't work
# Remove Microsoft Edge link so don't student don't try using that browser
Write-Host "Checking for microsoft edge link"
$edgeLink = "C:\Users\Public\Desktop\Microsoft Edge.lnk"
if (Test-Path $edgeLink)
{
    Write-Host "Found $edgeLink, removing..."
    Remove-Item -Path $edgeLink -Force
}
else
{
    Write-Host "Could not find $edgeLink, doing nothing"
}