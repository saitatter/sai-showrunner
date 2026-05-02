param(
	[string]$YouTubeClientId = $env:SHOWRUNNER_YOUTUBE_CLIENT_ID,
	[string]$YouTubeClientSecret = $env:SHOWRUNNER_YOUTUBE_CLIENT_SECRET,
	[string]$UserDir = "",
	[switch]$SkipBuild,
	[switch]$KeepData
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($YouTubeClientId)) {
	throw "Set SHOWRUNNER_YOUTUBE_CLIENT_ID or pass -YouTubeClientId."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ([string]::IsNullOrWhiteSpace($UserDir)) {
	$UserDir = Join-Path $repoRoot ".tmp\showrunner-clean-youtube"
}

$resolvedUserDir = [System.IO.Path]::GetFullPath($UserDir)
if (!$KeepData -and (Test-Path -LiteralPath $resolvedUserDir)) {
	Remove-Item -LiteralPath $resolvedUserDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $resolvedUserDir | Out-Null

$env:SHOWRUNNER_YOUTUBE_CLIENT_ID = $YouTubeClientId
if (![string]::IsNullOrWhiteSpace($YouTubeClientSecret)) {
	$env:SHOWRUNNER_YOUTUBE_CLIENT_SECRET = $YouTubeClientSecret
}
$env:SHOWRUNNER_USER_DIR = $resolvedUserDir
$env:CSC_IDENTITY_AUTO_DISCOVERY = "false"

Write-Host "ShowRunner clean profile: $resolvedUserDir"
Write-Host "YouTube client id: $YouTubeClientId"
Write-Host "YouTube client secret: $(if ([string]::IsNullOrWhiteSpace($YouTubeClientSecret)) { 'not set' } else { 'set' })"

Push-Location $repoRoot
try {
	corepack yarn setup-vite
	if (!$SkipBuild) {
		node .\vite-util\multi-vite.mjs build
	}
	corepack yarn workspace ShowRunner run inspect
} finally {
	Pop-Location
}
