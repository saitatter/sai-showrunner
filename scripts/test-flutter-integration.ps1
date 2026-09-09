$ErrorActionPreference = 'Stop'

Push-Location (Join-Path $PSScriptRoot '..\packages\showrunner-flutter')
try {
  $tests = @(
    'integration_test/application/document_lifecycle_test.dart',
    'integration_test/application/creation_lifecycle_test.dart',
    'integration_test/visual/app_surface_test.dart'
  )
  foreach ($test in $tests) {
    flutter test $test -d windows
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  }
} finally {
  Pop-Location
}
