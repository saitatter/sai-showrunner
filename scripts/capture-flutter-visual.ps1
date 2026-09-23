param(
  [string]$OutputDirectory = 'test/reference/flutter'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$packageDirectory = Join-Path $repoRoot 'packages\showrunner-flutter'
$outputPath = Join-Path $repoRoot $OutputDirectory
$exitCode = 0

$env:SHOWRUNNER_VISUAL_CAPTURE = '1'
$env:SHOWRUNNER_VISUAL_OUTPUT = $outputPath
Push-Location $packageDirectory
try {
  flutter test integration_test/visual/app_surface_test.dart
  if ($LASTEXITCODE -ne 0) {
    $exitCode = $LASTEXITCODE
  } else {
    flutter test integration_test/visual/workspace_catalog_test.dart
    if ($LASTEXITCODE -ne 0) {
      $exitCode = $LASTEXITCODE
    }
  }
} finally {
  Pop-Location
  Remove-Item Env:SHOWRUNNER_VISUAL_CAPTURE -ErrorAction SilentlyContinue
  Remove-Item Env:SHOWRUNNER_VISUAL_OUTPUT -ErrorAction SilentlyContinue
}

exit $exitCode
