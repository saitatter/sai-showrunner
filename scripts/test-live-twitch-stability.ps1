param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[a-zA-Z0-9_]{1,25}$')]
  [string]$TestAccount,
  [string]$ConfigPath = 'packages/showrunner-flutter/test/live/connections.local.yml'
)
# Sends six QA chat messages and one announcement, tests timeout/ban with undo,
# and temporarily changes/restores the configured broadcaster's stream title.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$qaConfig = (Resolve-Path -LiteralPath (Join-Path $repo $ConfigPath)).Path
$previous = @{}
foreach ($name in @('SHOWRUNNER_LIVE_CONFIG','SHOWRUNNER_TWITCH_MUTATIONS','SHOWRUNNER_TWITCH_TEST_ACCOUNT')) {
  $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
}
Push-Location (Join-Path $repo 'packages/showrunner-flutter')
try {
  $env:SHOWRUNNER_LIVE_CONFIG = $qaConfig
  $env:SHOWRUNNER_TWITCH_MUTATIONS = '1'
  $env:SHOWRUNNER_TWITCH_TEST_ACCOUNT = $TestAccount
  # Sequential: EventSub subscriptions must not overlap another live fixture.
  flutter test test/live/twitch_stability_test.dart --reporter expanded
  $qaExitCode = $LASTEXITCODE
  if ($qaExitCode -eq 0) {
    flutter test test/live/twitch_actions_live_test.dart --reporter expanded
    $qaExitCode = $LASTEXITCODE
  }
} finally {
  foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
  Pop-Location
}
exit $qaExitCode
