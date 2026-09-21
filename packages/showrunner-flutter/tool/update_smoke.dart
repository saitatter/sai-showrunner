import 'dart:convert';
import 'dart:io';

import 'package:showrunner_flutter/services/update_install_service.dart';

Future<void> main(List<String> arguments) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('The packaged updater smoke test requires Windows.');
  }

  final bundlePath = _argument(arguments, 'bundle');
  if (bundlePath == null) {
    throw ArgumentError('Pass --bundle=<Flutter Windows bundle directory>.');
  }
  final sourceBundle = Directory(bundlePath);
  if (!await sourceBundle.exists() ||
      !await File('${sourceBundle.path}/showrunner_flutter.exe').exists()) {
    throw ArgumentError.value(
      bundlePath,
      'bundle',
      'The bundle must contain showrunner_flutter.exe.',
    );
  }

  final root = await Directory.systemTemp.createTemp(
    'showrunner-update-smoke-',
  );
  try {
    final source = Directory('${root.path}/source')..createSync();
    final install = Directory('${root.path}/install')..createSync();
    final rollback = Directory('${root.path}/rollback');
    final artifact = File('${root.path}/update.zip');
    final userDirectory = Directory('${root.path}/user');

    await _copyDirectory(sourceBundle, source);
    await _copyDirectory(sourceBundle, install);
    await File('${source.path}/update-marker.txt').writeAsString('new');
    await File('${install.path}/update-marker.txt').writeAsString('old');
    await userDirectory.create(recursive: true);
    await _compress(source, artifact, root);

    final executable = File('${install.path}/showrunner_flutter.exe');
    final service = UpdateInstallService(
      isWindows: () => true,
      launcher: (script, arguments) => _runUpdater(
        script,
        arguments,
        executable: executable,
        userDirectory: userDirectory,
      ),
    );

    await service.install(
      artifact,
      executable: executable,
      installDirectory: install,
      rollbackDirectory: rollback,
      backupVersion: '2.0.0-local',
      processId: -1,
    );
    _assert(
      await File('${install.path}/update-marker.txt').readAsString() == 'new',
      'Install did not replace the bundle contents.',
    );
    _assert(
      await File('${rollback.path}/update-marker.txt').readAsString() == 'old',
      'Install did not preserve the rollback bundle.',
    );
    final manifest = jsonDecode(
      await File('${rollback.path}/manifest.json').readAsString(),
    );
    _assert(
      manifest['sourceVersion'] == '2.0.0-local',
      'Rollback manifest has the wrong source version.',
    );

    await service.rollback(
      executable: executable,
      installDirectory: install,
      rollbackDirectory: rollback,
      processId: -1,
    );
    _assert(
      await File('${install.path}/update-marker.txt').readAsString() == 'old',
      'Rollback did not restore the previous bundle.',
    );

    stdout.writeln(
      jsonEncode({
        'status': 'passed',
        'installDirectory': install.path,
        'rollbackDirectory': rollback.path,
      }),
    );
  } finally {
    await root.delete(recursive: true);
  }
}

String? _argument(List<String> arguments, String name) {
  final prefix = '--$name=';
  for (final argument in arguments) {
    if (argument.startsWith(prefix)) return argument.substring(prefix.length);
  }
  return null;
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final target = '${destination.path}/${_basename(entity.path)}';
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(target));
    } else if (entity is File) {
      await entity.copy(target);
    }
  }
}

Future<void> _compress(
  Directory source,
  File archive,
  Directory environmentRoot,
) async {
  final result = await Process.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      r'Compress-Archive -Path (Join-Path $env:SHOWRUNNER_UPDATE_SOURCE "*") -DestinationPath $env:SHOWRUNNER_UPDATE_ARCHIVE -Force',
    ],
    environment: {
      ...Platform.environment,
      'SHOWRUNNER_UPDATE_SOURCE': source.absolute.path,
      'SHOWRUNNER_UPDATE_ARCHIVE': archive.absolute.path,
      'SHOWRUNNER_UPDATE_ROOT': environmentRoot.absolute.path,
    },
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell.exe',
      const [],
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}

Future<void> _runUpdater(
  File script,
  List<String> arguments, {
  required File executable,
  required Directory userDirectory,
}) async {
  final result = await Process.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
      ...arguments,
    ],
    environment: {
      ...Platform.environment,
      'SHOWRUNNER_USER_DIR': userDirectory.absolute.path,
    },
  );
  await _stopExecutable(executable);
  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell.exe',
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}

Future<void> _stopExecutable(File executable) async {
  final target = executable.absolute.path;
  for (var attempt = 0; attempt < 20; attempt++) {
    await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r'''
$target = [IO.Path]::GetFullPath($env:SHOWRUNNER_UPDATE_EXECUTABLE)
Get-CimInstance Win32_Process |
  Where-Object { $_.ExecutablePath -and [IO.Path]::GetFullPath($_.ExecutablePath) -ieq $target } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
''',
      ],
      environment: {
        ...Platform.environment,
        'SHOWRUNNER_UPDATE_EXECUTABLE': target,
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

void _assert(bool condition, String message) {
  if (!condition) throw StateError(message);
}
