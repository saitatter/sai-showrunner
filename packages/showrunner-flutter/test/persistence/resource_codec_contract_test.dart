import 'package:yaml/yaml.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/domain/errors/unsupported_document_exception.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/persistence/document_codec.dart';
import 'package:showrunner_flutter/persistence/persistence_issue.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'package:showrunner_flutter/schema/identifiers.dart';
import 'package:showrunner_flutter/schema/queue.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/schema/stream_plan.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  late Directory root;
  late ShowRunnerDataService data;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('showrunner-codec-contract-');
    Future<List<int>> cipher(List<int> bytes) async =>
        bytes.map((b) => b ^ 0x5a).toList();
    data = ShowRunnerDataService(
      root,
      secretSettings: SecretSettingsStore(
        directory: Directory('${root.path}/secrets'),
        encrypt: cipher,
        decrypt: cipher,
      ),
    );
  });
  tearDown(() => root.delete(recursive: true));

  for (final spec in builtInResourceSpecs) {
    for (final extension in ['yaml', 'json']) {
      test(
        '${spec.resourceTypeId} preserves current $extension content, unknown fields and runtime state',
        () async {
          final config = {
            ...spec.createDefaultConfig('Fixture'),
            'futureField': {
              'typed': [null, true, 2.5],
            },
          };
          final expected = ResourceData(
            id: 'fixture',
            config: config,
            state: const {'generation': 1},
          );
          final repository = data.storage.resource(spec.resourceTypeId);
          await repository.directory.create(recursive: true);
          final file = File('${repository.directory.path}/fixture.$extension');
          final private = secretResourceFieldIdsFor(spec.resourceTypeId.value);
          final public = {
            for (final entry in config.entries)
              if (!private.contains(entry.key)) entry.key: entry.value,
          };
          await file.writeAsString(
            extension == 'yaml'
                ? encodeYaml(public)
                : jsonEncode(
                    ResourceData(id: 'fixture', config: public).toJson(),
                  ),
          );
          await repository.save(expected);
          final loaded = (await repository.load('fixture'))!;
          expect(loaded.toJson(), expected.toJson());
          await repository.save(loaded);
          expect(
            (await repository.load('fixture'))!.toJson(),
            expected.toJson(),
          );
          expect(
            await File(
              '${repository.directory.path}/fixture.${extension == 'yaml' ? 'json' : 'yaml'}',
            ).exists(),
            isFalse,
          );
        },
      );
    }
  }

  for (final fixture in <(String, Map<String, dynamic>)>[
    (
      'Overlay',
      {
        'widgets': ['discarded'],
      },
    ),
    (
      'Overlay',
      {
        'size': {'width': 'invalid'},
      },
    ),
    (
      'Dashboard',
      {
        'pages': [
          {
            'sections': [
              {
                'widgets': [false],
              },
            ],
          },
        ],
      },
    ),
    ('Dashboard', {'resourceSlots': 'invalid'}),
    (
      'StreamPlan',
      {
        'segments': [
          {'components': []},
        ],
      },
    ),
    (
      'StreamPlan',
      {
        'activationAutomation': {'schemaVersion': 2},
      },
    ),
  ]) {
    for (final extension in ['yaml', 'json']) {
      test(
        '${fixture.$1} rejects malformed $extension ${fixture.$2.keys.single} without normalization',
        () async {
          final repository = data.storage.resource(ResourceTypeId(fixture.$1));
          await repository.directory.create(recursive: true);
          final file = File('${repository.directory.path}/broken.$extension');
          final source = extension == 'yaml'
              ? encodeYaml(fixture.$2)
              : jsonEncode(
                  ResourceData(id: 'broken', config: fixture.$2).toJson(),
                );
          await file.writeAsString(source);
          await expectLater(repository.load('broken'), throwsFormatException);
          await expectLater(
            repository.save(
              ResourceData(
                id: 'broken',
                config: builtInResourceSpec(
                  fixture.$1,
                ).createDefaultConfig('Replacement'),
              ),
            ),
            throwsFormatException,
          );
          expect(await file.readAsString(), source);
        },
      );
    }
  }

  test(
    'disabled queue timeouts remain disabled after YAML save and restart',
    () async {
      final repository = data.storage.queueConfigs;
      await repository.save(
        'queue.yaml',
        const QueueConfig(name: 'No timeout', timeout: null),
      );
      expect((await repository.find('queue.yaml'))!.timeout, isNull);
      final file = File('${repository.directory.path}/queue.yaml');
      expect(await file.readAsString(), contains('"timeout": null'));
      await file.writeAsString('name: Existing queue\n');
      expect(
        (await repository.find('queue.yaml'))!.timeout,
        const Duration(seconds: 30),
      );
      expect(await file.readAsString(), 'name: Existing queue\n');
    },
  );

  test(
    'known queue field type errors remain visible without being reset to defaults',
    () async {
      for (final config in [
        {'paused': 'false'},
        {'gap': '10'},
        {'timeout': -1},
      ]) {
        expect(() => QueueConfig.fromJson(config), throwsFormatException);
      }
    },
  );

  test(
    'malformed profile trigger lists are rejected instead of dropping entries',
    () async {
      final profile = <String, dynamic>{
        'activationAutomation': AutomationDocument.empty().toJson(),
        'deactivationAutomation': AutomationDocument.empty().toJson(),
        'triggers': [true],
      };
      final file = File('${root.path}/bad-profile.yaml');
      await file.writeAsString(jsonEncode(profile));
      await expectLater(ProfileRepository(file).load(), throwsFormatException);
      expect(jsonDecode(await file.readAsString()), profile);
    },
  );

  test('Stream Plan segment unknown fields survive typed editor snapshots', () {
    final source = {
      'id': 'segment',
      'name': 'Segment',
      'components': <String, dynamic>{},
      'activationAutomation': emptyInlineAutomation(),
      'deactivationAutomation': emptyInlineAutomation(),
      'futureField': {
        'typed': [true, 2],
      },
    };
    expect(StreamPlanSegmentData.fromJson(source).toJson(), source);
  });

  test(
    'unsupported schema and malformed syntax have distinct safe diagnostics',
    () {
      try {
        AutomationDocument.fromJson({'schemaVersion': 2});
        fail('unsupported schema accepted');
      } on UnsupportedDocumentException catch (error) {
        expect(
          PersistenceIssue.fromError(
            error,
            owner: 'automation',
            document: 'future.yaml',
          ).kind,
          PersistenceIssueKind.unsupportedDocument,
        );
      }
      expect(
        PersistenceIssue.fromError(
          const FormatException('Malformed document'),
          owner: 'automation',
          document: 'bad.yaml',
        ).kind,
        PersistenceIssueKind.invalidDocument,
      );
      expect(
        () => decodeYamlValue(loadYaml('1: first\n"1": second\n')),
        throwsFormatException,
      );
    },
  );
}
