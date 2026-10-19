param(
  [string]$ExecutablePath = '',
  [string]$ArchivePath = '',
  [ValidateSet('Debug', 'Release')]
  [string]$Configuration = 'Release',
  [ValidateSet('startup', 'first-run', 'automation', 'workflow', 'profile', 'integrations', 'overlays', 'updates')]
  [string]$Scenario = 'startup',
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
$process = $null
$processStarted = $false
$stdoutTask = $null
$stderrTask = $null

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

  $env:SHOWRUNNER_USER_DIR = [IO.Path]::GetFullPath($UserDirectory)
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $resolvedExecutable
  $startInfo.WorkingDirectory = Split-Path -Parent $resolvedExecutable
  $startInfo.Arguments = "--showrunner-smoke=$Scenario"
  $startInfo.CreateNoWindow = $true
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $processStarted = $true
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $waitError = $null
  try {
    $exited = $process.WaitForExit($StartupTimeoutMilliseconds)
  } catch {
    $exited = $false
    $waitError = $_.Exception.Message
  }
  $process.Refresh()
  if (-not $exited -or -not $process.HasExited) {
    if (-not $process.HasExited) {
      $process.Kill()
      $process.WaitForExit()
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    throw "Flutter process did not finish the $Scenario smoke scenario. Exited=$($process.HasExited), WaitError=$waitError`nstdout: $stdout`nstderr: $stderr"
  }
  $stdout = $stdoutTask.GetAwaiter().GetResult()
  $stderr = $stderrTask.GetAwaiter().GetResult()
  if ($process.ExitCode -ne 0) {
    throw "Flutter process failed the $Scenario smoke scenario. ExitCode=$($process.ExitCode)`nstdout: $stdout`nstderr: $stderr"
  }

  Write-Host "Flutter Windows $Scenario smoke passed: $resolvedExecutable"
}
finally {
  if ($process -and $processStarted) {
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

  foreach ($temporaryDirectory in $temporaryDirectories) {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($ownsUserDirectory -and $UserDirectory) {
    Remove-Item -LiteralPath $UserDirectory -Recurse -Force -ErrorAction SilentlyContinue
  }
}
