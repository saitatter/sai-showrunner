param(
  [string]$ConfigPath = 'packages/showrunner-flutter/test/live/connections.local.yml',
  [ValidateRange(0,240)][int]$WaitChatSeconds = 0
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$qaConfig = (Resolve-Path -LiteralPath (Join-Path $repo $ConfigPath)).Path
$previous = @{}
foreach ($name in @('SHOWRUNNER_LIVE_CONFIG','SHOWRUNNER_TWITCH_LIVE','SHOWRUNNER_TWITCH_WAIT_CHAT_SECONDS')) {
  $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
}
Push-Location (Join-Path $repo 'packages/showrunner-flutter')
try {
  $env:SHOWRUNNER_LIVE_CONFIG = $qaConfig
  $env:SHOWRUNNER_TWITCH_LIVE = '1'
  $env:SHOWRUNNER_TWITCH_WAIT_CHAT_SECONDS = "$WaitChatSeconds"
  flutter test test/live/twitch_connection_test.dart --reporter expanded
  $qaExitCode = $LASTEXITCODE
} finally {
  foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
  Pop-Location
}
exit $qaExitCode
