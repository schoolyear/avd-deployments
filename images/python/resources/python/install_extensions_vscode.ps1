$scriptName = Split-Path -Path $PSCommandPath -Leaf
$logFile = "C:\${scriptName}.log"

# TODO, path aanpassen naar C:\imagebuild_resources\python\
. "C:\imagebuild_resources\python\helperFunctions.ps1"

$extensions = @(
  "ms-python.python",
  "ms-python.vscode-pylance",
  "ms-toolsai.jupyter",
  "ms-toolsai.vscode-jupyter-cell-tags",
  "ms-toolsai.jupyter-keymap",
  "ms-toolsai.jupyter-renderers",
  "ms-toolsai.vscode-jupyter-slideshow",
  "tankashing.blinds-theme"
)

$codeCommandLinePath = "C:\VSCode\bin\code.cmd"

function Install-VSCodeExtension {
    param (
        [string]$Extension,
        [int]$Retries = 3
    )

    for ($i = 0; $i -lt $Retries; $i++) {
        try {
            Log-Message "Attempting to install extension: $Extension (try $($i + 1)/$Retries)"
            Start-Process -FilePath $codeCommandLinePath -ArgumentList "--install-extension", $Extension -Wait -NoNewWindow -ErrorAction Stop
            Log-Message "Successfully installed: $Extension"
            return
        } catch {
            if ($i -eq $Retries - 1) {
                Log-Message "❌ Failed to install $Extension after $Retries attempts: $_"
            } else {
                Log-Message "Retrying $Extension due to error: $_"
                Start-Sleep -Seconds 5
            }
        }
    }
}

try {
    foreach ($extension in $extensions) {
        Install-VSCodeExtension -Extension $extension
    }
} catch {
    Log-Message "⚠️ General failure during extension installation process: $_"
}
Try {
    Copy-Item -Path "C:\Windows\System32\config\systemprofile\.vscode\extensions" -Destination "C:\users\Default\.vscode" -Recurse -Force
    }
    Catch {
        Log-Message "Failed to copy extensions to Default user due to error: $_"
    }
