param(
  [string]$Version = '0.5.9',
  [string]$OutputDirectory = 'release',
  [switch]$SkipSmoke
)

$ErrorActionPreference = 'Stop'

Push-Location (Join-Path $PSScriptRoot '..\packages\showrunner-flutter')
try {
  flutter build windows --release --build-name=$Version --build-number=1
  $bundle = Join-Path (Get-Location) 'build\windows\x64\runner\Release'
  if (-not (Test-Path $bundle)) {
    throw "Flutter Windows bundle was not produced at $bundle"
  }

  $requiredBundlePaths = @(
    'showrunner_flutter.exe',
    'flutter_windows.dll',
    'libmpv-2.dll',
    'media_kit_libs_windows_audio_plugin.dll',
    'data\flutter_assets'
  )
  $missingBundlePaths = @(
    $requiredBundlePaths |
      Where-Object { -not (Test-Path -LiteralPath (Join-Path $bundle $_)) }
  )
  if ($missingBundlePaths.Count -gt 0) {
    throw "Flutter Windows bundle is missing required files: $($missingBundlePaths -join ', ')"
  }

  $outputRoot = Join-Path (Get-Location) "..\..\$OutputDirectory"
  New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
  $archive = Join-Path $outputRoot "ShowRunner-Flutter-windows-$Version.zip"
  if (Test-Path $archive) {
    Remove-Item -Force $archive
  }
  Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $archive
  Write-Host "Created $archive"

  if (-not $SkipSmoke) {
    $smokeScenarios = @(
      'startup',
      'first-run',
      'data-migration',
      'automation',
      'profile',
      'integrations',
      'overlays',
      'updates'
    )
    foreach ($scenario in $smokeScenarios) {
      & (Join-Path $PSScriptRoot 'smoke-flutter-windows.ps1') `
        -ArchivePath $archive `
        -Configuration Release `
        -Scenario $scenario
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
  }
}
finally {
  Pop-Location
}
