param(
  [string]$OutputDirectory = 'test/reference/flutter'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$packageDirectory = Join-Path $repoRoot 'packages\showrunner-flutter'
$outputPath = Join-Path $repoRoot $OutputDirectory
$exitCode = 0
$previousCapture = $env:SHOWRUNNER_VISUAL_CAPTURE
$previousOutput = $env:SHOWRUNNER_VISUAL_OUTPUT

$env:SHOWRUNNER_VISUAL_CAPTURE = '1'
$env:SHOWRUNNER_VISUAL_OUTPUT = $outputPath
Push-Location $packageDirectory
try {
  flutter test integration_test/visual_capture_test.dart --no-pub -d windows
  if ($LASTEXITCODE -ne 0) {
    $exitCode = $LASTEXITCODE
  }
} finally {
  Pop-Location
  $env:SHOWRUNNER_VISUAL_CAPTURE = $previousCapture
  $env:SHOWRUNNER_VISUAL_OUTPUT = $previousOutput
}

exit $exitCode
