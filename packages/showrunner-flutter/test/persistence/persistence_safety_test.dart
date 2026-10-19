import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:showrunner_flutter/persistence/document_codec.dart';
import 'package:showrunner_flutter/persistence/filesystem/atomic_file.dart';
import 'package:showrunner_flutter/persistence/filesystem/safe_path.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/services/update_install_service.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('showrunner-safety-');
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'junction ancestors cannot redirect a file outside the allowed root',
    () async {
      final allowed = Directory('${root.path}/allowed');
      await allowed.create();
      final outside = Directory('${root.path}/outside');
      await outside.create();
      final marker = File('${outside.path}/marker.txt');
      await marker.writeAsString('fixture');
      final junction = '${allowed.path}/redirect';
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        "New-Item -ItemType Junction -Path '${junction.replaceAll("'", "''")}' -Target '${outside.path.replaceAll("'", "''")}' | Out-Null",
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      await expectLater(
        containedFile(allowed, ['redirect', 'marker.txt']),
        throwsArgumentError,
      );
      await expectLater(
        containedFile(allowed, ['redirect', 'new.txt']),
        throwsArgumentError,
      );
      expect(await marker.readAsString(), 'fixture');
    },
    skip: !Platform.isWindows,
  );

  test('YAML preserves nested collections, keys and multiline scalars', () {
    final value = <String, dynamic>{
      'widgets': [
        {
          'config': {'text': 'line1\nline2\t"\\'},
          'id': 'w1',
        },
      ],
      'a: b': [
        [null, true, 2.5],
        {},
        [],
      ],
      'empty': <String, dynamic>{},
    };
    expect(decodeYamlValue(loadYaml(encodeYaml(value))), value);
  });

  test(
    'YAML resource state survives restart without changing the config shape',
    () async {
      final directory = Directory('${root.path}/resources');
      await directory.create();
      final file = File('${directory.path}/variable.yaml');
      await file.writeAsString('type: number\ndefaultValue: 0\n');
      final repository = ResourceRepository(directory);
      await repository.save(
        const ResourceData(
          id: 'variable',
          config: {'type': 'number', 'defaultValue': 0},
          state: {'value': 42},
        ),
      );
      expect(
        (await ResourceRepository(directory).load('variable'))!.state['value'],
        42,
      );
      expect(loadYaml(await file.readAsString())['config'], isNull);
      await repository.delete('variable');
      expect(
        await File('${directory.path}/.state/variable.json').exists(),
        isFalse,
      );
    },
  );

  test(
    'concurrent writers succeed, leave valid JSON and clean up temporaries',
    () async {
      final file = File('${root.path}/state.json');
      await Future.wait(
        List.generate(
          30,
          (index) => writeAtomicText(
            file,
            jsonEncode({'index': index, 'payload': 'x' * 10000}),
          ),
        ),
      );
      expect(jsonDecode(await file.readAsString())['payload'], 'x' * 10000);
      expect(
        await root.list().where((file) => file.path.endsWith('.tmp')).length,
        0,
      );
    },
  );

  test('read modify write transactions do not lose increments', () async {
    final file = File('${root.path}/counter.json');
    await writeAtomicText(file, '0');
    await Future.wait(
      List.generate(
        30,
        (_) => withFileLock('${file.path}.transaction', () async {
          final value = int.parse(await file.readAsString());
          await writeAtomicText(file, '${value + 1}');
        }),
      ),
    );
    expect(await file.readAsString(), '30');
  });

  test('repository rejects traversal before load, save or delete', () async {
    final repository = ResourceRepository(Directory('${root.path}/resources'));
    for (final id in [
      '../outside',
      r'..\outside',
      '.',
      '..',
      'name:stream',
      'NUL',
      'trailing.',
    ]) {
      await expectLater(repository.load(id), throwsArgumentError);
      expect(
        () => repository.save(ResourceData(id: id, config: const {})),
        throwsArgumentError,
      );
      expect(() => repository.delete(id), throwsArgumentError);
    }
  });

  test('unsafe decoded segments cannot reach files outside web root', () async {
    await expectLater(
      containedFile(root, [r'..\marker.txt']),
      throwsArgumentError,
    );
    await expectLater(
      containedFile(root, ['..', 'marker.txt']),
      throwsArgumentError,
    );
  });

  test(
    'corrupted resource remains visible in the catalog with its error',
    () async {
      await File('${root.path}/broken.json').writeAsString('not JSON');
      final entries = await ResourceRepository(root).listWithErrors();
      expect(entries.single.fileName, 'broken.json');
      expect(entries.single.error, isNotNull);
    },
  );

  test(
    'failed secret decryption does not overwrite the old encrypted file',
    () async {
      final secrets = Directory('${root.path}/secrets');
      await secrets.create();
      final file = File('${secrets.path}/twitch.yaml');
      await file.writeAsString('old encrypted data');
      final data = ShowRunnerDataService(
        root,
        secretSettings: SecretSettingsStore(
          directory: secrets,
          decrypt: (_) async => throw StateError('decryption failed'),
          encrypt: (bytes) async => bytes,
        ),
      );
      await expectLater(
        data.savePluginSettings('twitch', {'accessToken': 'new value'}),
        throwsStateError,
      );
      expect(await file.readAsString(), 'old encrypted data');
    },
  );

  test(
    'updater rejects ancestor, descendant and identical rollback roots',
    () async {
      final install = Directory('${root.path}/install');
      await install.create();
      final executable = File('${install.path}/app.exe');
      await executable.writeAsString('fixture');
      final artifact = File('${root.path}/update.zip');
      await artifact.writeAsString('fixture');
      var launched = false;
      final service = UpdateInstallService(
        isWindows: () => true,
        launcher: (_, _) async {
          launched = true;
        },
      );
      for (final backup in [
        root,
        install,
        Directory('${install.path}/backup'),
      ]) {
        await expectLater(
          service.install(
            artifact,
            executable: executable,
            installDirectory: install,
            rollbackDirectory: backup,
          ),
          throwsArgumentError,
        );
      }
      expect(launched, isFalse);
    },
  );
}
