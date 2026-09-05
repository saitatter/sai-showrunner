import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/update_install_service.dart';

void main() {
  test('stages a Windows update script with validated paths', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-update-install-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final artifact = File('${directory.path}/update.zip')
      ..writeAsStringSync('zip');
    final executable = File('${directory.path}/showrunner_flutter.exe')
      ..writeAsStringSync('exe');
    final captured = <Object>[];
    final service = UpdateInstallService(
      isWindows: () => true,
      launcher: (script, arguments) async {
        captured.add(script);
        captured.add(arguments);
        expect(await script.readAsString(), contains('Expand-Archive'));
      },
    );

    await service.install(
      artifact,
      executable: executable,
      installDirectory: directory,
      processId: 1234,
    );

    expect(captured, hasLength(2));
    expect(captured[1], contains('-ProcessId'));
    expect(captured[1], contains('1234'));
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
      ),
      throwsA(isA<FormatException>()),
    );
    expect(launched, isFalse);
  });
}
