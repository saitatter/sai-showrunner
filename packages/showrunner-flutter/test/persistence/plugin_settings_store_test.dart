import 'package:showrunner_flutter/persistence/document_revision.dart';
import 'package:showrunner_flutter/persistence/filesystem/file_transaction.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/plugin_settings_store.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/schema/identifiers.dart';
import '../support/transaction_file_fixtures.dart';

void main() {
  late Directory root;
  late Directory directory;
  late SecretSettingsStore secrets;
  const plugin = PluginId('obs');
  FilePluginSettingsStore store() =>
      FilePluginSettingsStore(directory: directory, secrets: secrets);
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'showrunner-settings-transaction-',
    );
    directory = Directory('${root.path}/settings');
    Future<List<int>> cipher(List<int> bytes) async =>
        bytes.map((b) => b ^ 0x5a).toList();
    secrets = SecretSettingsStore(
      directory: Directory('${root.path}/secrets'),
      encrypt: cipher,
      decrypt: cipher,
    );
  });
  tearDown(() => root.delete(recursive: true));

  for (var step = 1; step <= 3; step++) {
    for (final after in [false, true]) {
      test(
        'settings recover write step $step after=$after without plaintext journal credentials',
        () async {
          await store().save(plugin, {
            'host': 'old',
            'password': 'old-password',
          });
          final failing = FilePluginSettingsStore(
            directory: directory,
            secrets: secrets,
            operations: FaultInjectingFiles(writeAt: step, after: after),
          );
          await expectLater(
            failing.save(plugin, {'host': 'new', 'password': 'new-password'}),
            throwsA(isA<FileSystemException>()),
          );
          final journal = File('${directory.path}/.transactions/obs.json');
          if (await journal.exists()) {
            final raw = await journal.readAsString();
            expect(raw, isNot(contains('new-password')));
            for (final entry in (jsonDecode(raw) as Map)['writes'] as List) {
              if (entry['data'] != null) {
                expect(
                  utf8.decode(
                    base64Decode(entry['data'] as String),
                    allowMalformed: true,
                  ),
                  isNot(contains('new-password')),
                );
              }
            }
          }
          expect(
            await store().load(plugin),
            step == 1 && !after
                ? {'host': 'old', 'password': 'old-password'}
                : {'host': 'new', 'password': 'new-password'},
          );
          expect(await journal.exists(), isFalse);
        },
      );
    }
  }

  test('independent owners transform the latest persisted settings', () async {
    await Future.wait(
      List.generate(
        20,
        (_) => store().transform(
          plugin,
          (values) => {...values, 'count': (values['count'] as int? ?? 0) + 1},
        ),
      ),
    );
    expect(await store().load(plugin), {'count': 20});
  });

  test(
    'unsupported public shape is preserved with its encrypted credentials',
    () async {
      await store().save(plugin, {'password': 'original'});
      final file = File('${directory.path}/obs.yaml');
      await file.writeAsString('- unsupported\n');
      final encrypted = await (await secrets.settingsStorageFile(
        'obs',
      )).readAsBytes();
      await expectLater(
        store().save(plugin, {'password': 'replacement'}),
        throwsFormatException,
      );
      expect(await file.readAsString(), '- unsupported\n');
      expect(
        await (await secrets.settingsStorageFile('obs')).readAsBytes(),
        encrypted,
      );
    },
  );

  test(
    'unknown encrypted settings remain encrypted after editing merged values',
    () async {
      await secrets.save('obs', {'futureCredential': 'confidential-marker'});
      final values = await store().load(plugin);
      expect(jsonEncode(values), isNot(contains('confidential-marker')));
      values['host'] = 'localhost';
      await store().save(plugin, values);
      expect(
        await File('${directory.path}/obs.yaml').readAsString(),
        isNot(contains('confidential-marker')),
      );
      expect(await secrets.load('obs'), {
        'futureCredential': 'confidential-marker',
      });
      expect(await store().load(plugin), {'host': 'localhost'});
    },
  );

  test(
    'unknown encrypted resource fields remain encrypted after resaving',
    () async {
      final resources = Directory('${root.path}/connections');
      await resources.create();
      await File(
        '${resources.path}/studio.yaml',
      ).writeAsString('host: localhost\n');
      await secrets.saveResource('OBSConnection', 'studio', {
        'futureCredential': 'confidential-marker',
      });
      final repository = ResourceRepository(
        resources,
        resourceType: 'OBSConnection',
        secretSettings: secrets,
      );
      final visible = (await repository.load('studio'))!;
      expect(
        jsonEncode(visible.toJson()),
        isNot(contains('confidential-marker')),
      );
      await repository.save(visible);
      expect(
        await File('${resources.path}/studio.yaml').readAsString(),
        isNot(contains('confidential-marker')),
      );
      expect(await secrets.loadResource('OBSConnection', 'studio'), {
        'futureCredential': 'confidential-marker',
      });
    },
  );

  test(
    'opaque encrypted fields cannot shadow metadata or be overwritten by transforms',
    () async {
      await secrets.save('obs', {
        'host': 'hidden-host',
        'password': 'declared',
      });
      expect(await store().load(plugin), {'password': 'declared'});
      await store().transform(
        plugin,
        (values) => {...values, 'host': 'attempted'},
      );
      expect(await secrets.load('obs'), {
        'host': 'hidden-host',
        'password': 'declared',
      });
      expect(await store().load(plugin), {'password': 'declared'});
      expect(
        await File('${directory.path}/obs.yaml').readAsString(),
        isNot(contains('hidden-host')),
      );
    },
  );

  test('stale settings saves preserve public and encrypted bytes', () async {
    await store().save(plugin, {
      'host': 'original',
      'password': 'secret-original',
    });
    final values = await store().load(plugin);
    final revision = DocumentRevision.of(values);
    await store().transform(
      plugin,
      (current) => {...current, 'host': 'external'},
    );
    final public = File('${directory.path}/obs.yaml');
    final sealed = await secrets.settingsStorageFile('obs');
    final publicBytes = await public.readAsBytes(),
        secretBytes = await sealed.readAsBytes();
    await expectLater(
      store().save(plugin, {
        ...values,
        'password': 'stale-replacement',
      }, expectedRevision: revision),
      throwsA(isA<PersistenceConflictException>()),
    );
    expect(await public.readAsBytes(), publicBytes);
    expect(await sealed.readAsBytes(), secretBytes);
    var transformed = false;
    await expectLater(
      store().transform(plugin, (current) {
        transformed = true;
        return current;
      }, expectedRevision: revision),
      throwsA(isA<PersistenceConflictException>()),
    );
    expect(transformed, isFalse);
  });

  test(
    'background patches preserve accepted editor values in either writer order',
    () async {
      await store().save(plugin, {'host': 'original', 'password': 'secret'});
      final revision = DocumentRevision.of(await store().load(plugin));
      Future<bool> saveEditor() async {
        try {
          await store().save(plugin, {
            'host': 'edited',
            'password': 'secret',
          }, expectedRevision: revision);
          return true;
        } on PersistenceConflictException {
          return false;
        }
      }

      final edited = saveEditor();
      final patched = store().transform(
        plugin,
        (current) => {...current, 'background': true},
      );
      final accepted = await edited;
      await patched;
      expect(await store().load(plugin), {
        'host': accepted ? 'edited' : 'original',
        'password': 'secret',
        'background': true,
      });
    },
  );

  test('accepted settings are snapshotted before asynchronous IO', () async {
    final values = <String, dynamic>{
      'nested': {'value': 'accepted'},
    };
    final saving = store().save(plugin, values);
    (values['nested'] as Map)['value'] = 'mutated';
    await saving;
    expect(await store().load(plugin), {
      'nested': {'value': 'accepted'},
    });
  });
}
