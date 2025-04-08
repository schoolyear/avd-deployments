$scriptName = Split-Path -Path $PSCommandPath -Leaf
$logFile = "C:\${scriptName}.log"
#TODO, path aanpassen naar C:\imagebuild_resources\python\
. "C:\imagebuild_resources\python\helperFunctions.ps1"

$extensions = @(
  "ms-python.python",
  "ms-python.vscode-pylance",
  "ms-toolsai.jupyter",
  "ms-toolsai.vscode-jupyter-cell-tags",
  "ms-toolsai.jupyter-keymap",
  "ms-toolsai.jupyter-renderers",
  "ms-toolsai.vscode-jupyter-slideshow"
)

$codeCommandLinePath = "C:\VSCode\bin\code.cmd"
try {
  foreach ($extension in $extensions) {
    Start-Process -FilePath $codeCommandLinePath -ArgumentList "--install-extension", $extension -Wait -NoNewWindow
  }
} catch {
  Log-Message "Failed to install VSCode extensions: $_"
}