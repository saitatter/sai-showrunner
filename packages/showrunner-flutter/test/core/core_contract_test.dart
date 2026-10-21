import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/persistence/queue_config_repository.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/action_queue.dart';
import 'package:showrunner_flutter/schema/queue.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/schema/update.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/services/structured_logger.dart';
import 'package:showrunner_flutter/persistence/document_codec.dart';
import 'package:showrunner_flutter/schema/profile.dart';
import '../support/graph_fixtures.dart';

void main() {
  test(
    'round-trips queue configuration with duration values and extra fields',
    () {
      const config = QueueConfig(
        name: 'Alerts',
        paused: true,
        gap: Duration(seconds: 2),
        timeout: Duration(seconds: 45),
        extra: {'custom': 'value'},
      );
      final restored = QueueConfig.fromJson(config.toJson());
      expect(restored.name, 'Alerts');
      expect(restored.paused, isTrue);
      expect(restored.gap, const Duration(seconds: 2));
      expect(restored.timeout, const Duration(seconds: 45));
      expect(restored.extra['custom'], 'value');
    },
  );

  test('persists queue configs and isolates malformed files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-queues-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = QueueConfigRepository(directory);
    await repository.save(
      'alerts.yaml',
      const QueueConfig(name: 'Alerts', gap: Duration(seconds: 3)),
    );
    await File('${directory.path}/broken.yaml').writeAsString('not: [valid');

    final entries = await repository.list();
    expect(
      entries.map((entry) => entry.fileName),
      containsAll(<String>['alerts.yaml', 'broken.yaml']),
    );
    expect(
      entries
          .firstWhere((entry) => entry.fileName == 'alerts.yaml')
          .config
          ?.gap,
      const Duration(seconds: 3),
    );
    expect(
      entries.firstWhere((entry) => entry.fileName == 'broken.yaml').config,
      isNull,
    );

    await repository.delete('alerts.yaml');
    expect(await File('${directory.path}/alerts.yaml').exists(), isFalse);
  });

  test('uses configured queue gap and timeout defaults', () async {
    final queue = DartActionQueue(
      defaultGap: const Duration(milliseconds: 1),
      defaultTimeout: const Duration(seconds: 1),
    );
    addTearDown(queue.dispose);
    queue.enqueue({'name': 'one'}, {});
    queue.enqueue({'name': 'two'}, {});
    var executions = 0;
    await queue.processAll((_) async {
      executions++;
      return null;
    });
    expect(executions, 2);
  });

  test('loads and saves plugin YAML settings with a health snapshot', () async {
    final directory = await Directory.systemTemp.createTemp('showrunner-data-');
    addTearDown(() => directory.delete(recursive: true));
    final service = ShowRunnerDataService(directory);

    await service.savePluginSettings('sample', {
      'enabled': true,
      'retryCount': 3,
      'label': 'Flutter runtime',
      'metadata': {
        'channels': ['chat', 'alerts'],
      },
    });
    final settings = await service.loadPluginSettings('sample');
    final health = await service.health();

    expect(settings, {
      'enabled': true,
      'retryCount': 3,
      'label': 'Flutter runtime',
      'metadata': {
        'channels': ['chat', 'alerts'],
      },
    });
    expect(health.isReady, isFalse);
    expect(health.settingsDirectoryExists, isTrue);
    expect(health.settingsFileCount, 1);

    await service.savePluginSettings('sample', {'enabled': false});
    expect(await service.loadPluginSettings('sample'), {'enabled': false});

    await service.updatePluginSetting('sample', 'newSetting', 42);
    expect(await service.loadPluginSettings('sample'), {
      'enabled': false,
      'newSetting': 42,
    });
  });

  test('loads resource configs from a user data directory', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-resources-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final service = ShowRunnerDataService(directory);

    await service.saveResourceConfig('automations', 'welcome', {
      'name': 'Welcome',
      'enabled': true,
    });
    await File(
      '${directory.path}/automations/readme.txt',
    ).writeAsString('ignored');

    expect(await service.loadResourceConfigs('automations'), {
      'welcome': {'name': 'Welcome', 'enabled': true},
    });
  });

  test('evaluates graph expressions against Dart runtime context', () {
    final context = EvaluationContext(
      locals: {'count': 3},
      contextState: {
        'message': 'hello',
        'payload': {'amount': 7},
      },
      nodeResults: {
        'action-1': {'result': 4},
      },
    );

    expect(
      evaluateExpression({'type': 'variable', 'name': 'count'}, context),
      3,
    );
    expect(
      evaluateExpression({'type': 'variable', 'name': 'message'}, context),
      'hello',
    );
    expect(
      evaluateExpression({
        'type': 'binary',
        'op': '+',
        'left': {'type': 'variable', 'name': 'count'},
        'right': {'type': 'port', 'nodeId': 'action-1', 'port': 'result'},
      }, context),
      7,
    );
    expect(
      evaluateExpression({
        'type': 'call',
        'fn': 'includes',
        'args': [
          {
            'type': 'literal',
            'value': ['chat', 'alerts'],
          },
          {'type': 'literal', 'value': 'alerts'},
        ],
      }, context),
      isTrue,
    );
    expect(
      evaluateExpression({
        'type': 'member',
        'object': {'type': 'variable', 'name': 'payload'},
        'property': 'amount',
      }, context),
      7,
    );
    expect(
      () => evaluateExpression({
        'type': 'binary',
        'op': '/',
        'left': {'type': 'literal', 'value': 1},
        'right': {'type': 'literal', 'value': 0},
      }, context),
      throwsStateError,
    );
  });

  test('lists user files in stable order', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-catalog-',
    );
    final service = ShowRunnerDataService(directory);
    await Directory('${directory.path}/profiles').create(recursive: true);
    await File(
      '${directory.path}/profiles/zeta.yaml',
    ).writeAsString('name: Zeta');
    await File(
      '${directory.path}/profiles/alpha.yaml',
    ).writeAsString('name: Alpha');

    expect(await service.listUserFiles('profiles'), [
      'alpha.yaml',
      'zeta.yaml',
    ]);
    await directory.delete(recursive: true);
  });

  test(
    'loads existing YAML automation files through the Dart repository',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-automation-yaml-',
      );
      final file = File('${directory.path}/automation.yaml');
      await file.writeAsString(
        encodeYaml(automationFixture(name: 'Existing automation').toJson()),
      );

      final automation = await AutomationRepository(file).load();

      expect(automation, isNotNull);
      expect(automation!.metadata['name'], 'Existing automation');
      await directory.delete(recursive: true);
    },
  );

  test(
    'loads a profile with activation and deactivation automations',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-profile-',
      );
      final file = File('${directory.path}/profile.yaml');
      await file.writeAsString(
        encodeYaml(
          ShowRunnerProfile(
            name: 'Main',
            activationMode: 'toggle',
            triggers: [],
            activationCondition: {},
            activationAutomation: AutomationDocument.empty(),
            deactivationAutomation: AutomationDocument.empty(),
          ).toJson(),
        ),
      );

      final profile = await ProfileRepository(file).load();

      expect(profile?.name, 'Main');
      expect(profile?.activationMode, 'toggle');
      expect(
        profile?.activationAutomation.graph.spaces[mainAutomationSpace]!.nodes,
        isEmpty,
      );
      expect(
        profile
            ?.deactivationAutomation
            .graph
            .spaces[mainAutomationSpace]!
            .nodes,
        isEmpty,
      );
      await directory.delete(recursive: true);
    },
  );

  test('processes all queue items with a configured gap', () async {
    final queue = DartActionQueue();
    queue.enqueue({'type': 'one'}, {});
    queue.enqueue({'type': 'two'}, {});
    final processed = <String>[];

    await queue.processAll((item) async {
      processed.add(item.id);
      return null;
    }, gap: const Duration(milliseconds: 1));

    expect(processed, ['queue-0', 'queue-1']);
    expect(queue.pending, isEmpty);
    expect(queue.history, hasLength(2));
  });

  test('parses UpdateInfo and determines update availability', () {
    final update = UpdateInfo.fromJson({
      'version': '1.0.0-beta2',
      'releaseNotes': 'New feature release',
    }, currentVersion: '1.0.0-beta1');

    expect(update.hasUpdate, isTrue);
    expect(update.latestVersion, '1.0.0-beta2');
    expect(update.status, UpdateStatus.available);

    final upToDate = UpdateInfo.fromJson({
      'version': '1.0.0-beta1',
    }, currentVersion: '1.0.0-beta1');
    expect(upToDate.hasUpdate, isFalse);
    expect(upToDate.status, UpdateStatus.upToDate);
  });

  test('captures structured logs and notifies listeners', () async {
    final logger = ShowRunnerLogger.instance;
    logger.clear();
    final logs = <LogEntry>[];
    final subscription = logger.stream.listen(logs.add);

    logger.info('runtime', 'Runtime started');
    logger.error('plugin', 'Failed to connect', error: 'Connection refused');

    await Future<void>.delayed(Duration.zero);
    expect(logs, hasLength(2));
    expect(logs.first.message, 'Runtime started');
    expect(logs.last.level, LogLevel.error);
    await subscription.cancel();
  });

  test('persists and loads ResourceData through ResourceRepository', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-resource-repo-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = ResourceRepository(directory);

    const resource = ResourceData(
      id: 'res-1',
      config: {'name': 'Test Resource'},
    );
    await repository.save(resource);

    final list = await repository.list();
    expect(list, hasLength(1));
    expect(list.first.name, 'Test Resource');

    final loaded = await repository.load('res-1');
    expect(loaded?.id, 'res-1');

    await repository.delete('res-1');
    expect(await repository.load('res-1'), isNull);
  });

  test('loads and edits YAML resources without creating duplicates', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-yaml-resource-repo-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final yamlResource = File('${directory.path}/yaml-resource.yaml');
    await yamlResource.writeAsString('''
name: Overlay
width: 1920
widgets:
  - type: text
    text: Hello
''');
    final repository = ResourceRepository(directory);

    final loaded = await repository.load('yaml-resource');
    expect(loaded?.config['name'], 'Overlay');
    expect((loaded?.config['widgets'] as List).single['text'], 'Hello');

    await repository.save(
      ResourceData(
        id: 'yaml-resource',
        config: {...loaded!.config, 'name': 'Updated overlay'},
      ),
    );
    expect(
      await File('${directory.path}/yaml-resource.json').exists(),
      isFalse,
    );
    expect((await repository.load('yaml-resource'))?.name, 'Updated overlay');
    expect(
      (await directory.list().where((entity) => entity is File).toList()).map(
        (entity) => entity.uri.pathSegments.last,
      ),
      ['yaml-resource.yaml'],
    );
  });
}
