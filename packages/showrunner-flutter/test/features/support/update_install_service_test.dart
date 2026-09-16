import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/update_install_service.dart';

void main() {
  test('stages a Windows update script with validated paths', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-update-install-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final installDirectory = Directory('${directory.path}/install')
      ..createSync();
    final rollbackDirectory = Directory('${directory.path}/rollback');
    final artifact = File('${directory.path}/update.zip')
      ..writeAsStringSync('zip');
    final executable = File('${installDirectory.path}/showrunner_flutter.exe')
      ..writeAsStringSync('exe');
    final captured = <Object>[];
    final service = UpdateInstallService(
      isWindows: () => true,
      launcher: (script, arguments) async {
        captured.add(script);
        captured.add(arguments);
        final scriptText = await script.readAsString();
        expect(scriptText, contains('Expand-Archive'));
        expect(scriptText, contains(r'$RollbackDirectory'));
        expect(
          scriptText,
          contains('Updated ShowRunner executable was not installed.'),
        );
        expect(scriptText, contains(r'sourceVersion = $BackupVersion'));
        expect(scriptText, contains(r'if ($Mode -eq "Install")'));
        expect(
          scriptText,
          contains(r'Copy-DirectoryContents $sourceRoot $InstallDirectory'),
        );
      },
    );

    await service.install(
      artifact,
      executable: executable,
      installDirectory: installDirectory,
      rollbackDirectory: rollbackDirectory,
      backupVersion: '1.0.0',
      processId: 1234,
    );

    expect(captured, hasLength(2));
    expect(captured[1], contains('-ProcessId'));
    expect(captured[1], contains('1234'));
    expect(captured[1], contains('-RollbackDirectory'));
    expect(captured[1], contains(rollbackDirectory.absolute.path));
  });

  test('stages an explicit rollback using the persistent backup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-update-rollback-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final rollbackDirectory = Directory('${directory.path}/rollback')
      ..createSync();
    File('${rollbackDirectory.path}/manifest.json').writeAsStringSync('{}');
    final installDirectory = Directory('${directory.path}/install')
      ..createSync();
    final executable = File('${installDirectory.path}/showrunner_flutter.exe')
      ..writeAsStringSync('exe');
    final captured = <List<String>>[];
    final service = UpdateInstallService(
      isWindows: () => true,
      launcher: (script, arguments) async {
        captured.add(arguments);
        expect(await script.readAsString(), contains('Rollback'));
      },
    );

    await service.rollback(
      executable: executable,
      installDirectory: installDirectory,
      rollbackDirectory: rollbackDirectory,
      processId: 1234,
    );

    expect(captured, hasLength(1));
    expect(captured.single, contains('Rollback'));
    expect(captured.single, contains('1234'));
  });

  test('rejects a rollback directory inside the install directory', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-update-invalid-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final executable = File('${directory.path}/showrunner_flutter.exe')
      ..writeAsStringSync('exe');
    final artifact = File('${directory.path}/update.zip')
      ..writeAsStringSync('zip');
    final service = UpdateInstallService(
      isWindows: () => true,
      launcher: (_, _) async => fail('The launcher must not be called.'),
    );

    await expectLater(
      service.install(
        artifact,
        executable: executable,
        installDirectory: directory,
        rollbackDirectory: Directory('${directory.path}/rollback'),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects a missing or non-ZIP artifact before launching', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-update-install-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final executable = File('${directory.path}/showrunner_flutter.exe')
      ..writeAsStringSync('exe');
    var launched = false;
    final service = UpdateInstallService(
      isWindows: () => true,
      launcher: (_, _) async => launched = true,
    );

    await expectLater(
      service.install(
        File('${directory.path}/update.txt'),
        executable: executable,
        installDirectory: directory,
        rollbackDirectory: Directory('${directory.path}/rollback'),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(launched, isFalse);
  });
}
