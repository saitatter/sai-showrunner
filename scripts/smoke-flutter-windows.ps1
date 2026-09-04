param(
  [string]$ExecutablePath = '',
  [string]$ArchivePath = '',
  [ValidateSet('Debug', 'Release')]
  [string]$Configuration = 'Release',
  [string]$UserDirectory = '',
  [int]$StartupTimeoutMilliseconds = 15000
)

$ErrorActionPreference = 'Stop'

if ($ExecutablePath -and $ArchivePath) {
  throw 'Specify either -ExecutablePath or -ArchivePath, not both.'
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporaryDirectories = @()
$ownsUserDirectory = [string]::IsNullOrWhiteSpace($UserDirectory)
$previousUserDirectory = $env:SHOWRUNNER_USER_DIR
$stdoutPath = $null
$stderrPath = $null
$process = $null

try {
  if ($ArchivePath) {
    $archive = [IO.Path]::GetFullPath($ArchivePath)
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
      throw "Flutter archive does not exist: $archive"
    }
    $extractRoot = Join-Path ([IO.Path]::GetTempPath()) "showrunner-flutter-smoke-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    $temporaryDirectories += $extractRoot
    Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot -Force
    $candidate = Get-ChildItem -Path $extractRoot -Recurse -Filter 'showrunner_flutter.exe' -File |
      Select-Object -First 1
    if (-not $candidate) {
      throw "Flutter archive does not contain showrunner_flutter.exe: $archive"
    }
    $resolvedExecutable = $candidate.FullName
  } elseif ($ExecutablePath) {
    $resolvedExecutable = [IO.Path]::GetFullPath($ExecutablePath)
  } else {
    $resolvedExecutable = Join-Path $repositoryRoot "packages\showrunner-flutter\build\windows\x64\runner\$Configuration\showrunner_flutter.exe"
  }

  if (-not (Test-Path -LiteralPath $resolvedExecutable -PathType Leaf)) {
    throw "Flutter executable does not exist: $resolvedExecutable"
  }

  if ($ownsUserDirectory) {
    $UserDirectory = Join-Path ([IO.Path]::GetTempPath()) "showrunner-flutter-user-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path $UserDirectory | Out-Null
  } elseif (-not (Test-Path -LiteralPath $UserDirectory -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $UserDirectory | Out-Null
  }

  $stdoutPath = Join-Path ([IO.Path]::GetTempPath()) "showrunner-flutter-smoke-$([guid]::NewGuid().ToString('N')).out.log"
  $stderrPath = Join-Path ([IO.Path]::GetTempPath()) "showrunner-flutter-smoke-$([guid]::NewGuid().ToString('N')).err.log"
  $env:SHOWRUNNER_USER_DIR = [IO.Path]::GetFullPath($UserDirectory)
  $process = Start-Process `
    -FilePath $resolvedExecutable `
    -WorkingDirectory (Split-Path -Parent $resolvedExecutable) `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru

  $ready = $process.WaitForInputIdle($StartupTimeoutMilliseconds)
  $process.Refresh()
  if (-not $ready -or $process.HasExited) {
    $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -Raw -LiteralPath $stdoutPath } else { '' }
    $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -Raw -LiteralPath $stderrPath } else { '' }
    $exitCode = if ($process.HasExited) { $process.ExitCode } else { 'running' }
    throw "Flutter process did not reach an idle UI process. Exited=$($process.HasExited), ExitCode=$exitCode`nstdout: $stdout`nstderr: $stderr"
  }

  Write-Host "Flutter Windows startup smoke passed: $resolvedExecutable"
}
finally {
  if ($process) {
    $process.Refresh()
    if (-not $process.HasExited) {
      $process.CloseMainWindow() | Out-Null
      if (-not $process.WaitForExit(5000)) {
        $process.Kill()
        $process.WaitForExit()
      }
    }
    $process.Dispose()
  }

  if ($null -eq $previousUserDirectory) {
    Remove-Item Env:SHOWRUNNER_USER_DIR -ErrorAction SilentlyContinue
  } else {
    $env:SHOWRUNNER_USER_DIR = $previousUserDirectory
  }

  Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
  foreach ($temporaryDirectory in $temporaryDirectories) {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($ownsUserDirectory -and $UserDirectory) {
    Remove-Item -LiteralPath $UserDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}