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

    final script = File(
      '${Directory.systemTemp.path}/showrunner-update-${DateTime.now().microsecondsSinceEpoch}.ps1',
    );
    await writeAtomicText(script, _updateScript);
    try {
      await launcher(script, [
        '-ArchivePath',
        artifact.absolute.path,
        '-InstallDirectory',
        installDirectory.absolute.path,
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
  [Parameter(Mandatory = $true)][string]$ArchivePath,
  [Parameter(Mandatory = $true)][string]$InstallDirectory,
  [Parameter(Mandatory = $true)][string]$ExecutablePath,
  [Parameter(Mandatory = $true)][int]$ProcessId
)

$ErrorActionPreference = 'Stop'
$staging = Join-Path ([IO.Path]::GetTempPath()) "showrunner-update-$([guid]::NewGuid().ToString('N'))"

try {
  if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "Update archive does not exist: $ArchivePath"
  }
  if (-not (Test-Path -LiteralPath $InstallDirectory -PathType Container)) {
    throw "Install directory does not exist: $InstallDirectory"
  }

  try {
    Wait-Process -Id $ProcessId -Timeout 60
  } catch {
    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
      throw "ShowRunner did not close before the update timeout."
    }
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
  Get-ChildItem -LiteralPath $sourceRoot -Force |
    Copy-Item -Destination $InstallDirectory -Recurse -Force
  Start-Process -FilePath $ExecutablePath -WorkingDirectory $InstallDirectory
} finally {
  if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
  Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
}
''';
