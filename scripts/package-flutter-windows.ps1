param(
  [string]$Version = '0.5.9',
  [string]$OutputDirectory = 'release'
)

$ErrorActionPreference = 'Stop'

Push-Location (Join-Path $PSScriptRoot '..\packages\showrunner-flutter')
try {
  flutter build windows --release --build-name=$Version --build-number=1
  $bundle = Join-Path (Get-Location) 'build\windows\x64\runner\Release'
  if (-not (Test-Path $bundle)) {
    throw "Flutter Windows bundle was not produced at $bundle"
  }

  $outputRoot = Join-Path (Get-Location) "..\..\$OutputDirectory"
  New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
  $archive = Join-Path $outputRoot "ShowRunner-Flutter-windows-$Version.zip"
  if (Test-Path $archive) {
    Remove-Item -Force $archive
  }
  Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $archive
  Write-Host "Created $archive"
}
finally {
  Pop-Location
}