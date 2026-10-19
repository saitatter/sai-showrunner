param([string]$CaptureDirectory = '')

$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previousCapture = $env:SHOWRUNNER_VISUAL_CAPTURE
$previousOutput = $env:SHOWRUNNER_VISUAL_OUTPUT
if ($CaptureDirectory) {
  $env:SHOWRUNNER_VISUAL_CAPTURE = '1'
  $env:SHOWRUNNER_VISUAL_OUTPUT = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $CaptureDirectory))
}

Push-Location (Join-Path $repositoryRoot 'packages\showrunner-flutter')
try {
  # Compile once instead of rebuilding a Windows executable for each fixture.
  flutter test integration_test/native_suite_test.dart --no-pub -d windows
  if ($LASTEXITCODE -ne 0) { throw "Native integration suite failed with exit code $LASTEXITCODE." }
} finally {
  Pop-Location
  $env:SHOWRUNNER_VISUAL_CAPTURE = $previousCapture
  $env:SHOWRUNNER_VISUAL_OUTPUT = $previousOutput
}
