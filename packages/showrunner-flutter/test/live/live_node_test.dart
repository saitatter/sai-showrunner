import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import '../support/graph_fixtures.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

Object? _resolve(Object? value) {
  if (value is String && value.startsWith('env:')) {
    final name = value.substring(4);
    final result = Platform.environment[name];
    if (result == null || result.isEmpty) {
      throw StateError('Missing environment variable: $name');
    }
    return result;
  }
  if (value is Map) {
    return value.map((key, child) => MapEntry('$key', _resolve(child)));
  }
  if (value is List) return value.map(_resolve).toList();
  return value;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

bool _contains(Object? actual, Object? expected) {
  if (expected is Map) {
    return actual is Map &&
        expected.keys.every(
          (key) =>
              actual.containsKey(key) && _contains(actual[key], expected[key]),
        );
  }
  if (expected is List) {
    return actual is List && jsonEncode(actual) == jsonEncode(expected);
  }
  return actual == expected;
}

void main() {
  final path = Platform.environment['SHOWRUNNER_LIVE_CONFIG'];
  test(
    'enabled YAML scenarios execute through the production graph engine',
    () => runLiveNodeScenarios(path!),
    skip: path == null
        ? 'Set SHOWRUNNER_LIVE_CONFIG using scripts/test-live-nodes.ps1.'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> runLiveNodeScenarios(String path) async {
  final raw = _map(
    jsonDecode(jsonEncode(loadYaml(await File(path).readAsString()))),
  );
  expect(raw['version'], 1);
  final enabled = (raw['enabled_plugins'] as List? ?? [])
      .cast<String>()
      .toSet();
  final scenarios = (raw['scenarios'] as List? ?? [])
      .map(_map)
      .where((scenario) => scenario['enabled'] == true)
      .toList();
  if (scenarios.isEmpty) {
    fail('No enabled scenarios: no live actions were tested.');
  }
  final directory = await Directory.systemTemp.createTemp(
    'showrunner-live-nodes-',
  );
  addTearDown(() => directory.delete(recursive: true));
  final service = ShowRunnerDataService(directory);
  final catalog = createDefaultPluginRegistry();
  final plugins = catalog.plugins.toList();
  try {
    for (final id in enabled) {
      if (!plugins.any((plugin) => plugin.id.value == id)) {
        throw StateError('Unknown enabled plugin: $id');
      }
    }
    final settings = _map(raw['plugin_settings']);
    for (final id in enabled) {
      await service.savePluginSettings(id, _map(_resolve(settings[id])));
    }
    await service.savePluginSettings('showrunner-flutter', {
      'disabledPlugins': [
        for (final plugin in plugins)
          if (!enabled.contains(plugin.id.value)) plugin.id.value,
      ],
    });
    for (final resource in (raw['resources'] as List? ?? []).map(_map)) {
      final type = resource['type']?.toString();
      final owner = plugins
          .where(
            (plugin) =>
                plugin.resources.any((r) => r.resourceTypeId.value == type),
          )
          .firstOrNull;
      if (owner == null) throw StateError('Unknown resource type: $type');
      if (!enabled.contains(owner.id.value)) continue;
      final contract = owner.resources.firstWhere(
        (r) => r.resourceTypeId.value == type,
      );
      await ResourceRepository(
        Directory('${directory.path}/${contract.storageDirectory}'),
        resourceType: type,
        secretSettings: service.secretSettingsStore,
      ).save(
        ResourceData(
          id: resource['id'] as String,
          config: {
            ...contract.createDefaultConfig('QA resource'),
            ..._map(_resolve(resource['config'])),
          },
        ),
      );
    }
  } finally {
    await catalog.close();
  }
  final registry = await createConfiguredPluginRegistry(
    service,
    httpPortOverride: 0,
  );
  addTearDown(registry.close);
  final engine = CompiledExecutionEngine();
  for (final scenario in scenarios) {
    final plugin = scenario['plugin'] as String;
    final action = scenario['action'] as String;
    final name = scenario['name']?.toString() ?? '$plugin.$action';
    if (!enabled.contains(plugin)) {
      fail('$name: plugin must be listed in enabled_plugins.');
    }
    final token = DartCancellationToken();
    try {
      final result = await engine
          .executeWithRegistry(
            automation: automationFixture(
              entryNodeId: 'probe',
              nodes: [
                GraphNode(
                  id: 'probe',
                  type: actionNodeType(plugin, action),
                  data: {'config': _map(_resolve(scenario['config']))},
                ),
              ],
            ),
            context: EvaluationContext(cancellationToken: token),
            registry: registry,
          )
          .timeout(
            Duration(seconds: (scenario['timeout_seconds'] as int?) ?? 30),
            onTimeout: () {
              token.cancel();
              throw StateError('Scenario timed out');
            },
          );
      if (!result.completed) fail('$name: graph did not complete.');
      if (scenario.containsKey('expect') &&
          !_contains(
            result.nodeResults['probe'],
            _resolve(scenario['expect']),
          )) {
        fail(
          '$name: result does not match expected fields (values omitted to protect credentials).',
        );
      }
      stdout.writeln('PASS $name ($plugin.$action)');
    } on Object catch (error) {
      // Provider errors may contain request bodies, headers or response tokens.
      fail(
        '$name ($plugin.$action) failed: ${error.runtimeType}. Check credentials, target IDs, permissions and expectations.',
      );
    } finally {
      token.cancel();
    }
  }
}
