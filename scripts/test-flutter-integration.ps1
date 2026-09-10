$ErrorActionPreference = 'Stop'

Push-Location (Join-Path $PSScriptRoot '..\packages\showrunner-flutter')
try {
  $tests = @(
    'integration_test/application/document_lifecycle_test.dart',
    'integration_test/application/creation_lifecycle_test.dart',
    'integration_test/application/document_edit_save_close_test.dart',
    'integration_test/runtime/runtime_workflows_test.dart',
    'integration_test/plugins/provider_lifecycle_test.dart',
    'integration_test/resources/resource_crud_test.dart',
    'integration_test/migration/strict_schema_restart_test.dart',
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
