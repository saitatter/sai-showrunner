param(
  [Parameter(Mandatory = $true)][string]$ConfigPath,
  [switch]$Native
)
$ErrorActionPreference = 'Stop'
$qaConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
$qaPreviousConfig = $env:SHOWRUNNER_LIVE_CONFIG
Push-Location (Join-Path $PSScriptRoot '..\packages\showrunner-flutter')
try {
  $env:SHOWRUNNER_LIVE_CONFIG = $qaConfigPath
  if ($Native) {
    flutter test integration_test/live_nodes_test.dart -d windows --reporter expanded
  } else {
    flutter test test/live/live_node_test.dart --reporter expanded
  }
  $qaExitCode = $LASTEXITCODE
} finally {
  $env:SHOWRUNNER_LIVE_CONFIG = $qaPreviousConfig
  Pop-Location
}
exit $qaExitCode
