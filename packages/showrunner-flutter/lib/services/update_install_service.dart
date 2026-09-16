import 'dart:io';

import '../persistence/filesystem/atomic_file.dart';

typedef UpdateProcessLauncher =
    Future<void> Function(File script, List<String> arguments);
typedef UpdatePlatformCheck = bool Function();

final class UpdateInstallService {
  const UpdateInstallService({
    this.launcher = _launchPowerShell,
    this.isWindows = _isWindows,
  });

  final UpdateProcessLauncher launcher;
  final UpdatePlatformCheck isWindows;

  Future<void> install(
    File artifact, {
    required File executable,
    required Directory installDirectory,
    required Directory rollbackDirectory,
    String backupVersion = 'unknown',
    int? processId,
  }) async {
    if (!isWindows()) {
      throw UnsupportedError('Windows update installation is unavailable.');
    }
    if (!await artifact.exists() ||
        !artifact.path.toLowerCase().endsWith('.zip')) {
      throw const FormatException(
        'The update artifact must be an existing ZIP.',
      );
    }
    if (!await executable.exists()) {
      throw const FileSystemException(
        'The current ShowRunner executable was not found.',
      );
    }
    if (!await installDirectory.exists()) {
      throw const FileSystemException(
        'The ShowRunner install directory was not found.',
      );
    }
    _validateRollbackDirectory(installDirectory, rollbackDirectory);
    await rollbackDirectory.create(recursive: true);

    final script = File(
      '${Directory.systemTemp.path}/showrunner-update-${DateTime.now().microsecondsSinceEpoch}.ps1',
    );
    await writeAtomicText(script, _updateScript);
    try {
      await launcher(script, [
        '-Mode',
        'Install',
        '-ArchivePath',
        artifact.absolute.path,
        '-InstallDirectory',
        installDirectory.absolute.path,
        '-RollbackDirectory',
        rollbackDirectory.absolute.path,
        '-BackupVersion',
        backupVersion,
        '-ExecutablePath',
        executable.absolute.path,
        '-ProcessId',
        (processId ?? pid).toString(),
      ]);
    } on Object {
      if (await script.exists()) await script.delete();
      rethrow;
    }
  }

  Future<void> rollback({
    required File executable,
    required Directory installDirectory,
    required Directory rollbackDirectory,
    int? processId,
  }) async {
    if (!isWindows()) {
      throw UnsupportedError('Windows update installation is unavailable.');
    }
    if (!await executable.exists()) {
      throw const FileSystemException(
        'The current ShowRunner executable was not found.',
      );
    }
    if (!await installDirectory.exists()) {
      throw const FileSystemException(
        'The ShowRunner install directory was not found.',
      );
    }
    if (!await rollbackDirectory.exists()) {
      throw const FileSystemException(
        'No ShowRunner rollback backup was found.',
      );
    }
    if (!await File('${rollbackDirectory.path}/manifest.json').exists()) {
      throw const FileSystemException(
        'The ShowRunner rollback backup is incomplete.',
      );
    }
    _validateRollbackDirectory(installDirectory, rollbackDirectory);

    final script = File(
      '${Directory.systemTemp.path}/showrunner-rollback-${DateTime.now().microsecondsSinceEpoch}.ps1',
    );
    await writeAtomicText(script, _updateScript);
    try {
      await launcher(script, [
        '-Mode',
        'Rollback',
        '-InstallDirectory',
        installDirectory.absolute.path,
        '-RollbackDirectory',
        rollbackDirectory.absolute.path,
        '-ExecutablePath',
        executable.absolute.path,
        '-ProcessId',
        (processId ?? pid).toString(),
      ]);
    } on Object {
      if (await script.exists()) await script.delete();
      rethrow;
    }
  }
}

void _validateRollbackDirectory(
  Directory installDirectory,
  Directory rollbackDirectory,
) {
  final installPath = _normalizedPath(installDirectory.absolute.path);
  final rollbackPath = _normalizedPath(rollbackDirectory.absolute.path);
  if (rollbackPath == installPath ||
      rollbackPath.startsWith('$installPath${Platform.pathSeparator}')) {
    throw ArgumentError(
      'The rollback directory must not be inside the install directory.',
    );
  }
}

String _normalizedPath(String path) => path
    .replaceAll('/', Platform.pathSeparator)
    .replaceFirst(RegExp(r'[\\/]+$'), '')
    .toLowerCase();

bool _isWindows() => Platform.isWindows;

Future<void> _launchPowerShell(File script, List<String> arguments) async {
  await Process.start('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    script.path,
    ...arguments,
  ], mode: ProcessStartMode.detached);
}

const _updateScript = r'''
param(
  [ValidateSet("Install", "Rollback")][string]$Mode = "Install",
  [string]$ArchivePath,
  [Parameter(Mandatory = $true)][string]$InstallDirectory,
  [Parameter(Mandatory = $true)][string]$RollbackDirectory,
  [string]$BackupVersion = "unknown",
  [Parameter(Mandatory = $true)][string]$ExecutablePath,
  [Parameter(Mandatory = $true)][int]$ProcessId
)

$ErrorActionPreference = 'Stop'
$staging = Join-Path ([IO.Path]::GetTempPath()) "showrunner-update-$([guid]::NewGuid().ToString('N'))"
$backupReady = $false

function Clear-DirectoryContents([string]$Path) {
  if (Test-Path -LiteralPath $Path -PathType Container) {
    Get-ChildItem -LiteralPath $Path -Force |
      Remove-Item -Recurse -Force
  } else {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Copy-DirectoryContents([string]$Source, [string]$Destination, [switch]$ExcludeMetadata) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $items = Get-ChildItem -LiteralPath $Source -Force
  if ($ExcludeMetadata) {
    $items = $items | Where-Object { $_.Name -ne 'manifest.json' }
  }
  $items |
    Copy-Item -Destination $Destination -Recurse -Force
}

function Restore-Backup {
  if (-not (Test-Path -LiteralPath $RollbackDirectory -PathType Container)) {
    throw "ShowRunner rollback backup does not exist: $RollbackDirectory"
  }
  Clear-DirectoryContents $InstallDirectory
  Copy-DirectoryContents $RollbackDirectory $InstallDirectory -ExcludeMetadata
}

try {
  if (-not (Test-Path -LiteralPath $InstallDirectory -PathType Container)) {
    throw "Install directory does not exist: $InstallDirectory"
  }
  New-Item -ItemType Directory -Force -Path $RollbackDirectory | Out-Null
  $installFullPath = [IO.Path]::GetFullPath($InstallDirectory).TrimEnd('\', '/')
  $rollbackFullPath = [IO.Path]::GetFullPath($RollbackDirectory).TrimEnd('\', '/')
  if ($rollbackFullPath.Equals($installFullPath, [StringComparison]::OrdinalIgnoreCase) -or
      $rollbackFullPath.StartsWith("$installFullPath\", [StringComparison]::OrdinalIgnoreCase)) {
    throw "Rollback directory must not be inside the install directory."
  }

  try {
    Wait-Process -Id $ProcessId -Timeout 60
  } catch {
    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
      throw "ShowRunner did not close before the update timeout."
    }
  }

  if ($Mode -eq "Install") {
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
      throw "Update archive does not exist: $ArchivePath"
    }
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $staging -Force
    $executableName = [IO.Path]::GetFileName($ExecutablePath)
    $candidate = Get-ChildItem -LiteralPath $staging -Recurse -Filter $executableName -File |
      Select-Object -First 1
    if (-not $candidate) {
      throw "Update archive does not contain $executableName."
    }

    $sourceRoot = Split-Path -Parent $candidate.FullName
    Clear-DirectoryContents $RollbackDirectory
    Copy-DirectoryContents $InstallDirectory $RollbackDirectory
    $metadata = [ordered]@{
      schemaVersion = 1
      createdAtUtc = (Get-Date).ToUniversalTime().ToString("o")
      sourceVersion = $BackupVersion
      executableName = $executableName
    } | ConvertTo-Json
    Set-Content -LiteralPath (Join-Path $RollbackDirectory 'manifest.json') -Value $metadata -Encoding UTF8
    $backupReady = $true

    Clear-DirectoryContents $InstallDirectory
    Copy-DirectoryContents $sourceRoot $InstallDirectory
    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
      throw "Updated ShowRunner executable was not installed."
    }
  } else {
    if (-not (Test-Path -LiteralPath (Join-Path $RollbackDirectory 'manifest.json') -PathType Leaf)) {
      throw "ShowRunner rollback metadata was not found."
    }
    Restore-Backup
    if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
      throw "Rolled back ShowRunner executable was not installed."
    }
  }

  Start-Process -FilePath $ExecutablePath -WorkingDirectory $InstallDirectory
} catch {
  if ($Mode -eq "Install" -and $backupReady) {
    try {
      Restore-Backup
    } catch {
      Write-Error "ShowRunner update failed and rollback also failed: $($_.Exception.Message)"
    }
  }
  throw
} finally {
  if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
''';
