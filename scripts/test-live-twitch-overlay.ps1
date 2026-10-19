param(
  [string]$ConfigPath = 'packages/showrunner-flutter/test/live/connections.local.yml',
  [switch]$LocalPrecheck,
  [switch]$Stability
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$qaConfig = (Resolve-Path -LiteralPath (Join-Path $repo $ConfigPath)).Path
$previous = @{}
foreach ($name in @('SHOWRUNNER_LIVE_CONFIG','SHOWRUNNER_TWITCH_OVERLAY_OBS','SHOWRUNNER_CHAT_OVERLAY_DRY_RUN','SHOWRUNNER_OVERLAY_STABILITY')) {
  $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
}
Push-Location (Join-Path $repo 'packages/showrunner-flutter')
try {
  $env:SHOWRUNNER_LIVE_CONFIG = $qaConfig
  $env:SHOWRUNNER_TWITCH_OVERLAY_OBS = '1'
  $env:SHOWRUNNER_CHAT_OVERLAY_DRY_RUN = if ($LocalPrecheck) { '1' } else { '0' }
  $env:SHOWRUNNER_OVERLAY_STABILITY = if ($Stability) { '1' } else { '0' }
  flutter test test/live/twitch_overlay_obs_test.dart --reporter expanded
  $qaExitCode = $LASTEXITCODE
} finally {
  foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
  Pop-Location
}
exit $qaExitCode
