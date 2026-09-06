$ErrorActionPreference = 'Stop'

Push-Location (Join-Path $PSScriptRoot '..\packages\showrunner-flutter')
try {
  flutter test integration_test
} finally {
  Pop-Location
}
