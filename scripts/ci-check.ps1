param(
  [ValidateSet('All', 'Scripts', 'Flutter', 'Parity')]
  [string]$Stage = 'All',
  [switch]$Integration,
  [switch]$Visual
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$yarnScript = Join-Path $repoRoot '.yarn\releases\yarn-4.1.0.cjs'
function Invoke-Check {
  param([string]$Command, [string[]]$Arguments)
  Get-Command $Command -ErrorAction Stop | Out-Null
  $previousPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $Command @Arguments
    $checkExit = $LASTEXITCODE
  } finally { $ErrorActionPreference = $previousPreference }
  if ($checkExit -ne 0) { throw "Check failed ($checkExit): $Command $($Arguments -join ' ')" }
}
Push-Location $repoRoot
try {
  if ($Stage -in @('All', 'Scripts')) {
    Invoke-Check node @('tools/check-docs.mjs')
    Invoke-Check node @('tools/verify-local-version.mjs')
    Invoke-Check node @('tools/release/prepare.mjs', '--check')
    foreach ($check in @('overlay:test', 'overlay:typecheck', 'overlay:verify-no-vue', 'overlay:generate', 'overlay:build')) {
      Invoke-Check node @($yarnScript, $check)
    }
    Invoke-Check git @('diff', '--exit-code', '--',
      'packages/showrunner-obs-overlay/src/generated',
      'packages/showrunner-flutter/assets/overlay_widgets.generated.json',
      'packages/showrunner-flutter/lib/plugins/overlays/overlay_widget_catalog.generated.dart',
      'packages/showrunner-flutter/lib/plugins/overlays/overlay_protocol.generated.dart',
      'packages/showrunner-flutter/lib/plugins/remote/remote_protocol.generated.dart',
      'libs/showrunner-overlay-core/src/generated')
  }
  if ($Stage -in @('All', 'Flutter')) {
    Push-Location packages/showrunner-flutter
    try {
      Invoke-Check flutter @('pub', 'get', '--enforce-lockfile')
      Invoke-Check dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tool', 'integration_test')
      Invoke-Check flutter @('analyze', '--no-pub', '--fatal-infos')
      Invoke-Check flutter @('test', '--no-pub')
    } finally { Pop-Location }
  }
  if ($Stage -in @('All', 'Parity')) {
    Invoke-Check node @($yarnScript, 'parity:check')
    Invoke-Check node @($yarnScript, 'parity:product')
  }
  if ($Stage -eq 'All') {
    Invoke-Check node @('tools/overlay_registry/transport-browser-smoke.mjs')
  }
  if ($Integration) {
    $integrationArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', './scripts/test-flutter-integration.ps1')
    if ($Visual) { $integrationArgs += @('-CaptureDirectory', '.tmp/visual/flutter') }
    Invoke-Check powershell $integrationArgs
  }
  if ($Visual) {
    if (-not $Integration) {
      Invoke-Check powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', './scripts/capture-flutter-visual.ps1', '-OutputDirectory', '.tmp/visual/flutter')
    }
    Invoke-Check node @($yarnScript, 'visual:compare:catalog', '--actual-root=.tmp/visual/flutter')
    Invoke-Check node @($yarnScript, 'visual:regression', '--actual-root=.tmp/visual/flutter')
  }
} finally { Pop-Location }
