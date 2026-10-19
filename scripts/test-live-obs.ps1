param(
  [string]$ConfigPath = 'packages/showrunner-flutter/test/live/connections.local.yml',
  [switch]$SkipStudio
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$package = Join-Path $repo 'packages/showrunner-flutter'
$config = (Resolve-Path (Join-Path $repo $ConfigPath)).Path
$receiver = Join-Path $package '.tmp/rtmp-receiver'
New-Item -ItemType Directory -Force -Path $receiver | Out-Null
if (!(Test-Path (Join-Path $receiver 'node_modules/node-media-server/package.json'))) {
  & npm install --prefix $receiver --no-audit --no-fund node-media-server@4.4.3
  if ($LASTEXITCODE -ne 0) { throw 'Could not install the local RTMP receiver.' }
}
$server = Join-Path $receiver 'server.cjs'
@'
const NodeMediaServer = require('node-media-server');
new NodeMediaServer({bind:'127.0.0.1',rtmp:{port:19359},http:{port:18089}}).run();
'@ | Set-Content -LiteralPath $server
$previous = @{}
foreach ($name in @('SHOWRUNNER_LIVE_CONFIG','SHOWRUNNER_OBS_FULL_TEST','SHOWRUNNER_OBS_LOCAL_RTMP','SHOWRUNNER_OBS_SKIP_STUDIO')) {
  $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$process = $null
Push-Location $package
try {
  $process = Start-Process -FilePath (Get-Command node).Source -ArgumentList @('server.cjs') -WorkingDirectory $receiver -WindowStyle Hidden -PassThru
  $env:SHOWRUNNER_LIVE_CONFIG = $config
  $env:SHOWRUNNER_OBS_FULL_TEST = '1'
  $env:SHOWRUNNER_OBS_LOCAL_RTMP = 'rtmp://127.0.0.1:19359/live'
  $env:SHOWRUNNER_OBS_SKIP_STUDIO = if ($SkipStudio) { '1' } else { '0' }
  & flutter test test/live/obs_full_test.dart --reporter expanded
  if ($LASTEXITCODE -ne 0) { throw 'OBS live tests failed; inspect the printed report path.' }
} finally {
  if ($process -and !$process.HasExited) { Stop-Process -Id $process.Id }
  foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
  Pop-Location
}
